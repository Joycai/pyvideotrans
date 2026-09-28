import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/features/editor/editor_widgets.dart';

void main() {
  late FocusNode outside;
  late List<String> outerKeys;

  Future<void> pump(WidgetTester tester) async {
    outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);
    outerKeys = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            // 外层（比如编辑器）也管 Esc：菜单开着时不该轮到它。
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  outerKeys.add('esc'),
            },
            child: Column(
              children: [
                Focus(focusNode: outside, child: const SizedBox(height: 20)),
                AnchoredPopover(
                  width: 200,
                  anchor: (context, toggle, open) => TextButton(
                    onPressed: toggle,
                    child: Text(open ? '收起' : '打开'),
                  ),
                  popover: (context, close) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('菜单'),
                      TextButton(onPressed: close, child: const Text('选这个')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    outside.requestFocus();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Esc 只关浮层，不穿到外层；焦点回到打开前的位置', (tester) async {
    await pump(tester);
    await open(tester);
    expect(find.text('菜单'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('菜单'), findsNothing);
    expect(outerKeys, isEmpty);
    expect(outside.hasFocus, isTrue);

    // 关掉之后外层的键照常生效。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(outerKeys, ['esc']);
  });

  testWidgets('点菜单项关闭时焦点也还回去', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('选这个'));
    await tester.pump();
    expect(find.text('菜单'), findsNothing);
    expect(outside.hasFocus, isTrue);
  });
}
