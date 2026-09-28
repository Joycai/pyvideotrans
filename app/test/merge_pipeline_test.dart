import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/mux/merge_options.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_control.dart';
import 'package:subtitle_studio/domain/transcode/command.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

import 'helpers.dart';

/// 不起子进程的 Transcoder：探测按文件名给结果，执行时把参数记下来，
/// 按 [onRun] 决定写出产物、失败还是等取消。
class _FakeTranscoder extends Transcoder {
  _FakeTranscoder();

  final probes = <String, MediaProbe>{};
  List<String>? lastArgs;

  /// 执行时 ffmpeg 读到的临时文件内容（执行完临时目录就删了，只能当场读）。
  final seen = <String, String>{};

  Future<void> Function(List<String> args, CancellationToken token)? onRun;

  @override
  Future<MediaProbe> probe(String path) async =>
      probes[path] ??
      const MediaProbe(
        duration: Duration(seconds: 10),
        video: [
          VideoStreamInfo(
            codec: 'h264',
            width: 640,
            height: 360,
            fps: 30,
            pixFmt: 'yuv420p',
          ),
        ],
        audio: [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
      );

  @override
  Future<void> run({
    required List<String> args,
    required String? encoderId,
    String action = '转码',
    required CancellationToken token,
    required void Function(TranscodeProgress) onProgress,
  }) async {
    lastArgs = args;
    for (final (i, a) in args.indexed) {
      if (a != '-i') continue;
      final path = args[i + 1];
      seen[path.split('/').last] = File(path).readAsStringSync();
    }
    await (onRun ?? _writeOutput)(args, token);
  }

  static Future<void> _writeOutput(List<String> args, CancellationToken _) =>
      File(args.last).writeAsString('video');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late _FakeTranscoder transcoder;
  late TaskRunner runner;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('merge_pipeline_test');
    transcoder = _FakeTranscoder();
    runner = TaskRunner(
      settings: await AppSettings.load(),
      workDir: dir.path,
      transcoder: transcoder,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  String file(String name, [String content = '']) =>
      (File('${dir.path}/$name')..writeAsStringSync(content)).path;

  String srt(List<(int, int, String)> cues) => [
    for (final (i, (s, e, t)) in cues.indexed)
      '${i + 1}\n'
          '00:00:${'$s'.padLeft(2, '0')},000 --> 00:00:${'$e'.padLeft(2, '0')},000\n'
          '$t\n',
  ].join('\n');

  SubtitleTask task(MergeOptions options) => SubtitleTask(
    id: 'm',
    sourcePath: options.segments.first.videoPath,
    kind: TaskKind.merge,
    options: testOptions(),
    media: MergeJob(options: options),
  );

  MergeOptions options({
    List<String?> subs = const [null, null],
    bool sidecar = false,
  }) => MergeOptions(
    segments: [
      for (final (i, sub) in subs.indexed)
        MergeSegment(
          videoPath: file('v$i.mp4'),
          subtitlePath: sub,
          chapterTitle: '第 ${i + 1} 章',
        ),
    ],
    sidecarSubtitles: sidecar,
    outputStem: 'out',
  );

  Future<SubtitleTask> run(SubtitleTask t, [CancellationToken? token]) async {
    await runner.run(t, token: token ?? CancellationToken(), onChange: () {});
    return t;
  }

  test('合并任务只有四个阶段', () {
    expect(TaskKind.merge.stages, [
      TaskStage.queued,
      TaskStage.prepare,
      TaskStage.merge,
      TaskStage.finish,
    ]);
    expect(TaskKind.merge.isMedia, isTrue);
    expect(TaskKind.merge.needsRecognition, isFalse);
  });

  test('跑完：章节、平移后的字幕内嵌并旁挂、产物与命令', () async {
    final a = file('a.srt', srt([(1, 2, '甲')]));
    final b = file('b.srt', srt([(0, 1, '乙'), (9, 12, '越界截尾')]));
    final t = await run(task(options(subs: [a, b], sidecar: true)));

    expect(
      t.status,
      TaskStatus.done,
      reason: '${t.error?.title} ${t.error?.detail}',
    );
    final job = t.media! as MergeJob;
    expect(job.outputPath, '${dir.path}/out.mp4');
    expect(File(job.outputPath!).readAsStringSync(), 'video');
    expect(job.outputBytes, 5);
    expect(t.mediaDuration, const Duration(seconds: 20));
    expect(job.segmentCues, [1, 2]);
    expect(job.command, contains('-i list.txt -i chapters.txt -i merged.srt'));
    expect(t.fileName, 'out.mp4');

    expect(transcoder.seen['list.txt'], contains('duration 10.000'));
    expect(transcoder.seen['chapters.txt'], contains('START=10000\nEND=20000'));
    expect(transcoder.seen['chapters.txt'], contains('title=第 2 章'));
    final merged = transcoder.seen['merged.srt']!;
    expect(merged, contains('00:00:10,000 --> 00:00:11,000\n乙'));
    expect(merged, contains('00:00:19,000 --> 00:00:20,000\n越界截尾'));
    expect(File('${dir.path}/out.srt').readAsStringSync(), merged);
    expect(job.sidecarPath, '${dir.path}/out.srt');
  });

  test('参数不一致在准备阶段拦下，指明第几段哪一项', () async {
    final o = options();
    transcoder.probes[o.segments.last.videoPath] = const MediaProbe(
      duration: Duration(seconds: 3),
      video: [
        VideoStreamInfo(
          codec: 'h264',
          width: 1280,
          height: 720,
          fps: 30,
          pixFmt: 'yuv420p',
        ),
      ],
      audio: [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
    );
    final t = await run(task(o));
    expect(t.status, TaskStatus.failed);
    expect(t.stage, TaskStage.prepare);
    expect(t.error?.title, '第 2 段的分辨率与第 1 段不同');
    expect(t.error?.detail, '分辨率 1280×720 ≠ 第 1 段 640×360');
    expect(transcoder.lastArgs, isNull);
  });

  test('某段文件不见了', () async {
    final o = options();
    File(o.segments.last.videoPath).deleteSync();
    final t = await run(task(o));
    expect(t.error?.title, '第 2 段的文件找不到了');
    expect(t.error?.detail, o.segments.last.videoPath);
  });

  test('字幕读不出条目时指明第几段', () async {
    final bad = file('bad.srt', 'not a subtitle');
    final t = await run(task(options(subs: [null, bad])));
    expect(t.status, TaskStatus.failed);
    expect(t.error?.title, '第 2 段的字幕读不出来');
  });

  test('没字幕时不带字幕输入，也不写旁挂', () async {
    final t = await run(task(options(sidecar: true)));
    expect(t.status, TaskStatus.done);
    final job = t.media! as MergeJob;
    expect(job.sidecarPath, isNull);
    expect(transcoder.lastArgs!.join(' '), isNot(contains('merged.srt')));
    expect(File('${dir.path}/out.srt').existsSync(), isFalse);
  });

  test('取消后 .part 与临时目录都清掉；续跑沿用产物路径', () async {
    final token = CancellationToken();
    String? tmpDir;
    transcoder.onRun = (args, _) async {
      tmpDir = File(args[args.indexOf('-i') + 1]).parent.path;
      await File(args.last).writeAsString('half');
      token.cancel();
      throw const TaskCancelled();
    };
    final t = task(options());
    await run(t, token);

    expect(t.status, TaskStatus.cancelled);
    final job = t.media! as MergeJob;
    expect(File('${job.outputPath}.part').existsSync(), isFalse);
    expect(Directory(tmpDir!).existsSync(), isFalse);

    // 续跑时准备阶段重跑，但产物路径沿用，不会变成 out-2。
    final first = job.outputPath;
    transcoder.onRun = null;
    await run(t);
    expect(t.status, TaskStatus.done);
    expect(job.outputPath, first);
  });

  test('ffmpeg 失败时标题写「合并失败」而不是「转码失败」', () {
    final e = Transcoder.describeFailure(
      'Error initializing output stream 0:0',
      null,
      action: '合并',
    );
    expect(e.message, 'FFmpeg 合并失败');
  });
}
