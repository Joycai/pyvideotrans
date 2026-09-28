@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';
import 'package:subtitle_studio/features/merge/merge_form.dart';
import 'package:subtitle_studio/features/merge/merge_page.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

/// 与其他页的 golden 同样的字体处理：测试默认字体不含汉字。
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

MediaProbe _probe(
  int minutes,
  int seconds, {
  int width = 1920,
  int height = 1080,
}) => MediaProbe(
  duration: Duration(minutes: minutes, seconds: seconds),
  video: [
    VideoStreamInfo(
      codec: 'h264',
      width: width,
      height: height,
      fps: 30,
      pixFmt: 'yuv420p',
    ),
  ],
  audio: const [AudioStreamInfo(codec: 'aac', channels: 2, sampleRate: 48000)],
);

/// 设计稿 M-Merge 的样例：采访三段，第 3 段在 [_slow] 时永远停在读取中，
/// 在 [_mismatch] 时第 2 段是 720p。
class _FakeTranscoder extends Transcoder {
  _FakeTranscoder({this.slow = false, this.mismatch = false});

  final bool slow;
  final bool mismatch;

  @override
  Future<MediaProbe> probe(String path) {
    final name = path.split('/').last;
    return switch (name) {
      'interview_ep12_part1.mp4' => Future.value(_probe(32, 10)),
      'interview_ep12_part2.mp4' => Future.value(
        mismatch ? _probe(24, 36, width: 1280, height: 720) : _probe(24, 36),
      ),
      'interview_ep12_part3.mp4' when slow => Completer<MediaProbe>().future,
      _ => Future.value(_probe(11, 46)),
    };
  }
}

const _dir = '/Users/mia/Movies/采访';

String _cues(int n) => [
  for (var i = 0; i < n; i++)
    '${i + 1}\n00:00:${(i % 50 + 10).toString().padLeft(2, '0')},000 --> '
        '00:00:${(i % 50 + 10).toString().padLeft(2, '0')},900\n第 $i 句\n',
].join('\n');

void main() {
  setUpAll(_loadCjkFont);

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    bool empty = false,
    bool slow = false,
    bool mismatch = false,
    bool advanced = false,
    double width = 1440,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final transcoder = _FakeTranscoder(slow: slow, mismatch: mismatch);
    final form = MergeFormController(
      settings: settings,
      transcoder: transcoder,
      listDir: (dir) async => [
        '$dir/interview_ep12_part1.srt',
        '$dir/interview_ep12_part3.srt',
      ],
      readSubtitle: (path) async =>
          _cues(path.endsWith('part1.srt') ? 402 : 311),
    );
    addTearDown(form.dispose);
    final queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: '/tmp',
        transcoder: transcoder,
      ),
      settings: settings,
    );

    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.merge,
          onSectionChanged: (_) {},
          chrome: () => mergeChrome(form),
          status: () => const StatusSnapshot(
            ffmpeg: 'ffmpeg · 就绪',
            asr: (connected: true, label: '阿里百炼 · 已配置'),
            translation: (connected: true, label: 'DeepSeek · 已配置'),
          ),
          live: form,
          child: MergePage(form: form, queue: queue, onOpenTasks: () {}),
        ),
      ),
    );

    if (!empty) {
      await tester.runAsync(
        () => form
            .addPaths([
              '$_dir/interview_ep12_part1.mp4',
              '$_dir/interview_ep12_part2.mp4',
              '$_dir/interview_ep12_part3.mp4',
            ])
            .timeout(const Duration(milliseconds: 200), onTimeout: () {}),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      form.setChapterTitle(0, '开场与嘉宾介绍');
      form.advancedOpen = advanced;
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
  }

  testWidgets('合并页 · 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_page_empty_light',
      brightness: Brightness.light,
      empty: true,
    );
  });

  testWidgets('合并页 · 常态（第 3 段读取中）· 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_page_light',
      brightness: Brightness.light,
      slow: true,
    );
  });

  testWidgets('合并页 · 就绪、展开命令预览 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'merge_page_dark',
      brightness: Brightness.dark,
      advanced: true,
    );
  });

  testWidgets('合并页 · 第 2 段不一致 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_page_mismatch_light',
      brightness: Brightness.light,
      mismatch: true,
    );
  });

  testWidgets('合并页 · 窄窗口 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_page_narrow_light',
      brightness: Brightness.light,
      width: 1024,
    );
  });
}
