import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/transcribe/new_transcribe_dialog.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 不碰 ffprobe 的探测：文件列表只要大小与时长，测试里给固定值。
class FakeMedia extends Media {
  @override
  Future<MediaFileInfo> probeFile(String path) async => MediaFileInfo(
    path: path,
    sizeBytes: 1288490188,
    duration: const Duration(minutes: 48, seconds: 12),
  );
}

Future<AppSettings> _settings({bool withKey = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  if (withKey) {
    settings
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk-test'))
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
  }
  return settings;
}

void main() {
  EnqueueRequest? result;
  var openedSettings = false;

  Future<void> open(
    WidgetTester tester, {
    bool withKey = true,
    List<String> paths = const [],
  }) async {
    result = null;
    openedSettings = false;
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
              result = await showNewTranscribeDialog(
                context,
                settings: settings,
                initialPaths: paths,
                media: FakeMedia(),
                onOpenSettings: () => openedSettings = true,
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
          .widget<PrimaryButton>(
            find.widgetWithText(PrimaryButton, '开始转写'),
          )
          .onPressed !=
      null;

  group('空态', () {
    testWidgets('没有文件时不能开始，并说清楚缺什么', (tester) async {
      await open(tester);
      expect(find.text('把音视频文件拖到这里'), findsOneWidget);
      expect(find.text('先选择音视频文件'), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });
  });

  group('有文件', () {
    testWidgets('列出文件，并预告会建几个什么任务', (tester) async {
      await open(tester, paths: ['/v/interview_ep12.mp4']);
      expect(find.text('interview_ep12.mp4'), findsOneWidget);
      expect(find.text('48:12'), findsOneWidget);
      expect(find.text('1.2 GB'), findsOneWidget);
      expect(
        find.text('将创建 1 个转写并翻译任务，加入队列后在任务页查看进度'),
        findsOneWidget,
      );
      expect(startEnabled(tester), isTrue);
    });

    testWidgets('多个文件时说明参数统一应用', (tester) async {
      await open(tester, paths: ['/v/a.mp4', '/v/b.mov', '/v/c.m4a']);
      expect(find.text('共 3 个文件，以下参数统一应用到每个文件'), findsOneWidget);
      expect(find.text('将创建 3 个转写并翻译任务，按列表顺序排队'), findsOneWidget);
    });

    testWidgets('移除后回到空态', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      await tester.tap(find.byTooltip('移除'));
      await tester.pumpAndSettle();
      expect(find.text('把音视频文件拖到这里'), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });

    testWidgets('同一个文件不会重复加进来', (tester) async {
      await open(tester, paths: ['/v/a.mp4', '/v/a.mp4']);
      expect(find.text('a.mp4'), findsOneWidget);
    });
  });

  group('阻断与提示', () {
    // 原实现遇到没配密钥时直接弹出渠道设置窗，把用户从当前流程里拽走。
    testWidgets('服务没配密钥时拦住，并说去哪儿填', (tester) async {
      await open(tester, withKey: false, paths: ['/v/a.mp4']);
      expect(find.textContaining('未配置密钥'), findsWidgets);
      expect(startEnabled(tester), isFalse);
    });

    testWidgets('「去设置」关掉对话框并跳过去', (tester) async {
      await open(tester, withKey: false, paths: ['/v/a.mp4']);
      await tester.tap(find.text('去设置').first);
      await tester.pumpAndSettle();
      expect(find.byType(NewTranscribeDialog), findsNothing);
      expect(openedSettings, isTrue);
    });

    testWidgets('字幕文件被拒，并指向「新建翻译」', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      tester
          .state<NewTranscribeDialogState>(find.byType(NewTranscribeDialog))
          .handleDrop(['/v/sub.srt']);
      await tester.pumpAndSettle();
      expect(find.textContaining('新建翻译'), findsOneWidget);
      expect(find.text('sub.srt'), findsNothing);
    });
  });

  group('翻译开关', () {
    testWidgets('关掉后任务类型变成「转写」，翻译参数一并收起', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      expect(find.text('目标语言'), findsOneWidget);

      await tester.tap(find.text('转写完成后继续翻译'));
      await tester.pumpAndSettle();

      expect(find.text('目标语言'), findsNothing);
      expect(
        find.text('将创建 1 个转写任务，加入队列后在任务页查看进度'),
        findsOneWidget,
      );
    });
  });

  group('高级', () {
    testWidgets('默认收起，标题旁给出摘要', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      expect(find.textContaining('每行 15 / 40'), findsOneWidget);
      expect(find.text('识别提示词（可选）'), findsNothing);

      await tester.ensureVisible(find.text('高级'));
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      expect(find.text('识别提示词（可选）'), findsOneWidget);
      expect(find.text('输出格式'), findsOneWidget);
    });

    testWidgets('ASS 未实施，灰掉但仍然可读', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      await tester.ensureVisible(find.text('高级'));
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ASS'));
      expect(find.text('ASS'), findsOneWidget);
      await tester.tap(find.text('ASS'));
      await tester.pumpAndSettle();
      // 点不动，格式仍然是 SRT。
      expect(find.textContaining('第二期'), findsOneWidget);
    });
  });

  group('提交', () {
    testWidgets('确认后交出文件与参数，对话框关闭', (tester) async {
      await open(tester, paths: ['/v/a.mp4', '/v/b.mov']);
      await tester.tap(find.text('开始转写'));
      await tester.pumpAndSettle();

      expect(find.byType(NewTranscribeDialog), findsNothing);
      expect(result!.paths, ['/v/a.mp4', '/v/b.mov']);
      expect(result!.options.translate, isTrue);
      expect(result!.options.format, SubtitleFormat.srt);
    });

    testWidgets('取消什么都不返回', (tester) async {
      await open(tester, paths: ['/v/a.mp4']);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
