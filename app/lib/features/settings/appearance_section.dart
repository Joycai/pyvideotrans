import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/settings.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 「外观」分区：主题。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({
    super.key,
    required this.settings,
    required this.stacked,
    required this.saved,
    required this.onChanged,
  });

  final AppSettings settings;

  /// 窄窗口下标签与控件上下堆叠。
  final bool stacked;

  /// 这一区刚改过，标题右侧显示「已保存」。
  final bool saved;

  /// 改动回报：页面据此显示「已保存」并刷新目录高亮；typed 表示是键盘输入。
  final void Function({bool typed}) onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      section: SettingsSectionKey.appearance,
      saved: saved,
      children: [
        SettingsRow(
          label: '主题',
          note: '跟随系统时随桌面的浅色 / 深色设置切换',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillSegments<String>(
              segments: const [
                (value: 'system', label: '跟随系统', icon: Symbols.brightness_auto),
                (value: 'light', label: '浅色', icon: Symbols.light_mode),
                (value: 'dark', label: '深色', icon: Symbols.dark_mode),
              ],
              value: settings.themeMode,
              onChanged: (v) {
                settings.themeMode = v;
                onChanged();
              },
            ),
          ),
        ),
      ],
    );
  }
}
