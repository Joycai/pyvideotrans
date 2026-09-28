import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/editor/cue_table_rows.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_page.dart';
import 'package:subtitle_studio/features/editor/editor_shortcuts.dart';
import 'package:subtitle_studio/features/editor/editor_widgets.dart';
import 'package:subtitle_studio/features/editor/speaker_manager.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';

/// 编辑器快捷键按焦点分范围：单键只在字幕列表有焦点时生效，带主修饰键的
/// 组合在编辑页任何地方都生效。测试平台固定为 macOS（主修饰键 ⌘）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  var saved = 0;

  Future<EditorController> pump(WidgetTester tester) async {
    saved = 0;
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final c = EditorController(session: localSession(), settings: settings);
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final page = GlobalKey<EditorPageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        // 与 main.dart 一样：组合键包住整个外壳，顶栏也在它底下。
        home: EditorShortcuts(
          target: () => page.currentState?.shortcutTarget,
          onSave: () => saved++,
          child: Scaffold(
            body: Column(
              children: [
                // 模拟顶栏：在编辑页的子树之外，有自己的浮层和按钮。
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      AnchoredPopover(
                        width: 200,
                        anchor: (context, toggle, open) => TextButton(
                          onPressed: toggle,
                          child: const Text('顶栏浮层'),
                        ),
                        popover: (context, close) => const Text('浮层内容'),
                      ),
                      TextButton(onPressed: () {}, child: const Text('顶栏按钮')),
                    ],
                  ),
                ),
                SizedBox(
                  width: 1332,
                  height: 800,
                  child: EditorPage(
                    key: page,
                    controller: c,
                    onSave: () async => saved++,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool command = false,
    bool shift = false,
  }) async {
    // 主修饰键按测试平台选：macOS 是 ⌘，其余是 Ctrl。
    final primary = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    if (command) await tester.sendKeyDownEvent(primary);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (command) await tester.sendKeyUpEvent(primary);
    await tester.pump();
  }

  bool tableHasFocus() =>
      FocusManager.instance.primaryFocus?.debugLabel == 'CueTable';

  /// 检视面板里的原文输入框。
  Future<void> focusSourceField(WidgetTester tester) async {
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
  }

  group('焦点在字幕列表', () {
    testWidgets('进页面就能用单键：J/K 上下、数字指派、Enter 校对', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(c.selected, 1);
      await press(tester, LogicalKeyboardKey.keyK);
      expect(c.selected, 0);

      final third = c.speakers[2];
      await press(tester, LogicalKeyboardKey.digit3);
      expect(c.document.cues[0].speaker, third.id);

      final reviewed = c.document.cues[0].reviewed;
      await press(tester, LogicalKeyboardKey.enter);
      expect(c.document.cues[0].reviewed, !reviewed);
    }, variant: mac);

    testWidgets('Shift+↓ 从锚点往下扩选，Shift+↑ 收回', (tester) async {
      final c = await pump(tester);
      c.select(1);
      await press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      await press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(c.selectedPositions, [1, 2, 3]);
      await press(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(c.selectedPositions, [1, 2]);
      // 不带 Shift 的方向键回到单选。
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(c.selectedPositions, [3]);
    }, variant: mac);

    testWidgets('一次性操作长按不连发', (tester) async {
      final c = await pump(tester);
      c.select(0);
      final reviewed = c.document.cues[0].reviewed;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(c.document.cues[0].reviewed, !reviewed);

      // 上下移动可以连发。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      expect(c.selected, 2);
    }, variant: mac);

    testWidgets('名单里没有第 N 位时数字键不处理', (tester) async {
      final c = await pump(tester);
      c.select(0);
      final before = c.document;
      await press(tester, LogicalKeyboardKey.digit9);
      expect(identical(c.document, before), isTrue);
    }, variant: mac);
  });

  group('焦点不会被带出字幕列表', () {
    testWidgets('没有预览时 ←/→ 什么都不做，也不把焦点带走', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      expect(c.media.playback, isNull);
      // 每按一下都看：→ 把焦点带走后 ← 可能又带回来。
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(tableHasFocus(), isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(tableHasFocus(), isTrue);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(c.selected, 1);
    }, variant: mac);

    testWidgets('在输入框里点外面，焦点回到字幕列表，快捷键都还在', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      await focusSourceField(tester);
      // 点页脚（不在列表区里）：输入框 unfocus，焦点落到编辑页作用域再转给列表。
      await tester.tap(find.textContaining('显示 '));
      await tester.pump();
      expect(tableHasFocus(), isTrue);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(c.selected, 1);
      await press(tester, LogicalKeyboardKey.keyS, command: true);
      expect(saved, 1);
    }, variant: mac);

    testWidgets('点列表区的空白（没有行的地方）也让列表拿焦点', (tester) async {
      final c = await pump(tester);
      c.select(0);
      c.setSearch('没有这句');
      await tester.pump();
      await focusSourceField(tester);
      await tester.tap(find.text('没有符合条件的字幕'));
      await tester.pump();
      expect(tableHasFocus(), isTrue);
    }, variant: mac);

    testWidgets('数字键长按只指派一次', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      final before = c.session.pendingEdits;
      // 名单每次现算，按位置找第一位不是当前说话人的。
      final speakers = c.speakers;
      final n =
          speakers.indexWhere((s) => s.id != c.document.cues[0].speaker) + 1;
      final target = speakers[n - 1];
      final key = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
      ][n - 1];
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      expect(c.document.cues[0].speaker, target.id);
      expect(c.session.pendingEdits, before + 1);
    }, variant: mac);
  });

  group('提示文案', () {
    testWidgets('页脚跟着列表有没有焦点变', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      expect(find.textContaining('J/K 上下条'), findsOneWidget);
      expect(find.textContaining('⌘S 保存'), findsOneWidget);
      await focusSourceField(tester);
      expect(find.textContaining('按 Esc 或点表格使用单键快捷键'), findsOneWidget);
      expect(find.textContaining('J/K 上下条'), findsNothing);
    }, variant: mac);

    testWidgets(
      '完整快捷键表按平台写修饰键，两个范围都列出',
      (tester) async {
        final sheet = editorShortcutSheet();
        final mac = defaultTargetPlatform == TargetPlatform.macOS;
        expect(sheet, startsWith('字幕表里'));
        expect(sheet, contains('编辑页任意处'));
        expect(sheet, contains(mac ? '⌘S　保存到字幕文件' : 'Ctrl+S　保存到字幕文件'));
        expect(sheet, contains(mac ? '⇧↓ / ⇧↑' : 'Shift+↓ / Shift+↑'));
        expect(sheet, contains('Esc　退出多选'));
        expect(sheet, contains('Esc　回到字幕表'));
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  });

  group('编辑器分区范围', () {
    testWidgets('顶栏浮层开着时 ⌘S 照样保存', (tester) async {
      await pump(tester);
      await tester.tap(find.text('顶栏浮层'));
      await tester.pump();
      await tester.pump();
      expect(find.text('浮层内容'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyS, command: true);
      expect(saved, 1);
    }, variant: mac);

    testWidgets('没有 ⌘⇧数字（macOS 截屏键）', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      await focusSourceField(tester);
      final before = c.document;
      await press(
        tester,
        LogicalKeyboardKey.digit3,
        command: true,
        shift: true,
      );
      expect(identical(c.document, before), isTrue);
    }, variant: mac);

    testWidgets('Tab 走得出编辑页', (tester) async {
      await pump(tester);
      var escaped = false;
      for (var i = 0; i < 80 && !escaped; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final label = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>();
        escaped =
            label != null &&
            (label.child as Text?)?.data?.startsWith('顶栏') == true;
      }
      expect(escaped, isTrue);
    }, variant: mac);

    testWidgets('输入法组字时 Esc 让给输入法', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      await focusSourceField(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.escape);
      expect(tableHasFocus(), isFalse);
    }, variant: mac);
  });

  group('焦点在输入框', () {
    testWidgets('单键是打字，不当快捷键', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      await focusSourceField(tester);
      final before = c.document.cues[0];
      await press(tester, LogicalKeyboardKey.keyJ);
      await press(tester, LogicalKeyboardKey.digit3);
      await press(tester, LogicalKeyboardKey.space);
      expect(c.selected, 0);
      expect(c.document.cues[0].speaker, before.speaker);
      expect(c.document.cues[0].reviewed, before.reviewed);
    }, variant: mac);

    testWidgets(
      '主修饰键组合照常生效：数字指派、Enter 校对、S 保存',
      (tester) async {
        final c = await pump(tester);
        c.select(0);
        await tester.pump();
        await focusSourceField(tester);
        final third = c.speakers[2];
        await press(tester, LogicalKeyboardKey.digit3, command: true);
        expect(c.document.cues[0].speaker, third.id);
        final reviewed = c.document.cues[0].reviewed;
        await press(tester, LogicalKeyboardKey.enter, command: true);
        expect(c.document.cues[0].reviewed, !reviewed);
        await press(tester, LogicalKeyboardKey.keyS, command: true);
        expect(saved, 1);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    testWidgets('⌘Z 撤销的是输入框里的字，不是整份文档', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      c.toggleReviewed(); // 撤销栈里先有一步文档修改
      await tester.pump();
      await focusSourceField(tester);
      final before = c.document;
      await press(tester, LogicalKeyboardKey.keyZ, command: true);
      expect(identical(c.document, before), isTrue);
    }, variant: mac);

    testWidgets('Esc 把焦点还给字幕列表，单键马上可用', (tester) async {
      final c = await pump(tester);
      c.select(0);
      await tester.pump();
      await focusSourceField(tester);
      await press(tester, LogicalKeyboardKey.escape);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(c.selected, 1);
    }, variant: mac);
  });

  testWidgets('焦点在按钮上时单键不触发', (tester) async {
    final c = await pump(tester);
    c.select(0);
    await tester.pump();
    Focus.of(tester.element(find.text('关联视频…'))).requestFocus();
    await tester.pump();
    final reviewed = c.document.cues[0].reviewed;
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    expect(c.selected, 0);
    expect(c.document.cues[0].reviewed, reviewed);
  }, variant: mac);

  testWidgets('对话框按 Esc 关掉后，焦点回到字幕列表', (tester) async {
    final c = await pump(tester);
    c.select(0);
    await tester.tap(find.byType(CueTableRow).first);
    await tester.pump();
    unawaited(showSpeakerManager(tester.element(find.byType(EditorPage)), c));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ); // 对话框开着：不动
    expect(c.selected, 0);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(c.selected, 1);
  }, variant: mac);
}
