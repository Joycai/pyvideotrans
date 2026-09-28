import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/task.dart';
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

  Future<void> pumpPage(WidgetTester tester) async {
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
    );
    addTearDown(form.dispose);
    tester.view.physicalSize = const Size(1440, 1200);
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
}
