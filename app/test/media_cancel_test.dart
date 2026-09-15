import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/provider_api.dart';

/// Scoop / Chocolatey 的 ffmpeg.exe 是 shim，真 ffmpeg 是它的子进程。
/// 这里用不 exec 的 shell 包装器模拟同样的进程树，确认取消时连子进程一起停。
void main() {
  final media = Media();
  final Object skip = !media.available
      ? '本机没有 ffmpeg'
      : Platform.isWindows
      ? '用 shell 包装器模拟，Windows 上不适用'
      : false;

  test('ffmpeg 是包装器时取消抽音：很快抛 TaskCancelled，子进程不残留', () async {
    final dir = await Directory.systemTemp.createTemp('media_cancel');
    addTearDown(() => dir.delete(recursive: true));
    final wrapper = File('${dir.path}/ffmpeg-shim');
    await wrapper.writeAsString('#!/bin/sh\n"${media.ffmpeg}" "\$@"\n');
    await Process.run('chmod', ['+x', wrapper.path]);

    // 抽音很快，参数又是固定的，用一小时长的音频让它跑上几秒，好在中途取消。
    final src = '${dir.path}/long.wav';
    final gen = await Process.run(media.ffmpeg, [
      '-hide_banner', '-v', 'error', '-y',
      '-f', 'lavfi', '-i', 'sine=d=3600:r=48000', '-ac', '2', src,
    ]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');

    final shimmed = Media(ffmpegPath: wrapper.path, ffprobePath: media.ffprobe);
    final token = CancellationToken();
    final out = '${dir.path}/out.wav';
    final started = DateTime.now();
    final run = shimmed.extractAudio(sourcePath: src, outputPath: out, token: token);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    await expectLater(run, throwsA(isA<TaskCancelled>()));
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));

    await Future<void>.delayed(const Duration(milliseconds: 500));
    final left = await Process.run('pgrep', ['-f', out]);
    expect('${left.stdout}'.trim(), isEmpty, reason: '子进程 ffmpeg 还在跑');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
