import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';

/// 主按钮：竖向渐变 + 顶部内高光。M3 的 ButtonStyle 不支持 gradient，所以自绘背景，
/// 但状态层（hover / focus / pressed）仍交给 InkWell，保持与 M3 一致的手感。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 36,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  /// 对话框里的默认按钮：打开就拿到焦点，回车即按下。
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final enabled = onPressed != null;
    final fg = enabled
        ? cs.onPrimary
        : cs.onSurface.withValues(alpha: AppStateLayer.disabledContent);
    final radius = BorderRadius.circular(AppRadius.md);

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: e.primaryGradient,
              )
            : null,
        color: enabled
            ? null
            : cs.onSurface.withValues(alpha: AppStateLayer.disabledContainer),
        boxShadow: enabled ? e.primaryShadow : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          autofocus: autofocus,
          borderRadius: radius,
          hoverColor: cs.onPrimary.withValues(alpha: AppStateLayer.hover),
          focusColor: cs.onPrimary.withValues(alpha: AppStateLayer.focus),
          highlightColor: cs.onPrimary.withValues(alpha: AppStateLayer.pressed),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: _ButtonContent(
              label: label,
              icon: icon,
              color: fg,
              style: context.texts.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// 次级按钮：白色微渐变 + 1px 软阴影 + outlineVariant 描边。
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 36,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  /// 表格行内的小一号形态（32px 高、labelMedium）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final enabled = onPressed != null;
    final fg = enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: AppStateLayer.disabledContent);
    final radius = BorderRadius.circular(AppRadius.md);

    return Container(
      height: dense ? 32 : height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.controlGradient,
        ),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: e.controlShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          hoverColor: cs.primary.withValues(alpha: AppStateLayer.hover),
          focusColor: cs.primary.withValues(alpha: AppStateLayer.focus),
          highlightColor: cs.primary.withValues(alpha: AppStateLayer.pressed),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? AppSpacing.s3 : AppSpacing.s4,
            ),
            child: _ButtonContent(
              label: label,
              icon: icon,
              color: fg,
              iconSize: dense ? 16 : 18,
              style: dense
                  ? context.texts.labelMedium
                  : context.texts.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// 纯文字按钮，用于面板内的低权重操作（拆分、合并、选择文件…）。
class QuietButton extends StatelessWidget {
  const QuietButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 36,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = onPressed != null;
    final fg = enabled
        ? cs.primary
        : cs.onSurface.withValues(alpha: AppStateLayer.disabledContent);
    final radius = BorderRadius.circular(AppRadius.md);

    return SizedBox(
      height: height,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          hoverColor: cs.primary.withValues(alpha: AppStateLayer.hover),
          focusColor: cs.primary.withValues(alpha: AppStateLayer.focus),
          highlightColor: cs.primary.withValues(alpha: AppStateLayer.pressed),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
            child: _ButtonContent(
              label: label,
              icon: icon,
              color: fg,
              style: context.texts.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形图标按钮（表格行操作、播放控制）。
class IconActionButton extends StatelessWidget {
  const IconActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 32,
    this.iconSize = 20,
    this.selected = false,
    this.fill = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  /// 选中态用 secondaryContainer 做底，与 Rail 的选中指示一致。
  final bool selected;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = onPressed != null;
    final fg = !enabled
        ? cs.onSurface.withValues(alpha: AppStateLayer.disabledContent)
        : selected
        ? cs.onSecondaryContainer
        : cs.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
            focusColor: cs.onSurface.withValues(alpha: AppStateLayer.focus),
            highlightColor: cs.onSurface.withValues(
              alpha: AppStateLayer.pressed,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: fg,
              fill: fill ? 1 : 0,
              weight: 400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.color,
    required this.style,
    this.icon,
    this.iconSize = 18,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: color, weight: 400),
          const SizedBox(width: AppSpacing.s1 + 2),
        ],
        // 表格里的操作列很窄（「从准备阶段继续」这类长文案放不下），
        // 让文字省略而不是溢出。
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: style?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 分段切换（原文 / 译文 / 双语）。
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.fill = false,
  });

  /// [enabled] 为 false 的段仍然显示 —— 灰掉但可读，理由由调用方在旁边说明。
  /// 设计规范要求禁用项必须给出原因，不能只是消失或单纯变灰。
  final List<({T value, String label, bool enabled})> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// 撑满父级、各段等宽（页面 400px 参数面板里的用法）。这时不画选中对勾，
  /// 「双语 · 译文在上」这样的长标签加上对勾会挤不下；选中态靠底色区分。
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    return Container(
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.controlGradient,
        ),
        boxShadow: e.controlShadow,
      ),
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final (i, seg) in segments.indexed) ...[
            if (i > 0) VerticalDivider(width: 1, color: cs.outlineVariant),
            _maybeExpand(
              fill,
              Material(
                  color: seg.value == value
                      ? cs.secondaryContainer
                      : Colors.transparent,
                  child: InkWell(
                    onTap: seg.enabled ? () => onChanged(seg.value) : null,
                    mouseCursor: seg.enabled
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.forbidden,
                    hoverColor: cs.onSurface.withValues(
                      alpha: AppStateLayer.hover,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: fill ? 6 : 14),
                      child: SizedBox(
                        height: 34,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (seg.value == value && !fill) ...[
                                Icon(
                                  Symbols.check,
                                  size: 18,
                                  weight: 400,
                                  color: cs.onSecondaryContainer,
                                ),
                                const SizedBox(width: AppSpacing.s1 + 2),
                              ],
                              Flexible(
                                child: Text(
                                  seg.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelLarge?.copyWith(
                                    color: seg.value == value
                                        ? cs.onSecondaryContainer
                                        : seg.enabled
                                        ? cs.onSurface
                                        : cs.onSurface.withValues(
                                            alpha: AppStateLayer.disabledContent,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _maybeExpand(bool fill, Widget child) =>
      fill ? Expanded(child: child) : child;
}

/// 过滤筹码：选中用 secondaryContainer 实底 + 对勾，未选中用描边。
class FilterChipBar extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<({String key, String label, int count})> items;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final it in items) ...[
          Builder(
            builder: (context) {
              final active = it.key == value;
              return Container(
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  color: active ? cs.secondaryContainer : null,
                  border: Border.all(
                    color: active ? Colors.transparent : cs.outlineVariant,
                  ),
                  boxShadow: active ? null : e.controlShadow,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onChanged(it.key),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    hoverColor: cs.onSurface.withValues(
                      alpha: AppStateLayer.hover,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (active) ...[
                            Icon(
                              Symbols.check,
                              size: 18,
                              color: cs.onSecondaryContainer,
                              weight: 400,
                            ),
                            const SizedBox(width: AppSpacing.s1 + 2),
                          ],
                          Text(
                            it.label,
                            style: context.texts.labelLarge?.copyWith(
                              color: active
                                  ? cs.onSecondaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s1 + 2),
                          Text(
                            '${it.count}',
                            style: kTimecodeStyle.copyWith(
                              fontSize: 12,
                              color: active
                                  ? cs.onSecondaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ],
    );
  }
}
