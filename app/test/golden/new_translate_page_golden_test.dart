@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/features/tasks/new_translate_page.dart';
import 'package:subtitle_studio/features/tasks/translate_form.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/media.dart';
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

/// 设计稿 M-TranslatePage 里的样例：两个解析完，`lecture_week3.ass` 永远
/// 停在「解析中」，`notes_raw.txt` 解析不出内容。
class _FakeMedia extends Media {
  static const _known = {
    'interview_ep12.en.srt': (1284, Duration(minutes: 48, seconds: 12), 24576),
    'product_demo_en.vtt': (312, Duration(minutes: 6, seconds: 40), 7168),
    'notes_raw.srt': (0, null, 2150),
  };

  @override
  bool get available => false;

  @override
  Future<MediaFileInfo> probeFile(String path) {
    final entry = _known[path.split('/').last];
    if (entry == null) return Completer<MediaFileInfo>().future;
    final (cues, length, size) = entry;
    return Future.value(
      MediaFileInfo(
        path: path,
        sizeBytes: size,
        duration: length,
        cueCount: cues,
      ),
    );
  }
}

void main() {
  setUpAll(_loadCjkFont);

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    required String variant,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load()
      ..setConfig(
        'dashscope_qwen_asr',
        const ProviderConfig(apiKey: 'sk-test'),
      );
    if (variant != 'C') {
      settings.setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
    }
    final media = _FakeMedia();
    final form = TranslateFormController(settings: settings, media: media);
    addTearDown(form.dispose);
    final queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: '/tmp', media: media),
      settings: settings,
    );

    switch (variant) {
      case 'B':
        form.handleDrop([
          '/Users/mia/Movies/采访/interview_ep12.en.srt',
          '/Users/mia/Movies/产品/product_demo_en.vtt',
          '/Users/mia/Music/课程/lecture_week3.ass',
          '/Users/mia/Movies/产品/product_demo_final_v3.mov',
        ]);
      case 'C':
        form
          ..handleDrop([
            '/Users/mia/Movies/采访/interview_ep12.en.srt',
            '/Users/mia/Desktop/notes_raw.srt',
          ])
          ..update(
            (o) => o.copyWith(
              sourceLanguage: Languages.resolve('en'),
              targetLanguage: Languages.resolve('zh'),
              bilingual: BilingualLayout.targetAbove,
            ),
          )
          ..advancedOpen = true;
    }

    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.newTranslate,
          onSectionChanged: (_) {},
          chrome: () => newTranslateChrome(form),
          status: () => StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: (connected: true, label: '阿里百炼 · 已配置'),
            localBackend: variant == 'C'
                ? (connected: false, label: 'DeepSeek · 未配置')
                : (connected: true, label: 'DeepSeek · 已配置'),
          ),
          live: form,
          child: NewTranslatePage(
            form: form,
            queue: queue,
            onOpenSettings: () {},
            onOpenTasks: () {},
            onSwitchToTranscribe: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    if (variant == 'D') {
      tester
          .state<NewTranslatePageState>(find.byType(NewTranslatePage))
          .showEnqueuedBanner(3);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
    // 横幅的 6 秒定时器不能留到测试结束。
    await tester.pump(const Duration(seconds: 7));
  }

  testWidgets('翻译页 · A 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_page_empty_light',
      brightness: Brightness.light,
      variant: 'A',
    );
  });

  testWidgets('翻译页 · B 常态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_page_light',
      brightness: Brightness.light,
      variant: 'B',
    );
  });

  testWidgets('翻译页 · B 常态 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_page_dark',
      brightness: Brightness.dark,
      variant: 'B',
    );
  });

  testWidgets('翻译页 · C 阻断态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_page_blocked_light',
      brightness: Brightness.light,
      variant: 'C',
    );
  });

  testWidgets('翻译页 · D 提交后 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_translate_page_submitted_light',
      brightness: Brightness.light,
      variant: 'D',
    );
  });
}
