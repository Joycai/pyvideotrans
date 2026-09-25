@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/tasks/new_translate_dialog.dart';
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
  /// 与设计稿同一批样例：条数、时间跨度、大小。
  static const _files = {
    'interview_ep12.en.srt': (1284, Duration(minutes: 48, seconds: 12), 24576),
    'product_demo_en.vtt': (312, Duration(minutes: 6, seconds: 40), 7168),
    'lecture_week3.ass': (820, Duration(hours: 1, minutes: 32, seconds: 5), 31744),
    'chapter4_draft.srt': (0, null, 512),
  };

  @override
  Future<MediaFileInfo> probeFile(String path) async {
    final (cues, length, size) = _files[path.split('/').last]!;
    return MediaFileInfo(
      path: path,
      sizeBytes: size,
      duration: length,
      cueCount: cues,
    );
  }
}

void main() {
  setUpAll(_loadCjkFont);

  Future<AppSettings> settingsWith({
    required bool key,
    String mt = 'deepseek',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load()..translationProviderId = mt;
    if (key) settings.setConfig(mt, const ProviderConfig(apiKey: 'sk-test'));
    return settings;
  }

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    List<String> paths = const [],
    bool key = true,
    String mt = 'deepseek',
    bool expand = false,
    String? layout,
  }) async {
    final settings = await settingsWith(key: key, mt: mt);

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
            child: NewTranslateDialog(
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
      if (layout != null) {
        await tester.ensureVisible(find.text(layout));
        await tester.tap(find.text(layout));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('输出位置'));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(NewTranslateDialog),
      matchesGoldenFile('$file.png'),
    );
  }

  testWidgets('新建翻译 · A 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_empty_light',
      brightness: Brightness.light,
    );
  });

  testWidgets('新建翻译 · B 常态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_light',
      brightness: Brightness.light,
      paths: const [
        '/s/interview_ep12.en.srt',
        '/s/product_demo_en.vtt',
        '/s/lecture_week3.ass',
      ],
    );
  });

  testWidgets('新建翻译 · C 展开态（双语 · 译文在上）· 深色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_expanded_dark',
      brightness: Brightness.dark,
      paths: const [
        '/s/interview_ep12.en.srt',
        '/s/product_demo_en.vtt',
        '/s/lecture_week3.ass',
        '/s/chapter4_draft.srt',
      ],
      expand: true,
      layout: '双语 · 译文在上',
    );
  });

  testWidgets('新建翻译 · D 阻断态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_blocked_light',
      brightness: Brightness.light,
      paths: const ['/s/interview_ep12.en.srt'],
      mt: 'openai_chat',
      key: false,
    );
  });

  testWidgets('新建翻译 · E 提示态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_ignored_light',
      brightness: Brightness.light,
      paths: const [
        '/s/interview_ep12.en.srt',
        '/v/clip_a.mp4',
        '/v/clip_b.mov',
      ],
    );
  });
}
