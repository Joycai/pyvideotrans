import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';

/// 询问对话框的外壳：玻璃底、标题、正文、灰底说明条、一行按钮。
///
/// 按钮行左边放一个纯文字的次要 / 破坏性操作（[leading]），右边是取消与
/// 主按钮（[actions]）—— 破坏性的操作离主按钮远一点，不容易误点。
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.title,
    required this.message,
    this.note,
    this.leading,
    required this.actions,
    this.width = 440,
  });

  final String title;
  final String message;
  final String? note;
  final Widget? leading;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.glass.glassStrong,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: context.glass.glassBorder),
            boxShadow: context.elevation.shadow3,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s3,
              children: [
                Text(title, style: context.texts.titleLarge),
                Text(message, style: context.texts.bodyMedium),
                if (note != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      note!,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s1),
                  child: Row(
                    children: [
                      ?leading,
                      const Spacer(),
                      for (final (i, action) in actions.indexed) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.s2),
                        action,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [GlassDialog] 左下角的纯文字操作。
class DialogTextAction extends StatelessWidget {
  const DialogTextAction({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.s2),
    hoverColor: color.withValues(alpha: AppStateLayer.hover),
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      alignment: Alignment.center,
      child: Text(
        label,
        style: context.texts.labelLarge?.copyWith(color: color),
      ),
    ),
  );
}
