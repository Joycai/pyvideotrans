import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/wallpaper.dart';
import 'package:subtitle_studio/features/shared/page_chrome.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';

/// 渲染性能的两条回归线：
/// 1. 壁纸必须是烘焙好的一张图，不能退回逐帧叠四层全窗口渐变；
/// 2. 任务进度只刷新顶栏与状态栏，不能把整棵树连内容区一起重建。
void main() {
  testWidgets('壁纸只画一张烘焙图，没有逐帧的渐变层', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: const AppWallpaper(child: SizedBox.expand()),
      ),
    );
    // 首帧在 post-frame 里同步烘焙并 setState，再 pump 一帧就该有图了。
    await tester.pump();

    final wallpaper = find.byType(AppWallpaper);
    expect(
      find.descendant(of: wallpaper, matching: find.byType(RawImage)),
      findsOneWidget,
    );
    final gradients = find.descendant(
      of: wallpaper,
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.gradient != null,
      ),
    );
    expect(gradients, findsNothing);

    // 反复 pump 不能反复重烘：图片实例必须保持同一张。
    final first = tester.widget<RawImage>(find.byType(RawImage)).image;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
      identical(tester.widget<RawImage>(find.byType(RawImage)).image, first),
      isTrue,
    );
  });

  testWidgets('进度通知只重建顶栏与状态栏，不重建内容区', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final live = ChangeNotifier();
    var chromeBuilds = 0;
    var statusBuilds = 0;
    var childBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: AppShell(
          section: AppSection.tasks,
          onSectionChanged: (_) {},
          live: live,
          chrome: () {
            chromeBuilds++;
            return const PageChrome(title: '任务');
          },
          status: () {
            statusBuilds++;
            return StatusSnapshot.idle;
          },
          child: Builder(
            builder: (_) {
              childBuilds++;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect((chromeBuilds, statusBuilds, childBuilds), (1, 1, 1));

    live.notifyListeners();
    await tester.pump();
    expect((chromeBuilds, statusBuilds, childBuilds), (2, 2, 1));
  });
}
