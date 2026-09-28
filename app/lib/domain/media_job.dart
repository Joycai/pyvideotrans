import 'mux/merge_options.dart';
import 'paths.dart';
import 'task_kind.dart';
import 'transcode/codecs.dart';
import 'transcode/encoder_params.dart';
import 'transcode/options.dart';

/// 产出一个媒体文件、不产字幕的任务挂在 `SubtitleTask.media` 上的状态。
///
/// 为什么是 sealed：任务列表、详情、队列、执行分派都要区分「字幕任务 / 哪种
/// 媒体任务」。只用得着通用信息的（产物、命令、倍速、定位）走下面的接口；
/// 要按种类画不同界面的写 `switch (task.media)`，以后加重混流等新种类时，
/// 编译器会在每个 switch 处提示补分支，不会漏改某一处。
///
/// 子类必须和它在同一个库里（sealed 的要求），所以各种 Job 都写在这个文件。
sealed class MediaJob {
  /// 任务行 / 详情头第二行：「HEVC → MP4」。
  String get summary;

  /// 任务行的主名字；null 时用源文件名。
  String? get title;

  /// 产物还没定下时的占位：「视频 · MP4」。
  String get outputLabel;

  /// 准备阶段定下。续跑沿用同一个路径，不会越跑越多 `-2`、`-3`。
  String? get outputPath;

  /// 实际执行的命令（给人看的形式），详情面板里可复制。
  String? get command;

  /// 完成后的产物大小。
  int? get outputBytes;

  /// 跑 ffmpeg 时的倍速，运行时状态，不存。
  double? get speed;

  /// 跑 ffmpeg 的那一段，任务行里显示成「转码 · 2.4x」。
  TaskStage get workStage;

  Map<String, Object?> toJson();

  /// 存进任务 JSON 时用的键。沿用改名前的 `'transcode'`，旧存档不用迁移，
  /// 降级回旧版本也能读回转码任务。
  String get jsonKey => switch (this) {
    TranscodeJob() => 'transcode',
    MergeJob() => 'merge',
  };

  /// 从任务 JSON 里读回：哪个键在就是哪种。都不在时是字幕任务。
  static MediaJob? fromTaskJson(Map<String, Object?> task) {
    if (task['transcode'] case final Map m) {
      return TranscodeJob.fromJson(m.cast<String, Object?>());
    }
    if (task['merge'] case final Map m) {
      return MergeJob.fromJson(m.cast<String, Object?>());
    }
    return null;
  }
}

/// 挂在转码任务上的状态：参数、准备阶段读出的源信息、定下来的产物路径与命令。
final class TranscodeJob extends MediaJob {
  TranscodeJob({
    required this.options,
    this.sourceVideo,
    this.sourceAudio,
    this.outputPath,
    this.command,
    this.outputBytes,
  });

  final TranscodeOptions options;

  /// 「HEVC」「3840×2160 · 60p」这类摘要，准备阶段填。
  String? sourceVideo;
  String? sourceAudio;

  @override
  String? outputPath;

  @override
  String? command;

  @override
  int? outputBytes;

  @override
  double? speed;

  /// 「HEVC → MP4」：源视频编码 → 目标。
  @override
  String get summary {
    final target = options.remux
        ? options.container.label
        : options.effectiveVideo == VideoCodec.copy
        ? options.container.label
        : '${options.videoCodec.label} · ${options.container.label}';
    return '${sourceVideo ?? '视频'} → $target';
  }

  /// 转码任务就叫源文件名。
  @override
  String? get title => null;

  @override
  String get outputLabel => '视频 · ${options.container.label}';

  @override
  TaskStage get workStage => TaskStage.transcode;

  /// 用的是哪个编码器；复制视频时为 null。
  VideoEncoder? get encoder =>
      options.effectiveVideo == VideoCodec.copy ? null : options.encoder;

  @override
  Map<String, Object?> toJson() => {
    'options': options.toJson(),
    'sourceVideo': sourceVideo,
    'sourceAudio': sourceAudio,
    'outputPath': outputPath,
    'command': command,
    'outputBytes': outputBytes,
  };

  factory TranscodeJob.fromJson(Map<String, Object?> json) => TranscodeJob(
    options: TranscodeOptions.fromJson(
      (json['options'] as Map? ?? const {}).cast<String, Object?>(),
    ),
    sourceVideo: json['sourceVideo'] as String?,
    sourceAudio: json['sourceAudio'] as String?,
    outputPath: json['outputPath'] as String?,
    command: json['command'] as String?,
    outputBytes: json['outputBytes'] as int?,
  );
}

/// 挂在合并任务上的状态：入队时定死的参数，准备阶段读出的各段时长与字幕条数，
/// 定下来的产物路径与命令。
final class MergeJob extends MediaJob {
  MergeJob({
    required this.options,
    this.segmentDurations,
    this.segmentCues,
    this.outputPath,
    this.sidecarPath,
    this.command,
    this.outputBytes,
  });

  final MergeOptions options;

  /// 各段时长，准备阶段探测填；续跑时重新探测（入队后文件可能被换）。
  List<Duration>? segmentDurations;

  /// 各段字幕条数，没挂字幕的段为 null。准备阶段读字幕时填。
  List<int?>? segmentCues;

  @override
  String? outputPath;

  /// 开了旁挂 SRT 且有字幕时的字幕产物路径，与 [outputPath] 一起定下。
  String? sidecarPath;

  @override
  String? command;

  @override
  int? outputBytes;

  @override
  double? speed;

  int get segmentCount => options.segments.length;

  /// 「3 段 → MP4」。
  @override
  String get summary => '$segmentCount 段 → ${options.container.label}';

  /// 产物定下前叫「a.mp4 等 3 段」，之后就是产物文件名。
  @override
  String get title => switch (outputPath) {
    final path? => baseName(path),
    null when options.segments.isEmpty => '合并',
    null =>
      '${baseName(options.segments.first.videoPath)} 等 $segmentCount 段',
  };

  @override
  String get outputLabel => '视频 · ${options.container.label}';

  @override
  TaskStage get workStage => TaskStage.merge;

  @override
  Map<String, Object?> toJson() => {
    'options': options.toJson(),
    if (segmentDurations case final d?)
      'segmentDurationsMs': [for (final x in d) x.inMilliseconds],
    'segmentCues': ?segmentCues,
    'outputPath': outputPath,
    'sidecarPath': sidecarPath,
    'command': command,
    'outputBytes': outputBytes,
  };

  factory MergeJob.fromJson(Map<String, Object?> json) {
    final options = MergeOptions.fromJson(
      (json['options'] as Map? ?? const {}).cast<String, Object?>(),
    );
    final n = options.segments.length;
    // 段数对不上的缓存值作废，准备阶段会重新填。
    final durations = switch (json['segmentDurationsMs']) {
      final List l when l.length == n && l.every((x) => x is int) => [
        for (final x in l) Duration(milliseconds: x as int),
      ],
      _ => null,
    };
    final cues = switch (json['segmentCues']) {
      final List l when l.length == n && l.every((x) => x == null || x is int) =>
        l.cast<int?>(),
      _ => null,
    };
    return MergeJob(
      options: options,
      segmentDurations: durations,
      segmentCues: cues,
      outputPath: json['outputPath'] as String?,
      sidecarPath: json['sidecarPath'] as String?,
      command: json['command'] as String?,
      outputBytes: json['outputBytes'] as int?,
    );
  }
}
