import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import 'section_outline.dart';

/// 一个设置分区（设计稿 C-SettingsSection）：图标 + 标题 + 状态标签，
/// 下划 1px 分隔线；右侧是「已保存」反馈，2 秒后淡出。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.section,
    required this.children,
    this.note,
    this.tag,
    this.saved = false,
  });

  final SettingsSectionKey section;
  final List<Widget> children;

  /// 标题下一行的灰色说明。
  final String? note;

  /// 标题右侧的状态标签（已配置 / 未配置 / 第一期未实施）。
  final StatusTag? tag;

  /// 该分区刚写入成功。反馈只出现在改动的那个分区，不是全页。
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 20,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s2 + 2),
              Text(section.title, style: context.texts.titleMedium),
              if (tag != null) ...[
                const SizedBox(width: AppSpacing.s2 + 2),
                tag!,
              ],
              const Spacer(),
              SavedIndicator(visible: saved),
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2 + 2),
            child: Text(
              note!,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 2),
        ...children,
      ],
    );
  }
}

/// 「已保存」：success 色 + 对勾。常驻占位、只切透明度，标题行不会因它抖动。
class SavedIndicator extends StatelessWidget {
  const SavedIndicator({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final success = context.ext.success;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppDuration.long,
      curve: AppEasing.standard,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.check, size: 16, weight: 400, color: success),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '已保存',
            style: context.texts.labelMedium?.copyWith(color: success),
          ),
        ],
      ),
    );
  }
}

/// 表单行（设计稿 C-SettingsRow）：左 180px 标签列 + 右侧控件列，列距 24，
/// 上下各 10。窄窗口（stacked）时标签堆到控件上方。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.child,
    this.note,
    this.stacked = false,
    this.labelWidth = 180,
  });

  final String label;
  final String? note;
  final Widget child;
  final bool stacked;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.texts.titleSmall),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2 + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            labelColumn,
            const SizedBox(height: AppSpacing.s1 + 2),
            child,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2 + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              // 标签的基线对齐 36px 控件里的文字，而不是贴控件顶边。
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: labelColumn,
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 一段说明（服务不需要密钥、写入失败…）：小图标 + bodySmall。
class InlineNote extends StatelessWidget {
  const InlineNote({
    super.key,
    required this.text,
    this.icon = Symbols.info,
    this.color,
  });

  final String text;
  final IconData icon;

  /// 默认 onSurfaceVariant；出错时传 error。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, weight: 400, color: fg),
        ),
        const SizedBox(width: AppSpacing.s1),
        Flexible(
          child: Text(
            text,
            style: context.texts.bodySmall?.copyWith(color: fg),
          ),
        ),
      ],
    );
  }
}

/// 设置页用的分段按钮：surfaceContainerLow 容器 + 选中块浮起（白底 + 软阴影）。
///
/// 与编辑器里的 [SegmentedToggle] 是两种东西：那个是并列的实底段，
/// 这个是「一颗药丸在槽里滑」，设计稿给设置页定的就是这一款。
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<({T value, String label, IconData? icon})> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final seg in segments)
            _Pill(
              label: seg.label,
              icon: seg.icon,
              selected: seg.value == value,
              shadow: e.controlShadow,
              onTap: () => onChanged(seg.value),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.shadow,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final List<BoxShadow> shadow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    final radius = BorderRadius.circular(AppRadius.md - 2);
    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: AppEasing.standard,
      height: 30,
      decoration: BoxDecoration(
        color: selected ? cs.surfaceContainerLowest : Colors.transparent,
        borderRadius: radius,
        boxShadow: selected ? shadow : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, weight: 400, color: fg),
                  const SizedBox(width: AppSpacing.s1 + 2),
                ],
                Text(
                  label,
                  style: context.texts.labelLarge?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单行文本输入：36px 控件皮 + 无边框 TextField。
///
/// 值由外部持有；换服务时用 key 重建，控制器才会拿到新值。
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.mono = false,
    this.error = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  /// 等宽显示（模型名、地址这类要逐字符核对的值）。
  final bool mono;
  final bool error;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
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
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = widget.mono
        ? AppTextStyles.timecode.copyWith(color: cs.onSurface)
        : context.texts.bodyMedium;
    return ControlSurface(
      focused: _focus.hasFocus,
      error: widget.error,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: style,
        decoration: bareInputDecoration(context, hint: widget.hint),
        onChanged: widget.onChanged,
      ),
    );
  }
}
