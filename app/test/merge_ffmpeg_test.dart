import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/mux/merge_options.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/transcode/codecs.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

/// 真的跑 ffmpeg 的端到端测试：入队 → 准备 → 合并 → 完成，用 ffprobe 核对
/// 时长、章节与字幕流。本机没有 ffmpeg 时整组跳过。
void main() {
  final media = Ffmpeg();
  final Object skip = media.available ? false : '本机没有 ffmpeg';

  late Directory dir;
  late TaskQueue queue;

  Future<void> ffmpeg(List<String> args) async {
    final r = await Process.run(media.ffmpeg, [
      '-hide_banner',
      '-v',
      'error',
      '-y',
      ...args,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  /// 一段 [seconds] 秒的 h264 + aac 短片。
  Future<String> clip(
    String name,
    int seconds, {
    String size = '320x240',
  }) async {
    final path = '${dir.path}/$name';
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'testsrc2=s=$size:r=25:d=$seconds',
      '-f',
      'lavfi',
      '-i',
      'sine=d=$seconds:sample_rate=48000',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-shortest',
      path,
    ]);
    return path;
  }

  Future<Map<String, Object?>> probe(String path) async {
    final r = await Process.run(media.ffprobe, [
      '-v',
      'error',
      '-show_chapters',
      '-show_format',
      '-show_entries',
      'stream=codec_type,codec_name:stream_tags=language',
      '-of',
      'json',
      path,
    ]);
    return (jsonDecode('${r.stdout}') as Map).cast<String, Object?>();
  }

  Future<SubtitleTask> run(MergeOptions options) async {
    final task = queue.enqueueMerge(options);
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (task.isActive && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return task;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    dir = await Directory.systemTemp.createTemp('merge_test');
    queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: dir.path,
        media: media,
        transcoder: Transcoder(media: media),
      ),
      settings: settings,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  for (final container in MergeOptions.containers) {
    test('两段合并成 ${container.label}：时长、章节、字幕流与旁挂 SRT', () async {
      final a = await clip('a.mp4', 2);
      final b = await clip('b.mp4', 3);
      final bSrt = File('${dir.path}/b.zh.srt')
        ..writeAsStringSync('1\n00:00:00,500 --> 00:00:01,500\n第二段\n');
      final task = await run(
        MergeOptions(
          segments: [
            MergeSegment(videoPath: a, chapterTitle: '开场'),
            MergeSegment(
              videoPath: b,
              subtitlePath: bSrt.path,
              chapterTitle: '正片',
            ),
          ],
          container: container,
          sidecarSubtitles: true,
          outputStem: 'out',
        ),
      );

      expect(
        task.status,
        TaskStatus.done,
        reason: '${task.error?.title}\n${task.error?.detail}',
      );
      for (final s in TaskKind.merge.stages) {
        expect(task.stages[s]!.state, StageState.done, reason: s.label);
      }
      final job = task.media! as MergeJob;
      expect(job.outputPath, '${dir.path}/out.${container.extension}');
      expect(File('${job.outputPath}.part').existsSync(), isFalse);

      final info = await probe(job.outputPath!);
      final seconds = double.parse('${(info['format'] as Map)['duration']}');
      expect(seconds, closeTo(5, 0.2));

      final chapters = (info['chapters'] as List).cast<Map>();
      expect(chapters, hasLength(2));
      expect(double.parse('${chapters[1]['start_time']}'), closeTo(2, 0.05));
      expect((chapters[1]['tags'] as Map)['title'], '正片');

      final streams = (info['streams'] as List).cast<Map>();
      expect([
        for (final s in streams) s['codec_type'],
      ], containsAll(['video', 'audio', 'subtitle']));
      final subtitle = streams.firstWhere((s) => s['codec_type'] == 'subtitle');
      expect(subtitle['codec_name'], 'mov_text');
      // 语言从 `b.zh.srt` 推断；MOV 只认 Macintosh 语言表里的码，`chi` 在表里。
      expect((subtitle['tags'] as Map)['language'], 'chi');

      expect(job.sidecarPath, '${dir.path}/out.zh.srt');

      final sidecar = Srt.parse(File(job.sidecarPath!).readAsStringSync());
      expect(sidecar.single.startMs, 2500);
      expect(sidecar.single.endMs, 3500);
    }, skip: skip);
  }

  test('分辨率不同的两段在准备阶段被拦下，不跑 ffmpeg', () async {
    final a = await clip('a.mp4', 1);
    final b = await clip('b.mp4', 1, size: '640x360');
    final task = await run(
      MergeOptions(
        segments: [
          MergeSegment(videoPath: a, chapterTitle: 'a'),
          MergeSegment(videoPath: b, chapterTitle: 'b'),
        ],
        outputStem: 'out',
      ),
    );
    expect(task.status, TaskStatus.failed);
    expect(task.stage, TaskStage.prepare);
    expect(task.error?.title, '第 2 段的分辨率与第 1 段不同');
    expect(File('${dir.path}/out.mp4').existsSync(), isFalse);
  }, skip: skip);

  test('关掉章节与字幕：只拼音视频，没有章节', () async {
    final a = await clip('a.mp4', 1);
    final b = await clip('b.mp4', 1);
    final task = await run(
      MergeOptions(
        segments: [
          MergeSegment(videoPath: a, chapterTitle: 'a'),
          MergeSegment(videoPath: b, chapterTitle: 'b'),
        ],
        container: OutputContainer.mov,
        chapters: false,
        outputStem: 'plain',
      ),
    );
    expect(task.status, TaskStatus.done, reason: task.error?.detail);
    final info = await probe((task.media! as MergeJob).outputPath!);
    expect(info['chapters'] as List, isEmpty);
    expect([
      for (final s in (info['streams'] as List).cast<Map>()) s['codec_type'],
    ], isNot(contains('subtitle')));
  }, skip: skip);
}
