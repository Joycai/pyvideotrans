import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/features/editor/editor_widgets.dart';

void main() {
  late FocusNode outside;
  late List<String> outerKeys;
  var adding = false;

  Future<void> pump(WidgetTester tester) async {
    adding = false;
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
                  popover: (context, close) => StatefulBuilder(
                    builder: (context, setState) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('菜单'),
                        TextButton(onPressed: close, child: const Text('选这个')),
                        if (adding)
                          const TextField(autofocus: true)
                        else
                          TextButton(
                            onPressed: () => setState(() => adding = true),
                            child: const Text('新增…'),
                          ),
                      ],
                    ),
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

  testWidgets('浮层里后建出来的 autofocus 输入框拿得到光标', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('新增…'));
    await tester.pump();
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.widget is EditableText ||
          focused?.findAncestorWidgetOfExactType<EditableText>() != null,
      isTrue,
    );
    // 输入框里按 Esc 也关浮层，焦点回到打开前的位置。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('菜单'), findsNothing);
    expect(outside.hasFocus, isTrue);
  });

  testWidgets('输入法组字时 Esc 是取消候选，不关浮层', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('新增…'));
    await tester.pump();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('菜单'), findsOneWidget);

    // 选定之后再按 Esc 照常关闭。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('菜单'), findsNothing);
  });
}
