import '../paths.dart';
import '../task_options.dart';
import 'codecs.dart';
import 'options.dart';

// ═══════════════════════════════════════════════════════════════════════
// 命令
// ═══════════════════════════════════════════════════════════════════════

abstract final class TranscodeCommand {
  /// 拼出 ffmpeg 的参数（不含可执行文件本身）。
  ///
  /// [audioEncoder] 是实际可用的音频编码器名与它要的额外参数；null 时用
  /// [AudioCodec.encoder]。[progress] 为 true 时加上机器可读的进度输出，
  /// 界面上的命令预览不带它 —— 用户复制去终端跑，要的是正常输出。
  static List<String> build({
    required TranscodeOptions options,
    required String input,
    required String output,
    (String, List<String>)? audioEncoder,
    bool progress = false,
  }) {
    final video = options.effectiveVideo;
    final audio = options.effectiveAudio;
    final encoder = video == VideoCodec.copy ? null : options.encoder;
    final encoderArgs = encoder?.build(encoder.sanitize(options.encoderParams));

    final filters = [
      if (encoder != null && options.resolution.height != null)
        "scale=w=-2:h='min(${options.resolution.height},ih)'",
      if (encoder != null && options.fps != null) 'fps=${options.fps}',
    ];

    final audioArgs = switch (audio) {
      AudioCodec.copy => const ['-c:a', 'copy'],
      _ => [
        '-c:a', audioEncoder?.$1 ?? audio.encoder,
        ...?audioEncoder?.$2,
        '-b:a', '${options.audioBitrate}k',
        if (options.audioChannels != null) ...['-ac', '${options.audioChannels}'],
      ],
    };

    return [
      '-hide_banner',
      '-nostdin',
      '-y',
      if (progress) ...['-v', 'error', '-progress', 'pipe:1', '-nostats'],
      ...?encoderArgs?.input,
      '-i', input,
      // 大写 V：视频流里排除封面附图，封面按视频转码会出错或凭空多一路。
      '-map', '0:V?',
      '-map', '0:a?',
      '-map_metadata', '0',
      '-map_chapters', '0',
      if (encoderArgs == null) ...['-c:v', 'copy'] else ...encoderArgs.output,
      if (filters.isNotEmpty) ...['-vf', filters.join(',')],
      ...audioArgs,
      if (options.faststart) ...['-movflags', '+faststart'],
      ...splitArgs(options.extraArgs),
      '-f', options.container.extension,
      output,
    ];
  }

  /// 把用户写的额外参数按空白切开，支持单双引号包住带空格的值。
  static List<String> splitArgs(String raw) {
    final out = <String>[];
    final buf = StringBuffer();
    String? quote;
    var hasToken = false;
    for (final ch in raw.split('')) {
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
        hasToken = true;
      } else if (ch.trim().isEmpty) {
        if (hasToken) out.add(buf.toString());
        buf.clear();
        hasToken = false;
      } else {
        buf.write(ch);
        hasToken = true;
      }
    }
    if (hasToken) out.add(buf.toString());
    return out;
  }

  /// 给人看的命令行：带空格或特殊字符的参数加引号。
  static String display(List<String> args, {String executable = 'ffmpeg'}) =>
      [executable, ...args.map(_quote)].join(' ');

  static String _quote(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'''^[\w@%+=:,./-]+$''').hasMatch(arg)) return arg;
    return "'${arg.replaceAll("'", r"'\''")}'";
  }

  /// 产物路径：`目录/原文件名.后缀.mp4`。[exists] 判断文件是否已存在，
  /// 已存在或与源文件同路径时加序号，不覆盖任何已有文件。
  static String outputPath({
    required String input,
    required TranscodeOptions options,
    required bool Function(String path) exists,
  }) {
    final sep = input.contains('\\') && !input.contains('/') ? '\\' : '/';
    final sourceDir = dirName(input);
    final stem = stemOf(baseName(input));
    final dir = options.outputLocation == OutputLocation.custom &&
            (options.outputDir?.trim().isNotEmpty ?? false)
        ? options.outputDir!.trim().replaceAll(RegExp(r'[/\\]+$'), '')
        : sourceDir;
    final base = '$dir$sep$stem.${options.resolvedSuffix}';
    final ext = options.container.extension;
    var candidate = '$base.$ext';
    for (var n = 2; candidate == input || exists(candidate); n++) {
      candidate = '$base-$n.$ext';
    }
    return candidate;
  }
}

/// ffmpeg `-progress` 输出的一个区块。
class TranscodeProgress {
  const TranscodeProgress({
    this.position = Duration.zero,
    this.frame,
    this.speed,
    this.done = false,
  });

  final Duration position;
  final int? frame;

  /// 相对实时的倍速：2.4 表示 1 秒处理 2.4 秒素材。
  final double? speed;

  /// 收到 `progress=end`。
  final bool done;

  /// 从一个区块的 `key=value` 行里取出进度。
  static TranscodeProgress parse(Map<String, String> block) {
    // out_time_us 是微秒；老版本的 out_time_ms 名字写着毫秒，实际也是微秒。
    final us = int.tryParse(block['out_time_us'] ?? block['out_time_ms'] ?? '');
    final speed = double.tryParse(
      (block['speed'] ?? '').trim().replaceAll('x', ''),
    );
    return TranscodeProgress(
      position: us == null || us < 0
          ? Duration.zero
          : Duration(microseconds: us),
      frame: int.tryParse(block['frame'] ?? ''),
      speed: speed,
      done: block['progress'] == 'end',
    );
  }
}
