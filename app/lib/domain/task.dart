import 'cue.dart';
import 'language.dart';
import 'recognition_checkpoint.dart';
import 'task_options.dart';
import 'transcode/command.dart';

/// 流水线的阶段，顺序固定。每种任务只走其中一部分（见 [TaskKind.stages]），
/// 界面上的阶段条画的就是那一部分。
enum TaskStage {
  queued('排队'),
  prepare('准备'),
  recognize('识别'),
  segment('断句'),
  translate('翻译'),
  transcode('转码'),
  finish('完成');

  const TaskStage(this.label);

  final String label;
}

/// 单个阶段的结果。
enum StageState { pending, active, done, failed, cancelled, skipped }

class StageRecord {
  const StageRecord({
    this.state = StageState.pending,
    this.duration,
    this.note,
  });

  final StageState state;
  final Duration? duration;

  /// 补充说明：「1,284 条」「第 809 / 1,284 条」「未选择翻译」。
  final String? note;

  StageRecord copyWith({
    StageState? state,
    Duration? duration,
    String? note,
    bool clearNote = false,
  }) => StageRecord(
    state: state ?? this.state,
    duration: duration ?? this.duration,
    note: clearNote ? null : (note ?? this.note),
  );

  Map<String, Object?> toJson() => {
    'state': state.name,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (note != null) 'note': note,
  };

  factory StageRecord.fromJson(Map<String, Object?> json) => StageRecord(
    state: StageState.values.byName(json['state']! as String),
    duration: json['durationMs'] == null
        ? null
        : Duration(milliseconds: json['durationMs']! as int),
    note: json['note'] as String?,
  );
}

enum TaskStatus { queued, running, paused, done, failed, cancelled }

enum TaskKind {
  /// 音视频 → 原文字幕。
  transcribe('转写'),

  /// 音视频 → 原文字幕 → 译文字幕。
  transcribeAndTranslate('转写并翻译'),

  /// 已有字幕 → 译文字幕。
  translate('翻译'),

  /// 视频 → 另一种编码或容器的视频。FFmpeg 跑，不产字幕。
  transcode('转码');

  const TaskKind(this.label);

  final String label;

  bool get needsRecognition =>
      this == TaskKind.transcribe || this == TaskKind.transcribeAndTranslate;
  bool get needsTranslation =>
      this == TaskKind.transcribeAndTranslate || this == TaskKind.translate;

  /// 这种任务走的阶段。字幕任务是固定的六段（不需要的那段记为跳过，
  /// 阶段条上画成虚线）；转码只有四段。
  List<TaskStage> get stages => this == TaskKind.transcode
      ? const [
          TaskStage.queued,
          TaskStage.prepare,
          TaskStage.transcode,
          TaskStage.finish,
        ]
      : const [
          TaskStage.queued,
          TaskStage.prepare,
          TaskStage.recognize,
          TaskStage.segment,
          TaskStage.translate,
          TaskStage.finish,
        ];
}

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'level': level.name,
    'message': message,
  };

  static LogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse(raw['time'] as String? ?? '');
    final level = LogLevel.values
        .where((l) => l.name == raw['level'])
        .firstOrNull;
    final message = raw['message'];
    if (time == null || level == null || message is! String) return null;
    return LogEntry(time, level, message);
  }

  String get clock =>
      '${_p(time.hour)}:${_p(time.minute)}:${_p(time.second)}';

  static String _p(int v) => v.toString().padLeft(2, '0');
}

/// 任务产物。
class TaskOutput {
  const TaskOutput({
    required this.name,
    required this.meta,
    this.path,
    this.ready = false,
  });

  final String name;

  /// 右侧灰字：文件名与大小，或「生成中 · 63%」「未选择翻译」。
  final String meta;
  final String? path;
  final bool ready;
}

/// 一个可断点续跑的任务。
///
/// 失败或取消时**保留已完成阶段的结果**，重试从中断处继续 —— 这是
/// 原 Python 实现最被依赖的行为，界面上也明确向用户承诺了。
class SubtitleTask {
  SubtitleTask({
    required this.id,
    required this.sourcePath,
    required this.kind,
    required this.options,
    this.status = TaskStatus.queued,
    this.stage = TaskStage.queued,
    Map<TaskStage, StageRecord>? stages,
    this.progress = 0,
    this.document = SubtitleDocument.empty,
    List<LogEntry>? log,
    this.error,
    this.mediaDuration,
    this.eta,
    this.transcode,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       stages = stages ?? {for (final s in TaskStage.values) s: const StageRecord()},
       log = log ?? [];

  final String id;
  final String sourcePath;
  final TaskKind kind;

  /// 入队时间。持久化后恢复时按它排出列表顺序（新的在前）。
  final DateTime createdAt;

  /// 入队那一刻定死的全部参数。之后用户改设置不影响已排队的任务。
  final TaskOptions options;

  /// provider 的注册 id。本地后端只是其中一个 id，客户端不分「本地 / 在线」两条路径。
  String get asrProviderId => options.asrProviderId;
  String get translationProviderId => options.translationProviderId;

  Language get sourceLanguage => options.sourceLanguage;
  Language get targetLanguage => options.targetLanguage;

  TaskStatus status;
  TaskStage stage;
  final Map<TaskStage, StageRecord> stages;

  /// 0..1，当前阶段内的整体完成度。
  double progress;

  SubtitleDocument document;
  final List<LogEntry> log;
  TaskError? error;

  /// 识别阶段的分段检查点。失败或取消时保留，续跑只重试没完成的段；
  /// 准备阶段重跑（音频重新抽取）或识别完成后清掉。
  RecognitionCheckpoint? recognition;
  Duration? mediaDuration;
  Duration? eta;

  /// 转码任务的参数与产物；字幕任务为 null。[options] 对转码任务无意义。
  final TranscodeJob? transcode;

  /// 同时兼容 POSIX 与 Windows 分隔符。
  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  bool get isActive =>
      status == TaskStatus.running || status == TaskStatus.queued;

  /// 可以从哪个阶段续跑：第一个未完成（且未跳过）的阶段。
  TaskStage get resumeStage {
    for (final s in kind.stages) {
      final st = stages[s]!.state;
      if (st != StageState.done && st != StageState.skipped) return s;
    }
    return TaskStage.finish;
  }

  /// 持久化用。[eta] 是运行时估算，不存。
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'sourcePath': sourcePath,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'options': options.toJson(),
    'status': status.name,
    'stage': stage.name,
    'stages': {for (final e in stages.entries) e.key.name: e.value.toJson()},
    'progress': progress,
    'document': document.toJson(),
    'log': [for (final l in log) l.toJson()],
    if (error != null) 'error': error!.toJson(),
    if (recognition != null) 'recognition': recognition!.toJson(),
    if (mediaDuration != null) 'mediaDurationMs': mediaDuration!.inMilliseconds,
    if (transcode != null) 'transcode': transcode!.toJson(),
  };

  /// 从存档读回。参数缺项回落到 [fallbackOptions]；未知的阶段 / 状态名按
  /// 待执行处理，不因为一份旧存档抛异常。缺 id 或源文件路径的存档无法使用，
  /// 抛 [FormatException] 由调用方跳过。
  factory SubtitleTask.fromJson(
    Map<String, Object?> json, {
    required TaskOptions fallbackOptions,
  }) {
    final id = json['id'];
    final sourcePath = json['sourcePath'];
    if (id is! String || sourcePath is! String) {
      throw const FormatException('任务存档缺少 id 或 sourcePath');
    }
    T byName<T extends Enum>(List<T> values, Object? name, T orElse) =>
        values.where((v) => v.name == name).firstOrNull ?? orElse;
    Map<String, Object?>? map(Object? v) =>
        v is Map ? v.cast<String, Object?>() : null;

    final rawStages = map(json['stages']) ?? const {};
    final task = SubtitleTask(
      id: id,
      sourcePath: sourcePath,
      kind: byName(TaskKind.values, json['kind'], TaskKind.transcribe),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      options: TaskOptions.fromJson(
        map(json['options']) ?? const {},
        fallback: fallbackOptions,
      ),
      status: byName(TaskStatus.values, json['status'], TaskStatus.paused),
      stage: byName(TaskStage.values, json['stage'], TaskStage.queued),
      stages: {
        for (final s in TaskStage.values)
          s: switch (map(rawStages[s.name])) {
            final m? => StageRecord.fromJson(m),
            null => const StageRecord(),
          },
      },
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      document: switch (map(json['document'])) {
        final m? => SubtitleDocument.fromJson(m),
        null => SubtitleDocument.empty,
      },
      log: [
        for (final raw in json['log'] as List? ?? const [])
          ?LogEntry.fromJson(raw),
      ],
      error: switch (map(json['error'])) {
        final m? => TaskError.fromJson(m),
        null => null,
      },
      mediaDuration: switch (json['mediaDurationMs']) {
        final int ms => Duration(milliseconds: ms),
        _ => null,
      },
      transcode: switch (map(json['transcode'])) {
        final m? => TranscodeJob.fromJson(m),
        null => null,
      },
    );
    task.recognition = switch (map(json['recognition'])) {
      final m? => RecognitionCheckpoint.fromJson(m),
      null => null,
    };
    return task;
  }

  void note(String message, [LogLevel level = LogLevel.info]) =>
      log.add(LogEntry(DateTime.now(), level, message));

  /// 界面上阶段一行的文案，规则来自设计稿。
  String get stageLabel => switch (status) {
    TaskStatus.running when transcode?.speed != null &&
        stage == TaskStage.transcode =>
      '${stage.label} · ${transcode!.speed}x',
    TaskStatus.running => stage.label,
    TaskStatus.queued => '排队中',
    TaskStatus.paused => '已暂停 · ${stage.label}',
    TaskStatus.done =>
      document.reviewCount > 0 ? '完成 · 待校对 ${document.reviewCount}' : '完成',
    TaskStatus.failed => '失败 · ${stage.label}阶段',
    TaskStatus.cancelled =>
      '已取消 · ${stage.label} ${(progress * 100).round()}%',
  };

  String get percentLabel =>
      switch (status) {
        TaskStatus.done => '100%',
        TaskStatus.queued || TaskStatus.failed => '—',
        _ => '${(progress * 100).round()}%',
      };
}

/// 结构化的失败信息。设计规范要求错误必须给出可行动信息。
class TaskError {
  const TaskError({
    required this.title,
    required this.detail,
    required this.hint,
    this.primaryAction,
  });

  /// 一句话说明发生了什么：「模型文件校验不通过」「云端超时」。
  final String title;

  /// 原始报错，等宽显示，可复制。
  final String detail;

  /// 建议用户做什么。
  final String hint;

  /// 主按钮文案，null 表示只提供「从 X 阶段继续」。
  final String? primaryAction;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'hint': hint,
    if (primaryAction != null) 'primaryAction': primaryAction,
  };

  factory TaskError.fromJson(Map<String, Object?> json) => TaskError(
    title: json['title'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    hint: json['hint'] as String? ?? '',
    primaryAction: json['primaryAction'] as String?,
  );
}
