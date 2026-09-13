import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/features/tasks/new_transcribe_page.dart';
import 'package:subtitle_studio/features/tasks/transcribe_form.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/settings.dart';

class FakeMedia extends Media {
  @override
  bool get available => false;

  @override
  Future<MediaFileInfo> probeFile(String path) async => MediaFileInfo(
    path: path,
    sizeBytes: 1288490188,
    duration: const Duration(minutes: 48, seconds: 12),
    exists: !path.contains('missing'),
  );
}

void main() {
  late Directory work;
  late AppSettings settings;
  late TaskQueue queue;
  late TranscribeFormController form;
  var openedSettings = false;
  var openedTasks = false;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('subtitle_studio_page');
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load()
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk-test'))
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
    final media = FakeMedia();
    queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: work.path, media: media),
      settings: settings,
    );
    form = TranscribeFormController(settings: settings, media: media);
    openedSettings = false;
    openedTasks = false;
  });

  tearDown(() {
    form.dispose();
    work.deleteSync(recursive: true);
  });

  Widget app() => MaterialApp(
    theme: lightTheme,
    home: Scaffold(
      body: NewTranscribePage(
        form: form,
        queue: queue,
        onOpenSettings: () => openedSettings = true,
        onOpenTasks: () => openedTasks = true,
      ),
    ),
  );

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
  }

  NewTranscribePageState state(WidgetTester tester) =>
      tester.state(find.byType(NewTranscribePage));

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<PrimaryButton>(find.byWidgetPredicate(
            (w) => w is PrimaryButton && w.label.startsWith('开始转写'),
          ))
          .onPressed !=
      null;

  testWidgets('空态：参数可编辑，开始禁用', (tester) async {
    await pumpPage(tester);
    expect(find.text('把音视频文件拖到这里'), findsOneWidget);
    expect(find.text('先选择音视频文件'), findsOneWidget);
    expect(find.text('语音语言'), findsOneWidget);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('拖入文件后列出，按钮带数量，读不出的标出来', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/v/a.mp4', '/v/missing.mov']);
    await tester.pump();
    await tester.pump();

    expect(find.text('a.mp4'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    expect(find.text('无法读取'), findsOneWidget);
    expect(find.text('开始转写 · 1'), findsOneWidget);
    expect(startEnabled(tester), isTrue);
  });

  testWidgets('提交后入队、列表清空、参数保留，横幅可跳任务页', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/v/a.mp4', '/v/b.mov']);
    await tester.pump();
    await tester.pump();
    form.update((o) => o.copyWith(cjkLineLength: 30));

    await tester.tap(find.text('开始转写 · 2'));
    // 横幅 200ms 展开，展开完才点得到里面的链接（AnimatedSize 要多一帧起步）。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(queue.tasks.length, 2);
    expect(queue.tasks.every((t) => t.options.cjkLineLength == 30), isTrue);
    expect(form.files, isEmpty);
    expect(form.options.cjkLineLength, 30);
    expect(find.text('已加入队列 '), findsOneWidget);
    expect(find.text(' 个任务，按列表顺序排队'), findsOneWidget);
    expect(find.text('把音视频文件拖到这里'), findsOneWidget);

    await tester.tap(find.text('查看任务'));
    await tester.pump();
    expect(openedTasks, isTrue);

    // 横幅 6 秒后自动收起。
    await tester.pump(const Duration(seconds: 7));
    expect(find.textContaining('已加入队列'), findsNothing);
  });

  testWidgets('表单挂在页面外面，页面重建后文件与参数还在', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/v/a.mp4']);
    await tester.pump();
    await tester.pump();
    form.update((o) => o.copyWith(translate: false));

    // 模拟切去别的页再回来：整页卸掉重建。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('a.mp4'), findsOneWidget);
    expect(find.text('开始转写 · 1'), findsOneWidget);
    expect(find.text('目标语言'), findsNothing);
  });

  testWidgets('缺密钥时「去设置」不会把页面关掉', (tester) async {
    settings.setConfig('openai', const ProviderConfig());
    await pumpPage(tester);
    state(tester).handleDrop(['/v/a.mp4']);
    await tester.pump();
    await tester.pump();

    expect(startEnabled(tester), isFalse);
    await tester.tap(find.text('去设置').first);
    await tester.pump();
    expect(openedSettings, isTrue);
    expect(find.byType(NewTranscribePage), findsOneWidget);
  });
}
