import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/glass_panel.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';

Future<Rect> _pumpPanel(WidgetTester tester, double height, Key key) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: height,
            child: GlassPanel(
              child: Row(
                children: [SizedBox(key: key, height: 20, width: 20)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byKey(key));
}

void main() {
  group('GlassPanel', () {
    // Stack 默认 loose + topStart，会把内容钉在面板顶部。顶栏和状态栏都是
    // 固定高度的容器，一旦回退，里面的文字会整体偏上。
    testWidgets('内容在固定高度里垂直居中，而不是贴顶', (tester) async {
      for (final height in [32.0, 52.0, 120.0]) {
        const key = ValueKey('probe');
        final child = await _pumpPanel(tester, height, key);
        final panel = tester.getRect(find.byType(GlassPanel));
        expect(
          child.center.dy,
          moreOrLessEquals(panel.center.dy, epsilon: 0.5),
          reason: '高度 $height 时内容没有垂直居中',
        );
      }
    });
  });

  group('应用框架', () {
    testWidgets('顶栏与状态栏的文字垂直居中', (tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: AppShell(
            section: AppSection.tasks,
            onSectionChanged: (_) {},
            chrome: const PageChrome(title: '任务', subtitle: '副标题'),
            status: StatusSnapshot.idle,
            child: const SizedBox(),
          ),
        ),
      );

      // 0 是 Rail，1 是顶栏，最后一个是状态栏。
      final bars = find.byType(GlassPanel);
      final topBar = bars.at(1);
      final statusBar = bars.last;

      final topBarRect = tester.getRect(topBar);
      expect(topBarRect.height, 52);
      // 「任务」在导航栏和顶栏里各有一处，必须限定在顶栏子树内找。
      final title = tester.getRect(
        find.descendant(of: topBar, matching: find.text('任务')),
      );
      expect(
        title.center.dy,
        moreOrLessEquals(topBarRect.center.dy, epsilon: 1.5),
        reason: '顶栏标题没有垂直居中',
      );

      final statusRect = tester.getRect(statusBar);
      expect(statusRect.height, 32);
      final statusText = tester.getRect(
        find.descendant(
          of: statusBar,
          matching: find.textContaining('本地识别'),
        ),
      );
      expect(
        statusText.center.dy,
        moreOrLessEquals(statusRect.center.dy, epsilon: 1.5),
        reason: '状态栏文字没有垂直居中',
      );
    });
  });
}
