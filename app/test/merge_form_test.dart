import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/task_control.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/domain/transcode/codecs.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';
import 'package:subtitle_studio/features/merge/merge_form.dart';
import 'package:subtitle_studio/features/shared/footer_message.dart';
import 'package:subtitle_studio/services/file_io.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

MediaProbe probeOf({
  int seconds = 60,
  int width = 1920,
  int height = 1080,
  String video = 'h264',
}) => MediaProbe(
  duration: Duration(seconds: seconds),
  video: [
    VideoStreamInfo(
      codec: video,
      width: width,
      height: height,
      fps: 30,
      pixFmt: 'yuv420p',
    ),
  ],
  audio: const [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
);

/// 探测按路径给结果；[gates] 里有的路径要等放行才回来，用来测「探测中」。
class _FakeTranscoder extends Transcoder {
  final probes = <String, MediaProbe>{};
  final gates = <String, Completer<void>>{};

  @override
  Future<MediaProbe> probe(String path) async {
    await gates[path]?.future;
    if (path.contains('broken')) {
      throw const ActionableException(
        'ffprobe 读不出这个文件',
        detail: 'moov atom not found',
      );
    }
    return probes[path] ?? probeOf();
  }
}

const _srt =
    '1\n00:00:01,000 --> 00:00:02,000\n一\n\n2\n00:00:03,000 --> 00:00:04,000\n二\n';

void main() {
  late AppSettings settings;
  late _FakeTranscoder transcoder;
  late Map<String, List<String>> dirs;
  late Map<String, Object> files;
  late MergeFormController form;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    transcoder = _FakeTranscoder();
    dirs = {};
    files = {};
    form = MergeFormController(
      settings: settings,
      transcoder: transcoder,
      listDir: (dir) async => dirs[dir] ?? const [],
      readSubtitle: (path) async => switch (files[path]) {
        final String text => text,
        final Exception e => throw e,
        _ => throw const FileSystemException('找不到文件'),
      },
      pickDirectory: () async => '/out',
    );
  });

  /// 等异步的探测与字幕解析都回来。
  Future<void> settle() =>
      Future<void>.delayed(Duration.zero)
          .then((_) => Future<void>.delayed(Duration.zero));

  test('空与一段时不能开始，页脚引导添加', () async {
    expect(form.footer, (text: '先添加至少 2 段视频', tone: FooterTone.add));
    await form.addPaths(['/v/a.mp4']);
    expect(form.footer.text, '至少要 2 段才能合并');
    expect(form.canStart, isFalse);
  });

  test('两段就绪：页脚、文件名跟随第 1 段、起点与总长', () async {
    transcoder.probes['/v/b.mp4'] = probeOf(seconds: 30);
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    await settle();
    expect(form.canStart, isTrue);
    expect(form.options.outputStem, 'a.merged');
    expect(form.footer.text, '将合并成 a.merged.mp4 · 2 个章节');
    expect(form.offsets, [Duration.zero, const Duration(seconds: 60)]);
    expect(form.totalDuration, const Duration(seconds: 90));
    expect(form.baseSummary, 'H.264 1920×1080 · 30p');
    expect(form.segments.first.audioShape, '48 kHz · 2ch');
  });

  test('还在探测时不能开始，说明是第几段', () async {
    transcoder.gates['/v/b.mp4'] = Completer();
    unawaited(form.addPaths(['/v/a.mp4', '/v/b.mp4']));
    await settle();
    expect(form.footer, (text: '第 2 段还在读取参数，读完才能开始', tone: FooterTone.info));
    expect(form.canStart, isFalse);
    transcoder.gates['/v/b.mp4']!.complete();
    await settle();
    expect(form.canStart, isTrue);
  });

  test('参数不一致时阻止开始，页脚写明哪段哪项与转成什么', () async {
    transcoder.probes['/v/b.mp4'] = probeOf(width: 1280, height: 720);
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    await settle();
    expect(form.issues.last?.message, '分辨率 1280×720 ≠ 第 1 段 1920×1080');
    expect(form.footer.tone, FooterTone.error);
    expect(
      form.footer.text,
      '第 2 段分辨率与第 1 段不同，不能无转码拼接。换掉它，或先用「转码」转成 1920×1080',
    );
    expect(form.canStart, isFalse);
  });

  test('读不出的段阻止开始', () async {
    await form.addPaths(['/v/a.mp4', '/v/broken.mp4']);
    await settle();
    expect(form.segments.last.probeError, 'moov atom not found');
    expect(form.footer.text, '第 2 段读不出音视频流，移除或换一个文件');
  });

  test('排序后基准随之变：不一致的标记挪到另一段，文件名跟着新的第 1 段', () async {
    transcoder.probes['/v/b.mp4'] = probeOf(width: 1280, height: 720);
    await form.addPaths(['/v/a.mp4', '/v/b.mp4', '/v/c.mp4']);
    await settle();
    expect([for (final i in form.issues) i != null], [false, true, false]);

    form.moveUp(1);
    expect(
      [for (final s in form.segments) s.fileName],
      ['b.mp4', 'a.mp4', 'c.mp4'],
    );
    expect([for (final i in form.issues) i != null], [false, true, true]);
    expect(form.options.outputStem, 'b.merged');

    form.reorder(0, 3);
    expect(
      [for (final s in form.segments) s.fileName],
      ['a.mp4', 'c.mp4', 'b.mp4'],
    );
    form.moveDown(2);
    form.moveUp(0);
    expect(
      [for (final s in form.segments) s.fileName],
      ['a.mp4', 'c.mp4', 'b.mp4'],
    );
  });

  test('文件名被用户改过后不再跟着第 1 段；重置回到跟随', () async {
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    form.setOutputStem('成片');
    form.remove(0);
    expect(form.options.outputStem, '成片');
    form.setOutputStem('');
    await form.addPaths(['/v/c.mp4']);
    await settle();
    expect(form.footer.text, '文件名不能为空');
    form.reset();
    expect(form.options.outputStem, 'b.merged');
  });

  test('添加视频时旁边的同名字幕自动挂上：完全同名优先，其次带语言后缀', () async {
    dirs['/v'] = [
      '/v/a.en.srt',
      '/v/a.srt',
      '/v/b.zh.vtt',
      '/v/b.ass',
      '/v/c.txt',
    ];
    files['/v/a.srt'] = _srt;
    files['/v/b.zh.vtt'] = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n乙\n';
    await form.addPaths(['/v/a.mp4', '/v/b.mp4', '/v/c.mp4']);
    await settle();
    final [a, b, c] = form.segments;
    expect(
      (a.subtitlePath, a.subtitleAuto, a.subtitleCues),
      ('/v/a.srt', true, 2),
    );
    expect((b.subtitlePath, b.subtitleCues), ('/v/b.zh.vtt', 1));
    expect(c.subtitlePath, isNull);
    expect(form.subtitledCount, 2);
    expect(form.cueCount, 3);
    expect(form.footer.text, '将合并成 a.merged.mp4 · 3 个章节 · 字幕内嵌 3 条');
  });

  test('拖入的字幕配给同名、还没挂字幕的段；配不上的一律拒收', () async {
    files['/s/b.srt'] = _srt;
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    await form.addPaths([
      '/s/b.srt',
      '/s/x.srt',
      '/s/y.srt',
      '/s/a.ass',
      '/s/n.txt',
    ]);
    await settle();
    expect(form.segments.last.subtitlePath, '/s/b.srt');
    expect(form.segments.last.subtitleAuto, isFalse);
    // 只剩一段（a）没字幕，也不把 x.srt 硬挂给它。
    expect(form.segments.first.subtitlePath, isNull);
    expect(
      form.rejected,
      '忽略了 2 个文件：1 个 ASS 字幕（本期只支持 SRT / VTT），1 个不是视频或字幕；'
      '2 个字幕找不到同名的段，请在对应段上点「挂字幕…」',
    );
    await form.addPaths(['/v/c.mp4']);
    expect(form.rejected, isNull);
  });

  test('字幕读不出来时阻止开始；两个字幕开关都关时不拦；摘下后解除', () async {
    files['/v/a.srt'] = const FormatException('bad');
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    form.attachSubtitle(0, '/v/a.srt');
    await settle();
    expect(form.segments.first.subtitleError, contains('不是 UTF-8'));
    expect(form.footer.text, '第 1 段的字幕读不出来，摘下或换一个');

    form.setEmbedSubtitles(false);
    form.setSidecarSubtitles(false);
    expect(form.canStart, isTrue);
    form.setEmbedSubtitles(true);
    expect(form.canStart, isFalse);

    form.detachSubtitle(0);
    expect(form.canStart, isTrue);
  });

  test('章节标题：输入即写回，清空后失焦回填默认', () async {
    await form.addPaths(['/v/采访 1.mp4', '/v/b.mp4']);
    form.setChapterTitle(0, '开场');
    expect(form.segments.first.chapterTitle, '开场');
    form.setChapterTitle(0, '');
    form.commitChapterTitle(0);
    expect(form.segments.first.chapterTitle, '采访 1');
  });

  test('关章节、开旁挂时页脚与命令预览随之变', () async {
    files['/v/a.srt'] = _srt;
    dirs['/v'] = ['/v/a.srt'];
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    await settle();
    expect(
      form.commandPreview,
      contains('-i list.txt -i chapters.txt -i merged.srt'),
    );
    form.setChapters(false);
    form.setSidecarSubtitles(true);
    expect(form.footer.text, '将合并成 a.merged.mp4 · 字幕内嵌并旁挂 2 条');
    expect(form.commandPreview, isNot(contains('chapters.txt')));
    form.setContainer(OutputContainer.mov);
    expect(form.commandPreview, endsWith('-f mov a.merged.mov'));
  });

  test('提交：交出参数并记住容器与开关，清空段列表，输出位置保留', () async {
    files['/v/a.srt'] = _srt;
    dirs['/v'] = ['/v/a.srt'];
    await form.addPaths(['/v/a.mp4', '/v/b.mp4']);
    await settle();
    form.setContainer(OutputContainer.mov);
    form.setChapters(false);
    await form.pickOutputDir();
    form.setChapterTitle(1, '正片');

    final submitted = form.submit()!;
    expect(
      [for (final s in submitted.segments) s.videoPath],
      ['/v/a.mp4', '/v/b.mp4'],
    );
    expect(submitted.segments.first.subtitlePath, '/v/a.srt');
    expect(submitted.segments.last.chapterTitle, '正片');
    expect(submitted.outputStem, 'a.merged');
    expect(submitted.resolvedDir, '/out');

    expect(form.segments, isEmpty);
    expect(form.options.outputStem, '');
    expect(form.options.outputLocation, OutputLocation.custom);
    final last = settings.lastMergeOptions!;
    expect((last.container, last.chapters), (OutputContainer.mov, false));
    expect(last.segments, isEmpty);

    final next = MergeFormController(
      settings: settings,
      transcoder: transcoder,
    );
    expect(next.options.container, OutputContainer.mov);
    expect(next.options.outputLocation, OutputLocation.besideSource);
    next.dispose();
  });

  test('不能开始时 submit 返回 null', () async {
    await form.addPaths(['/v/a.mp4']);
    expect(form.submit(), isNull);
    expect(form.segments, hasLength(1));
  });

  test('探测期间被移除的段，结果回来丢掉', () async {
    transcoder.gates['/v/a.mp4'] = Completer();
    unawaited(form.addPaths(['/v/a.mp4', '/v/b.mp4']));
    await settle();
    form.remove(0);
    transcoder.gates['/v/a.mp4']!.complete();
    await settle();
    expect([for (final s in form.segments) s.fileName], ['b.mp4']);
  });

  test('同一个文件可以加两次', () async {
    await form.addPaths(['/v/a.mp4', '/v/a.mp4']);
    await settle();
    expect(form.segments, hasLength(2));
    expect(form.canStart, isTrue);
  });
}
