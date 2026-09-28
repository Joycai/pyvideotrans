import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/mux/merge_options.dart';
import 'package:subtitle_studio/domain/mux/merge_rules.dart';
import 'package:subtitle_studio/domain/mux/mux_plan.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/domain/transcode/codecs.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';

import 'helpers.dart';

MediaProbe _probe({
  Duration? duration = const Duration(minutes: 1),
  List<VideoStreamInfo>? video,
  List<AudioStreamInfo>? audio,
}) => MediaProbe(
  duration: duration,
  video: video ?? [_v()],
  audio: audio ?? [_a()],
);

VideoStreamInfo _v({
  String codec = 'h264',
  String? profile = 'High',
  int width = 1920,
  int height = 1080,
  double fps = 30,
  String pixFmt = 'yuv420p',
}) => VideoStreamInfo(
  codec: codec,
  profile: profile,
  width: width,
  height: height,
  fps: fps,
  pixFmt: pixFmt,
);

AudioStreamInfo _a({
  String codec = 'aac',
  String? profile = 'LC',
  int sampleRate = 48000,
  int channels = 2,
}) => AudioStreamInfo(
  codec: codec,
  profile: profile,
  sampleRate: sampleRate,
  channels: channels,
);

MergeSegment _seg(String path, {String? sub}) => MergeSegment(
  videoPath: path,
  subtitlePath: sub,
  chapterTitle: MergeSegment.defaultTitle(path),
);

Cue _cue(int start, int end, [String text = 'x']) =>
    Cue(index: 0, startMs: start, endMs: end, source: text);

void main() {
  group('ffprobe 补读的字段', () {
    test('视频 profile、音频采样率（字符串）与 profile', () {
      final probe = MediaProbe.fromJson({
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'profile': 'High',
            'width': 1920,
            'height': 1080,
          },
          {
            'codec_type': 'audio',
            'codec_name': 'aac',
            'profile': 'LC',
            'sample_rate': '44100',
            'channels': 2,
          },
        ],
        'format': {'duration': '12.5'},
      });
      expect(probe.video.single.profile, 'High');
      expect(probe.audio.single.sampleRate, 44100);
      expect(probe.audio.single.profile, 'LC');
    });
  });

  group('mergeIssues', () {
    List<MergeIssue?> check(MediaProbe second, {MediaProbe? first}) =>
        mergeIssues([first ?? _probe(), second], OutputContainer.mp4);

    test('参数一致时都可以拼', () {
      expect(check(_probe()), [null, null]);
    });

    final cases = <String, (MediaProbe, MergeIssueKind, String)>{
      '视频流路数': (
        _probe(video: [_v(), _v()]),
        MergeIssueKind.streams,
        '视频流 2 路 ≠ 第 1 段 1 路',
      ),
      '音频流路数': (
        _probe(audio: []),
        MergeIssueKind.streams,
        '音频流 0 路 ≠ 第 1 段 1 路',
      ),
      '视频编码': (
        _probe(
          video: [_v(codec: 'hevc', profile: 'Main')],
        ),
        MergeIssueKind.video,
        '视频编码 HEVC ≠ 第 1 段 H.264',
      ),
      'profile': (
        _probe(video: [_v(profile: 'Main')]),
        MergeIssueKind.video,
        '视频 profile Main ≠ 第 1 段 High',
      ),
      '分辨率': (
        _probe(video: [_v(width: 1280, height: 720)]),
        MergeIssueKind.video,
        '分辨率 1280×720 ≠ 第 1 段 1920×1080',
      ),
      '像素格式': (
        _probe(video: [_v(pixFmt: 'yuv420p10le')]),
        MergeIssueKind.video,
        '像素格式 yuv420p10le ≠ 第 1 段 yuv420p',
      ),
      '帧率': (
        _probe(video: [_v(fps: 25)]),
        MergeIssueKind.video,
        '帧率 25p ≠ 第 1 段 30p',
      ),
      '音频编码': (
        _probe(audio: [_a(codec: 'mp3', profile: null)]),
        MergeIssueKind.audio,
        '音频编码 MP3 ≠ 第 1 段 AAC',
      ),
      '采样率': (
        _probe(audio: [_a(sampleRate: 44100)]),
        MergeIssueKind.audio,
        '采样率 44.1 kHz ≠ 第 1 段 48 kHz',
      ),
      '声道': (
        _probe(audio: [_a(channels: 1)]),
        MergeIssueKind.audio,
        '声道 1ch ≠ 第 1 段 2ch',
      ),
    };
    for (final MapEntry(key: name, value: (probe, kind, message))
        in cases.entries) {
      test('$name不一致', () {
        final issues = check(probe);
        expect(issues.first, isNull);
        expect(issues.last?.kind, kind);
        expect(issues.last?.message, message);
      });
    }

    test('不一致的项附带第 1 段的值，给页脚提示转成什么', () {
      final issue = check(_probe(video: [_v(width: 1280, height: 720)])).last!;
      expect(issue.field, '分辨率');
      expect(issue.expected, '1920×1080');
    });

    test('帧率差不超过 0.01 算一致（29.97 的两种写法）', () {
      expect(
        check(
          _probe(video: [_v(fps: 29.97)]),
          first: _probe(video: [_v(fps: 29.971)]),
        ),
        [null, null],
      );
    });

    test('读不出的项不比，只报第一处问题', () {
      final second = _probe(
        video: [_v(profile: null, width: 1280, height: 720, fps: 25)],
      );
      expect(check(second).last?.field, '分辨率');
    });

    test('编码放不进所选容器，第 1 段也会被标出', () {
      final vp9 = _probe(video: [_v(codec: 'vp9', profile: null)]);
      final issues = mergeIssues([vp9, vp9], OutputContainer.mov);
      expect(issues.first?.kind, MergeIssueKind.container);
      expect(issues.first?.message, 'VP9 视频不能原样放进 MOV');
      expect(mergeIssues([vp9, vp9], OutputContainer.mp4), [null, null]);

      final flac = _probe(audio: [_a(codec: 'flac', profile: null)]);
      expect(
        mergeIssues([flac, flac], OutputContainer.mov).first?.message,
        'FLAC 音频不能原样放进 MOV',
      );
    });

    test('读不出时长的段报错，算不出偏移', () {
      final issues = check(_probe(duration: null));
      expect(issues.last?.kind, MergeIssueKind.duration);
    });

    test('还没探测完的段结果未知；第 1 段未知时其余段只查容器与时长', () {
      expect(
        mergeIssues([
          null,
          _probe(video: [_v(width: 640, height: 360)]),
        ], OutputContainer.mp4),
        [null, null],
      );
      expect(mergeIssues([_probe(), null], OutputContainer.mp4), [null, null]);
    });
  });

  group('偏移、章节与 concat 列表', () {
    const durations = [
      Duration(minutes: 32, seconds: 10),
      Duration(minutes: 24, seconds: 36, milliseconds: 500),
      Duration(minutes: 11, seconds: 46),
    ];

    test('偏移是前缀和', () {
      expect(offsets(durations), [
        Duration.zero,
        const Duration(minutes: 32, seconds: 10),
        const Duration(minutes: 56, seconds: 46, milliseconds: 500),
      ]);
      expect(offsets(const []), isEmpty);
    });

    test('章节起止与偏移一致，标题转义特殊字符', () {
      final text = ffmetadata(['第一段', 'a=b;c#d\\e\nf', 'end'], durations);
      expect(text, startsWith(';FFMETADATA1\n'));
      expect('[CHAPTER]'.allMatches(text), hasLength(3));
      expect(text, contains('START=1930000\nEND=3406500\n'));
      expect(
        text,
        contains(
          r'title=a\=b\;c\#d\\e\'
          '\nf\n',
        ),
      );
      expect(text, contains('START=3406500\nEND=4112500\n'));
    });

    test('concat 列表：绝对路径、单引号转义、中文路径、毫秒精度时长', () {
      final text = concatList(
        ["/v/it's.mp4", '/视频/第二段.mp4'],
        const [Duration(seconds: 1, milliseconds: 5), Duration(minutes: 2)],
      );
      expect(
        text,
        'ffconcat version 1.0\n'
        "file '/v/it'\\''s.mp4'\n"
        'duration 1.005\n'
        "file '/视频/第二段.mp4'\n"
        'duration 120.000\n',
      );
    });
  });

  group('concatCues', () {
    test('按偏移平移，序号从 1 重排', () {
      final out = concatCues([
        (
          cues: [_cue(0, 1000, 'a')],
          offset: Duration.zero,
          length: const Duration(seconds: 10),
        ),
        (
          cues: [_cue(500, 1500, 'b')],
          offset: const Duration(seconds: 10),
          length: const Duration(seconds: 10),
        ),
      ]);
      expect(
        [for (final c in out) (c.index, c.startMs, c.endMs, c.source)],
        [(1, 0, 1000, 'a'), (2, 10500, 11500, 'b')],
      );
    });

    test('越出段尾的截到段尾，起点在段外的丢掉', () {
      final out = concatCues([
        (
          cues: [_cue(8000, 12000), _cue(10000, 11000), _cue(11000, 12000)],
          offset: Duration.zero,
          length: const Duration(seconds: 10),
        ),
      ]);
      expect([for (final c in out) (c.startMs, c.endMs)], [(8000, 10000)]);
    });

    test('没挂字幕的段不贡献字幕，但偏移照算', () {
      final out = concatCues([
        (
          cues: null,
          offset: Duration.zero,
          length: const Duration(seconds: 30),
        ),
        (
          cues: [_cue(0, 1000)],
          offset: const Duration(seconds: 30),
          length: const Duration(seconds: 5),
        ),
      ]);
      expect(out.single.startMs, 30000);
      expect(out.single.index, 1);
    });

    test('全都没字幕时是空的', () {
      expect(
        concatCues([
          (
            cues: null,
            offset: Duration.zero,
            length: const Duration(seconds: 1),
          ),
          (
            cues: const [],
            offset: const Duration(seconds: 1),
            length: const Duration(seconds: 1),
          ),
        ]),
        isEmpty,
      );
    });

    test('保留译文与说话人等其余字段', () {
      final out = concatCues([
        (
          cues: [
            const Cue(
              index: 7,
              startMs: 0,
              endMs: 10,
              source: 's',
              translation: 't',
              speaker: 1,
            ),
          ],
          offset: const Duration(seconds: 2),
          length: const Duration(seconds: 1),
        ),
      ]);
      expect(out.single.translation, 't');
      expect(out.single.speaker, 1);
    });
  });

  group('mergeOutputPath', () {
    final options = MergeOptions(
      segments: [_seg('/v/a.mp4'), _seg('/v/b.mp4')],
      outputStem: 'a.merged',
    );

    test('默认写到第 1 段所在目录', () {
      expect(mergeOutputPath(options, exists: (_) => false), (
        video: '/v/a.merged.mp4',
        sidecar: null,
      ));
    });

    test('同名已存在时加序号', () {
      expect(
        mergeOutputPath(options, exists: (p) => p == '/v/a.merged.mp4').video,
        '/v/a.merged-2.mp4',
      );
    });

    test('开了旁挂时 SRT 撞名也要避让，两者序号一致', () {
      final o = options.copyWith(sidecarSubtitles: true);
      expect(mergeOutputPath(o, exists: (p) => p == '/v/a.merged.srt'), (
        video: '/v/a.merged-2.mp4',
        sidecar: '/v/a.merged-2.srt',
      ));
    });

    test('不写到某一段源文件身上；指定目录与 mov 扩展名', () {
      final o = MergeOptions(
        segments: [_seg('/v/x.mov'), _seg('/v/y.mov')],
        container: OutputContainer.mov,
        outputStem: 'y',
      );
      expect(mergeOutputPath(o, exists: (_) => false).video, '/v/y-2.mov');
      final custom = o.copyWith(
        outputLocation: OutputLocation.custom,
        outputDir: '/out/',
      );
      expect(mergeOutputPath(custom, exists: (_) => false).video, '/out/y.mov');
    });

    test('Windows 路径沿用反斜杠', () {
      final o = MergeOptions(
        segments: [_seg(r'C:\v\a.mp4'), _seg(r'C:\v\b.mp4')],
        outputStem: 'a.merged',
      );
      expect(
        mergeOutputPath(o, exists: (_) => false).video,
        r'C:\v\a.merged.mp4',
      );
    });
  });

  group('MergeOptions', () {
    test('问题：段数、文件名、指定目录', () {
      expect(const MergeOptions().problem, '至少要 2 段才能合并');
      final two = MergeOptions(segments: [_seg('/a.mp4'), _seg('/b.mp4')]);
      expect(two.problem, '文件名不能为空');
      expect(two.copyWith(outputStem: 'x/y').problem, contains('不能有'));
      expect(two.copyWith(outputStem: 'ok').problem, isNull);
      expect(
        two
            .copyWith(outputStem: 'ok', outputLocation: OutputLocation.custom)
            .problem,
        '还没有选择输出目录',
      );
    });

    test('默认值：mp4、章节与内嵌开、旁挂关', () {
      const o = MergeOptions();
      expect(o.container, OutputContainer.mp4);
      expect(
        (o.chapters, o.embedSubtitles, o.sidecarSubtitles),
        (true, true, false),
      );
      expect(MergeOptions.defaultStem('/v/采访 1.mp4'), '采访 1.merged');
      expect(MergeSegment.defaultTitle('/v/采访 1.mp4'), '采访 1');
    });

    test('JSON 往返', () {
      final o = MergeOptions(
        segments: [
          const MergeSegment(
            videoPath: '/v/a.mp4',
            subtitlePath: '/v/a.srt',
            chapterTitle: '开场',
          ),
          _seg('/v/b.mp4'),
        ],
        container: OutputContainer.mov,
        chapters: false,
        embedSubtitles: false,
        sidecarSubtitles: true,
        outputLocation: OutputLocation.custom,
        outputDir: '/out',
        outputStem: '成片',
      );
      final back = MergeOptions.fromJson(
        (jsonDecode(jsonEncode(o.toJson())) as Map).cast<String, Object?>(),
      );
      expect(back.toJson(), o.toJson());
      expect(back.segments.first.subtitlePath, '/v/a.srt');
      expect(back.segments.last.subtitlePath, isNull);
    });

    test('缺项与坏值回落默认，坏的段丢掉', () {
      final back = MergeOptions.fromJson({
        'segments': [
          {'videoPath': '/v/a.mp4'},
          {'subtitlePath': '/v/x.srt'},
          'junk',
          {'videoPath': '/v/b.mp4', 'chapterTitle': '  ', 'subtitlePath': 3},
        ],
        'container': 'mkv',
        'chapters': 'yes',
        'outputLocation': 'custom',
      });
      expect(
        [for (final s in back.segments) s.videoPath],
        ['/v/a.mp4', '/v/b.mp4'],
      );
      expect(back.segments.first.chapterTitle, 'a');
      expect(back.segments.last.chapterTitle, 'b');
      expect(back.segments.last.subtitlePath, isNull);
      expect(back.container, OutputContainer.mp4);
      expect(back.chapters, isTrue);
      expect(back.outputLocation, OutputLocation.besideSource);
      expect(back.outputStem, 'a.merged');
    });
  });

  group('MuxPlan', () {
    String argsOf({
      String? chapters,
      String? subtitles,
      bool progress = false,
    }) => MuxPlan.merge(
      concatList: 'list.txt',
      chapters: chapters,
      subtitles: subtitles,
      container: OutputContainer.mp4,
    ).args('out.mp4', progress: progress).join(' ');

    test('章节 + 内嵌字幕：与设计文档的示例逐项一致', () {
      expect(
        argsOf(chapters: 'chapters.txt', subtitles: 'merged.srt'),
        '-hide_banner -nostdin -y '
        '-f concat -safe 0 -i list.txt -i chapters.txt -i merged.srt '
        '-map 0:V? -map 0:a? -map 2:s '
        '-map_metadata 1 -map_chapters 1 '
        '-c copy -c:s mov_text -f mp4 out.mp4',
      );
    });

    test('只有章节：不带字幕输入与字幕编码', () {
      expect(
        argsOf(chapters: 'chapters.txt'),
        '-hide_banner -nostdin -y '
        '-f concat -safe 0 -i list.txt -i chapters.txt '
        '-map 0:V? -map 0:a? '
        '-map_metadata 1 -map_chapters 1 '
        '-c copy -f mp4 out.mp4',
      );
    });

    test('只有字幕：字幕是输入 1，并去掉第 1 段自带的章节', () {
      expect(
        argsOf(subtitles: 'merged.srt'),
        '-hide_banner -nostdin -y '
        '-f concat -safe 0 -i list.txt -i merged.srt '
        '-map 0:V? -map 0:a? -map 1:s '
        '-map_chapters -1 '
        '-c copy -c:s mov_text -f mp4 out.mp4',
      );
    });

    test('都不要：只拼音视频', () {
      expect(
        argsOf(),
        '-hide_banner -nostdin -y -f concat -safe 0 -i list.txt '
        '-map 0:V? -map 0:a? -map_chapters -1 -c copy -f mp4 out.mp4',
      );
    });

    test('进度输出只在执行时加；mov 的 -f 与字幕编码', () {
      expect(
        argsOf(progress: true),
        contains('-v error -progress pipe:1 -nostats'),
      );
      expect(argsOf(), isNot(contains('-progress')));
      final mov = MuxPlan.merge(
        concatList: 'l',
        subtitles: 's',
        container: OutputContainer.mov,
      ).args('o.part');
      expect(mov.join(' '), endsWith('-c copy -c:s mov_text -f mov o.part'));
    });
  });

  group('MergeJob', () {
    final options = MergeOptions(
      segments: [
        _seg('/v/a.mp4', sub: '/v/a.srt'),
        _seg('/v/b.mp4'),
        _seg('/v/c.mp4'),
      ],
      outputStem: 'a.merged',
    );

    test('摘要与名字：产物定下前叫「a.mp4 等 3 段」', () {
      final job = MergeJob(options: options);
      expect(job.summary, '3 段 → MP4');
      expect(job.title, 'a.mp4 等 3 段');
      expect(job.outputLabel, '视频 · MP4');
      expect(job.workStage, TaskStage.merge);
      job.outputPath = '/v/a.merged.mp4';
      expect(job.title, 'a.merged.mp4');
    });

    test('存进任务 JSON 的 merge 键，读回仍是 MergeJob', () {
      final task = SubtitleTask(
        id: 'm1',
        sourcePath: '/v/a.mp4',
        kind: TaskKind.merge,
        options: testOptions(),
        media: MergeJob(
          options: options,
          segmentDurations: const [
            Duration(seconds: 10),
            Duration(seconds: 20),
            Duration(milliseconds: 30500),
          ],
          segmentCues: const [12, null, null],
          outputPath: '/v/a.merged.mp4',
          sidecarPath: '/v/a.merged.srt',
          command: 'ffmpeg …',
          outputBytes: 99,
        ),
      );
      final json = (jsonDecode(jsonEncode(task.toJson())) as Map)
          .cast<String, Object?>();
      expect(json.keys, contains('merge'));
      expect(json.keys, isNot(contains('transcode')));
      final back = SubtitleTask.fromJson(json, fallbackOptions: testOptions());
      final job = back.media! as MergeJob;
      expect(job.options.toJson(), options.toJson());
      expect(job.segmentDurations, const [
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(milliseconds: 30500),
      ]);
      expect(job.segmentCues, [12, null, null]);
      expect(
        (job.outputPath, job.sidecarPath, job.command, job.outputBytes),
        ('/v/a.merged.mp4', '/v/a.merged.srt', 'ffmpeg …', 99),
      );
      expect(back.fileName, 'a.merged.mp4');
    });

    test('缺项回落；与段数对不上的缓存值作废', () {
      final job = MergeJob.fromJson({
        'options': options.toJson(),
        'segmentDurationsMs': [1000, 2000],
        'segmentCues': 'bad',
      });
      expect(job.options.segments, hasLength(3));
      expect(job.segmentDurations, isNull);
      expect(job.segmentCues, isNull);
      expect(job.outputPath, isNull);
      expect(MergeJob.fromJson(const {}).options.segments, isEmpty);
    });
  });
}
