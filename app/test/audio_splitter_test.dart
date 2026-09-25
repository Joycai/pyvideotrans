import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/task_control.dart';
import 'package:subtitle_studio/services/audio_splitter.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';

/// 真的起 ffmpeg 切一段合成音频。没装 ffmpeg 的机器上跳过。
void main() {
  final media = Ffmpeg();
  final hasFfmpeg = media.available;

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('splitter_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    '1s 正弦 + 1s 静音 + 1s 正弦 切成两段，时间码落在静音两侧',
    () async {
      final wav = '${tmp.path}/a.wav';
      final gen = await Process.run(media.ffmpeg, [
        '-y',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
        '-f', 'lavfi', '-i', 'anullsrc=r=16000:cl=mono:d=1',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
        '-filter_complex', '[0][1][2]concat=n=3:v=0:a=1',
        '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le',
        wav,
      ]);
      expect(gen.exitCode, 0, reason: gen.stderr.toString());

      final clips = await FfmpegAudioSplitter(
        Ffmpeg(),
      ).split(wav, token: CancellationToken());

      expect(clips, hasLength(2));
      expect(clips[0].startMs, 0);
      expect(clips[0].endMs, closeTo(1000, 150));
      expect(clips[1].startMs, closeTo(2000, 150));
      expect(clips[1].endMs, closeTo(3000, 50));
      for (final c in clips) {
        expect(File(c.path).lengthSync(), greaterThan(1000));
      }
      // 前后各补 200ms 静音：文件比语音段长 400ms，文件起点早 200ms。
      for (final c in clips) {
        expect(c.fileStartMs, c.startMs - 200);
      }
      final probe = await Ffmpeg().probeDuration(clips[1].path);
      expect(
        probe!.inMilliseconds,
        closeTo(clips[1].endMs - clips[1].startMs + 400, 30),
      );
    },
    skip: hasFfmpeg ? false : '本机没有 ffmpeg',
  );
}
