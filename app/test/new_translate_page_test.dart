import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/features/translate/new_translate_page.dart';
import 'package:subtitle_studio/features/translate/translate_form.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 不碰文件系统的解析。名字里带 broken 的当作解析不出内容的字幕。
class FakeFfmpeg extends Ffmpeg {
  @override
  bool get available => false;

  @override
  Future<MediaFileInfo> probeFile(String path) async {
    final broken = path.contains('broken');
    return MediaFileInfo(
      path: path,
      sizeBytes: 24576,
      duration: broken ? null : const Duration(minutes: 48, seconds: 12),
      cueCount: broken ? 0 : 1284,
    );
  }
}

void main() {
  late Directory work;
  late AppSettings settings;
  late TaskQueue queue;
  late TranslateFormController form;
  var openedSettings = false;
  var openedTasks = false;
  List<String>? switchedToTranscribe;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('subtitle_studio_translate');
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load()
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
    final media = FakeFfmpeg();
    queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: work.path, media: media),
      settings: settings,
    );
    form = TranslateFormController(settings: settings, media: media);
    openedSettings = false;
    openedTasks = false;
    switchedToTranscribe = null;
  });

  tearDown(() {
    form.dispose();
    work.deleteSync(recursive: true);
  });

  Widget app() => MaterialApp(
    theme: lightTheme,
    home: Scaffold(
      body: NewTranslatePage(
        form: form,
        queue: queue,
        onOpenSettings: () => openedSettings = true,
        onOpenTasks: () => openedTasks = true,
        onSwitchToTranscribe: (m) => switchedToTranscribe = m,
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

  NewTranslatePageState state(WidgetTester tester) =>
      tester.state(find.byType(NewTranslatePage));

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<PrimaryButton>(
            find.byWidgetPredicate(
              (w) => w is PrimaryButton && w.label.startsWith('开始翻译'),
            ),
          )
          .onPressed !=
      null;

  testWidgets('空态：参数可编辑，开始禁用，没有识别相关字段', (tester) async {
    await pumpPage(tester);
    expect(find.text('把字幕文件拖到这里'), findsOneWidget);
    expect(find.text('先添加字幕文件'), findsOneWidget);
    expect(find.text('原文语言'), findsOneWidget);
    expect(find.text('识别'), findsNothing);
    expect(find.text('转写完成后继续翻译'), findsNothing);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('拖入文件后列出条数，按钮带数量，解析不出的标出来', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/s/a.srt', '/s/broken.srt']);
    await tester.pump();
    await tester.pump();

    expect(find.text('a.srt'), findsOneWidget);
    expect(find.text('1,284'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    expect(find.text('无法解析'), findsOneWidget);
    expect(find.text('解析不出字幕内容，将跳过'), findsOneWidget);
    expect(find.textContaining('约 65 次调用'), findsOneWidget);
    expect(find.text('开始翻译 · 1'), findsOneWidget);
    expect(startEnabled(tester), isTrue);
  });

  testWidgets('拖错门的音视频：中性提示条，「改用新建转写」把它们带走', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/v/x.mp4', '/s/a.srt']);
    await tester.pump();
    await tester.pump();

    expect(find.text('已忽略 1 个音视频文件，音视频请用「新建转写」'), findsOneWidget);
    await tester.tap(find.text('改用新建转写'));
    await tester.pump();
    expect(switchedToTranscribe, ['/v/x.mp4']);
    expect(find.textContaining('已忽略'), findsNothing);
    expect(find.byType(NewTranslatePage), findsOneWidget);
  });

  testWidgets('语言对换：自动检测时禁用，指定原文后可换', (tester) async {
    await pumpPage(tester);
    expect(find.byTooltip('原文为自动检测时不能对换'), findsOneWidget);

    form.update((o) => o.copyWith(sourceLanguage: Languages.resolve('zh')));
    await tester.pump();
    await tester.tap(find.byTooltip('对换原文与目标语言'));
    await tester.pump();
    expect(form.options.sourceLanguage.code, 'en');
    expect(form.options.targetLanguage.code, 'zh');
  });

  testWidgets('提交后入队、列表清空、参数保留，横幅可跳任务页', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/s/a.srt', '/s/b.vtt']);
    await tester.pump();
    await tester.pump();
    form.update((o) => o.copyWith(translationBatchSize: 40));

    await tester.tap(find.text('开始翻译 · 2'));
    // 横幅 200ms 展开，展开完才点得到里面的链接（AnimatedSize 要多一帧起步）。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(queue.tasks.length, 2);
    expect(
      queue.tasks.every((t) => t.options.translationBatchSize == 40),
      isTrue,
    );
    expect(form.files, isEmpty);
    expect(form.options.translationBatchSize, 40);
    expect(settings.lastTranslateOptions?.translationBatchSize, 40);
    expect(find.text('已加入队列 '), findsOneWidget);
    expect(find.text(' 个任务，按列表顺序排队'), findsOneWidget);
    expect(find.text('把字幕文件拖到这里'), findsOneWidget);

    await tester.tap(find.text('查看任务'));
    await tester.pump();
    expect(openedTasks, isTrue);

    // 横幅 6 秒后自动收起。
    await tester.pump(const Duration(seconds: 7));
    expect(find.textContaining('已加入队列'), findsNothing);
  });

  testWidgets('表单挂在页面外面，页面重建后文件与参数还在', (tester) async {
    await pumpPage(tester);
    state(tester).handleDrop(['/s/a.srt']);
    await tester.pump();
    await tester.pump();
    form.update((o) => o.copyWith(translationBatchSize: 50));

    // 模拟切去别的页再回来：整页卸掉重建。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('a.srt'), findsOneWidget);
    expect(find.text('开始翻译 · 1'), findsOneWidget);
    expect(find.textContaining('每批 50 条'), findsOneWidget);
  });

  testWidgets('缺密钥时「去设置」不会把页面关掉', (tester) async {
    settings.setConfig('deepseek', const ProviderConfig());
    await pumpPage(tester);
    state(tester).handleDrop(['/s/a.srt']);
    await tester.pump();
    await tester.pump();

    expect(startEnabled(tester), isFalse);
    await tester.tap(find.text('去设置').first);
    await tester.pump();
    expect(openedSettings, isTrue);
    expect(find.byType(NewTranslatePage), findsOneWidget);
  });

  testWidgets('高级展开后有排版预览，选 TXT 时回落到仅译文', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('仅译文 · 15 / 40 字 · SRT'), findsOneWidget);

    await tester.tap(find.text('高级'));
    await tester.pump();
    expect(find.text('00:01:23,450 --> 00:01:26,100'), findsOneWidget);
    expect(find.text("We'll start from chapter two"), findsNothing);

    await tester.tap(find.text('双语 · 译文在下'));
    await tester.pump();
    expect(find.text("We'll start from chapter two"), findsOneWidget);
    expect(find.textContaining('原文件名.src-en.srt'), findsOneWidget);

    await tester.ensureVisible(find.text('TXT'));
    await tester.tap(find.text('TXT'));
    await tester.pump();
    expect(find.textContaining('纯文本不保留双语排版'), findsOneWidget);
    expect(find.text("We'll start from chapter two"), findsNothing);
    expect(find.textContaining('原文件名.en.txt'), findsOneWidget);
  });
}
