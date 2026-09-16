import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';
import 'form_fields.dart';

/// 下拉里的一项。
class DropdownEntry<T> {
  const DropdownEntry({
    required this.value,
    required this.label,
    this.description,
    this.badge,
    this.badgeIcon,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// 第二行小字。禁用项**必须**给出原因 —— 设计规范里写死的要求。
  final String? description;

  /// 名字右侧的小标签，例如本机跑的服务标「本机」。
  final String? badge;
  final IconData? badgeIcon;

  final bool enabled;
}

/// 下拉里的一组，带标题（「可用」「第二期未实施」）。
class DropdownGroup<T> {
  const DropdownGroup({this.title, required this.entries});

  final String? title;
  final List<DropdownEntry<T>> entries;
}

/// 分组下拉。菜单用玻璃浮层，选中项打勾，禁用项灰掉但保留说明文字。
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.groups,
    required this.onChanged,
    this.display,
    this.leading,
    this.enabled = true,
    this.error = false,
    this.menuWidth = 344,
    this.placeholder = '—',
  });

  final T value;
  final List<DropdownGroup<T>> groups;
  final ValueChanged<T> onChanged;

  /// 收起时显示的文字。默认取选中项的 label。
  final String? display;

  /// 收起时文字前面的小图标（设置页的服务下拉用它区分云端 / 本机）。
  final Widget? leading;

  final bool enabled;
  final bool error;
  final double menuWidth;
  final String placeholder;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _controller = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final label =
        widget.display ??
        widget.groups
            .expand((g) => g.entries)
            .where((e) => e.value == widget.value)
            .map((e) => e.label)
            .firstOrNull ??
        widget.placeholder;

    return MenuAnchor(
      controller: _controller,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      alignmentOffset: const Offset(0, 4),
      // 菜单必须不透明：它浮在对话框的文字上方，半透明会把下层文字透出来，
      // 分组标题与选项说明混成一片。层次感改由投影提供。
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerLowest),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(cs.shadow.withValues(alpha: 0.35)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: AppSpacing.s1),
        ),
        maximumSize: const WidgetStatePropertyAll(Size.fromHeight(420)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg - 4),
            side: BorderSide(color: cs.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        for (final group in widget.groups) ...[
          if (group.title != null)
            _GroupHeader(
              title: group.title!,
              divider: group != widget.groups.first,
            ),
          for (final entry in group.entries)
            _DropdownItem<T>(
              entry: entry,
              selected: entry.value == widget.value,
              width: widget.menuWidth,
              onTap: () {
                widget.onChanged(entry.value);
                _controller.close();
              },
            ),
        ],
      ],
      builder: (context, controller, _) => ControlSurface(
        enabled: widget.enabled,
        error: widget.error,
        onTap: widget.enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        child: Row(
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: AppSpacing.s2),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  color: widget.enabled
                      ? cs.onSurface
                      : cs.onSurface.withValues(
                          alpha: AppStateLayer.disabledContent,
                        ),
                ),
              ),
            ),
            Icon(
              _open ? Symbols.arrow_drop_up : Symbols.arrow_drop_down,
              size: 20,
              weight: 400,
              color: widget.enabled
                  ? cs.onSurfaceVariant
                  : cs.onSurface.withValues(
                      alpha: AppStateLayer.disabledContent,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.divider});

  final String title;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
            child: Container(height: 1, color: cs.outlineVariant),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            title,
            style: context.texts.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownItem<T> extends StatelessWidget {
  const _DropdownItem({
    required this.entry,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final DropdownEntry<T> entry;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return MenuItemButton(
      // 禁用项不可点，但文字与说明照常渲染 —— 用户得知道为什么不能选。
      onPressed: entry.enabled ? onTap : null,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        backgroundColor: WidgetStatePropertyAll(
          selected
              ? cs.onSurface.withValues(alpha: AppStateLayer.hover)
              : Colors.transparent,
        ),
      ),
      child: SizedBox(
        width: width - 24,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium?.copyWith(
                            color: entry.enabled
                                ? cs.onSurface
                                : cs.onSurface.withValues(
                                    alpha: AppStateLayer.disabledContent,
                                  ),
                          ),
                        ),
                      ),
                      if (entry.badge != null) ...[
                        const SizedBox(width: AppSpacing.s2),
                        _EntryBadge(
                          label: entry.badge!,
                          icon: entry.badgeIcon,
                          filled: entry.enabled,
                        ),
                      ],
                    ],
                  ),
                  if (entry.description != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      entry.description!,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Symbols.check, size: 18, weight: 400, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

/// 下拉项右侧的小标签。可用的用实底，未实施的用描边 —— 后者本来就是灰的，
/// 实底会让它看起来反而更显眼。
class _EntryBadge extends StatelessWidget {
  const _EntryBadge({
    required this.label,
    required this.icon,
    required this.filled,
  });

  final String label;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = filled ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? cs.secondaryContainer : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: filled ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, weight: 400, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
