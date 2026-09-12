import 'dart:io';

import '../domain/cue.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../services/media.dart';
import '../services/provider_api.dart';
import '../services/registry.dart';
import '../services/settings.dart';

/// 把一个任务跑完，或者在中途安全地停下来。
///
/// 核心承诺：**失败与取消都保留已完成阶段的结果**，重试时从 [SubtitleTask.resumeStage]
/// 继续，不重做已经花过钱和时间的阶段。界面上向用户明确承诺了这件事。
class TaskRunner {
  TaskRunner({
    required this.settings,
    required this.workDir,
    Media? media,
    AsrProvider Function(String, AppSettings)? asrFactory,
    TranslationProvider Function(String, AppSettings)? translationFactory,
  }) : media = media ?? Media(),
       _asrFactory = asrFactory ?? Registry.buildAsr,
       _translationFactory = translationFactory ?? Registry.buildTranslation;

  final AppSettings settings;

  /// 每个任务的中间产物目录（抽出的音频、阶段快照）。
  final String workDir;

  final Media media;
  final AsrProvider Function(String, AppSettings) _asrFactory;
  final TranslationProvider Function(String, AppSettings) _translationFactory;

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
      await _prepare(task, token, onChange);
      await _recognize(task, token, onChange);
      await _segment(task, onChange);
      await _translate(task, token, onChange);
      await _finish(task, onChange);

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
    if (task.kind == TaskKind.translate) {
      // 输入本来就是字幕，解析出来即可。
      final text = await File(task.sourcePath).readAsString();
      final cues = Srt.parse(text);
      if (cues.isEmpty) {
        throw const ProviderException(
          '字幕文件里没有可用的条目',
          hint: '确认文件是 SRT / VTT 且时间码格式正确。',
        );
      }
      task.document = SubtitleDocument(
        cues: cues,
        sourceLanguage: task.sourceLanguage,
        targetLanguage: task.targetLanguage,
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
      final provider = _asrFactory(task.asrProviderId, settings);
      final cues = await provider.transcribe(
        audioPath: '$workDir/${task.id}.wav',
        language: task.sourceLanguage,
        token: token,
        onProgress: (done, total, {note}) {
          task.progress = total == 0 ? 0 : done / total;
          task.stages[TaskStage.recognize] =
              task.stages[TaskStage.recognize]!.copyWith(note: note);
          onChange();
        },
      );

      task.document = SubtitleDocument(
        cues: cues,
        sourceLanguage: task.sourceLanguage,
        targetLanguage: task.targetLanguage,
      );

      final low = cues.where((c) => (c.confidence ?? 1) < Cue.lowConfidence).length;
      task.stages[TaskStage.recognize] = task.stages[TaskStage.recognize]!
          .copyWith(note: '${provider.info.name} · ${cues.length} 段');
      task.note('识别完成 ${cues.length} 段');
      if (low > 0) {
        task.note('$low 段置信度低于 ${Cue.lowConfidence}，已标记待校对', LogLevel.warn);
      }
    },
  );

  /// 断句：合并过短的分段，避免字幕闪一下就过去。
  Future<void> _segment(SubtitleTask task, void Function() onChange) => _stage(
    task,
    TaskStage.segment,
    onChange,
    skip: !task.kind.needsRecognition,
    () async {
      const minDurationMs = 500;
      final cues = task.document.cues;
      final merged = <Cue>[];
      var joined = 0;

      for (final cue in cues) {
        final last = merged.isEmpty ? null : merged.last;
        // 过短且与上一条紧邻时并进去；相隔较远说明是独立的短应答，保留。
        if (last != null &&
            cue.durationMs < minDurationMs &&
            cue.startMs - last.endMs < 200) {
          merged[merged.length - 1] = last.copyWith(
            endMs: cue.endMs,
            source: '${last.source}${_join(task.sourceLanguage)}${cue.source}',
          );
          joined++;
        } else {
          merged.add(cue.copyWith(index: merged.length + 1));
        }
      }

      task.document = task.document.copyWith(cues: merged);
      task.stages[TaskStage.segment] = task.stages[TaskStage.segment]!
          .copyWith(note: '${merged.length} 条');
      task.note('断句完成，合并短句 $joined 处');
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
      );
      final cues = [...task.document.cues];
      final started = DateTime.now();

      // 已有译文的跳过 —— 这就是翻译阶段的断点续跑。
      final pending = [
        for (final (i, c) in cues.indexed)
          if (!c.hasTranslation) i,
      ];

      if (pending.isEmpty) {
        task.note('全部条目已有译文，跳过翻译');
        return;
      }

      task.note(
        '翻译开始 · ${provider.info.name} · 批大小 ${settings.translationBatchSize}',
      );

      var cursor = 0;
      var batchSize = settings.translationBatchSize;
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
            sourceLanguage: task.sourceLanguage,
            targetLanguage: task.targetLanguage,
            token: token,
          );
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
      });

  /// 写出 SRT 产物。返回实际写出的路径。
  Future<List<String>> writeOutputs(SubtitleTask task) async {
    final dir = settings.outputDir ?? File(task.sourcePath).parent.path;
    final stem = task.fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
    final written = <String>[];

    Future<void> write(String suffix, SrtField field) async {
      final content = Srt.serialize(task.document.cues, field: field);
      if (content.trim().isEmpty) return;
      final path = '$dir/$stem.$suffix.srt';
      await File(path).writeAsString(content);
      written.add(path);
    }

    await write(_langTag(task.sourceLanguage), SrtField.source);
    if (task.kind.needsTranslation) {
      await write(_langTag(task.targetLanguage), SrtField.translation);
    }
    return written;
  }

  /// 剩余时间估算：按已完成条目的平均耗时外推。
  static Duration? _estimate(DateTime started, int done, int total) {
    if (done == 0) return null;
    final elapsed = DateTime.now().difference(started);
    final perItem = elapsed.inMilliseconds / done;
    return Duration(milliseconds: (perItem * (total - done)).round());
  }

  /// 中日韩等语言词间不加空格。
  static String _join(String language) =>
      _cjk.any(language.toLowerCase().startsWith) ? '' : ' ';

  static const _cjk = ['zh', 'ja', 'ko', 'yue', 'th', 'km'];

  static String _langTag(String language) {
    final trimmed = language.trim();
    if (trimmed.isEmpty || trimmed == 'auto') return 'src';
    // 文件名里不要出现路径分隔符与空格。
    return trimmed.replaceAll(RegExp(r'[\\/\s]+'), '_');
  }
}
