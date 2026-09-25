import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';

// 表单里的布局与轻量交互零件：整行可点、链接文字、单选行、两列、平铺段。
// 经 fields.dart 导出。

/// 整行可点：设计稿里开关和「高级」标题的热区都是一整行，不是那个小控件。
class Tappable extends StatelessWidget {
  const Tappable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}

/// 设计稿里「去设置」「改用新建转写」都是链接，不是按钮。
class LinkText extends StatelessWidget {
  const LinkText({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    ),
  );
}

/// 左右两列等宽。
Widget twoColumn(Widget left, Widget right, {double gap = AppSpacing.s4}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );

/// 页面参数面板里的平铺段：上方 1px 分隔线 + 16px 内边距。
/// 对话框里每段是一张卡片（FormSection），页面里三段平铺、用分隔线隔开。
Widget flatSection(
  BuildContext context, {
  required List<Widget> children,
  double gap = AppSpacing.s3,
  bool divider = true,
  EdgeInsets padding = const EdgeInsets.all(AppSpacing.s4),
}) => Container(
  padding: padding,
  decoration: divider
      ? BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.outlineVariant)),
        )
      : null,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) SizedBox(height: gap),
        child,
      ],
    ],
  ),
);

/// 竖排单选的一行：圆点 + 文字 + 可选的尾随内容（比如已选目录）。
class RadioRow extends StatelessWidget {
  const RadioRow({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Tappable(
      onTap: onTap,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? cs.primary : cs.outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Text(label, style: context.texts.bodyMedium),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s1),
              Flexible(child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}
