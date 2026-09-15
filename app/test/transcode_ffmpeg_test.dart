import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/transcode.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/transcoder.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 真的跑 ffmpeg 的端到端测试：入队 → 准备 → 转码 → 完成，核对产物的编码。
/// 本机没有 ffmpeg 时整组跳过。
void main() {
  final media = Media();
  final Object skip = media.available ? false : '本机没有 ffmpeg';
  final Object macSkip = skip != false
      ? skip
      : Platform.isMacOS
      ? false
      : '只在 macOS 上跑';
  final Object winSkip = skip != false
      ? skip
      : Platform.isWindows
      ? false
      : '只在 Windows 上跑';

  late Directory dir;
  late TaskQueue queue;
  late Transcoder transcoder;

  Future<void> ffmpeg(List<String> args) async {
    final r = await Process.run(media.ffmpeg, ['-hide_banner', '-v', 'error', '-y', ...args]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  Future<Map<String, Object?>> probe(String path) async {
    final r = await Process.run(media.ffprobe, [
      '-v', 'error', '-show_entries', 'stream=codec_type,codec_name,height',
      '-of', 'json', path,
    ]);
    return (jsonDecode('${r.stdout}') as Map).cast<String, Object?>();
  }

  Future<SubtitleTask> run(String input, TranscodeOptions options) async {
    final task = queue.enqueueTranscode([input], options: options).single;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (task.isActive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return task;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    dir = await Directory.systemTemp.createTemp('transcode_test');
    transcoder = Transcoder(media: media);
    queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: dir.path,
        media: media,
        transcoder: transcoder,
      ),
      settings: settings,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test('x264 转码：只缩不放、写到源文件旁、阶段完整', () async {
    final src = '${dir.path}/clip.mkv';
    await ffmpeg([
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=2',
      '-f', 'lavfi', '-i', 'sine=d=2',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', src,
    ]);
    // 480p 上限对 360 的源不放大，输出仍是 360。
    final task = await run(
      src,
      const TranscodeOptions(
        videoCodec: VideoCodec.h264,
        encoderId: 'libx264',
        encoderParams: {'preset': 'ultrafast', 'crf': 30},
        resolution: ResolutionLimit.p480,
        audioCodec: AudioCodec.mp3,
      ),
    );
    expect(task.status, TaskStatus.done, reason: task.error?.detail);
    final out = task.transcode!.outputPath!;
    expect(out, '${dir.path}/clip.h264.mp4');
    expect(File('$out.part').existsSync(), isFalse);
    expect(task.transcode!.outputBytes, greaterThan(0));
    expect(task.transcode!.sourceVideo, 'H.264');
    for (final s in TaskKind.transcode.stages) {
      expect(task.stages[s]!.state, StageState.done, reason: s.name);
    }
    final streams = (await probe(out))['streams']! as List;
    expect(streams.map((s) => (s as Map)['codec_name']), containsAll(['h264', 'mp3']));
    expect(streams.firstWhere((s) => (s as Map)['codec_type'] == 'video')['height'], 360);
  }, skip: skip);

  test('重混流进 MOV；再跑一次不覆盖，自动加序号', () async {
    final src = '${dir.path}/clip.mkv';
    await ffmpeg([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=25:d=1',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', src,
    ]);
    const options = TranscodeOptions(
      mode: TranscodeMode.remux,
      container: OutputContainer.mov,
    );
    final first = await run(src, options);
    expect(first.status, TaskStatus.done, reason: first.error?.detail);
    expect(first.transcode!.outputPath, '${dir.path}/clip.remux.mov');
    final second = await run(src, options);
    expect(second.status, TaskStatus.done, reason: second.error?.detail);
    expect(second.transcode!.outputPath, '${dir.path}/clip.remux-2.mov');
  }, skip: skip);

  test('WMV2 复制进 MP4：准备阶段就拦下，给出可行动的提示', () async {
    final src = '${dir.path}/old.wmv';
    await ffmpeg([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x240:d=1',
      '-c:v', 'wmv2', src,
    ]);
    final task = await run(
      src,
      const TranscodeOptions(mode: TranscodeMode.remux),
    );
    expect(task.status, TaskStatus.failed);
    expect(task.stage, TaskStage.prepare);
    expect(task.error!.title, contains('WMV2'));
    expect(task.resumeStage, TaskStage.prepare);
  }, skip: skip);

  // 本机硬件编码：只在 Mac 上、且检测为可用时跑。HEVC 产物要带 hvc1 标签，
  // 否则 QuickTime 与 iPhone 不认。
  for (final (id, codec, container) in [
    ('h264_videotoolbox', 'h264', OutputContainer.mov),
    ('hevc_videotoolbox', 'hevc', OutputContainer.mp4),
  ]) {
    test('VideoToolbox 硬件编码：$id → ${container.label}', () async {
      await transcoder.refresh();
      if (!transcoder.status(id).usable) {
        markTestSkipped('$id 在这台电脑上不可用：${transcoder.status(id).reason}');
        return;
      }
      final src = '${dir.path}/clip.mkv';
      await ffmpeg([
        '-f', 'lavfi', '-i', 'testsrc2=s=1280x720:r=30:d=2',
        '-f', 'lavfi', '-i', 'sine=d=2',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', src,
      ]);
      final encoder = VideoEncoders.byId(id)!;
      final task = await run(
        src,
        TranscodeOptions(
          container: container,
          videoCodec: encoder.codec,
          encoderId: id,
          encoderParams: {...encoder.defaults, 'quality': 60},
        ),
      );
      expect(task.status, TaskStatus.done, reason: task.error?.detail);
      expect(task.transcode!.command, contains('-hwaccel videotoolbox'));
      final out = task.transcode!.outputPath!;
      final streams = (await probe(out))['streams']! as List;
      expect(streams.map((s) => (s as Map)['codec_name']), contains(codec));
      if (codec == 'hevc') {
        final tag = await Process.run(media.ffprobe, [
          '-v', 'error', '-select_streams', 'v:0',
          '-show_entries', 'stream=codec_tag_string', '-of', 'csv=p=0', out,
        ]);
        expect('${tag.stdout}'.trim(), 'hvc1');
      }
    }, skip: macSkip, timeout: const Timeout(Duration(minutes: 2)));
  }

  // Windows 上的 NVENC / AMF：只在检测为可用时跑，没有对应显卡就跳过。
  // 开着硬件解码，连 -hwaccel 那一段一起验；HEVC 同样要带 hvc1 标签。
  for (final (id, codec, hwaccel) in [
    ('h264_nvenc', 'h264', 'cuda'),
    ('hevc_nvenc', 'hevc', 'cuda'),
    ('av1_nvenc', 'av1', 'cuda'),
    ('h264_amf', 'h264', 'd3d11va'),
    ('hevc_amf', 'hevc', 'd3d11va'),
  ]) {
    test('Windows 硬件编码：$id + -hwaccel $hwaccel', () async {
      await transcoder.refresh();
      if (!transcoder.status(id).usable) {
        markTestSkipped('$id 在这台电脑上不可用：${transcoder.status(id).reason}');
        return;
      }
      final src = '${dir.path}/clip.mkv';
      await ffmpeg([
        '-f', 'lavfi', '-i', 'testsrc2=s=1280x720:r=30:d=2',
        '-f', 'lavfi', '-i', 'sine=d=2',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', src,
      ]);
      final encoder = VideoEncoders.byId(id)!;
      final task = await run(
        src,
        TranscodeOptions(
          videoCodec: encoder.codec,
          encoderId: id,
          encoderParams: {...encoder.defaults, 'hwdec': true},
        ),
      );
      expect(task.status, TaskStatus.done, reason: task.error?.detail);
      expect(task.transcode!.command, contains('-hwaccel $hwaccel'));
      final out = task.transcode!.outputPath!;
      final streams = (await probe(out))['streams']! as List;
      expect(streams.map((s) => (s as Map)['codec_name']), contains(codec));
      if (codec == 'hevc') {
        final tag = await Process.run(media.ffprobe, [
          '-v', 'error', '-select_streams', 'v:0',
          '-show_entries', 'stream=codec_tag_string', '-of', 'csv=p=0', out,
        ]);
        expect('${tag.stdout}'.trim(), 'hvc1');
      }
    }, skip: winSkip, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('编码器检测：CPU 编码器可用，不存在的硬件编码器不会被当成可用', () async {
    await transcoder.refresh();
    expect(transcoder.ffmpegProblem, isNull);
    expect(transcoder.status('libx264').usable, isTrue);
    for (final enc in VideoEncoders.all.where((e) => e.backend.isHardware)) {
      final s = transcoder.status(enc.id);
      expect(s.state, isNot(EncoderState.probing), reason: enc.id);
      if (!s.usable) expect(s.reason, isNotNull, reason: enc.id);
    }
    // 在 macOS 上，NVENC 不可能可用。
    if (Platform.isMacOS) {
      expect(transcoder.status('h264_nvenc').usable, isFalse);
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
