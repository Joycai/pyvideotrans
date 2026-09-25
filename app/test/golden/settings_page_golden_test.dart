@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/settings/section_outline.dart';
import 'package:subtitle_studio/features/settings/settings_page.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 「环境」分区要显示 ffmpeg 路径。给一份写死的，截图才不会随测试机
/// 装没装 ffmpeg、装在哪而变。
Ffmpeg _fixedFfmpeg() => Ffmpeg(
  ffmpegPath: '/usr/local/bin/ffmpeg',
  ffprobePath: '/usr/local/bin/ffprobe',
);

/// 与 render_test.dart 同样的字体处理：测试默认字体不含汉字。
Future<void> _loadCjkFont() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/STHeiti Light.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync().buffer.asByteData();
    for (final family in ['Noto Sans SC', 'JetBrains Mono']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    return;
  }
}

ThemeData _readable(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Noto Sans SC'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Noto Sans SC'),
);

void main() {
  setUpAll(_loadCjkFont);

  /// 设计稿的两种状态：A 全部已配置；B 识别选 Groq 没填密钥、翻译选 Ollama。
  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    required String variant,
    double width = 1440,
    SettingsSectionKey? saved,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    if (variant == 'B') {
      settings
        ..asrProviderId = 'groq'
        ..translationProviderId = 'ollama'
        ..translationBatchSize = 12
        ..setConfig(
          'ollama',
          const ProviderConfig(model: 'qwen2.5:14b-instruct'),
        );
    } else {
      settings
        ..asrProviderId = 'dashscope_qwen_asr'
        ..translationProviderId = 'deepseek'
        ..outputDir = '/Users/mia/Movies/Subs/2026'
        ..setConfig(
          'dashscope_qwen_asr',
          const ProviderConfig(apiKey: 'sk-a93f4c210e7b48d5b6c1f7e2'),
        )
        ..setConfig(
          'deepseek',
          const ProviderConfig(apiKey: 'sk-7c1d9b04f2ae4831'),
        );
    }
    settings
      ..asrPrompt = '术语：缓存穿透、布隆过滤器、Kubernetes。人名：陈嘉行、Aaron Patterson。'
      ..translationGuidance = '保留英文专有名词原文；人称用「你」；口语化，短句优先；不要添加原文没有的内容。';

    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final asrOk = variant != 'B';
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.settings,
          onSectionChanged: (_) {},
          chrome: () => settingsChrome(onReset: () {}),
          status: () => StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: asrOk
                ? (connected: true, label: '阿里百炼 · Qwen3-ASR · 已配置')
                : (connected: false, label: 'Groq · 未配置'),
            localBackend: asrOk
                ? (connected: true, label: 'DeepSeek · 已配置')
                : (connected: true, label: 'Ollama · 已配置'),
            runningTasks: asrOk ? 2 : 0,
          ),
          live: settings,
          child: SettingsPage(settings: settings, media: _fixedFfmpeg()),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<SettingsPageState>(find.byType(SettingsPage));
    if (variant == 'B') {
      state.jumpTo(SettingsSectionKey.asr);
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (saved != null) {
      state.showSaved(saved);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
    // 「已保存」的 2 秒定时器不能留到测试结束。
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('设置页 · 画板 1 · 浅色 · 全部已配置', (tester) async {
    await shoot(
      tester,
      file: 'settings_page_light',
      brightness: Brightness.light,
      variant: 'A',
      saved: SettingsSectionKey.appearance,
    );
  });

  testWidgets('设置页 · 画板 2 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'settings_page_dark',
      brightness: Brightness.dark,
      variant: 'A',
      saved: SettingsSectionKey.mt,
    );
  });

  testWidgets('设置页 · 画板 3 · 识别未配置 + Ollama 无密钥', (tester) async {
    await shoot(
      tester,
      file: 'settings_page_states_light',
      brightness: Brightness.light,
      variant: 'B',
    );
  });

  testWidgets('设置页 · 画板 4 · 960 窄窗', (tester) async {
    await shoot(
      tester,
      file: 'settings_page_narrow_light',
      brightness: Brightness.light,
      variant: 'A',
      width: 960,
    );
  });

  testWidgets('设置页 · 画板 4 · 960 窄窗 · 深色未配置', (tester) async {
    await shoot(
      tester,
      file: 'settings_page_narrow_states_dark',
      brightness: Brightness.dark,
      variant: 'B',
      width: 960,
    );
  });
}
