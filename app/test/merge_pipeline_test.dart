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

  /// 完成阶段探测产物（out.*）时给的时长；默认等于两段默认时长之和。
  Duration outputDuration = const Duration(seconds: 20);
  List<String>? lastArgs;

  /// 执行时 ffmpeg 读到的临时文件内容（执行完临时目录就删了，只能当场读）。
  final seen = <String, String>{};

  Future<void> Function(List<String> args, CancellationToken token)? onRun;

  /// 执行时先喂给进度回调的区块。
  List<TranscodeProgress> feed = const [];

  int probeCount = 0;

  @override
  Future<MediaProbe> probe(String path) async {
    probeCount++;
    if (probes[path] case final p?) return p;
    if (path.split('/').last.startsWith('out')) {
      return MediaProbe(duration: outputDuration);
    }
    return const MediaProbe(
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
  }

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
    feed.forEach(onProgress);
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

  test('产物明显短于各段之和（某段没拼进去）时完成阶段报错', () async {
    transcoder.outputDuration = const Duration(seconds: 10);
    final t = await run(task(options()));
    expect(t.status, TaskStatus.failed);
    expect(t.stage, TaskStage.finish);
    expect(t.error?.title, '合并结果比各段加起来短，可能有一段没拼进去');
  });

  const hd = MediaProbe(
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

  test('合并阶段失败后续跑会重新探测：换进来的文件不一致照样拦下', () async {
    transcoder.onRun = (_, _) async =>
        throw const ActionableException('FFmpeg 合并失败');
    final o = options();
    final t = task(o);
    await run(t);
    expect(t.stage, TaskStage.merge);
    expect(transcoder.probeCount, 2);

    transcoder.onRun = null;
    transcoder.probes[o.segments.last.videoPath] = hd;
    await run(t);
    expect(transcoder.probeCount, 4);
    expect(t.status, TaskStatus.failed);
    expect(t.stage, TaskStage.prepare);
    expect(t.error?.title, '第 2 段的分辨率与第 1 段不同');
  });

  test('续跑按现在的时长重排：concat 列表、总长都更新', () async {
    transcoder.onRun = (_, _) async =>
        throw const ActionableException('FFmpeg 合并失败');
    final o = options();
    final t = task(o);
    await run(t);

    transcoder.onRun = null;
    transcoder.probes[o.segments.last.videoPath] = const MediaProbe(
      duration: Duration(seconds: 4),
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
    transcoder.outputDuration = const Duration(seconds: 14);
    await run(t);
    expect(t.status, TaskStatus.done, reason: t.error?.title);
    expect(t.mediaDuration, const Duration(seconds: 14));
    expect(transcoder.seen['list.txt'], contains('duration 4.000'));
  });

  test('续跑时产物位置被别的文件占了，改写到下一个序号，旁挂跟着走', () async {
    transcoder.onRun = (_, _) async =>
        throw const ActionableException('FFmpeg 合并失败');
    final a = file('a.srt', srt([(1, 2, '甲')]));
    final t = task(options(subs: [a, null], sidecar: true));
    await run(t);
    final job = t.media! as MergeJob;
    expect(job.outputPath, '${dir.path}/out.mp4');

    file('out.mp4', 'someone else');
    transcoder.onRun = null;
    await run(t);
    expect(t.status, TaskStatus.done, reason: t.error?.title);
    expect(job.outputPath, '${dir.path}/out-2.mp4');
    expect(job.sidecarPath, '${dir.path}/out-2.srt');
    expect(File('${dir.path}/out.mp4').readAsStringSync(), 'someone else');
  });

  test('字幕全落在段外：命令里不带字幕输入，不写旁挂', () async {
    final a = file('a.srt', '1\n00:00:30,000 --> 00:00:31,000\n段外\n');
    final t = await run(task(options(subs: [a, null], sidecar: true)));
    expect(t.status, TaskStatus.done, reason: t.error?.title);
    final job = t.media! as MergeJob;
    expect(job.sidecarPath, isNull);
    expect(job.segmentCues, [0, null]);
    expect(job.command, isNot(contains('merged.srt')));
    expect(t.log.map((l) => l.message), contains('1 条字幕起点在所属段的时长之外，已丢掉'));
  });

  test('两个字幕开关都关时不读字幕，坏字幕不拦合并', () async {
    final bad = file('bad.srt', 'not a subtitle');
    final o = options(subs: [bad, null]);
    final t = await run(
      task(o.copyWith(embedSubtitles: false, sidecarSubtitles: false)),
    );
    expect(t.status, TaskStatus.done, reason: t.error?.title);
    expect((t.media! as MergeJob).segmentCues, [null, null]);
  });

  test('字幕不是 UTF-8 时报编码，不静默变成乱码；带 BOM 的 UTF-16 能读', () async {
    // 「中文」的 GBK 编码。
    final gbk = File('${dir.path}/gbk.srt')
      ..writeAsBytesSync([
        ...'1\n00:00:01,000 --> 00:00:02,000\n'.codeUnits,
        0xD6,
        0xD0,
        0xCE,
        0xC4,
        0x0A,
      ]);
    final t = await run(task(options(subs: [gbk.path, null])));
    expect(t.error?.title, '第 1 段的字幕编码认不出');

    const text = '1\n00:00:01,000 --> 00:00:02,000\n中文\n';
    final utf16 = File('${dir.path}/u16.srt')
      ..writeAsBytesSync([
        0xFF,
        0xFE,
        for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
      ]);
    final ok = await run(task(options(subs: [utf16.path, null])));
    expect(ok.status, TaskStatus.done, reason: ok.error?.title);
    expect((ok.media! as MergeJob).mergedCues!.single.source, '中文');
  });

  test('完成阶段发现缺段：删掉产物，续跑从合并阶段重来且沿用路径', () async {
    transcoder.outputDuration = const Duration(seconds: 10);
    final t = await run(task(options()));
    final job = t.media! as MergeJob;
    expect(t.stage, TaskStage.finish);
    expect(File(job.outputPath!).existsSync(), isFalse);
    expect(t.resumeStage, TaskStage.merge);

    transcoder.outputDuration = const Duration(seconds: 20);
    await run(t);
    expect(t.status, TaskStatus.done, reason: t.error?.title);
    expect(job.outputPath, '${dir.path}/out.mp4');
  });

  test('旁挂字幕写不出时不留下成片：续跑不会另写一份 -2', () async {
    final a = file('a.srt', srt([(1, 2, '甲')]));
    // 旁挂位置被一个同名目录占着，写 SRT 时改名失败。File.existsSync 对
    // 目录为假，所以避让规则看不见它。
    Directory('${dir.path}/out.srt').createSync();
    final t = await run(task(options(subs: [a, null], sidecar: true)));
    expect(t.status, TaskStatus.failed);
    expect(t.stage, TaskStage.merge);
    final job = t.media! as MergeJob;
    expect(File(job.outputPath!).existsSync(), isFalse);
    expect(File('${job.outputPath}.part').existsSync(), isFalse);
  });

  test('ffmpeg 出错（不是取消）时也删掉 .part', () async {
    transcoder.onRun = (args, _) async {
      await File(args.last).writeAsString('half');
      throw const ActionableException('FFmpeg 合并失败');
    };
    final t = await run(task(options()));
    expect(t.status, TaskStatus.failed);
    expect(
      File('${(t.media! as MergeJob).outputPath}.part').existsSync(),
      isFalse,
    );
  });

  test('进度折算到合并阶段：进度、剩余时间、倍速与阶段备注', () async {
    transcoder.feed = const [
      TranscodeProgress(position: Duration(seconds: 5), frame: 150, speed: 10),
    ];
    final t = task(options());
    final job = t.media! as MergeJob;
    var sawProgress = false;
    await runner.run(
      t,
      token: CancellationToken(),
      onChange: () {
        if (t.stage == TaskStage.merge && t.progress > 0 && t.progress < 1) {
          sawProgress = true;
          expect(t.progress, 0.25);
          expect(t.eta, const Duration(milliseconds: 1500));
          expect(job.speed, 10);
        }
      },
    );
    expect(sawProgress, isTrue);
    expect(t.stages[TaskStage.merge]!.note, '帧 150 · 10.0x');
    expect(job.speed, isNull);
  });

  test('ffmpeg 失败时标题写「合并失败」而不是「转码失败」', () {
    final e = Transcoder.describeFailure(
      'Error initializing output stream 0:0',
      null,
      action: '合并',
    );
    expect(e.message, 'FFmpeg 合并失败');
    final container = Transcoder.describeFailure(
      'Could not find tag for codec vp9',
      null,
      action: '合并',
    );
    expect(container.hint, contains('先用「转码」'));
    expect(
      Transcoder.describeFailure(
        'Could not find tag for codec',
        'libx264',
      ).hint,
      '换一个容器，或把那一路改为重新编码而不是复制。',
    );
  });
}
