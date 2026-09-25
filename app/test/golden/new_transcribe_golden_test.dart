@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/tasks/new_transcribe_dialog.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

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

class _FakeFfmpeg extends Ffmpeg {

  static const _lengths = {
    'interview_ep12.mp4': (Duration(minutes: 48, seconds: 12), 1288490188),
    'product_demo_en.mov': (Duration(minutes: 6, seconds: 40), 251658240),
    'lecture_week3.m4a': (Duration(hours: 1, minutes: 32, seconds: 5), 92274688),
  };

  @override
  Future<MediaFileInfo> probeFile(String path) async {
    final name = path.split('/').last;
    final (length, size) = _lengths[name]!;
    return MediaFileInfo(path: path, sizeBytes: size, duration: length);
  }
}

void main() {
  setUpAll(_loadCjkFont);

  Future<AppSettings> settingsWith({
    required bool key,
    String asr = 'openai',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load()..asrProviderId = asr;
    if (key) {
      settings
        ..setConfig(asr, const ProviderConfig(apiKey: 'sk-test'))
        ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
    }
    return settings;
  }

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    List<String> paths = const [],
    bool key = true,
    String asr = 'openai',
    bool expand = false,
  }) async {
    final settings = await settingsWith(key: key, asr: asr);

    tester.view
      ..physicalSize = const Size(880, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: Scaffold(
          body: Center(
            child: NewTranscribeDialog(
              settings: settings,
              initialPaths: paths,
              media: _FakeFfmpeg(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (expand) {
      await tester.ensureVisible(find.text('高级'));
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('输出位置'));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(NewTranscribeDialog),
      matchesGoldenFile('$file.png'),
    );
  }

  testWidgets('新建转写 · A 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_empty_light',
      brightness: Brightness.light,
    );
  });

  testWidgets('新建转写 · B 常态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_light',
      brightness: Brightness.light,
      paths: const ['/v/interview_ep12.mp4'],
    );
  });

  testWidgets('新建转写 · C 展开态 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_expanded_dark',
      brightness: Brightness.dark,
      paths: const [
        '/v/interview_ep12.mp4',
        '/v/product_demo_en.mov',
        '/v/lecture_week3.m4a',
      ],
      expand: true,
    );
  });

  testWidgets('新建转写 · D 阻断态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_blocked_light',
      brightness: Brightness.light,
      paths: const ['/v/interview_ep12.mp4'],
      asr: 'groq',
      key: false,
    );
  });
}
