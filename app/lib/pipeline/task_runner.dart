import 'dart:convert';
import 'dart:io';

import '../domain/cue.dart';
import '../domain/segmenter.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_options.dart';
import '../services/media.dart';
import '../services/provider_api.dart';
import '../services/registry.dart';
import '../services/settings.dart';
import '../services/transcoder.dart';
import 'subtitle_output_writer.dart';
import 'task_progress.dart';
import 'task_stage_runner.dart';
import 'transcode_task_pipeline.dart';

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

  final TaskStageRunner _stages = const TaskStageRunner();

  late final TranscodeTaskPipeline _transcodePipeline =
      TranscodeTaskPipeline(transcoder: transcoder, stages: _stages);

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
      await _stages.run(task, TaskStage.queued, onChange, () async {});
      if (task.kind == TaskKind.transcode) {
        await _transcodePipeline.prepare(task, onChange);
        await _transcodePipeline.run(task, token, onChange);
        await _transcodePipeline.finish(task, onChange);
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

  /// 写出字幕产物。保留在 TaskRunner 上作为队列与测试的稳定入口。
  Future<List<String>> writeOutputs(SubtitleTask task) =>
      SubtitleOutputWriter.write(task);

  void _markCurrent(SubtitleTask task, StageState state, String note) {
    task.stages[task.stage] = task.stages[task.stage]!.copyWith(
      state: state,
      note: note,
    );
  }

  Future<void> _prepare(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => _stages.run(task, TaskStage.prepare, onChange, () async {
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
  ) => _stages.run(
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
  Future<void> _segment(SubtitleTask task, void Function() onChange) => _stages.run(
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
  ) => _stages.run(
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
        task.eta = estimateRemaining(started, cursor, pending.length);
        task.stages[TaskStage.translate] = task.stages[TaskStage.translate]!
            .copyWith(note: '第 $cursor / ${pending.length} 条');
        onChange();
      }

      task.note('翻译完成 ${pending.length} 条');
    },
  );

  Future<void> _finish(SubtitleTask task, void Function() onChange) =>
      _stages.run(task, TaskStage.finish, onChange, () async {
        final outputs = await writeOutputs(task);
        // 产物按完成这一刻的文档写出，编辑器里之前改的也都在里面了。
        task.unsyncedEdits = 0;
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

}
