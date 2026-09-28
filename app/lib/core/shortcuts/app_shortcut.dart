import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 平台的主修饰键是不是 ⌘：macOS 用 ⌘，Windows 与 Linux 用 Ctrl。iOS 接
/// 实体键盘时也是 ⌘，一并算上；其余平台按 Ctrl。
///
/// 不两个都认：macOS 上 Ctrl+点击是系统右键，Ctrl+S 也不是那里的习惯；
/// Windows 上 Win 键归系统。
bool usesCommandKey([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };

/// 平台主修饰键此刻是否按着。给「⌘/Ctrl+点击」这类鼠标操作用 ——
/// 键盘快捷键一律走 [AppShortcut.activator]，不手查按键状态。
bool isPrimaryModifierPressed([TargetPlatform? platform]) {
  final keyboard = HardwareKeyboard.instance;
  return usesCommandKey(platform)
      ? keyboard.isMetaPressed
      : keyboard.isControlPressed;
}

/// 主修饰键给人看的名字：「⌘」或「Ctrl」。
String primaryModifierLabel([TargetPlatform? platform]) =>
    usesCommandKey(platform) ? '⌘' : 'Ctrl';

/// 一条快捷键：主键加修饰键。全应用的键盘绑定都从这里生成，界面上的
/// 提示也用 [label]，两边不会各写各的。
@immutable
class AppShortcut {
  const AppShortcut(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.repeats = false,
  });

  final LogicalKeyboardKey key;

  /// 带平台主修饰键（⌘ / Ctrl）。
  final bool primary;
  final bool shift;

  /// 按住不放时是否连发。上下移动、快进快退连发是想要的；指派说话人、
  /// 标记已校对、播放暂停这类一次性操作连发只会来回翻转或重复提交。
  final bool repeats;

  SingleActivator activator([TargetPlatform? platform]) {
    final command = usesCommandKey(platform);
    return SingleActivator(
      key,
      meta: primary && command,
      control: primary && !command,
      shift: shift,
      includeRepeats: repeats,
    );
  }

  /// 「⌘⇧S」「Ctrl+Shift+S」「J」。macOS 按系统菜单的写法连写符号。
  String label([TargetPlatform? platform]) {
    final name = keyName(key);
    if (usesCommandKey(platform)) {
      return '${primary ? '⌘' : ''}${shift ? '⇧' : ''}$name';
    }
    return [if (primary) 'Ctrl', if (shift) 'Shift', name].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is AppShortcut &&
      other.key == key &&
      other.primary == primary &&
      other.shift == shift &&
      other.repeats == repeats;

  @override
  int get hashCode => Object.hash(key, primary, shift, repeats);

  @override
  String toString() => 'AppShortcut(${label()})';
}

/// 键在提示里的名字。字母大写、数字原样，常用功能键用符号或中文。
String keyName(LogicalKeyboardKey key) {
  final named = _names[key];
  if (named != null) return named;
  final label = key.keyLabel;
  if (label.isEmpty) return key.debugName ?? '?';
  return label.length == 1 ? label.toUpperCase() : label;
}

final _names = {
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.space: '空格',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
};

/// 把「键 说明」若干条拼成一行提示：`J/K 上下条 · Enter 校对`。
String shortcutHints(Iterable<(String keys, String what)> items) =>
    items.map((e) => '${e.$1} ${e.$2}').join(' · ');
