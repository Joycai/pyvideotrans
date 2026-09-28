import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/transcode/codecs.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';
import 'package:subtitle_studio/features/merge/merge_form.dart';
import 'package:subtitle_studio/features/merge/merge_page.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

class _FakeTranscoder extends Transcoder {
  final probes = <String, MediaProbe>{};

  @override
  Future<MediaProbe> probe(String path) async =>
      probes[path] ??
      const MediaProbe(
        duration: Duration(minutes: 1),
        video: [
          VideoStreamInfo(
            codec: 'h264',
            width: 1920,
            height: 1080,
            fps: 30,
            pixFmt: 'yuv420p',
          ),
        ],
        audio: [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
      );
}

void main() {
  late TaskQueue queue;
  late MergeFormController form;
  late _FakeTranscoder transcoder;

  /// 「挂字幕…」弹过几次选择框。
  late int subtitlePicks;

  Future<void> pumpPage(WidgetTester tester, {double width = 1440}) async {
    subtitlePicks = 0;
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    transcoder = _FakeTranscoder();
    queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: '/tmp/none',
        transcoder: transcoder,
      ),
      settings: settings,
    );
    form = MergeFormController(
      settings: settings,
      transcoder: transcoder,
      listDir: (_) async => const [],
      readSubtitle: (_) async => '1\n00:00:01,000 --> 00:00:02,000\n一\n',
      pickSubtitle: (_) async {
        subtitlePicks++;
        return null;
      },
    );
    addTearDown(form.dispose);
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: MergePage(form: form, queue: queue, onOpenTasks: () {}),
        ),
      ),
    );
  }

  Future<void> add(WidgetTester tester, List<String> paths) async {
    await tester.runAsync(() => form.addPaths(paths));
    await tester.pumpAndSettle();
  }

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, '开始合并'))
          .onPressed !=
      null;

  testWidgets('空态：落区、三步说明，开始不可用', (tester) async {
    await pumpPage(tester);
    expect(find.text('把要合并的视频拖到这里'), findsOneWidget);
    expect(find.text('先添加至少 2 段视频'), findsOneWidget);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('加段后出现行与章节起点条，就绪时页脚写产物名', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    expect(find.text('a.mp4'), findsOneWidget);
    expect(find.text('b.mp4'), findsOneWidget);
    expect(find.textContaining('章节起点', findRichText: true), findsOneWidget);
    expect(find.text('00:01:00'), findsOneWidget);
    expect(find.text('将合并成 a.merged.mp4 · 2 个章节'), findsOneWidget);
    expect(find.text('就绪'), findsNWidgets(2));
    expect(startEnabled(tester), isTrue);
  });

  testWidgets('不一致时开始不可用，页脚与行内都写明原因', (tester) async {
    await pumpPage(tester);
    transcoder.probes['/v/b.mp4'] = const MediaProbe(
      duration: Duration(minutes: 1),
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
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    expect(find.text('不一致'), findsOneWidget);
    expect(find.text('分辨率 1280×720 ≠ 第 1 段 1920×1080'), findsOneWidget);
    expect(find.textContaining('第 2 段分辨率与第 1 段不同'), findsOneWidget);
    expect(startEnabled(tester), isFalse);

    // ⌘/Ctrl+Enter 也不入队。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    expect(queue.tasks, isEmpty);
  });

  testWidgets('点箭头排序，第 1 段换了文件名跟着变', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    await tester.tap(find.byTooltip('下移').first);
    await tester.pumpAndSettle();
    expect([for (final s in form.segments) s.fileName], ['b.mp4', 'a.mp4']);
    expect(form.options.outputStem, 'b.merged');
  });

  testWidgets('开始后入队 1 个合并任务、清空段列表并显示横幅', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4', '/v/c.mp4']);
    await tester.tap(find.text('开始合并'));
    await tester.pump();
    expect(queue.tasks, hasLength(1));
    final task = queue.tasks.single;
    expect(task.kind, TaskKind.merge);
    expect((task.media! as MergeJob).options.segments, hasLength(3));
    expect(form.segments, isEmpty);
    expect(find.textContaining('已加入队列'), findsOneWidget);
    queue.cancel(task.id);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('关掉添加章节：页脚不提章节数', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    form.setChapters(false);
    await tester.pump();
    expect(find.text('将合并成 a.merged.mp4'), findsOneWidget);
  });

  testWidgets('拖动把手排序：拖起的行不报错，顺序跟着变', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4', '/v/c.mp4']);
    final handle = find.byIcon(Symbols.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout);
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(form.segments.first.fileName, isNot('a.mp4'));
  });

  testWidgets('窄行（列表宽不到 760）：时长与音频写在目录前面，没有溢出', (tester) async {
    await pumpPage(tester, width: 1150);
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('01:00 · AAC 48 kHz · 2ch · /v', findRichText: true),
      findsNWidgets(2),
    );
    expect(find.text('时长'), findsNothing);
  });

  testWidgets('章节框：清空后失焦回填默认；关掉章节后不能编辑', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/采访 1.mp4', '/v/b.mp4']);
    final field = find.descendant(
      of: find.byKey(ValueKey('chapter-${form.segments.first.id}')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, '');
    expect(form.segments.first.chapterTitle, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(form.segments.first.chapterTitle, '采访 1');

    form.setChapters(false);
    await tester.pump();
    final exclude = tester.widget<ExcludeFocus>(
      find.ancestor(of: field, matching: find.byType(ExcludeFocus)).first,
    );
    expect(exclude.excluding, isTrue);
  });

  testWidgets('字幕 chip：点 × 只摘下，点本体弹选择框', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/b.mp4']);
    form.attachSubtitle(0, '/v/a.srt');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('1 条'), findsOneWidget);

    await tester.tap(find.text('a.srt'));
    await tester.pump();
    expect(subtitlePicks, 1);

    await tester.tap(find.byTooltip('摘下字幕'));
    await tester.pump();
    expect(subtitlePicks, 1);
    expect(form.segments.first.subtitlePath, isNull);
  });

  testWidgets('拒收说明显示在分段面板顶上，可以关掉', (tester) async {
    await pumpPage(tester);
    await add(tester, ['/v/a.mp4', '/v/x.ass']);
    expect(find.textContaining('1 个 ASS 字幕'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(find.textContaining('1 个 ASS 字幕'), findsNothing);
  });

  testWidgets('顶栏副标题按问题种类说：放不进容器不说成参数不一致', (tester) async {
    await pumpPage(tester);
    const av1 = MediaProbe(
      duration: Duration(minutes: 1),
      video: [
        VideoStreamInfo(codec: 'av1', width: 1920, height: 1080, fps: 30),
      ],
      audio: [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
    );
    transcoder.probes['/v/a.mkv'] = av1;
    transcoder.probes['/v/b.mkv'] = av1;
    await add(tester, ['/v/a.mkv', '/v/b.mkv']);
    expect(form.summary, contains('无转码 → MP4'));
    form.setContainer(OutputContainer.mov);
    expect(form.summary, '2 段 · 共 02:00 · 第 1 段：AV1 视频不能原样放进 MOV');
  });
}
