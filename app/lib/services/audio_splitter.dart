import 'dart:io';

import '../domain/speech_segments.dart';
import '../domain/task_control.dart';
import 'ffmpeg.dart';

/// 切出来的一段音频：落盘的文件，以及它在原音频里的位置。
class AudioClip {
  const AudioClip({
    required this.path,
    required this.startMs,
    required this.endMs,
    int? fileStartMs,
  }) : fileStartMs = fileStartMs ?? startMs;

  final String path;

  /// 这段语音在原音频里的起止（字幕时间码用它）。
  final int startMs;
  final int endMs;

  /// 片段文件第 0 毫秒对应原音频的位置。切的时候前面补了一段静音
  /// （见 [FfmpegAudioSplitter.padMs]），所以早于 [startMs]，第一段可以是负数；
  /// 识别服务返回的词级时间戳要用它换算回原音频，落在静音里的会被夹回片段范围。
  final int fileStartMs;
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

  final Ffmpeg media;
  final int maxMs;
  final int minMs;

  /// 每段前后补的静音。识别模型在片段紧贴首尾音节时容易吞字，补一点静音
  /// 让它有起落；补的是静音而不是相邻的真实音频，字幕时间码仍用切分点。
  final int padMs;

  @override
  Future<List<AudioClip>> split(
    String audioPath, {
    required CancellationToken token,
  }) async {
    final total = await media.probeDuration(audioPath);
    if (total == null) {
      throw ActionableException(
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
      throw const ActionableException(
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
        startMs: seg.startMs,
        endMs: seg.endMs,
        padMs: padMs,
        token: token,
      );
      clips.add(
        AudioClip(
          path: path,
          startMs: seg.startMs,
          endMs: seg.endMs,
          fileStartMs: seg.startMs - padMs,
        ),
      );
    }
    return clips;
  }
}
