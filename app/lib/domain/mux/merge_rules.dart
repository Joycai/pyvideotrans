// 合并的纯规则。页面（开始前校验、命令预览）与流水线（准备阶段二次把关、
// 真正写文件）用同一份，两边不可能判得不一样。
//
// 偏移是核心：concat 列表的 `duration`、章节起点、字幕平移都用 [offsets] 算出的
// 同一份数，三者不可能对不上。

import '../cue.dart';
import '../language.dart';
import '../output_naming.dart';
import '../paths.dart';
import '../transcode/codecs.dart';
import '../transcode/probe.dart';
import 'merge_options.dart';
import 'mux_plan.dart';

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

  // 比的是原始值，[show] 只管文案：pcm_s16le 与 pcm_s24le 都显示成「PCM」，
  // 按文案比会判成一致，拼出来第二段是满幅噪音。
  // [fixable] 为假的项（流路数、profile、方向…）转码页选不出来，页脚不提「转成 …」。
  MergeIssue? differ<T extends Object>(
    MergeIssueKind kind,
    String field,
    T? mine,
    T? theirs, {
    String Function(T)? show,
    bool Function(T, T)? same,
    bool fixable = true,
  }) {
    // 任一边读不出来就不比：拦错一个能拼的文件比漏拦一个更伤人，
    // 漏拦的会在 ffmpeg 那里失败并带上原话。
    if (mine == null || theirs == null) return null;
    if (same?.call(mine, theirs) ?? mine == theirs) return null;
    var m = show?.call(mine) ?? '$mine';
    var t = show?.call(theirs) ?? '$theirs';
    if (m == t) (m, t) = ('$mine', '$theirs');
    return MergeIssue(
      kind,
      '$field $m ≠ 第 1 段 $t',
      field: field,
      expected: fixable ? t : null,
    );
  }

  const streams = MergeIssueKind.streams;
  final issue =
      differ(
        streams,
        '视频流',
        p.video.length,
        base.video.length,
        show: _ways,
        fixable: false,
      ) ??
      differ(
        streams,
        '音频流',
        p.audio.length,
        base.audio.length,
        show: _ways,
        fixable: false,
      );
  if (issue != null) return issue;

  for (final (j, v) in p.video.indexed) {
    final b = base.video[j];
    const k = MergeIssueKind.video;
    final issue =
        differ(k, '视频编码', v.codec, b.codec, show: MediaProbe.codecLabel) ??
        differ(k, '视频 profile', v.profile, b.profile, fixable: false) ??
        differ(k, '分辨率', _size(v), _size(b)) ??
        differ(k, '像素格式', v.pixFmt, b.pixFmt, fixable: false) ??
        differ(
          k,
          '画面方向',
          v.rotation,
          b.rotation,
          show: _rotation,
          fixable: false,
        ) ??
        differ(k, '帧率', v.fps, b.fps, show: _fps, same: _sameFps);
    if (issue != null) return issue;
  }
  for (final (j, a) in p.audio.indexed) {
    final b = base.audio[j];
    const k = MergeIssueKind.audio;
    final issue =
        differ(k, '音频编码', a.codec, b.codec, show: MediaProbe.codecLabel) ??
        differ(k, '音频 profile', a.profile, b.profile, fixable: false) ??
        differ(
          k,
          '采样率',
          a.sampleRate,
          b.sampleRate,
          show: sampleRateLabel,
          fixable: false,
        ) ??
        differ(k, '声道', a.channels, b.channels, show: (c) => '${c}ch');
    if (issue != null) return issue;
  }
  return null;
}

String _ways(int n) => '$n 路';

String _rotation(int deg) => deg == 0 ? '不旋转' : '旋转 $deg°';

/// 帧率差在 1% 以内算一致：29.97 与 30、23.976 与 24 原样拼接没问题，
/// 手机录的可变帧率片段 avg_frame_rate 每段都差一点，按绝对差会被误拦。
bool _sameFps(double a, double b) => (a - b).abs() <= b * 0.01;

String? _size(VideoStreamInfo v) =>
    v.width == null || v.height == null ? null : '${v.width}×${v.height}';

String _fps(double fps) =>
    '${fps % 1 == 0 ? fps.toInt() : fps.toStringAsFixed(2)}p';

/// 「48 kHz」「44.1 kHz」；一位小数说不清的（44056）直接写 Hz。
String sampleRateLabel(int hz) {
  if (hz % 100 != 0) return '$hz Hz';
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

/// 合并出来的文件是不是少了段。
///
/// concat 列表里某段打不开时 ffmpeg 只报一句、照样以 0 退出，写出前面几段就算
/// 「成功」。不用 `-xerror` 拦：它会把段与段接缝处常见、无害的「Non-monotonic
/// DTS」也变成失败。少一段至少短一个最短段，所以短过它的一半就算缺段；
/// 音频编码帧对齐带来的零点几秒出入不会误判。
bool looksTruncated(Duration actual, List<Duration> segments) {
  if (segments.isEmpty) return false;
  final total = segments.fold(Duration.zero, (a, b) => a + b);
  final shortest = segments.reduce((a, b) => a < b ? a : b);
  return actual < total - shortest ~/ 2;
}

/// FFMETADATA 章节文件：每段一个章节，毫秒精度。
///
/// 标题里的 `= ; # \` 与换行（含 `\r`，ffmpeg 也把它当行尾）按 ffmpeg 的规则
/// 转义，界面不必限制输入。
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
    s.replaceAllMapped(RegExp(r'[=;#\\\n\r]'), (m) => '\\${m[0]}');

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
      final end = _clippedEnd(c, length);
      if (end == null) continue;
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

/// 一段字幕平移截尾后还剩几条，取舍与 [concatCues] 一致；只数，不复制。
int keptCueCount(List<Cue> cues, Duration length) {
  final ms = length.inMilliseconds;
  return cues.where((c) => _clippedEnd(c, ms) != null).length;
}

/// 截到段尾后的终点（毫秒）；起点在段外、或截完什么都不剩时为 null（这条丢掉）。
int? _clippedEnd(Cue c, int lengthMs) {
  if (c.startMs >= lengthMs) return null;
  final end = c.endMs > lengthMs ? lengthMs : c.endMs;
  return end <= c.startMs ? null : end;
}

/// 合并命令里三个临时文件的占位名。合并页的命令预览与任务详情里存的命令都用
/// 它们，真正执行时换成临时目录里的路径。
abstract final class MergeTempFiles {
  static const list = 'list.txt';
  static const chapters = 'chapters.txt';
  static const subtitles = 'merged.srt';
}

/// 合并后那份字幕的语言与是否双语。
typedef MergedSubtitleLabel = ({Language? language, bool bilingual});

/// 从各段所挂字幕的文件名推断合并后字幕的语言：`ep1.zh.srt`、
/// `ep1.Bilingual.zh.srt` 这样的名字（与本应用写出的产物同一套规则）。
///
/// 各段都说得出、且说的一样才算数；有一段看不出或各段不一致就当作未知 ——
/// 标错比不标更糟，播放器会按错的语言自动选轨。没挂字幕的段不参与。
MergedSubtitleLabel mergedSubtitleLabel(MergeOptions options) {
  final labels = <MergedSubtitleLabel>[
    for (final s in options.segments)
      if (s.subtitlePath case final sub?) _labelOf(s.videoPath, sub),
  ];
  if (labels.isEmpty) return (language: null, bilingual: false);
  final first = labels.first;
  final bilingual = labels.every((l) => l.bilingual);
  final language = labels.every((l) => l.language == first.language)
      ? first.language
      : null;
  return (language: language, bilingual: bilingual);
}

MergedSubtitleLabel _labelOf(String video, String subtitle) {
  final tags = OutputNaming.sidecarTags(video, subtitle);
  if (tags == null) {
    // 手动挂的、不与视频同名的字幕：名字里认得出语言也算。
    return (language: Languages.fromFileName(subtitle), bilingual: false);
  }
  return (
    language: tags.isEmpty ? null : Languages.fromTag(tags.last),
    bilingual: tags.length == 2,
  );
}

/// 合并后字幕在文件名里的那几段，规则同 [OutputNaming.tags]。
List<String> mergedSubtitleTags(MergedSubtitleLabel label) => [
  if (label.bilingual) OutputNaming.bilingualTitle,
  if (label.language case final l?) languageTag(l),
];

/// 这份参数对应的封装计划。[list] 等是三个临时文件的路径（或 [MergeTempFiles]
/// 的占位名）；没开章节、没有字幕可内嵌时对应的输入不出现。
MuxPlan mergePlan(
  MergeOptions options, {
  required String list,
  required String chapters,
  required String subtitles,
  required bool hasCues,
}) => MuxPlan.merge(
  concatList: list,
  chapters: options.chapters ? chapters : null,
  subtitles: options.embedSubtitles && hasCues ? subtitles : null,
  subtitleLanguage: switch (mergedSubtitleLabel(options).language) {
    final l? => Languages.iso6392Of(l),
    null => null,
  },
  container: options.container,
);

/// 视频产物旁的字幕：视频主干加语言段，`ep.merged.mp4` →
/// `ep.merged.zh.srt`。Jellyfin 等播放器按主干配视频、按语言段定语言。
String sidecarPathFor(String video, List<String> tags) => [
  video.replaceAll(RegExp(r'\.[^./\\]*$'), ''),
  ...tags,
  'srt',
].join('.');

/// 产物路径：`<目录>/<文件名>.<扩展名>`；开了旁挂字幕时旁边那份字幕也要不存在。
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
  final tags = mergedSubtitleTags(mergedSubtitleLabel(options));

  // 根目录（`/`、`C:\`）本身带分隔符，别再拼一个。
  final prefix = dir.endsWith('/') || dir.endsWith('\\') ? dir : '$dir$sep';
  for (var n = 1; ; n++) {
    final base = '$prefix$stem${n == 1 ? '' : '-$n'}';
    final video = '$base.$ext';
    final sidecar = options.sidecarSubtitles
        ? sidecarPathFor(video, tags)
        : null;
    if (taken(video) || (sidecar != null && taken(sidecar))) continue;
    return (video: video, sidecar: sidecar);
  }
}
