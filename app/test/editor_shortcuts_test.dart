import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/features/editor/cue_table_rows.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_page.dart';
import 'package:subtitle_studio/features/editor/speaker_manager.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';

/// 编辑器快捷键按焦点分范围：单键只在字幕列表有焦点时生效，带主修饰键的
/// 组合在编辑页任何地方都生效。测试平台固定为 macOS（主修饰键 ⌘）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<EditorController> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final c = EditorController(session: localSession(), settings: settings);
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1332,
            height: 800,
            child: EditorPage(controller: c),
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
    if (command) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (command) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

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

    testWidgets('⌘ 组合照常生效：⌘数字指派、⌘Enter 校对', (tester) async {
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
    }, variant: mac);

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
