@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/features/tasks/new_transcribe_page.dart';
import 'package:subtitle_studio/features/tasks/transcribe_form.dart';
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

/// 设计稿里的三个文件：两个探完，`product_demo` 永远停在「探测中」。
class _FakeMedia extends Media {
  static const _known = {
    'interview_ep12.mp4': (Duration(minutes: 48, seconds: 12), 1288490188),
    'lecture_week3.m4a': (Duration(hours: 1, minutes: 32, seconds: 5), 92274688),
    'screen_capture.mkv': (null, 671088640),
  };

  @override
  bool get available => false;

  @override
  Future<MediaFileInfo> probeFile(String path) {
    final name = path.split('/').last;
    final entry = _known[name];
    if (entry == null) return Completer<MediaFileInfo>().future;
    final (length, size) = entry;
    return Future.value(
      MediaFileInfo(
        path: path,
        sizeBytes: size,
        duration: length,
        exists: length != null,
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
      ..asrProviderId = variant == 'C' ? 'groq' : 'dashscope_qwen_asr'
      ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'sk-test'))
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
    final media = _FakeMedia();
    final form = TranscribeFormController(settings: settings, media: media);
    addTearDown(form.dispose);
    final queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: '/tmp', media: media),
      settings: settings,
    );

    switch (variant) {
      case 'B':
        form.handleDrop([
          '/Users/mia/Movies/采访/interview_ep12.mp4',
          '/Users/mia/Music/课程/lecture_week3.m4a',
          '/Users/mia/Movies/产品/product_demo_final_v3.mov',
        ]);
      case 'C':
        form
          ..handleDrop([
            '/Users/mia/Movies/采访/interview_ep12.mp4',
            '/Users/mia/Desktop/screen_capture.mkv',
          ])
          ..update((o) => o.copyWith(translate: false))
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
          section: AppSection.newTranscribe,
          onSectionChanged: (_) {},
          chrome: () => newTranscribeChrome(form),
          status: () => StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: variant == 'C'
                ? (connected: false, label: 'Groq · 未配置')
                : (connected: true, label: '阿里百炼 · 已配置'),
            localBackend: (connected: true, label: 'DeepSeek · 已配置'),
          ),
          live: form,
          child: NewTranscribePage(
            form: form,
            queue: queue,
            onOpenSettings: () {},
            onOpenTasks: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    if (variant == 'D') {
      tester
          .state<NewTranscribePageState>(find.byType(NewTranscribePage))
          .showEnqueuedBanner(3);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
    // 横幅的 6 秒定时器不能留到测试结束。
    await tester.pump(const Duration(seconds: 7));
  }

  testWidgets('新建转写页 · A 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_page_empty_light',
      brightness: Brightness.light,
      variant: 'A',
    );
  });

  testWidgets('新建转写页 · B 常态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_page_light',
      brightness: Brightness.light,
      variant: 'B',
    );
  });

  testWidgets('新建转写页 · B 常态 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_page_dark',
      brightness: Brightness.dark,
      variant: 'B',
    );
  });

  testWidgets('新建转写页 · C 阻断态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_page_blocked_light',
      brightness: Brightness.light,
      variant: 'C',
    );
  });

  testWidgets('新建转写页 · D 提交后 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'new_transcribe_page_submitted_light',
      brightness: Brightness.light,
      variant: 'D',
    );
  });
}
