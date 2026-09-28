@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/task_filter.dart';
import 'package:subtitle_studio/features/shared/page_chrome.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/features/tasks/tasks_board.dart';

import '../merge_task_fixtures.dart';

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

void main() {
  setUpAll(_loadCjkFont);

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    required String selectedId,
  }) async {
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
          section: AppSection.tasks,
          onSectionChanged: (_) {},
          chrome: () =>
              const PageChrome(title: '任务', subtitle: '3 个任务 · 1 个进行中 · 1 个失败'),
          status: () => const StatusSnapshot(
            ffmpeg: 'ffmpeg · 就绪',
            asr: (connected: true, label: '阿里百炼 · 已配置'),
            translation: (connected: true, label: 'DeepSeek · 已配置'),
          ),
          live: ChangeNotifier(),
          child: TasksBoard(
            tasks: [mergeRunning(), mergeDone(), mergeFailed()],
            filter: TaskFilter.all,
            counts: const {
              TaskFilter.all: 3,
              TaskFilter.running: 1,
              TaskFilter.failed: 1,
              TaskFilter.done: 1,
            },
            selectedId: selectedId,
            onFilterChanged: (_) {},
            onSelect: (_) {},
            onAction: (_, _) {},
            onFiles: (_) {},
            onBrowse: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
  }

  testWidgets('任务页 · 合并任务进行中 + 详情 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_tasks_light',
      brightness: Brightness.light,
      selectedId: 'mg1',
    );
  });

  testWidgets('任务页 · 合并任务完成详情 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'merge_task_detail_done_dark',
      brightness: Brightness.dark,
      selectedId: 'mg2',
    );
  });

  testWidgets('任务页 · 合并任务准备失败详情 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'merge_task_failed_light',
      brightness: Brightness.light,
      selectedId: 'mg3',
    );
  });
}
