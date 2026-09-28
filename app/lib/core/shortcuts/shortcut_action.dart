import 'package:flutter/widgets.dart';

import '../widgets/text_focus.dart';

/// 全应用快捷键动作的共同基类：[enabled] 是这个动作自己的条件，输入法
/// 组字时则一律不启用。
///
/// 组字时 Enter 是选定候选、Esc 是取消候选，数字键是选第几个候选 —— 这时
/// 任何快捷键都不该抢。这条放在基类里而不是由各处自己判断：之前建任务入口、
/// 编辑器、浮层各写一遍，浮层那处漏了，拼音打到一半按 Esc 整个菜单连同
/// 打的字一起没了。
///
/// 未启用时按键不算处理过，继续往外传，交给真正该处理它的控件。
class ShortcutAction<T extends Intent> extends Action<T> {
  ShortcutAction(this.run, {this.enabled});

  final void Function(T intent) run;
  final bool Function(T intent)? enabled;

  @override
  bool isEnabled(T intent) =>
      !isComposingText() && (enabled?.call(intent) ?? true);

  @override
  void invoke(T intent) => run(intent);
}
