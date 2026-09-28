import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/shortcuts/shortcut_action.dart';

class _Hit extends Intent {
  const _Hit();
}

void main() {
  late List<String> calls;
  late bool allowed;

  Future<void> pump(WidgetTester tester) async {
    calls = [];
    allowed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            // 外层兜底：动作未启用时按键应该传到这里。
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  calls.add('outer'),
            },
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _Hit(),
              },
              child: Actions(
                actions: {
                  _Hit: ShortcutAction<_Hit>(
                    (_) => calls.add('hit'),
                    enabled: (_) => allowed,
                  ),
                },
                child: const TextField(autofocus: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('启用时处理按键', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, ['hit']);
  });

  testWidgets('自己的条件不满足时按键继续外传', (tester) async {
    await pump(tester);
    allowed = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, ['outer']);
  });

  testWidgets('输入法组字时一律不启用', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, isNot(contains('hit')));
  });
}
