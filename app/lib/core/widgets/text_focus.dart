import 'package:flutter/widgets.dart';

/// 键盘焦点是否落在输入框里。[multiline] 为 true 时只认多行输入框。
///
/// 页面级快捷键在用户打字时要让路：编辑器的 J/K 与数字键遇到任何输入框都让，
/// 建任务页面的「回车开始」只在多行输入框里让 —— 那里回车是换行，单行框里
/// 回车提交正是想要的。
///
/// 焦点节点挂在 EditableText 内部的 Focus 上，`primaryFocus.context.widget`
/// 是那个 Focus 而不是 EditableText，所以要往上找 —— 只比对 widget 本身的话
/// 永远判不出来。
bool isEditingText({bool multiline = false}) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final widget = context.widget;
  final editable = widget is EditableText
      ? widget
      : context.findAncestorWidgetOfExactType<EditableText>();
  if (editable == null) return false;
  return !multiline || editable.maxLines != 1;
}
