// 合并的纯规则。页面（开始前校验、命令预览）与流水线（准备阶段二次把关、
// 真正写文件）用同一份，两边不可能判得不一样。
//
// 偏移是核心：concat 列表的 `duration`、章节起点、字幕平移都用 [offsets] 算出的
// 同一份数，三者不可能对不上。

import '../cue.dart';
import '../paths.dart';
import '../transcode/codecs.dart';
import '../transcode/probe.dart';
import 'merge_options.dart';

/// 一段的问题出在哪一类，界面据此把对应那一列标红。
enum MergeIssueKind {
  /// 视频 / 音频流的路数与第 1 段不同。
  streams,
  video,
  audio,

  /// 这种编码不能原样放进所选容器。
  container,

  /// 读不出时长，算不出后面各段的起点。
  duration,
}

/// 一段不能参与拼接的原因。只报第一处：用户改好一处再看下一处。
class MergeIssue {
  const MergeIssue(this.kind, this.message, {this.field, this.expected});

  final MergeIssueKind kind;

  /// 写在该段下面的一句：「分辨率 1280×720 ≠ 第 1 段 1920×1080」。
  final String message;

  /// 与第 1 段不一致的那一项：「分辨率」。不是「与第 1 段不一致」类的问题为 null。
  final String? field;

  /// 第 1 段的值：「1920×1080」。页脚据此提示「先用转码转成 …」。
  final String? expected;

  @override
  String toString() => message;
}

/// 逐段与第 1 段比对，返回每段的问题（null = 可以拼）。
///
/// [probes] 里 null 表示那段还没探测完，结果也是 null（未知不算错）；
/// 第 1 段没探测完时，其余段只查容器与时长。
List<MergeIssue?> mergeIssues(
  List<MediaProbe?> probes,
  OutputContainer container,
) {
  final base = probes.firstOrNull;
  return [
    for (final (i, p) in probes.indexed)
      p == null ? null : _issue(p, i == 0 ? null : base, container),
  ];
}

MergeIssue? _issue(MediaProbe p, MediaProbe? base, OutputContainer c) {
  for (final v in p.video) {
    if (!c.acceptsVideoCopy(v.codec)) {
      return MergeIssue(
        MergeIssueKind.container,
        '${MediaProbe.codecLabel(v.codec)} 视频不能原样放进 ${c.label}',
      );
    }
  }
  for (final a in p.audio) {
    if (!c.acceptsAudioCopy(a.codec)) {
      return MergeIssue(
        MergeIssueKind.container,
        '${MediaProbe.codecLabel(a.codec)} 音频不能原样放进 ${c.label}',
      );
    }
  }
  if (p.duration == null || p.duration! <= Duration.zero) {
    return const MergeIssue(MergeIssueKind.duration, '读不出时长，算不出后面各段的起点');
  }
  if (base == null) return null;

  MergeIssue? differ(
    MergeIssueKind kind,
    String field,
    Object? mine,
    Object? theirs,
  ) {
    // 任一边读不出来就不比：拦错一个能拼的文件比漏拦一个更伤人，
    // 漏拦的会在 ffmpeg 那里失败并带上原话。
    if (mine == null || theirs == null || mine == theirs) return null;
    return MergeIssue(
      kind,
      '$field $mine ≠ 第 1 段 $theirs',
      field: field,
      expected: '$theirs',
    );
  }

  if (p.video.length != base.video.length) {
    return differ(
      MergeIssueKind.streams,
      '视频流',
      '${p.video.length} 路',
      '${base.video.length} 路',
    );
  }
  if (p.audio.length != base.audio.length) {
    return differ(
      MergeIssueKind.streams,
      '音频流',
      '${p.audio.length} 路',
      '${base.audio.length} 路',
    );
  }
  for (final (j, v) in p.video.indexed) {
    final b = base.video[j];
    const k = MergeIssueKind.video;
    final issue =
        differ(
          k,
          '视频编码',
          MediaProbe.codecLabel(v.codec),
          MediaProbe.codecLabel(b.codec),
        ) ??
        differ(k, '视频 profile', v.profile, b.profile) ??
        differ(k, '分辨率', _size(v), _size(b)) ??
        differ(k, '像素格式', v.pixFmt, b.pixFmt) ??
        (v.fps != null && b.fps != null && (v.fps! - b.fps!).abs() > 0.01
            ? differ(k, '帧率', _fps(v.fps!), _fps(b.fps!))
            : null);
    if (issue != null) return issue;
  }
  for (final (j, a) in p.audio.indexed) {
    final b = base.audio[j];
    const k = MergeIssueKind.audio;
    final issue =
        differ(
          k,
          '音频编码',
          MediaProbe.codecLabel(a.codec),
          MediaProbe.codecLabel(b.codec),
        ) ??
        differ(k, '音频 profile', a.profile, b.profile) ??
        differ(
          k,
          '采样率',
          a.sampleRate == null ? null : sampleRateLabel(a.sampleRate!),
          b.sampleRate == null ? null : sampleRateLabel(b.sampleRate!),
        ) ??
        differ(
          k,
          '声道',
          a.channels == null ? null : '${a.channels}ch',
          b.channels == null ? null : '${b.channels}ch',
        );
    if (issue != null) return issue;
  }
  return null;
}

String? _size(VideoStreamInfo v) =>
    v.width == null || v.height == null ? null : '${v.width}×${v.height}';

String _fps(double fps) =>
    '${fps % 1 == 0 ? fps.toInt() : fps.toStringAsFixed(2)}p';

/// 「48 kHz」「44.1 kHz」。
String sampleRateLabel(int hz) {
  final k = hz / 1000;
  return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)} kHz';
}

/// 各段在成片里的起点：前缀和，第 1 段是 0。
List<Duration> offsets(List<Duration> durations) {
  final out = <Duration>[];
  var at = Duration.zero;
  for (final d in durations) {
    out.add(at);
    at += d;
  }
  return out;
}

/// FFMETADATA 章节文件：每段一个章节，毫秒精度。
///
/// 标题里的 `= ; # \` 与换行按 ffmpeg 的规则转义，界面不必限制输入。
String ffmetadata(List<String> titles, List<Duration> durations) {
  assert(titles.length == durations.length);
  final starts = offsets(durations);
  final b = StringBuffer(';FFMETADATA1\n');
  for (final (i, d) in durations.indexed) {
    final start = starts[i].inMilliseconds;
    b
      ..writeln('[CHAPTER]')
      ..writeln('TIMEBASE=1/1000')
      ..writeln('START=$start')
      ..writeln('END=${start + d.inMilliseconds}')
      ..writeln('title=${_escapeMetadata(titles[i])}');
  }
  return b.toString();
}

String _escapeMetadata(String s) =>
    s.replaceAllMapped(RegExp(r'[=;#\\\n]'), (m) => '\\${m[0]}');

/// concat demuxer 的列表文件。每段写明 `duration`，让 ffmpeg 按我们算的
/// 时长排下一段的时间戳 —— 与章节、字幕用的是同一份偏移。
///
/// 路径放在单引号里（引号内反斜杠不转义，Windows 路径原样可用）；路径里的
/// 单引号写成 `'\''`。需要配 `-safe 0`，因为是绝对路径。
String concatList(List<String> paths, List<Duration> durations) {
  assert(paths.length == durations.length);
  final b = StringBuffer('ffconcat version 1.0\n');
  for (final (i, path) in paths.indexed) {
    b
      ..writeln("file '${path.replaceAll("'", r"'\''")}'")
      ..writeln('duration ${_seconds(durations[i])}');
  }
  return b.toString();
}

String _seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

/// 一段的字幕与它在成片里的位置。[cues] 为 null 表示这段没挂字幕。
typedef SegmentCues = ({List<Cue>? cues, Duration offset, Duration length});

/// 各段字幕按起点平移后拼成一份，序号从 1 重排。
///
/// 越出本段末尾的截到段尾；起点就在段外的丢掉 —— 否则会压到下一段的画面上。
List<Cue> concatCues(List<SegmentCues> segments) {
  final out = <Cue>[];
  for (final s in segments) {
    final length = s.length.inMilliseconds;
    final offset = s.offset.inMilliseconds;
    for (final c in s.cues ?? const <Cue>[]) {
      if (c.startMs >= length) continue;
      final end = c.endMs > length ? length : c.endMs;
      if (end <= c.startMs) continue;
      out.add(
        c.copyWith(
          index: out.length + 1,
          startMs: c.startMs + offset,
          endMs: end + offset,
        ),
      );
    }
  }
  return out;
}

/// 产物路径：`<目录>/<文件名>.<扩展名>`；开了旁挂字幕时同名 `.srt` 也要不存在。
/// 有冲突就加 `-2`、`-3`…，与转码同一规则：不覆盖任何已有文件，也不写到
/// 某一段源文件身上。
({String video, String? sidecar}) mergeOutputPath(
  MergeOptions options, {
  required bool Function(String path) exists,
}) {
  final first = options.segments.first.videoPath;
  final sep = first.contains('\\') && !first.contains('/') ? '\\' : '/';
  final dir = options.resolvedDir!;
  final stem = options.outputStem.trim();
  final ext = options.container.extension;
  final inputs = {
    for (final s in options.segments) sameSeparators(s.videoPath),
    for (final s in options.segments)
      if (s.subtitlePath != null) sameSeparators(s.subtitlePath!),
  };
  bool taken(String p) => inputs.contains(sameSeparators(p)) || exists(p);

  for (var n = 1; ; n++) {
    final base = '$dir$sep$stem${n == 1 ? '' : '-$n'}';
    final video = '$base.$ext';
    final sidecar = options.sidecarSubtitles ? '$base.srt' : null;
    if (taken(video) || (sidecar != null && taken(sidecar))) continue;
    return (video: video, sidecar: sidecar);
  }
}
