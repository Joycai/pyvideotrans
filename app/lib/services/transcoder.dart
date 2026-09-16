import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/transcode.dart';
import 'media.dart';
import 'provider_api.dart';

/// 一个编码器在这台电脑上能不能用。
enum EncoderState {
  /// 还没测，或正在测。
  probing('检测中'),
  available('可用'),

  /// 这份 ffmpeg 没有编入它。
  notCompiled('未编入'),

  /// 编入了，但试编码失败 —— 通常是没有对应的显卡或驱动。
  failed('设备不可用');

  const EncoderState(this.label);

  final String label;
}

class EncoderStatus {
  const EncoderStatus(this.state, [this.reason]);

  final EncoderState state;

  /// 不可用的原因，一句人话。
  final String? reason;

  bool get usable => state == EncoderState.available;
}

/// ffmpeg 转码相关的进程调用：探测源文件、检测编码器、跑转码。
///
/// 可用编码器的判断分两步：先看 `ffmpeg -encoders` 里有没有，再对硬件编码器
/// 真的试编码一帧。只看列表不够 —— Windows 上常见的「全功能」ffmpeg 把 NVENC、
/// QSV、AMF 全编进去了，但一台电脑通常只有其中一家的显卡。
class Transcoder extends ChangeNotifier {
  Transcoder({Media? media}) : media = media ?? Media();

  final Media media;

  Map<String, EncoderStatus> _encoders = const {};
  Set<String> _compiled = const {};
  Future<void>? _probing;
  bool _disposed = false;

  /// 找不到 ffmpeg 时的说明；找得到时为 null。
  String? get ffmpegProblem => _ffmpegProblem;
  String? _ffmpegProblem;

  /// 找不到时该怎么办。文案按平台分好在 [Media] 里，界面直接显示，
  /// 免得每个用到的地方各写一份 `Platform.isWindows ? …`。
  String? get ffmpegHint => _ffmpegHint;
  String? _ffmpegHint;

  bool get probed => _probing != null && !isProbing;
  bool _busy = false;
  bool get isProbing => _busy;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 某个编码器的状态。没测过的算检测中。
  EncoderStatus status(String encoderId) =>
      _encoders[encoderId] ?? const EncoderStatus(EncoderState.probing);

  /// 首次用到时检测一次；之后复用结果，除非 [refresh]。
  Future<void> ensureProbed() => _probing ??= _probe();

  /// 「重新检测」：装了驱动或换了 ffmpeg 之后用。
  Future<void> refresh() {
    if (_busy) return _probing!;
    // 用户很可能刚把 ffmpeg 放进投放目录，上次查找的结果（尤其是「找不到」）
    // 必须作废，否则点了也没用。
    media.reset();
    return _probing = _probe();
  }

  Future<void> _probe() async {
    _busy = true;
    _encoders = const {};
    _notify();
    try {
      final String exe;
      try {
        exe = media.ffmpeg;
        _ffmpegProblem = null;
        _ffmpegHint = null;
      } on ProviderException catch (e) {
        _ffmpegProblem = e.message;
        _ffmpegHint = e.hint;
        _encoders = {
          for (final enc in VideoEncoders.all)
            enc.id: const EncoderStatus(EncoderState.notCompiled, '找不到 FFmpeg'),
        };
        _compiled = const {};
        return;
      }

      final listing = await Process.run(exe, ['-hide_banner', '-encoders']);
      _compiled = parseEncoderList('${listing.stdout}');

      final result = <String, EncoderStatus>{};
      for (final enc in VideoEncoders.all) {
        result[enc.id] = _compiled.contains(enc.id)
            ? (enc.backend.isHardware
                  ? const EncoderStatus(EncoderState.probing)
                  : const EncoderStatus(EncoderState.available))
            : EncoderStatus(
                EncoderState.notCompiled,
                '此 FFmpeg 没有编入 ${enc.id}',
              );
      }
      _encoders = Map.of(result);
      _notify();

      // 硬件编码器逐个试，不并发：几路同时抢一块显卡的编码会话，
      // 本来能用的也可能报失败。
      for (final enc in VideoEncoders.all) {
        if (result[enc.id]!.state != EncoderState.probing) continue;
        result[enc.id] = await _tryEncode(exe, enc);
        _encoders = Map.of(result);
        _notify();
      }
    } on ProcessException catch (e) {
      _ffmpegProblem = '无法运行 FFmpeg：${e.message}';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 用一帧纯色画面试编码。
  Future<EncoderStatus> _tryEncode(String exe, VideoEncoder enc) async {
    final args = enc.build(enc.defaults);
    try {
      final process = await Process.start(exe, [
        '-hide_banner', '-nostdin', '-v', 'error',
        '-f', 'lavfi', '-i', 'color=black:s=640x360:r=30:d=0.2',
        '-frames:v', '1',
        ...args.output,
        '-f', 'null', '-',
      ]);
      final stderr = StringBuffer();
      final drain = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stderr.write);
      await process.stdout.drain<void>();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await drain.cancel();
      if (code == 0) return const EncoderStatus(EncoderState.available);
      return EncoderStatus(
        EncoderState.failed,
        explainEncoderFailure(enc, stderr.toString()),
      );
    } on ProcessException catch (e) {
      return EncoderStatus(EncoderState.failed, e.message);
    }
  }

  /// `ffmpeg -encoders` 输出里的编码器名。
  @visibleForTesting
  static Set<String> parseEncoderList(String output) => {
    for (final line in const LineSplitter().convert(output))
      // 表头图例那几行（「V..... = Video」）的名字位置是等号，要排除。
      if (RegExp(r'^\s*[VAS][F.][S.][X.][B.][D.]\s+([A-Za-z0-9_][\w-]*)\s')
              .firstMatch(line)
          case final m?)
        m.group(1)!,
  };

  /// 试编码失败时 stderr 里常见的几种话，翻成用户能行动的一句。
  @visibleForTesting
  static String explainEncoderFailure(VideoEncoder enc, String stderr) {
    final s = stderr.toLowerCase();
    switch (enc.backend) {
      case EncoderBackend.nvenc:
        if (s.contains('no capable devices') ||
            s.contains('cannot load') ||
            s.contains('nvcuda') ||
            s.contains('no nvenc capable')) {
          return '没有找到 NVIDIA 显卡或驱动';
        }
        if (s.contains('unsupported') || s.contains('not supported')) {
          return '显卡不支持 ${enc.codec.label} 编码';
        }
        if (s.contains('driver')) return 'NVIDIA 驱动版本过旧';
      case EncoderBackend.qsv:
        if (s.contains('mfx') || s.contains('session') || s.contains('device')) {
          return '没有找到 Intel 核显或驱动';
        }
      case EncoderBackend.amf:
        if (s.contains('amf') && (s.contains('dll') || s.contains('load'))) {
          return '没有找到 AMD 显卡或驱动';
        }
        // 显卡本身不支持这种编码时，AMF 建不出组件，ffmpeg 报
        // 「CreateComponent(...) failed」；-v error 下只剩「Encoder not found」。
        if (s.contains('createcomponent') || s.contains('encoder not found')) {
          return '显卡不支持 ${enc.codec.label} 编码';
        }
      case EncoderBackend.videotoolbox:
        return '这台 Mac 不支持用硬件编码 ${enc.codec.label}';
      case EncoderBackend.cpu:
        break;
    }
    final line = const LineSplitter()
        .convert(stderr)
        .where((l) => l.trim().isNotEmpty)
        .lastOrNull;
    return line == null ? '试编码失败' : '试编码失败：${line.trim()}';
  }

  /// 实际可用的音频编码器：首选没编进来就用替补。都没有时返回首选，
  /// 让 ffmpeg 报出原话。
  (String, List<String>) audioEncoder(AudioCodec codec) {
    if (_compiled.isEmpty || _compiled.contains(codec.encoder)) {
      return (codec.encoder, const []);
    }
    final fallback = codec.fallback;
    if (fallback != null && _compiled.contains(fallback.$1)) return fallback;
    return (codec.encoder, const []);
  }

  /// 读源文件的流信息。读不出来抛 [ProviderException]。
  Future<MediaProbe> probe(String path) async {
    final ProcessResult result;
    try {
      result = await Process.run(media.ffprobe, [
        '-v', 'error',
        '-show_entries',
        'format=duration:stream=index,codec_type,codec_name,width,height,'
            'avg_frame_rate,r_frame_rate,pix_fmt,channels:'
            'stream_disposition=attached_pic',
        '-of', 'json',
        path,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
    } on ProcessException catch (e) {
      throw ProviderException('无法运行 ffprobe', detail: e.message);
    }
    if (result.exitCode != 0) {
      throw ProviderException(
        'ffprobe 读不出这个文件',
        detail: '${result.stderr}'.trim(),
        hint: '多为文件损坏或不是音视频。用播放器确认文件能正常播放。',
      );
    }
    final probe = MediaProbe.fromJson(
      (jsonDecode('${result.stdout}') as Map).cast<String, Object?>(),
    );
    if (probe.isEmpty) {
      throw const ProviderException(
        '文件里没有音视频流',
        hint: '确认选中的是视频文件。',
      );
    }
    return probe;
  }

  /// 跑一次转码。[onProgress] 在每个进度区块到达时调用。取消时杀掉进程并
  /// 抛 [TaskCancelled]；失败抛 [ProviderException]，detail 是 stderr 末尾。
  Future<void> run({
    required List<String> args,
    required String encoderId,
    required CancellationToken token,
    required void Function(TranscodeProgress) onProgress,
  }) async {
    token.throwIfCancelled();
    final process = await Process.start(media.ffmpeg, args);
    final stderr = StringBuffer();
    // 完成信号在订阅时就取：等进程退出后再调 asFuture，流若已经结束，
    // 那个 future 永远不会完成，任务会一直卡在「转码中」。
    final errSub = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          stderr.write(chunk);
          // 只留末尾：长片出错时 ffmpeg 可能每帧刷一行警告。
          if (stderr.length > 64 * 1024) {
            final tail = stderr.toString().substring(stderr.length - 16 * 1024);
            stderr
              ..clear()
              ..write(tail);
          }
        });
    final errDone = errSub.asFuture<void>();
    final block = <String, String>{};
    final outSub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          final eq = line.indexOf('=');
          if (eq <= 0) return;
          final key = line.substring(0, eq).trim();
          block[key] = line.substring(eq + 1).trim();
          if (key == 'progress') {
            onProgress(TranscodeProgress.parse(block));
            block.clear();
          }
        });
    final outDone = outSub.asFuture<void>();
    final watchdog = Media.killOnCancel(process, token);
    final exitCode = await process.exitCode;
    await watchdog.cancel();
    if (token.isCancelled) {
      // 被杀的若只是包装器，漏网的子进程还攥着管道，等管道关上要等到它转完。
      await (outSub.cancel(), errSub.cancel()).wait;
      throw const TaskCancelled();
    }
    await outDone.catchError((_) {});
    await errDone.catchError((_) {});
    if (exitCode != 0) throw describeFailure(stderr.toString(), encoderId);
  }
  /// ffmpeg 退出码非零时的报错。
  @visibleForTesting
  static ProviderException describeFailure(String stderr, String encoderId) {
    final tail = stderr.trimRight();
    final detail = tail.length > 800
        ? '…${tail.substring(tail.length - 800)}'
        : tail;
    final s = tail.toLowerCase();
    if (s.contains('could not find tag for codec') ||
        s.contains('only supported in mp4') ||
        s.contains('not currently supported in container')) {
      return ProviderException(
        '容器装不下其中一路流',
        detail: detail,
        hint: '换一个容器，或把那一路改为重新编码而不是复制。',
      );
    }
    if (s.contains('error while opening encoder') ||
        s.contains('could not open encoder') ||
        s.contains('initializing output stream') ||
        s.contains('no capable devices') ||
        s.contains('unknown encoder')) {
      return ProviderException(
        '$encoderId 初始化失败',
        detail: detail,
        hint: '这个编码器在当前设备或参数下用不了。换一个编码器（例如 CPU 编码）后从转码阶段继续。',
      );
    }
    if (s.contains('unrecognized option') || s.contains('option not found')) {
      return ProviderException(
        'FFmpeg 不认识其中一个参数',
        detail: detail,
        hint: '检查「额外参数」的写法，或者这份 FFmpeg 版本过旧。',
      );
    }
    if (s.contains('no space left')) {
      return ProviderException(
        '磁盘空间不足',
        detail: detail,
        hint: '清理输出目录所在磁盘，或在高级里换一个输出目录。',
      );
    }
    return ProviderException(
      'FFmpeg 转码失败',
      detail: detail.isEmpty ? '退出码非零，没有输出报错' : detail,
      hint: '查看报错原文；多为源文件损坏或参数组合不受支持。',
    );
  }
}
