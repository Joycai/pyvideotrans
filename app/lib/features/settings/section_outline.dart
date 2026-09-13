import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';

/// 设置页的七个分区。目录、锚点、「恢复默认」都按它索引。
enum SettingsSectionKey {
  appearance('外观', '外观', Symbols.palette),
  asr('识别服务', '识别服务', Symbols.graphic_eq),
  mt('翻译服务', '翻译服务', Symbols.translate),
  lang('语言', '语言', Symbols.language),
  defaults('任务默认值', '任务默认值', Symbols.tune),
  output('输出', '输出', Symbols.folder),
  local('本地模型服务', '本地服务', Symbols.dns);

  const SettingsSectionKey(this.title, this.outlineLabel, this.icon);

  /// 分区标题。
  final String title;

  /// 目录里的短名（「本地模型服务」在 208px 的目录里叫「本地服务」）。
  final String outlineLabel;
  final IconData icon;
}

/// 目录的两种形态：宽窗口时是内容面板左侧 208px 的竖排目录，
/// 窗口窄于 1180 时折叠成面板顶部 48px 的横向 Tab。
enum OutlineMode { rail, tabs }

/// 分区目录（设计稿 C-SectionOutline）。点击跳转、滚动时高亮当前分区，
/// 未配置的服务在目录项右侧带一个 6px 的 error 圆点。
class SectionOutline extends StatelessWidget {
  const SectionOutline({
    super.key,
    required this.mode,
    required this.active,
    required this.onSelect,
    this.warn = const {},
  });

  final OutlineMode mode;
  final SettingsSectionKey active;
  final ValueChanged<SettingsSectionKey> onSelect;

  /// 要打红点的分区（服务未配置完整）。
  final Set<SettingsSectionKey> warn;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final rail = mode == OutlineMode.rail;

    final items = [
      for (final key in SettingsSectionKey.values)
        _OutlineItem(
          section: key,
          selected: key == active,
          warn: warn.contains(key),
          showIcon: rail,
          padding: rail ? 10 : 12,
          onTap: () => onSelect(key),
        ),
    ];

    if (rail) {
      return Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s4,
          horizontal: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Text(
                '分区',
                style: context.texts.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const SizedBox(height: 2),
              item,
            ],
          ],
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s1 + 2),
              item,
            ],
          ],
        ),
      ),
    );
  }
}

class _OutlineItem extends StatelessWidget {
  const _OutlineItem({
    required this.section,
    required this.selected,
    required this.warn,
    required this.showIcon,
    required this.padding,
    required this.onTap,
  });

  final SettingsSectionKey section;
  final bool selected;
  final bool warn;
  final bool showIcon;
  final double padding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
        focusColor: cs.onSurface.withValues(alpha: AppStateLayer.focus),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) ...[
                  Icon(
                    section.icon,
                    size: 18,
                    weight: 400,
                    fill: selected ? 1 : 0,
                    color: fg,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                ],
                Flexible(
                  child: Text(
                    section.outlineLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (selected
                                ? context.texts.titleSmall
                                : context.texts.bodyMedium)
                            ?.copyWith(color: fg),
                  ),
                ),
                if (warn) ...[
                  const SizedBox(width: AppSpacing.s2 + 2),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
