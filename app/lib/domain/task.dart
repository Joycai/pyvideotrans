import 'cue.dart';

/// 流水线的六个阶段，顺序固定。界面上的阶段条就是这六段。
enum TaskStage {
  queued('排队'),
  prepare('准备'),
  recognize('识别'),
  segment('断句'),
  translate('翻译'),
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
  translate('翻译');

  const TaskKind(this.label);

  final String label;

  bool get needsRecognition => this != TaskKind.translate;
  bool get needsTranslation => this != TaskKind.transcribe;
}

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

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
    required this.asrProviderId,
    required this.translationProviderId,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.status = TaskStatus.queued,
    this.stage = TaskStage.queued,
    Map<TaskStage, StageRecord>? stages,
    this.progress = 0,
    this.document = SubtitleDocument.empty,
    List<LogEntry>? log,
    this.error,
    this.mediaDuration,
    this.eta,
  }) : stages = stages ?? {for (final s in TaskStage.values) s: const StageRecord()},
       log = log ?? [];

  final String id;
  final String sourcePath;
  final TaskKind kind;

  /// provider 的注册 id。本地后端只是其中一个 id，客户端不分「本地 / 在线」两条路径。
  final String asrProviderId;
  final String translationProviderId;

  final String sourceLanguage;
  final String targetLanguage;

  TaskStatus status;
  TaskStage stage;
  final Map<TaskStage, StageRecord> stages;

  /// 0..1，当前阶段内的整体完成度。
  double progress;

  SubtitleDocument document;
  final List<LogEntry> log;
  TaskError? error;
  Duration? mediaDuration;
  Duration? eta;

  /// 同时兼容 POSIX 与 Windows 分隔符。
  String get fileName => sourcePath.split(RegExp(r'[/\\]')).last;

  bool get isActive =>
      status == TaskStatus.running || status == TaskStatus.queued;

  /// 可以从哪个阶段续跑：第一个未完成（且未跳过）的阶段。
  TaskStage get resumeStage {
    for (final s in TaskStage.values) {
      final st = stages[s]!.state;
      if (st != StageState.done && st != StageState.skipped) return s;
    }
    return TaskStage.finish;
  }

  void note(String message, [LogLevel level = LogLevel.info]) =>
      log.add(LogEntry(DateTime.now(), level, message));

  /// 界面上阶段一行的文案，规则来自设计稿。
  String get stageLabel => switch (status) {
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
}
