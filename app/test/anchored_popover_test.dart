import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
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

  late List<String> tapped;

  Future<void> pumpLongMenu(
    WidgetTester tester, {
    required double anchorTop,
    int rows = 40,
  }) async {
    tapped = [];
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: anchorTop,
                left: 20,
                child: AnchoredPopover(
                  width: 240,
                  anchor: (context, toggle, open) =>
                      TextButton(onPressed: toggle, child: const Text('打开')),
                  popover: (context, close) => GlassMenu(
                    children: [
                      const MenuRow(label: '标题'),
                      MenuScrollSection(
                        children: [
                          for (var i = 1; i <= rows; i++)
                            MenuRow(
                              label: '人$i',
                              onTap: () => tapped.add('人$i'),
                            ),
                        ],
                      ),
                      const MenuRow(label: '底部操作'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await open(tester);
  }

  testWidgets('列表过长时浮层封顶在窗口内，只有中间一段滚动', (tester) async {
    await pumpLongMenu(tester, anchorTop: 40);
    expect(tester.takeException(), isNull);
    // 标题与底部操作始终在窗口里。
    expect(tester.getRect(find.text('标题')).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(find.text('底部操作')).bottom, lessThanOrEqualTo(600));

    await tester.scrollUntilVisible(
      find.text('人40'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.getRect(find.text('人40')).bottom, lessThanOrEqualTo(600));
    await tester.tap(find.text('人40'));
    expect(tapped, ['人40']);
  });

  testWidgets('锚点靠近窗口底部时浮层往上开', (tester) async {
    await pumpLongMenu(tester, anchorTop: 520);
    expect(tester.takeException(), isNull);
    final anchor = tester.getRect(find.text('打开'));
    expect(tester.getRect(find.text('底部操作')).bottom, lessThan(anchor.top));
    expect(tester.getRect(find.text('标题')).top, greaterThanOrEqualTo(0));
  });

  testWidgets('锚点靠近窗口底部但菜单放得下时照常往下开', (tester) async {
    await pumpLongMenu(tester, anchorTop: 360, rows: 2);
    expect(tester.takeException(), isNull);
    final anchor = tester.getRect(find.text('打开'));
    expect(tester.getRect(find.text('标题')).top, greaterThan(anchor.bottom));
    expect(tester.getRect(find.text('底部操作')).bottom, lessThanOrEqualTo(600));
  });
}
