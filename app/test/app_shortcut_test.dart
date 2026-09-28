import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/shortcuts/app_shortcut.dart';

void main() {
  const save = AppShortcut(LogicalKeyboardKey.keyS, primary: true);
  const extend = AppShortcut(
    LogicalKeyboardKey.arrowDown,
    shift: true,
    repeats: true,
  );
  const undoAll = AppShortcut(
    LogicalKeyboardKey.keyZ,
    primary: true,
    shift: true,
  );

  group('按平台区分主修饰键', () {
    test('macOS 只认 ⌘', () {
      final a = save.activator(TargetPlatform.macOS);
      expect((a.meta, a.control), (true, false));
      expect(primaryModifierLabel(TargetPlatform.macOS), '⌘');
    });

    test('Windows 与 Linux 只认 Ctrl', () {
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        final a = save.activator(p);
        expect((a.meta, a.control), (false, true));
        expect(primaryModifierLabel(p), 'Ctrl');
      }
    });

    test('不带主修饰键的两边都不加', () {
      final a = extend.activator(TargetPlatform.macOS);
      expect((a.meta, a.control, a.shift), (false, false, true));
    });
  });

  test('连发只在声明了的键上开启', () {
    expect(save.activator(TargetPlatform.macOS).includeRepeats, isFalse);
    expect(extend.activator(TargetPlatform.windows).includeRepeats, isTrue);
  });

  group('文案', () {
    test('macOS 连写符号', () {
      expect(save.label(TargetPlatform.macOS), '⌘S');
      expect(undoAll.label(TargetPlatform.macOS), '⌘⇧Z');
      expect(extend.label(TargetPlatform.macOS), '⇧↓');
    });

    test('Windows 用加号连接', () {
      expect(save.label(TargetPlatform.windows), 'Ctrl+S');
      expect(undoAll.label(TargetPlatform.windows), 'Ctrl+Shift+Z');
      expect(extend.label(TargetPlatform.linux), 'Shift+↓');
    });

    test('常用键的名字', () {
      expect(keyName(LogicalKeyboardKey.keyJ), 'J');
      expect(keyName(LogicalKeyboardKey.digit1), '1');
      expect(keyName(LogicalKeyboardKey.space), '空格');
      expect(keyName(LogicalKeyboardKey.escape), 'Esc');
      expect(keyName(LogicalKeyboardKey.enter), 'Enter');
    });

    test('提示拼成一行', () {
      expect(
        shortcutHints([('J/K', '上下条'), ('Enter', '校对')]),
        'J/K 上下条 · Enter 校对',
      );
    });
  });

  test('未指定平台时跟着 defaultTargetPlatform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(save.label(), 'Ctrl+S');
    expect(usesCommandKey(), isFalse);
  });
}
