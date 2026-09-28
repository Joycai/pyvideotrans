import 'package:flutter/widgets.dart';

/// 键盘焦点是否落在输入框里。[multiline] 为 true 时只认多行输入框。
///
/// 页面级快捷键在用户打字时要让路。只剩两处用它：建任务入口的
/// `SubmitShortcuts`（打字时 Esc 先失焦，多行框里回车是换行），以及编辑页的
/// ⌘Z（打字时让给输入框撤销文字）。编辑器的单键靠焦点范围隔开，不用它。
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
