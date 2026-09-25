import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/translate/new_translate_dialog.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 不碰文件系统的探测。名字里带 broken 的当作解析不出内容的字幕，
/// 用来构造「拖进来一个不是字幕的 .srt」那种场景。
class FakeFfmpeg extends Ffmpeg {
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

Future<AppSettings> _settings({bool withKey = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  if (withKey) {
    settings.setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
  }
  return settings;
}

void main() {
  EnqueueRequest? result;
  var openedSettings = false;
  List<String>? switchedToTranscribe;

  Future<void> open(
    WidgetTester tester, {
    bool withKey = true,
    List<String> paths = const [],
  }) async {
    result = null;
    openedSettings = false;
    switchedToTranscribe = null;
    final settings = await _settings(withKey: withKey);
    tester.view
      ..physicalSize = const Size(1000, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // 主题扩展（玻璃、投影）都挂在 lightTheme 上，用默认主题会取不到。
        theme: lightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showNewTranslateDialog(
                context,
                settings: settings,
                initialPaths: paths,
                media: FakeFfmpeg(),
                onOpenSettings: () => openedSettings = true,
                onSwitchToTranscribe: (m) => switchedToTranscribe = m,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, '开始翻译'))
          .onPressed !=
      null;

  NewTranslateDialogState state(WidgetTester tester) =>
      tester.state<NewTranslateDialogState>(find.byType(NewTranslateDialog));

  Future<void> openAdvanced(WidgetTester tester) async {
    await tester.ensureVisible(find.text('高级'));
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
  }

  group('空态', () {
    testWidgets('没有文件时不能开始，并说清楚缺什么', (tester) async {
      await open(tester);
      expect(find.text('把字幕文件拖到这里'), findsOneWidget);
      expect(find.text('先添加字幕文件'), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });

    // 「识别」那一段是转写独有的，翻译这边不该出现。
    testWidgets('没有识别相关的字段', (tester) async {
      await open(tester);
      expect(find.text('识别'), findsNothing);
      expect(find.text('转写完成后继续翻译'), findsNothing);
      expect(find.text('翻译'), findsOneWidget);
    });
  });

  group('有文件', () {
    testWidgets('列出条数与时间跨度，页脚汇总总条数与语言方向', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/s/b.vtt']);
      expect(find.text('a.srt'), findsOneWidget);
      expect(find.text('已选 2 个文件'), findsOneWidget);
      // 千位分隔：2416 和 2,416 的可读性差得很远。
      expect(find.textContaining('2 个文件 · 共 2,568 条'), findsOneWidget);
      expect(startEnabled(tester), isTrue);
    });

    testWidgets('同一个文件不会重复加进来', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      state(tester).handleDrop(['/s/a.srt', '/s/b.srt']);
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个文件'), findsOneWidget);
    });

    testWidgets('移除后回到空态', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await tester.tap(find.byTooltip('移除'));
      await tester.pumpAndSettle();
      expect(find.text('把字幕文件拖到这里'), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });
  });

  group('解析不出内容的文件', () {
    // 直接不收下会让用户以为没拖进去，反复再拖一次。
    testWidgets('留在列表里但标明会被跳过，不计入总条数', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/s/broken.srt']);
      expect(find.text('已选 2 个文件，其中 1 个无法解析'), findsOneWidget);
      expect(find.text('无法解析，将跳过'), findsOneWidget);
      expect(find.textContaining('1 个文件 · 共 1,284 条'), findsOneWidget);
      expect(find.textContaining('1 个文件无法解析，将跳过'), findsOneWidget);
      expect(startEnabled(tester), isTrue);
    });

    testWidgets('不进结果，也就不会变成必然失败的任务', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/s/broken.srt']);
      await tester.tap(find.text('开始翻译'));
      await tester.pumpAndSettle();
      expect(result!.paths, ['/s/a.srt']);
    });

    testWidgets('全都解析不出时拦住', (tester) async {
      await open(tester, paths: ['/s/broken.srt']);
      expect(startEnabled(tester), isFalse);
      expect(find.textContaining('都解析不出字幕内容'), findsOneWidget);
    });
  });

  group('混进来的音视频', () {
    testWidgets('列在顶部说明被忽略，字幕照常排队', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/v/x.mp4', '/v/y.mov']);
      expect(find.text('已忽略 2 个音视频文件，音视频请用「新建转写」'), findsOneWidget);
      expect(find.text('已选 1 个文件'), findsOneWidget);
      expect(startEnabled(tester), isTrue);
      // 页脚不再重复「已忽略」：顶部提示条已经说过一次。
      expect(find.textContaining('已忽略 2 个音视频文件；'), findsNothing);
    });

    testWidgets('「改用新建转写」把它们原样带过去', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/v/x.mp4']);
      await tester.tap(find.text('改用新建转写'));
      await tester.pumpAndSettle();
      expect(switchedToTranscribe, ['/v/x.mp4']);
      expect(result, isNull);
    });
  });

  group('阻断', () {
    testWidgets('服务没配密钥时拦住，并说去哪儿填', (tester) async {
      await open(tester, withKey: false, paths: ['/s/a.srt']);
      expect(startEnabled(tester), isFalse);
      expect(find.textContaining('密钥'), findsWidgets);
      expect(find.text('去设置'), findsWidgets);
    });

    testWidgets('「去设置」关掉对话框并跳过去', (tester) async {
      await open(tester, withKey: false, paths: ['/s/a.srt']);
      await tester.tap(find.text('去设置').first);
      await tester.pumpAndSettle();
      expect(openedSettings, isTrue);
      expect(find.byType(NewTranslateDialog), findsNothing);
    });
  });

  group('高级', () {
    testWidgets('默认收起，标题旁给出摘要', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      expect(find.textContaining('仅译文 · 15 / 40 字 · SRT'), findsOneWidget);
      expect(find.text('字幕排版'), findsNothing);
    });

    testWidgets('选双语后出现预览，上下顺序跟着变', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await openAdvanced(tester);
      expect(find.text('字幕排版'), findsOneWidget);

      await tester.ensureVisible(find.text('双语 · 译文在上'));
      await tester.tap(find.text('双语 · 译文在上'));
      await tester.pumpAndSettle();
      expect(find.text('00:01:23,450 --> 00:01:26,100'), findsOneWidget);

      final above = tester.widgetList<Text>(find.textContaining('我们从第二章开始'));
      expect(above, hasLength(1));
    });

    // 纯文本没有「两行」的概念，选了双语也得回落。
    testWidgets('纯文本让字幕排版回落到仅译文', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await openAdvanced(tester);
      await tester.ensureVisible(find.text('双语 · 译文在下'));
      await tester.tap(find.text('双语 · 译文在下'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('TXT'));
      await tester.tap(find.text('TXT'));
      await tester.pumpAndSettle();

      expect(find.textContaining('纯文本不保留双语排版'), findsOneWidget);
      // 预览块还在，但回落成只剩译文一行。
      expect(find.text("We'll start from chapter two"), findsNothing);
      expect(find.text('我们从第二章开始'), findsOneWidget);
    });

    testWidgets('同目录时说清楚产物叫什么，双语带上两种语言', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await openAdvanced(tester);
      expect(find.textContaining('原文件名.en.srt'), findsOneWidget);

      await tester.ensureVisible(find.text('双语 · 译文在上'));
      await tester.tap(find.text('双语 · 译文在上'));
      await tester.pumpAndSettle();
      expect(find.textContaining('原文件名.src-en.srt'), findsOneWidget);
    });
  });

  group('提交', () {
    testWidgets('确认后交出文件与参数，对话框关闭', (tester) async {
      await open(tester, paths: ['/s/a.srt', '/s/b.srt']);
      await tester.tap(find.text('开始翻译'));
      await tester.pumpAndSettle();
      expect(result!.paths, ['/s/a.srt', '/s/b.srt']);
      expect(result!.options.translationProviderId, 'deepseek');
      expect(result!.options.bilingual, BilingualLayout.targetOnly);
      expect(find.byType(NewTranslateDialog), findsNothing);
    });

    testWidgets('双语选择跟着参数一起交出去', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await openAdvanced(tester);
      await tester.ensureVisible(find.text('双语 · 译文在下'));
      await tester.tap(find.text('双语 · 译文在下'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始翻译'));
      await tester.pumpAndSettle();
      expect(result!.options.bilingual, BilingualLayout.targetBelow);
    });

    testWidgets('取消什么都不返回', (tester) async {
      await open(tester, paths: ['/s/a.srt']);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
