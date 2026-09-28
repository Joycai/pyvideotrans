import 'package:flutter/services.dart';

import '../../core/shortcuts/app_shortcut.dart';

/// 编辑器的快捷键登记表。键位、作用范围与界面提示都从这里来。
///
/// 只放键位，不依赖控制器：控制器与各处文案（「⌘S 写入」）也要引用它，
/// 绑定与动作在 editor_shortcuts.dart。
///
/// 两个作用范围，用焦点树表达，而不是在一个处理函数里猜焦点在哪：
/// - 字幕表范围（`CueTableShortcuts`）：单键，只挂在字幕列表自己的焦点上。
///   焦点在输入框、按钮、浮层里时按键根本到不了这里，不用判断「是不是在
///   打字」。
/// - 编辑页范围（`EditorPageShortcuts`）：带主修饰键的组合，焦点在编辑页
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
