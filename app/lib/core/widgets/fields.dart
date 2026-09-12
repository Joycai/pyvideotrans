import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';
import 'glass_panel.dart';

/// 表单一项：标签在上、控件在下。设计规范里标签是 labelMedium + onSurfaceVariant。
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.enabled = true,
  });

  final String label;
  final Widget child;

  /// 控件禁用时标签也要跟着变淡，否则看起来像还能点。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: enabled
                ? cs.onSurfaceVariant
                : cs.onSurface.withValues(alpha: AppStateLayer.disabledContent),
          ),
        ),
        const SizedBox(height: AppSpacing.s1 + 2),
        child,
      ],
    );
  }
}

/// 控件外观：36px 高、10px 圆角、白色微渐变 + 1px 描边 + 1px 软阴影。
/// 下拉、数字框、多行框共用这一身皮。
class ControlSurface extends StatelessWidget {
  const ControlSurface({
    super.key,
    required this.child,
    this.height = 36,
    this.width,
    this.padding = const EdgeInsets.only(left: 12, right: 8),
    this.enabled = true,
    this.error = false,
    this.focused = false,
    this.onTap,
    this.minHeight,
  });

  final Widget child;
  final double? height;
  final double? width;
  final double? minHeight;
  final EdgeInsetsGeometry padding;
  final bool enabled;
  final bool error;
  final bool focused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final borderColor = !enabled
        ? cs.onSurface.withValues(alpha: AppStateLayer.disabledContainer)
        : error
        ? cs.error
        : focused
        ? cs.primary
        : cs.outlineVariant;

    final box = Container(
      height: height,
      width: width,
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      padding: padding,
      alignment: height == null ? null : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: enabled ? cs.surfaceContainerLowest : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: borderColor,
          width: error || focused ? 2 : 1,
        ),
        boxShadow: enabled ? e.controlShadow : null,
      ),
      child: child,
    );

    if (onTap == null || !enabled) {
      return MouseRegion(
        cursor: enabled ? MouseCursor.defer : SystemMouseCursors.forbidden,
        child: box,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: box),
    );
  }
}

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
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.glass.glassStrong),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: AppSpacing.s1),
        ),
        maximumSize: const WidgetStatePropertyAll(Size.fromHeight(420)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg - 4),
            side: BorderSide(color: context.glass.glassBorder),
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

/// 数字输入。等宽 tnum，免得改数字时框里的内容左右跳。
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 999,
    this.width = 88,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final double width;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 失焦时才把越界的值夹回区间，否则用户删到空就被塞回一个数字，没法输入。
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      final parsed = int.tryParse(_controller.text) ?? widget.value;
      final clamped = parsed.clamp(widget.min, widget.max);
      _controller.text = '$clamped';
      widget.onChanged(clamped);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControlSurface(
    width: widget.width,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    focused: _focus.hasFocus,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: kTimecodeStyle.copyWith(color: context.colors.onSurface),
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
      ),
      onChanged: (raw) {
        final parsed = int.tryParse(raw);
        if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
          widget.onChanged(parsed);
        }
      },
    ),
  );
}

/// 多行输入。空的时候显示提示文字。
class MultilineField extends StatefulWidget {
  const MultilineField({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.minHeight = 68,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final double minHeight;

  @override
  State<MultilineField> createState() => _MultilineFieldState();
}

class _MultilineFieldState extends State<MultilineField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControlSurface(
    height: null,
    minHeight: widget.minHeight,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    focused: _focus.hasFocus,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      maxLines: null,
      minLines: 2,
      style: context.texts.bodyMedium,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: context.texts.bodyMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      onChanged: widget.onChanged,
    ),
  );
}

/// 开关。44×24 轨道，关时是 2px 描边 + 16px 灰球，开时是实心 primary + 20px 白球。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final knob = value ? 20.0 : 16.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: AppDuration.medium,
          curve: kEasingStandard,
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: value ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: value ? null : Border.all(color: cs.outline, width: 2),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: AppDuration.medium,
                curve: kEasingStandard,
                top: 2,
                left: value ? 22 : 2,
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(
                    color: value ? cs.onPrimary : cs.outline,
                    borderRadius: BorderRadius.circular(knob / 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一段带标题的表单区块：不透明白底 + 1px 描边 + 16px 圆角。
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    this.title,
    required this.children,
    this.gap = AppSpacing.s3,
  });

  final String? title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => ContentPanel(
    clip: false,
    padding: const EdgeInsets.all(AppSpacing.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: context.texts.titleSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: gap),
        ],
        for (final (i, child) in children.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          child,
        ],
      ],
    ),
  );
}
