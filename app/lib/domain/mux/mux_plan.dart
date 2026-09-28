import '../transcode/codecs.dart';

/// 封装计划里的一个输入。[before] 是写在它的 `-i` 前面的参数，
/// 例如 concat 列表要的 `-f concat -safe 0`。
class MuxInput {
  const MuxInput(this.path, {this.before = const []});

  final String path;
  final List<String> before;
}

/// 一次「只搬流、不转码」的 ffmpeg 调用：有哪些输入、各取哪几路流、
/// 章节从哪来、字幕怎么封装。合并用它，以后的重混流（换音轨、加字幕轨、
/// 删流）也产出同一个结构，参数拼法只写这一处。
///
/// 为什么是声明式的数据而不是直接拼参数：流水线要拿它拼真正执行的命令，
/// 页面要拿它拼命令预览（临时文件名用占位），两处的差别只在路径上。
class MuxPlan {
  const MuxPlan({
    required this.inputs,
    required this.maps,
    required this.container,
    this.metadataFrom,
    this.subtitleCodec,
  });

  /// 合并：输入 0 是 concat 列表；开了章节时下一个是 FFMETADATA；
  /// 有字幕要内嵌时再下一个是拼好的 SRT。
  ///
  /// 只取视频（大写 V：排除封面附图）与音频；源文件里的字幕流、数据流不带入 ——
  /// 各段的内封字幕时间轴没有平移，带进来会错位。
  factory MuxPlan.merge({
    required String concatList,
    String? chapters,
    String? subtitles,
    required OutputContainer container,
  }) {
    final inputs = [
      MuxInput(concatList, before: const ['-f', 'concat', '-safe', '0']),
      if (chapters != null) MuxInput(chapters),
      if (subtitles != null) MuxInput(subtitles),
    ];
    return MuxPlan(
      inputs: inputs,
      maps: ['0:V?', '0:a?', if (subtitles != null) '${inputs.length - 1}:s'],
      container: container,
      metadataFrom: chapters == null ? null : 1,
      subtitleCodec: subtitles == null ? null : container.subtitleCodec,
    );
  }

  final List<MuxInput> inputs;

  /// `-map` 的值，按顺序成为输出里的流。
  final List<String> maps;

  final OutputContainer container;

  /// 全局元数据与章节取自第几个输入；null 时不写章节。
  final int? metadataFrom;

  /// 字幕流的封装编码（mp4 / mov 是 mov_text）；null 表示没有字幕流。
  final String? subtitleCodec;

  /// 拼出 ffmpeg 参数（不含可执行文件本身）。一律 `-c copy`，再按需覆盖字幕编码。
  ///
  /// 显式写 `-f`：流水线写到 `<产物>.part` 再改名，ffmpeg 认不出这个扩展名。
  /// [progress] 为 true 时加机器可读的进度输出，命令预览不带它。
  List<String> args(String output, {bool progress = false}) => [
    '-hide_banner',
    '-nostdin',
    '-y',
    if (progress) ...['-v', 'error', '-progress', 'pipe:1', '-nostats'],
    for (final input in inputs) ...[...input.before, '-i', input.path],
    for (final m in maps) ...['-map', m],
    if (metadataFrom case final i?) ...[
      '-map_metadata',
      '$i',
      '-map_chapters',
      '$i',
    ] else ...[
      // 不写章节时也别把第 1 段自带的章节原样搬过来：它们的时间只对得上第 1 段。
      '-map_chapters', '-1',
    ],
    '-c',
    'copy',
    if (subtitleCodec case final codec?) ...['-c:s', codec],
    '-f',
    container.extension,
    output,
  ];
}
