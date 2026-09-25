import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/widgets/text_focus.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(key: Key('single')),
            TextField(key: Key('multi'), maxLines: 4),
            TextButton(onPressed: null, child: Text('按钮')),
          ],
        ),
      ),
    ),
  );

  testWidgets('没有焦点时不算在打字', (tester) async {
    await pump(tester);
    expect(isEditingText(), isFalse);
  });

  // 焦点节点挂在 EditableText 内部的 Focus 上，只比对 widget 本身会永远判 false。
  testWidgets('单行输入框：算在打字，但不算多行', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('single')));
    await tester.pump();
    expect(isEditingText(), isTrue);
    expect(isEditingText(multiline: true), isFalse);
  });

  testWidgets('多行输入框：两种都算', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('multi')));
    await tester.pump();
    expect(isEditingText(), isTrue);
    expect(isEditingText(multiline: true), isTrue);
  });
}
