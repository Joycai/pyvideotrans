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

/// 焦点所在的输入框正在用输入法组字（拼音、假名还没选定）。这时 Enter 是
/// 选定候选、Esc 是取消候选，页面快捷键都得让出去 —— 由 `ShortcutAction`
/// 统一判断，别在各处动作里再写一遍。
bool isComposingText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final widget = context.widget;
  final editable = widget is EditableText
      ? widget
      : context.findAncestorWidgetOfExactType<EditableText>();
  return editable?.controller.value.composing.isValid ?? false;
}
