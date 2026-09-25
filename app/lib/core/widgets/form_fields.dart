import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// 放在 [ControlSurface] 里的 TextField 用的装饰：描边、底色都由外面的
/// 控件皮负责，这里必须把主题里的 enabledBorder / focusedBorder 一并关掉，
/// 只关 `border` 会留下第二圈描边。
InputDecoration bareInputDecoration(BuildContext context, {String? hint}) =>
    InputDecoration(
      isCollapsed: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      hintText: hint,
      hintStyle: context.texts.bodyMedium?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );

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
      decoration: bareInputDecoration(context),
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
      decoration: bareInputDecoration(context, hint: widget.hint),
      onChanged: widget.onChanged,
    ),
  );
}

/// 单行输入：36px 控件皮 + 无边框 TextField。
///
/// 值由外部持有。外部改了值（「重置为默认」「上次参数」、设置页恢复默认）且
/// 输入框没有焦点时同步进来；有焦点时不动 —— 这时的变化多半是自己输入的回声，
/// 覆盖回去会把光标甩到末尾。只认「外部值变了」，不认「外部值和框里不同」：
/// 调用方常把空串换成默认值或顺手 trim，失焦时不该把用户刚清空的框又填回去。
class SingleLineField extends StatefulWidget {
  const SingleLineField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.style,
    this.error = false,
    this.obscure = false,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  /// 缺省是 bodyMedium；地址、模型名这类要逐字符核对的值传等宽样式。
  final TextStyle? style;
  final bool error;

  /// 掩码显示（密钥）。
  final bool obscure;

  /// 框内右侧的附加控件（如密钥的显示/隐藏）。
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  State<SingleLineField> createState() => _SingleLineFieldState();
}

class _SingleLineFieldState extends State<SingleLineField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(SingleLineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      obscureText: widget.obscure,
      obscuringCharacter: '•',
      style: widget.style ?? context.texts.bodyMedium,
      decoration: bareInputDecoration(context, hint: widget.hint),
      onChanged: widget.onChanged,
    );
    return ControlSurface(
      focused: _focus.hasFocus,
      error: widget.error,
      padding: widget.padding,
      child: widget.trailing == null
          ? field
          : Row(
              children: [
                Expanded(child: field),
                widget.trailing!,
              ],
            ),
    );
  }
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
