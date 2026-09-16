import 'dart:convert';
import 'dart:io';

import '../domain/cue.dart';
import '../domain/language.dart';
import '../domain/line_wrap.dart';
import '../domain/segmenter.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_options.dart';
import '../domain/transcode/command.dart';
import '../domain/transcode/probe.dart';
import '../services/media.dart';
import '../services/provider_api.dart';
import '../services/registry.dart';
import '../services/settings.dart';
import '../services/transcoder.dart';

/// 识别服务的构造方式。测试注入假实现时换的就是它。
typedef AsrFactory =
    AsrProvider Function(String id, AppSettings settings, TaskOptions options);

typedef TranslationFactory =
    TranslationProvider Function(
      String id,
      AppSettings settings,
      TaskOptions options,
    );

/// 把一个任务跑完，或者在中途安全地停下来。
///
/// 核心承诺：**失败与取消都保留已完成阶段的结果**，重试时从 [SubtitleTask.resumeStage]
/// 继续，不重做已经花过钱和时间的阶段。界面上向用户明确承诺了这件事。
class TaskRunner {
  TaskRunner({
    required this.settings,
    required this.workDir,
    Media? media,
    Transcoder? transcoder,
    AsrFactory? asrFactory,
    TranslationFactory? translationFactory,
  }) : media = media ?? Media(),
       transcoder = transcoder ?? Transcoder(media: media),
       _asrOverride = asrFactory,
       _translationFactory = translationFactory ?? _defaultTranslationFactory;

  final AppSettings settings;

  /// 每个任务的中间产物目录（抽出的音频、阶段快照）。
  final String workDir;

  final Media media;

  /// 转码任务用它探测源文件与跑 ffmpeg。
  final Transcoder transcoder;

  final AsrFactory? _asrOverride;
  final TranslationFactory _translationFactory;

  /// 任务参数里的模型与提示词覆盖设置里的值 —— 参数在入队时就定死了。
  /// 默认实现把本实例的 [media] 交给需要切分音频的服务，共用同一份 ffmpeg 定位。
  AsrFactory get _asrFactory =>
      _asrOverride ??
      (id, settings, options) => Registry.buildAsr(
        id,
        settings,
        model: options.asrModel,
        prompt: options.asrPrompt,
        media: media,
        diarize: options.diarize,
      );

  static TranslationProvider _defaultTranslationFactory(
    String id,
    AppSettings settings,
    TaskOptions options,
  ) => Registry.buildTranslation(
    id,
    settings,
    model: options.translationModel,
    guidance: options.translationGuidance,
  );

  /// 翻译一批失败时最多把批量减半几次。
  static const _maxBatchRetries = 3;

  /// 运行 [task]。[onChange] 在每次状态变化时调用，供界面刷新。
  Future<void> run(
    SubtitleTask task, {
    required CancellationToken token,
    required void Function() onChange,
  }) async {
    task.status = TaskStatus.running;
    task.error = null;
    onChange();

    try {
      await _stage(task, TaskStage.queued, onChange, () async {});
      if (task.kind == TaskKind.transcode) {
        await _prepareTranscode(task, onChange);
        await _transcode(task, token, onChange);
        await _finishTranscode(task, onChange);
      } else {
        await _prepare(task, token, onChange);
        await _recognize(task, token, onChange);
        await _segment(task, onChange);
        await _translate(task, token, onChange);
        await _finish(task, onChange);
      }

      task.status = TaskStatus.done;
      task.progress = 1;
      task.eta = null;
      task.note('任务完成');
    } on TaskCancelled {
      // 已完成阶段保持 done，当前阶段记为 cancelled。
      task.status = TaskStatus.cancelled;
      _markCurrent(task, StageState.cancelled, '${task.percentLabel} 时手动停止');
      task.note('用户取消；已完成阶段的结果已保留', LogLevel.warn);
    } on ProviderException catch (e) {
      task.status = TaskStatus.failed;
      _markCurrent(task, StageState.failed, e.message);
      task.error = TaskError(
        title: e.message,
        detail: e.detail ?? e.message,
        hint: e.hint ?? '查看日志了解详情。',
      );
      task.note('${task.stage.label}阶段失败：${e.message}', LogLevel.error);
      if (e.detail != null) task.note(e.detail!, LogLevel.error);
    } catch (e) {
      task.status = TaskStatus.failed;
      _markCurrent(task, StageState.failed, '$e');
      task.error = TaskError(
        title: '${task.stage.label}阶段出错',
        detail: '$e',
        hint: '这是未预期的错误。已完成阶段的结果已保留，可从中断处继续。',
      );
      task.note('$e', LogLevel.error);
    } finally {
      onChange();
    }
  }

  void _markCurrent(SubtitleTask task, StageState state, String note) {
    task.stages[task.stage] = task.stages[task.stage]!.copyWith(
      state: state,
      note: note,
    );
  }

  /// 阶段包装：已完成的直接跳过（断点续跑），否则计时执行并记录耗时。
  Future<void> _stage(
    SubtitleTask task,
    TaskStage stage,
    void Function() onChange,
    Future<void> Function() body, {
    bool skip = false,
    String? skipNote,
  }) async {
    final existing = task.stages[stage]!;
    if (existing.state == StageState.done ||
        existing.state == StageState.skipped) {
      return;
    }

    task.stage = stage;

    if (skip) {
      task.stages[stage] = existing.copyWith(
        state: StageState.skipped,
        note: skipNote,
      );
      onChange();
      return;
    }

    task.stages[stage] = existing.copyWith(state: StageState.active);
    onChange();

    final started = DateTime.now();
    await body();

    task.stages[stage] = task.stages[stage]!.copyWith(
      state: StageState.done,
      duration: DateTime.now().difference(started),
    );
    onChange();
  }

  Future<void> _prepare(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => _stage(task, TaskStage.prepare, onChange, () async {
    // 音频要重新抽取，之前按旧音频切出来的识别记录作废。
    task.recognition = null;
    if (task.kind == TaskKind.translate) {
      // 输入本来就是字幕，解析出来即可。
      final bytes = await File(task.sourcePath).readAsBytes();
      late String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        // Keep the parser useful for legacy single-byte subtitle files. The
        // timestamps are ASCII even when the body encoding is not UTF-8.
        text = latin1.decode(bytes);
      }
      final cues = Srt.parse(text);
      if (cues.isEmpty) {
        throw const ProviderException(
          '字幕文件里没有可用的条目',
          hint: '确认文件是 SRT / VTT 且时间码格式正确。',
        );
      }
      task.document = SubtitleDocument(
        cues: cues,
        sourceLanguage: task.sourceLanguage.name,
        targetLanguage: task.targetLanguage.name,
      );
      task.note('解析字幕：${cues.length} 条');
      return;
    }

    task.mediaDuration = await media.probeDuration(task.sourcePath);
    final audioPath = '$workDir/${task.id}.wav';
    await media.extractAudio(
      sourcePath: task.sourcePath,
      outputPath: audioPath,
      token: token,
    );
    task.note(
      '抽取音频完成（16 kHz 单声道）'
      '${task.mediaDuration == null ? '' : '，时长 ${Srt.formatDuration(task.mediaDuration!)}'}',
    );
  });

  Future<void> _recognize(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => _stage(
    task,
    TaskStage.recognize,
    onChange,
    skip: !task.kind.needsRecognition,
    skipNote: 'SRT 无需识别',
    () async {
      final provider = _asrFactory(task.asrProviderId, settings, task.options);
      // 检查点挂在任务上：失败或取消后续跑，只重试没完成的段。
      final checkpoint = task.recognition ??= RecognitionCheckpoint();
      if (checkpoint.doneCount > 0) {
        task.note('识别续跑：${checkpoint.doneCount} 段已完成，只重试其余');
      }
      final cues = await provider.transcribe(
        audioPath: '$workDir/${task.id}.wav',
        // 下发的是语言代码（zh / en），不是界面上那个中文名。
        language: task.sourceLanguage.code,
        token: token,
        checkpoint: checkpoint,
        onProgress: (done, total, {note}) {
          task.progress = total == 0 ? 0 : done / total;
          task.stages[TaskStage.recognize] = task.stages[TaskStage.recognize]!
              .copyWith(note: note);
          onChange();
        },
      );

      task.document = SubtitleDocument(
        cues: cues,
        sourceLanguage: task.sourceLanguage.name,
        targetLanguage: task.targetLanguage.name,
      );

      final skipped = checkpoint.skippedCount;
      task.recognition = null;

      final low = cues
          .where((c) => (c.confidence ?? 1) < Cue.lowConfidence)
          .length;
      task.stages[TaskStage.recognize] = task.stages[TaskStage.recognize]!
          .copyWith(
            note:
                '${provider.info.name} · ${cues.length} 段'
                '${skipped > 0 ? ' · 已跳过 $skipped 段' : ''}',
          );
      task.note('识别完成 ${cues.length} 段');
      if (skipped > 0) {
        task.note('$skipped 段反复失败已跳过，留下空字幕待校对', LogLevel.warn);
      }
      if (low > 0) {
        task.note('$low 段置信度低于 ${Cue.lowConfidence}，已标记待校对', LogLevel.warn);
      }
    },
  );

  /// 断句：修正重叠、合并过短的分段。规则见 [Segmenter]。
  Future<void> _segment(SubtitleTask task, void Function() onChange) => _stage(
    task,
    TaskStage.segment,
    onChange,
    skip: !task.kind.needsRecognition,
    () async {
      final result = Segmenter(
        minDurationMs: task.options.minCueMs,
        maxDurationMs: task.options.maxCueMs,
      ).run(
        task.document.cues,
        cjk: task.sourceLanguage.cjk,
      );
      final merged = result.cues;
      final joined = result.joined;

      task.document = task.document.copyWith(cues: merged);
      task.stages[TaskStage.segment] = task.stages[TaskStage.segment]!.copyWith(
        note: '${merged.length} 条',
      );
      task.note('断句完成，合并短句 $joined 处，拆分过长字幕 ${result.split} 处');
    },
  );

  Future<void> _translate(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => _stage(
    task,
    TaskStage.translate,
    onChange,
    skip: !task.kind.needsTranslation,
    skipNote: '未选择翻译',
    () async {
      final provider = _translationFactory(
        task.translationProviderId,
        settings,
        task.options,
      );
      final cues = [...task.document.cues];
      final started = DateTime.now();

      // 已有译文的跳过 —— 这就是翻译阶段的断点续跑。
      final pending = [
        for (final (i, c) in cues.indexed)
          // 原文为空的是识别被跳过的占位条，送去翻译只会浪费一次请求。
          if (!c.hasTranslation && c.source.trim().isNotEmpty) i,
      ];

      if (pending.isEmpty) {
        task.note('全部条目已有译文，跳过翻译');
        return;
      }

      task.note(
        '翻译开始 · ${provider.info.name} · 批大小 ${task.options.translationBatchSize}',
      );

      var cursor = 0;
      var batchSize = task.options.translationBatchSize;
      var halvings = 0;

      while (cursor < pending.length) {
        token.throwIfCancelled();

        final slice = pending.sublist(
          cursor,
          (cursor + batchSize).clamp(0, pending.length),
        );
        final lines = [for (final i in slice) cues[i].source];

        final List<String> result;
        try {
          result = await provider.translateBatch(
            lines: lines,
            sourceLanguage: task.sourceLanguage.name,
            targetLanguage: task.targetLanguage.name,
            token: token,
          );
          if (result.length != lines.length) {
            throw ProviderException(
              '译文与原文条数对不上',
              detail: '期望 ${lines.length} 条，实际收到 ${result.length} 条',
              hint: '模型合并或丢弃了字幕行。流水线会自动减半批量重试。',
              batchTooLarge: true,
            );
          }
        } on ProviderException catch (e) {
          // 只有「一批给太多了」才值得减半重试；网络和鉴权错误减半没有意义，
          // 直接失败让用户去修，已翻译的条目留在 document 里供续跑。
          if (!e.batchTooLarge || lines.length == 1) rethrow;
          halvings++;
          if (halvings > _maxBatchRetries) rethrow;
          batchSize = (batchSize / 2).ceil();
          task.note('${e.message}，批量降到 $batchSize 后重试', LogLevel.warn);
          continue;
        }

        for (final (j, i) in slice.indexed) {
          cues[i] = cues[i].copyWith(translation: result[j]);
        }
        cursor += slice.length;

        task.document = task.document.copyWith(cues: cues);
        task.progress = cursor / pending.length;
        task.eta = _estimate(started, cursor, pending.length);
        task.stages[TaskStage.translate] = task.stages[TaskStage.translate]!
            .copyWith(note: '第 $cursor / ${pending.length} 条');
        onChange();
      }

      task.note('翻译完成 ${pending.length} 条');
    },
  );

  Future<void> _finish(SubtitleTask task, void Function() onChange) =>
      _stage(task, TaskStage.finish, onChange, () async {
        final outputs = await writeOutputs(task);
        for (final path in outputs) {
          task.note('已写出 $path');
        }
        // 空文本写不进 SRT（空块会和下一块粘在一起），产物里只能略过；
        // 在日志里说清楚，免得用户以为那段话本来就没有字幕。
        final blank = task.document.cues
            .where((c) => c.source.trim().isEmpty)
            .length;
        if (blank > 0) {
          task.note(
            '有 $blank 条字幕原文为空（识别时被跳过的段），未写入产物；'
            '在编辑器里补上文字后重新导出',
            LogLevel.warn,
          );
        }
      });

  /// 写出字幕产物。返回实际写出的路径。
  ///
  /// 折行在这里做而不是在断句阶段做：文档里存干净文本，用户在编辑器里
  /// 改完再导出会按当前设置重新折，不会叠加上一次的硬换行。
  Future<List<String>> writeOutputs(SubtitleTask task) async {
    final options = task.options;
    final format = options.format;
    if (!format.implemented) {
      throw ProviderException(
        '${format.label} 格式尚未实施',
        hint: 'ASS 要带一整套样式配置，留到第二期。先导出 SRT。',
      );
    }

    final dir = switch (options.outputLocation) {
      OutputLocation.custom =>
        options.outputDir?.trim().isNotEmpty == true
            ? options.outputDir!.trim()
            : File(task.sourcePath).parent.path,
      OutputLocation.besideSource => File(task.sourcePath).parent.path,
    };
    await Directory(dir).create(recursive: true);

    final stem = task.fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
    final written = <String>[];

    // 两路各按自己的语言折行：双语字幕的上下两行语种不同，用同一个上限
    // 必然有一边难看。
    String Function(String) wrapper(Language language) {
      final limit = language.cjk
          ? options.cjkLineLength
          : options.latinLineLength;
      return (text) => LineWrap.wrap(text, limit: limit, cjk: language.cjk);
    }

    final wrapSource = wrapper(task.sourceLanguage);
    final wrapTranslation = wrapper(task.targetLanguage);
    // 说话人标签跟着源语言走：中日韩「说话人1：」，其他「Speaker 1: 」；
    // 在编辑器里起过名字的写名字，关掉了标签就不写。
    final speakerLabel = task.document.speakerLabeler(task.sourceLanguage);

    Future<void> write(String tag, SrtField field) async {
      final content = switch (format) {
        SubtitleFormat.srt => Srt.serialize(
          task.document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.vtt => Srt.serializeVtt(
          task.document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.txt => Srt.serializePlain(
          task.document.cues,
          field: field,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.ass => '',
      };
      if (content.trim().isEmpty) return;

      final path = '$dir/$stem.$tag.${format.extension}';
      await File(path).writeAsString(content);
      written.add(path);
    }

    // 纯翻译任务的「原文」就是用户选的那个字幕文件，再写一份只是重复；
    // 转写任务则必须写出原文，那是识别的产物。
    if (task.kind != TaskKind.translate) {
      await write(_langTag(task.sourceLanguage), SrtField.source);
    }
    if (task.kind.needsTranslation) {
      final layout = options.resolvedBilingual;
      await write(
        layout.isBilingual
            // 双语产物带上两种语言，跟单语那份区分得开，也说明了里面有什么。
            ? '${_langTag(task.sourceLanguage)}-${_langTag(task.targetLanguage)}'
            : _langTag(task.targetLanguage),
        layout.field,
      );
    }
    return written;
  }

  // —— 转码 ————————————————————————————————————————————————————

  /// 准备：读源文件的流、核对容器兼容、定下产物路径与命令。
  Future<void> _prepareTranscode(
    SubtitleTask task,
    void Function() onChange,
  ) => _stage(task, TaskStage.prepare, onChange, () async {
    final job = task.transcode;
    if (job == null) {
      throw const ProviderException('转码任务缺少参数', hint: '删除这个任务后重新建。');
    }
    if (!File(task.sourcePath).existsSync()) {
      throw ProviderException(
        '源文件不存在',
        detail: task.sourcePath,
        hint: '文件可能已被移动或删除。重新选择文件。',
      );
    }
    final options = job.options;
    final problem = options.problem;
    if (problem != null) {
      throw ProviderException(problem, hint: '删除这个任务，改好参数后重新建。');
    }

    final probe = await transcoder.probe(task.sourcePath);
    task.mediaDuration = probe.duration;
    final v = probe.video.firstOrNull;
    final a = probe.audio.firstOrNull;
    job.sourceVideo = v == null ? null : MediaProbe.codecLabel(v.codec);
    job.sourceAudio = a == null ? null : MediaProbe.codecLabel(a.codec);

    final clash = probe.incompatibility(options);
    if (clash != null) {
      throw ProviderException(
        clash,
        hint: '把这一路改为重新编码，或换一个容器，然后从准备阶段继续。',
      );
    }
    if (probe.video.isEmpty) {
      task.note('源文件没有视频流，只处理音频', LogLevel.warn);
    }

    // 续跑沿用上次定下的路径（那里可能留着上次失败的半截文件，会被覆盖）。
    final output = job.outputPath ??= TranscodeCommand.outputPath(
      input: task.sourcePath,
      options: options,
      exists: (p) => File(p).existsSync(),
    );
    final args = TranscodeCommand.build(
      options: options,
      input: task.sourcePath,
      output: output,
      audioEncoder: transcoder.audioEncoder(options.effectiveAudio),
    );
    job.command = TranscodeCommand.display(args);
    task.stages[TaskStage.prepare] = task.stages[TaskStage.prepare]!.copyWith(
      note: 'ffprobe · ${probe.video.length + probe.audio.length} 路流',
    );
    task.note(
      '源文件：${[
        if (v != null) '${job.sourceVideo} ${v.shape}',
        if (a != null) '${job.sourceAudio} ${a.channels ?? '?'}ch',
        if (probe.duration != null) Srt.formatDuration(probe.duration!),
      ].join(' · ')}',
    );
    if (probe.subtitleCount > 0) {
      task.note('源文件里的 ${probe.subtitleCount} 路字幕不带入输出', LogLevel.warn);
    }
    task.note('输出：$output');
  });

  /// 转码：先写到 `.part` 临时文件，成功后改名，失败或取消删掉 ——
  /// 产物路径上只会出现完整的文件。
  Future<void> _transcode(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => _stage(task, TaskStage.transcode, onChange, () async {
    final job = task.transcode!;
    final output = job.outputPath!;
    final partial = '$output.part';
    final args = TranscodeCommand.build(
      options: job.options,
      input: task.sourcePath,
      output: partial,
      audioEncoder: transcoder.audioEncoder(job.options.effectiveAudio),
      progress: true,
    );
    final encoderId = job.encoder?.id ?? 'copy';
    task.progress = 0;
    job.speed = null;
    task.note('开始转码 · $encoderId');
    await Directory(File(output).parent.path).create(recursive: true);

    final started = DateTime.now();
    final total = task.mediaDuration;
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await transcoder.run(
        args: args,
        encoderId: encoderId,
        token: token,
        onProgress: (p) {
          job.speed = p.speed;
          if (total != null && total.inMilliseconds > 0) {
            task.progress = (p.position.inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0);
            final speed = p.speed;
            task.eta = speed != null && speed > 0
                ? Duration(
                    milliseconds:
                        ((total - p.position).inMilliseconds / speed).round(),
                  )
                : _estimate(
                    started,
                    p.position.inMilliseconds,
                    total.inMilliseconds,
                  );
          }
          task.stages[TaskStage.transcode] = task.stages[TaskStage.transcode]!
              .copyWith(
                note: [
                  if (p.frame != null) '帧 ${p.frame}',
                  if (p.speed != null) '${p.speed}x',
                ].join(' · '),
              );
          // 进度区块每 0.5 秒一个，界面与写盘不必每个都跟。
          final now = DateTime.now();
          if (p.done || now.difference(lastPaint).inMilliseconds >= 400) {
            lastPaint = now;
            onChange();
          }
        },
      );
      await File(partial).rename(output);
    } catch (_) {
      try {
        await File(partial).delete();
      } on FileSystemException {
        // 没生成过临时文件。
      }
      rethrow;
    } finally {
      // 失败或取消后重试时，别让上一次的速度残留在任务行上。
      job.speed = null;
    }
    task.progress = 1;
    task.eta = null;
  });

  Future<void> _finishTranscode(SubtitleTask task, void Function() onChange) =>
      _stage(task, TaskStage.finish, onChange, () async {
        final job = task.transcode!;
        final file = File(job.outputPath!);
        final size = file.existsSync() ? file.lengthSync() : 0;
        if (size == 0) {
          throw ProviderException(
            '产物为空',
            detail: job.outputPath,
            hint: '源文件可能没有可用的音视频流。从转码阶段继续重试一次。',
          );
        }
        job.outputBytes = size;
        task.stages[TaskStage.finish] = task.stages[TaskStage.finish]!.copyWith(
          note: MediaFileInfo(path: file.path, sizeBytes: size).sizeLabel,
        );
        task.note('已写出 ${job.outputPath}');
      });

  /// 剩余时间估算：按已完成条目的平均耗时外推。
  static Duration? _estimate(DateTime started, int done, int total) {
    if (done == 0) return null;
    final elapsed = DateTime.now().difference(started);
    final perItem = elapsed.inMilliseconds / done;
    return Duration(milliseconds: (perItem * (total - done)).round());
  }

  /// 产物文件名里的语言标签：`demo.zh.srt`。
  ///
  /// 用语言代码而不是中文名 —— 中文名带不进跨平台安全的文件名。
  static String _langTag(Language language) => language.isAuto
      ? 'src'
      : language.code.replaceAll(RegExp(r'[^\w-]+'), '_');
}
