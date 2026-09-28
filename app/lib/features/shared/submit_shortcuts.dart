import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/widgets/text_focus.dart';

/// 建任务入口（工作台页与两个对话框）共用的键盘约定：
///
/// - Enter：提交。焦点所在的控件自己要用 Enter 时让给它 —— 多行输入框里
///   是换行，按钮（登记了「激活」动作的控件）上是按下它，不能被抢成提交。
/// - ⌘Enter / Ctrl+Enter：无论焦点在哪都提交。
/// - Esc：正在输入框里打字时只让输入框失焦；否则交给 [onDismiss]（对话框
///   关闭）。打字时按一下 Esc 就丢掉整个对话框，填的东西全没了。失焦时焦点
///   交回这里的根节点，而不是 `unfocus()` 交给路由 —— 那样焦点落到本组件
///   外面，第二下 Esc 就到不了这里。
///
/// 条件不满足时动作是「未启用」而不是吃掉按键：按键继续往外传，交给真正
/// 该处理它的地方。
///
/// 根节点 autofocus：同一作用域里先挂上的 autofocus 赢，所以子孙按钮再设
/// autofocus 不会生效。要让某个按钮打开就有焦点，得在打开后显式请求。
class SubmitShortcuts extends StatefulWidget {
  const SubmitShortcuts({
    super.key,
    required this.onSubmit,
    this.onDismiss,
    required this.child,
  });

  static const submit = AppShortcut(LogicalKeyboardKey.enter);
  static const forceSubmit = AppShortcut(
    LogicalKeyboardKey.enter,
    primary: true,
  );
  static const dismiss = AppShortcut(LogicalKeyboardKey.escape);

  final VoidCallback onSubmit;

  /// Esc 的最后一级。工作台页没有「关闭」可言，传 null。
  final VoidCallback? onDismiss;
  final Widget child;

  @override
  State<SubmitShortcuts> createState() => _SubmitShortcutsState();
}

class _SubmitShortcutsState extends State<SubmitShortcuts> {
  final _home = FocusNode(debugLabel: 'SubmitShortcuts');

  @override
  void dispose() {
    _home.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const submit = SubmitShortcuts.submit;
    const forceSubmit = SubmitShortcuts.forceSubmit;
    const dismiss = SubmitShortcuts.dismiss;
    return Shortcuts(
      shortcuts: {
        submit.activator(): const _SubmitIntent(force: false),
        forceSubmit.activator(): const _SubmitIntent(force: true),
        dismiss.activator(): const _DismissIntent(),
      },
      child: Actions(
        actions: {
          _SubmitIntent: _SubmitAction(widget.onSubmit),
          _DismissIntent: _DismissAction(widget.onDismiss, _home),
        },
        child: Focus(focusNode: _home, autofocus: true, child: widget.child),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent({required this.force});
  final bool force;
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class _SubmitAction extends Action<_SubmitIntent> {
  _SubmitAction(this.onSubmit);
  final VoidCallback onSubmit;

  @override
  bool isEnabled(_SubmitIntent intent) =>
      intent.force || !focusedControlTakesEnter();

  @override
  void invoke(_SubmitIntent intent) => onSubmit();
}

class _DismissAction extends Action<_DismissIntent> {
  _DismissAction(this.onDismiss, this.home);
  final VoidCallback? onDismiss;
  final FocusNode home;

  @override
  bool isEnabled(_DismissIntent intent) => isEditingText() || onDismiss != null;

  @override
  void invoke(_DismissIntent intent) {
    if (isEditingText()) {
      home.requestFocus();
    } else {
      onDismiss?.call();
    }
  }
}

/// 焦点所在的控件自己会处理 Enter：多行输入框（换行），或者按钮这类登记了
/// 「激活」动作的控件。
bool focusedControlTakesEnter() {
  if (isEditingText(multiline: true)) return true;
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final activate = Actions.maybeFind<ActivateIntent>(context);
  return activate != null && activate.isEnabled(const ActivateIntent());
}
