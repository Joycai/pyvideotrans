import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/settings/section_outline.dart';
import 'package:subtitle_studio/features/settings/settings_page.dart';
import 'package:subtitle_studio/features/settings/settings_section.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 「环境」分区要显示 ffmpeg 路径。给一份写死的，测试就不去碰真实磁盘，
/// 结果也不随测试机装没装 ffmpeg 变。
Ffmpeg _fixedFfmpeg() => Ffmpeg(
  ffmpegPath: '/usr/local/bin/ffmpeg',
  ffprobePath: '/usr/local/bin/ffprobe',
);

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<SettingsPageState> pump(
    WidgetTester tester, {
    double width = 1440,
  }) async {
    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          // 左边留出 72px Rail + 12px 间隙，面板宽度才与真实外壳一致。
          body: Padding(
            padding: const EdgeInsets.fromLTRB(96, 12, 12, 12),
            child: SettingsPage(settings: settings, media: _fixedFfmpeg()),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<SettingsPageState>(find.byType(SettingsPage));
  }

  /// 目录里的一项（不是分区标题）。
  Finder outlineItem(String label) => find.descendant(
    of: find.byType(SectionOutline),
    matching: find.text(label),
  );

  testWidgets('宽窗口：左侧竖排目录，点击跳转并高亮', (tester) async {
    final page = await pump(tester);
    expect(find.text('分区'), findsOneWidget);
    expect(page.active, SettingsSectionKey.appearance);

    await tester.tap(outlineItem('输出'));
    await tester.pumpAndSettle();
    expect(page.active, SettingsSectionKey.output);
    // 跳过去之后「输出」分区标题应该在视口里。
    expect(
      find.descendant(
        of: find.byType(SettingsSection),
        matching: find.text('输出'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('环境分区：显示 ffmpeg 位置，给出打开目录与重新检测', (tester) async {
    final page = await pump(tester);
    await tester.tap(outlineItem('环境'));
    await tester.pumpAndSettle();
    expect(page.active, SettingsSectionKey.environment);

    // 路径是注入的那份，与测试机上装没装 ffmpeg 无关。
    expect(find.text('/usr/local/bin/ffmpeg'), findsOneWidget);
    expect(find.text('已找到'), findsOneWidget);
    expect(find.text('打开目录'), findsOneWidget);
    expect(find.text('重新检测'), findsOneWidget);
    // 说明里要点名 ffprobe：只放 ffmpeg 会落进「抽音能跑、读时长失败」的半坏状态。
    expect(find.textContaining('ffprobe'), findsWidgets);
  });

  testWidgets('窄于 1180：目录折叠成顶部 Tab；窄于 1000：标签堆叠', (tester) async {
    await pump(tester, width: 1100);
    expect(find.text('分区'), findsNothing);
    expect(find.byType(SectionOutline), findsOneWidget);
    var row = tester.widget<SettingsRow>(find.byType(SettingsRow).first);
    expect(row.stacked, isFalse);

    await pump(tester, width: 960);
    row = tester.widget<SettingsRow>(find.byType(SettingsRow).first);
    expect(row.stacked, isTrue);
  });

  testWidgets('未配置：目录红点、标签「未配置」、横幅说明后果', (tester) async {
    settings
      ..asrProviderId = 'groq'
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-x'));
    await pump(tester);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('识别服务未配置完整，转写任务无法启动'), findsOneWidget);
    expect(find.textContaining('Groq未配置密钥'), findsOneWidget);

    settings.setConfig('groq', const ProviderConfig(apiKey: 'sk-x'));
    await tester.pump();
    expect(find.text('未配置'), findsNothing);
    expect(find.text('识别服务未配置完整，转写任务无法启动'), findsNothing);
  });

  testWidgets('本机服务不需要密钥：密钥行换成一句说明', (tester) async {
    settings
      ..asrProviderId = 'openai'
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk-x'))
      ..translationProviderId = 'ollama';
    await pump(tester);
    // 识别服务（OpenAI）有密钥行，翻译服务（Ollama）没有。
    expect(find.text('API 密钥'), findsOneWidget);
    expect(find.textContaining('本机服务不需要密钥'), findsOneWidget);
  });

  testWidgets('改动即写入，并在该分区显示「已保存」后淡出', (tester) async {
    final page = await pump(tester);
    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(settings.themeMode, 'dark');

    final indicators = find.byType(SavedIndicator);
    SavedIndicator at(SettingsSectionKey key) => tester
        .widgetList<SavedIndicator>(indicators)
        .elementAt(SettingsSectionKey.values.indexOf(key));
    expect(at(SettingsSectionKey.appearance).visible, isTrue);
    expect(at(SettingsSectionKey.asr).visible, isFalse);
    expect(page.active, SettingsSectionKey.appearance);

    await tester.pump(const Duration(seconds: 3));
    expect(at(SettingsSectionKey.appearance).visible, isFalse);
  });

  testWidgets('键入的改动等停止输入后才提示已保存', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'https://x/v1');
    await tester.pump();
    final indicators = find.byType(SavedIndicator);
    expect(
      tester.widgetList<SavedIndicator>(indicators).any((i) => i.visible),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      tester.widgetList<SavedIndicator>(indicators).any((i) => i.visible),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('恢复默认：对话框可只重置当前分区，也可全部', (tester) async {
    settings
      ..themeMode = 'dark'
      ..targetLanguage = '日文';
    final page = await pump(tester);

    page.jumpTo(SettingsSectionKey.lang);
    await tester.pumpAndSettle();
    page.confirmReset();
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅「语言」'));
    await tester.pumpAndSettle();
    expect(settings.targetLanguage, '英文');
    expect(settings.themeMode, 'dark');

    page.confirmReset();
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部恢复'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, 'system');
    await tester.pump(const Duration(seconds: 3));
  });
}
