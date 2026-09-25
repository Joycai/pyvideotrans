import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';

/// 单行输入框的外部同步：「重置为默认」「上次参数」要能改进框里，
/// 但不能在输入时把光标甩走，也不能把用户刚清空的框又填回去。
void main() {
  Future<void> pump(WidgetTester tester, String value) => tester.pumpWidget(
    MaterialApp(
      theme: lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: SingleLineField(value: value, onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );

  String text(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('没有焦点时外部改了值就同步进来', (tester) async {
    await pump(tester, 'aac');
    await pump(tester, 'opus');
    expect(text(tester), 'opus');
  });

  testWidgets('有焦点时外部变化不覆盖正在输入的内容', (tester) async {
    await pump(tester, 'aac');
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'aa');
    await pump(tester, 'default');
    expect(text(tester), 'aa');
  });

  testWidgets('外部值没变时不回填：清空后换成默认值的调用方不会把框填回去', (tester) async {
    await pump(tester, 'model-x');
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '');
    // 调用方把空串换成了默认值 —— 这一帧还在输入，不同步。
    await pump(tester, 'default-model');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    // 失焦后的重建外部值没再变，框里保持用户清空的样子。
    await pump(tester, 'default-model');
    expect(text(tester), '');
  });
}
