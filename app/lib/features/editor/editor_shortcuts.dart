import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/widgets/text_focus.dart';
import 'editor_controller.dart';
import 'editor_keys.dart';

/// 页脚那一行提示。列表有焦点时列常用单键（用不上的不列），没焦点时说清
/// 怎么让单键生效 —— 焦点在别处时单键本来就不响应，列出来反而像坏了。
String editorFooterHint(EditorController c, {required bool tableFocused}) {
  if (!tableFocused) {
    return '按 ${keyName(LogicalKeyboardKey.escape)} 或点表格使用单键快捷键';
  }
  return shortcutHints([
    ('J/K', '上下条'),
    if (c.speakers.isNotEmpty) ('1–9', '说话人'),
    (EditorKeys.toggleReviewed.label(), '校对'),
    if (c.media.playback != null) (EditorKeys.playPause.label(), '播放'),
    (EditorKeys.save.label(), '保存'),
  ]);
}

/// 完整快捷键表，给页脚键盘图标的悬停提示用。
String editorShortcutSheet() {
  String both(AppShortcut a, AppShortcut b) => '${a.label()} / ${b.label()}';
  final table = [
    ('J / K、${both(EditorKeys.next[1], EditorKeys.previous[1])}', '下一条 / 上一条'),
    (both(EditorKeys.extendNext, EditorKeys.extendPrevious), '扩选到下一条 / 上一条'),
    ('1–9', '指派第 N 位说话人'),
    (
      '${const AppShortcut(LogicalKeyboardKey.digit1, shift: true).label()}–9',
      '按连续段指派',
    ),
    (EditorKeys.toggleReviewed.label(), '标记已校对'),
    (EditorKeys.playPause.label(), '播放 / 暂停'),
    (both(EditorKeys.back, EditorKeys.forward), '快退 / 快进 1 秒'),
    (EditorKeys.exitMultiSelect.label(), '退出多选'),
  ];
  final page = [
    (EditorKeys.save.label(), '保存到字幕文件'),
    (EditorKeys.undo.label(), '撤销'),
    (
      '${const AppShortcut(LogicalKeyboardKey.digit1, primary: true).label()}–9',
      '指派说话人',
    ),
    (EditorKeys.toggleReviewedAnywhere.label(), '标记已校对'),
    (EditorKeys.backToTable.label(), '回到字幕表'),
  ];
  String lines(List<(String, String)> rows) =>
      rows.map((r) => '${r.$1}　${r.$2}').join('\n');
  return '字幕表里\n${lines(table)}\n\n编辑页任意处\n${lines(page)}';
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
