import '../enum_by_name.dart';
import '../paths.dart';
import '../task_options.dart';
import '../transcode/codecs.dart';

/// 合并里的一段：一个视频，可选挂一个字幕，一个章节标题。
class MergeSegment {
  const MergeSegment({
    required this.videoPath,
    this.subtitlePath,
    required this.chapterTitle,
  });

  final String videoPath;

  /// SRT / VTT。没挂时这一段不出字幕，但时长照算，后面各段照样平移。
  final String? subtitlePath;

  final String chapterTitle;

  /// 默认章节标题：文件名去扩展名。
  static String defaultTitle(String videoPath) => stemOf(baseName(videoPath));

  Map<String, Object?> toJson() => {
    'videoPath': videoPath,
    'subtitlePath': ?subtitlePath,
    'chapterTitle': chapterTitle,
  };

  /// 缺视频路径的段没法用，返回 null 由调用方丢掉。
  static MergeSegment? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final video = raw['videoPath'];
    if (video is! String || video.isEmpty) return null;
    final sub = raw['subtitlePath'];
    final title = raw['chapterTitle'];
    return MergeSegment(
      videoPath: video,
      subtitlePath: sub is String && sub.isNotEmpty ? sub : null,
      chapterTitle: title is String && title.trim().isNotEmpty
          ? title
          : defaultTitle(video),
    );
  }
}

/// 把几段视频按顺序拼成一个文件的全部参数，入队那一刻定死。
///
/// 只做 `-c copy` 拼接，没有任何编码参数。以后加 mkv 输出时，在
/// [containers] 里加一项、补 `OutputContainer` 的名单即可；重混流另起
/// `RemuxOptions`，与这里共用 `MuxPlan`。
class MergeOptions {
  const MergeOptions({
    this.segments = const [],
    this.container = OutputContainer.mp4,
    this.chapters = true,
    this.embedSubtitles = true,
    this.sidecarSubtitles = false,
    this.outputLocation = OutputLocation.besideSource,
    this.outputDir,
    this.outputStem = '',
  });

  /// 有序，至少两段。第 1 段是参数基准。
  final List<MergeSegment> segments;

  final OutputContainer container;

  /// 每段一个章节，起点是前面各段时长之和。
  final bool chapters;

  /// 各段字幕平移后拼成一条软字幕轨写进视频。
  final bool embedSubtitles;

  /// 在视频旁另写一份合并后的 SRT。
  final bool sidecarSubtitles;

  /// 默认与第 1 段同目录。
  final OutputLocation outputLocation;
  final String? outputDir;

  /// 产物文件名（不含扩展名）。默认见 [defaultStem]。
  final String outputStem;

  /// 本期能选的容器。mp4 / mov 的字幕都是 mov_text。
  static const containers = [OutputContainer.mp4, OutputContainer.mov];

  /// 默认产物文件名：`<第 1 段文件名>.merged`。
  static String defaultStem(String firstVideo) =>
      '${stemOf(baseName(firstVideo))}.merged';

  /// 不用探测就知道不行的问题。null 表示没问题。
  String? get problem {
    if (segments.length < 2) return '至少要 2 段才能合并';
    if (!containers.contains(container)) return '合并不支持 ${container.label}';
    final stem = outputStem.trim();
    if (stem.isEmpty) return '文件名不能为空';
    if (stem.contains(RegExp(r'[/\\]'))) return '文件名里不能有 / 或 \\';
    if (outputLocation == OutputLocation.custom &&
        (outputDir?.trim().isEmpty ?? true)) {
      return '还没有选择输出目录';
    }
    return null;
  }

  /// 产物所在目录：指定目录，或第 1 段所在目录。
  String? get resolvedDir {
    if (outputLocation == OutputLocation.custom &&
        (outputDir?.trim().isNotEmpty ?? false)) {
      return outputDir!.trim().replaceAll(RegExp(r'[/\\]+$'), '');
    }
    return segments.isEmpty ? null : dirName(segments.first.videoPath);
  }

  Map<String, Object?> toJson() => {
    'segments': [for (final s in segments) s.toJson()],
    'container': container.name,
    'chapters': chapters,
    'embedSubtitles': embedSubtitles,
    'sidecarSubtitles': sidecarSubtitles,
    'outputLocation': outputLocation.name,
    'outputDir': outputDir,
    'outputStem': outputStem,
  };

  /// 缺项、类型不对、不认识的容器都回落到默认，不因为一份旧存档抛异常。
  factory MergeOptions.fromJson(Map<String, Object?> json) {
    T? pick<T>(String key) => json[key] is T ? json[key] as T : null;
    final segments = [
      for (final raw in pick<List>('segments') ?? const [])
        ?MergeSegment.tryFromJson(raw),
    ];
    final container = switch (OutputContainer.values.tryByName(
      json['container'],
    )) {
      final c? when containers.contains(c) => c,
      _ => OutputContainer.mp4,
    };
    final location =
        OutputLocation.values.tryByName(json['outputLocation']) ??
        OutputLocation.besideSource;
    final dir = pick<String>('outputDir');
    final stem = pick<String>('outputStem');
    return MergeOptions(
      segments: segments,
      container: container,
      chapters: pick<bool>('chapters') ?? true,
      embedSubtitles: pick<bool>('embedSubtitles') ?? true,
      sidecarSubtitles: pick<bool>('sidecarSubtitles') ?? false,
      outputLocation: location == OutputLocation.custom && dir == null
          ? OutputLocation.besideSource
          : location,
      outputDir: dir,
      outputStem: stem != null && stem.trim().isNotEmpty
          ? stem
          : segments.isEmpty
          ? ''
          : defaultStem(segments.first.videoPath),
    );
  }

  static const _unset = Object();

  MergeOptions copyWith({
    List<MergeSegment>? segments,
    OutputContainer? container,
    bool? chapters,
    bool? embedSubtitles,
    bool? sidecarSubtitles,
    OutputLocation? outputLocation,
    Object? outputDir = _unset,
    String? outputStem,
  }) => MergeOptions(
    segments: segments ?? this.segments,
    container: container ?? this.container,
    chapters: chapters ?? this.chapters,
    embedSubtitles: embedSubtitles ?? this.embedSubtitles,
    sidecarSubtitles: sidecarSubtitles ?? this.sidecarSubtitles,
    outputLocation: outputLocation ?? this.outputLocation,
    outputDir: identical(outputDir, _unset)
        ? this.outputDir
        : outputDir as String?,
    outputStem: outputStem ?? this.outputStem,
  );
}
