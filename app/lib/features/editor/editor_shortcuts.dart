import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/widgets/text_focus.dart';
import 'editor_controller.dart';

/// 编辑器的快捷键登记表。键位、作用范围与界面提示都从这里来。
///
/// 两个作用范围，用焦点树表达，而不是在一个处理函数里猜焦点在哪：
/// - 字幕表范围（[CueTableShortcuts]）：单键，只挂在字幕列表自己的焦点上。
///   焦点在输入框、按钮、浮层里时按键根本到不了这里，不用判断「是不是在
///   打字」。
/// - 编辑页范围（[EditorPageShortcuts]）：带主修饰键的组合，焦点在编辑页
///   任何地方都生效，打字时也能指派说话人、标记已校对、保存。
abstract final class EditorKeys {
  // —— 字幕表范围 ——
  static const next = [
    AppShortcut(LogicalKeyboardKey.keyJ, repeats: true),
    AppShortcut(LogicalKeyboardKey.arrowDown, repeats: true),
  ];
  static const previous = [
    AppShortcut(LogicalKeyboardKey.keyK, repeats: true),
    AppShortcut(LogicalKeyboardKey.arrowUp, repeats: true),
  ];
  static const extendNext = AppShortcut(
    LogicalKeyboardKey.arrowDown,
    shift: true,
    repeats: true,
  );
  static const extendPrevious = AppShortcut(
    LogicalKeyboardKey.arrowUp,
    shift: true,
    repeats: true,
  );

  /// 数字 1–9：指派名单里的第 N 位说话人。一次性操作，不连发。
  static const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const toggleReviewed = AppShortcut(LogicalKeyboardKey.enter);
  static const playPause = AppShortcut(LogicalKeyboardKey.space);
  static const back = AppShortcut(LogicalKeyboardKey.arrowLeft, repeats: true);
  static const forward = AppShortcut(
    LogicalKeyboardKey.arrowRight,
    repeats: true,
  );
  static const exitMultiSelect = AppShortcut(LogicalKeyboardKey.escape);

  // —— 编辑页范围 ——
  static const save = AppShortcut(LogicalKeyboardKey.keyS, primary: true);
  static const undo = AppShortcut(
    LogicalKeyboardKey.keyZ,
    primary: true,
    repeats: true,
  );
  static const toggleReviewedAnywhere = AppShortcut(
    LogicalKeyboardKey.enter,
    primary: true,
  );
  static const backToTable = AppShortcut(LogicalKeyboardKey.escape);

  /// 快退快进一次挪多少。
  static const nudge = Duration(seconds: 1);
}

/// 字幕表范围：包住字幕列表区域（不含工具栏 —— 工具栏上的筛选浮层挂在
/// 它底下，菜单开着时按数字键会被当成指派说话人）。
class CueTableShortcuts extends StatelessWidget {
  const CueTableShortcuts({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.child,
  });

  final EditorController controller;
  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Shortcuts(
      shortcuts: {
        for (final s in EditorKeys.next) s.activator(): const _StepIntent(1),
        for (final s in EditorKeys.previous)
          s.activator(): const _StepIntent(-1),
        EditorKeys.extendNext.activator(): const _StepIntent(1, extend: true),
        EditorKeys.extendPrevious.activator(): const _StepIntent(
          -1,
          extend: true,
        ),
        for (final (i, key) in EditorKeys.digits.indexed) ...{
          AppShortcut(key).activator(): _AssignIntent(i + 1),
          AppShortcut(key, shift: true).activator(): _AssignIntent(
            i + 1,
            run: true,
          ),
        },
        EditorKeys.toggleReviewed.activator(): const _ToggleReviewedIntent(),
        EditorKeys.playPause.activator(): const _PlayPauseIntent(),
        EditorKeys.back.activator(): const _NudgeIntent(-1),
        EditorKeys.forward.activator(): const _NudgeIntent(1),
        EditorKeys.exitMultiSelect.activator(): const _ExitMultiIntent(),
      },
      child: Actions(
        actions: {
          _StepIntent: _Act<_StepIntent>(
            (i) => i.extend ? c.extendStep(i.delta) : c.step(i.delta),
          ),
          _AssignIntent: _assignAction(c),
          _ToggleReviewedIntent: _Act<_ToggleReviewedIntent>(
            (_) => c.toggleReviewed(),
          ),
          _PlayPauseIntent: _Act<_PlayPauseIntent>(
            (_) => c.media.playback?.toggle(),
            enabled: (_) => c.media.playback != null,
          ),
          _NudgeIntent: _Act<_NudgeIntent>(
            (i) => c.media.playback?.nudge(EditorKeys.nudge * i.direction),
            enabled: (_) => c.media.playback != null,
          ),
          _ExitMultiIntent: _Act<_ExitMultiIntent>(
            (_) => c.clearMultiSelection(),
            enabled: (_) => c.multiSelected,
          ),
        },
        child: Focus(focusNode: focusNode, child: child),
      ),
    );
  }
}

/// 编辑页范围：包住整个编辑页。
class EditorPageShortcuts extends StatelessWidget {
  const EditorPageShortcuts({
    super.key,
    required this.controller,
    required this.tableFocus,
    required this.onSave,
    required this.child,
  });

  final EditorController controller;

  /// 字幕列表的焦点：Esc 把焦点还给它。
  final FocusNode tableFocus;
  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Shortcuts(
      shortcuts: {
        EditorKeys.save.activator(): const _SaveIntent(),
        EditorKeys.undo.activator(): const _UndoIntent(),
        for (final (i, key) in EditorKeys.digits.indexed) ...{
          AppShortcut(key, primary: true).activator(): _AssignIntent(i + 1),
          AppShortcut(key, primary: true, shift: true).activator():
              _AssignIntent(i + 1, run: true),
        },
        EditorKeys.toggleReviewedAnywhere.activator():
            const _ToggleReviewedIntent(),
        EditorKeys.backToTable.activator(): const _BackToTableIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: _Act<_SaveIntent>((_) => onSave()),
          // 页面级绑定比输入框自带的 ⌘Z 离焦点更近，会先拿到按键。打字时
          // 让出去：输入框里的 ⌘Z 撤销的是刚打的字，不是整份文档。
          _UndoIntent: _Act<_UndoIntent>(
            (_) => c.undo(),
            enabled: (_) => !isEditingText(),
          ),
          _AssignIntent: _assignAction(c),
          _ToggleReviewedIntent: _Act<_ToggleReviewedIntent>(
            (_) => c.toggleReviewed(),
          ),
          _BackToTableIntent: _Act<_BackToTableIntent>(
            (_) => tableFocus.requestFocus(),
            enabled: (_) => !tableFocus.hasFocus && tableFocus.context != null,
          ),
        },
        child: child,
      ),
    );
  }
}

/// 名单里没有第 N 位时不启用，按键照常外传。
_Act<_AssignIntent> _assignAction(EditorController c) => _Act<_AssignIntent>(
  (i) => c.assignSpeaker(c.speakers[i.n - 1].id, run: i.run),
  enabled: (i) => i.n <= c.speakers.length,
);

class _StepIntent extends Intent {
  const _StepIntent(this.delta, {this.extend = false});
  final int delta;
  final bool extend;
}

class _AssignIntent extends Intent {
  const _AssignIntent(this.n, {this.run = false});
  final int n;
  final bool run;
}

class _ToggleReviewedIntent extends Intent {
  const _ToggleReviewedIntent();
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.direction);
  final int direction;
}

class _ExitMultiIntent extends Intent {
  const _ExitMultiIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _BackToTableIntent extends Intent {
  const _BackToTableIntent();
}

/// 带启用条件的动作。未启用时按键不算处理过，继续往外传。
class _Act<T extends Intent> extends Action<T> {
  _Act(this.run, {this.enabled});

  final void Function(T intent) run;
  final bool Function(T intent)? enabled;

  @override
  bool isEnabled(T intent) => enabled?.call(intent) ?? true;

  @override
  void invoke(T intent) => run(intent);
}
