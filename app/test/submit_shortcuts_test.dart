import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/features/shared/submit_shortcuts.dart';

void main() {
  late List<String> calls;

  Future<void> pump(WidgetTester tester, {bool dismissible = true}) async {
    calls = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmitShortcuts(
            onSubmit: () => calls.add('submit'),
            onDismiss: dismissible ? () => calls.add('dismiss') : null,
            child: Column(
              children: [
                const TextField(key: Key('single')),
                const TextField(key: Key('multi'), maxLines: 4),
                TextButton(
                  key: const Key('button'),
                  onPressed: () => calls.add('button'),
                  child: const Text('按钮'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> focus(WidgetTester tester, String key) async {
    if (key == 'button') {
      Focus.of(tester.element(find.text('按钮'))).requestFocus();
    } else {
      await tester.tap(find.byKey(Key(key)));
    }
    await tester.pump();
  }

  group('Enter', () {
    testWidgets('没有焦点控件、或在单行输入框里：提交', (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await focus(tester, 'single');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['submit', 'submit']);
    });

    testWidgets('多行输入框里是换行，不提交', (tester) async {
      await pump(tester);
      await focus(tester, 'multi');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty);
    });

    testWidgets('焦点在按钮上：按下按钮，不提交', (tester) async {
      await pump(tester);
      await focus(tester, 'button');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, ['button']);
    });

    testWidgets('主修饰键+Enter 在哪都提交，按平台区分', (tester) async {
      await pump(tester);
      await focus(tester, 'multi');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      // macOS 上 Ctrl+Enter 不算。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls, ['submit']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  testWidgets('输入法组字时 Enter 是选定候选、Esc 是取消候选，都不当快捷键', (tester) async {
    await pump(tester);
    await focus(tester, 'single');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, isEmpty);
  });

  group('Esc', () {
    testWidgets('打字时只失焦，再按一次才关闭', (tester) async {
      await pump(tester);
      await focus(tester, 'single');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls, ['dismiss']);
    });

    testWidgets('没有关闭可言的页面：Esc 只失焦', (tester) async {
      await pump(tester, dismissible: false);
      await focus(tester, 'single');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls, isEmpty);
    });
  });
}
