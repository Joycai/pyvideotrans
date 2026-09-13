import 'dart:io';

import '../domain/speech_segments.dart';
import 'media.dart';
import 'provider_api.dart';

/// 切出来的一段音频：落盘的文件，以及它在原音频里的位置。
class AudioClip {
  const AudioClip({
    required this.path,
    required this.startMs,
    required this.endMs,
  });

  final String path;
  final int startMs;
  final int endMs;
}

/// 把整段音频切成可以逐段识别的片段。
///
/// 只有不带时间戳的识别接口（阿里百炼 Qwen3-ASR）需要它；Whisper 系自己
/// 分段。抽成接口是为了测试能塞假实现，不用真的起 ffmpeg。
abstract class AudioSplitter {
  Future<List<AudioClip>> split(
    String audioPath, {
    required CancellationToken token,
  });
}

/// ffmpeg 实现：silencedetect 找静音，再按静音把音频切开。
///
/// 片段落在 `<音频>.clips/` 目录下，识别完由调用方删掉。
class FfmpegAudioSplitter implements AudioSplitter {
  const FfmpegAudioSplitter(
    this.media, {
    this.maxMs = SpeechSegments.defaultMaxMs,
    this.minMs = SpeechSegments.defaultMinMs,
    this.padMs = 200,
  });

  final Media media;
  final int maxMs;
  final int minMs;

  /// 每段前后多带一点，避免首尾音节被切掉半个。字幕时间码仍用切分点。
  final int padMs;

  @override
  Future<List<AudioClip>> split(
    String audioPath, {
    required CancellationToken token,
  }) async {
    final total = await media.probeDuration(audioPath);
    if (total == null) {
      throw ProviderException(
        '读不到音频时长',
        detail: audioPath,
        hint: '准备阶段产出的音频可能已损坏，请从准备阶段继续。',
      );
    }
    final totalMs = total.inMilliseconds;
    final silences = await media.detectSilences(audioPath, token: token);
    final segments = SpeechSegments.fromSilences(
      silences,
      totalMs,
      maxMs: maxMs,
      minMs: minMs,
    );
    if (segments.isEmpty) {
      throw const ProviderException(
        '未识别到语音',
        hint: '整段音频都是静音。确认音视频中确有人声。',
      );
    }

    final dir = Directory('$audioPath.clips');
    await dir.create(recursive: true);
    final clips = <AudioClip>[];
    for (final (i, seg) in segments.indexed) {
      token.throwIfCancelled();
      final path = '${dir.path}${Platform.pathSeparator}clip_$i.wav';
      await media.cutAudio(
        sourcePath: audioPath,
        outputPath: path,
        startMs: (seg.startMs - padMs).clamp(0, totalMs),
        endMs: (seg.endMs + padMs).clamp(0, totalMs),
        token: token,
      );
      clips.add(AudioClip(path: path, startMs: seg.startMs, endMs: seg.endMs));
    }
    return clips;
  }
}
