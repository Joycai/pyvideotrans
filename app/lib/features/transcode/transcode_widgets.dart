import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';

/// 参数面板里的一段：16px 内边距，段与段之间 1px 分隔线。
class TranscodeSection extends StatelessWidget {
  const TranscodeSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.first = false,
    this.onTapTitle,
    this.leading,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool first;
  final VoidCallback? onTapTitle;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s4,
        first ? AppSpacing.s1 : AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onTapTitle,
            behavior: HitTestBehavior.opaque,
            child: MouseRegion(
              cursor: onTapTitle == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    if (leading != null) ...[
                      Icon(
                        leading,
                        size: 18,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s1),
                    ],
                    Text(
                      title,
                      style: context.texts.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    if (trailing != null) Expanded(child: trailing!),
                  ],
                ),
              ),
            ),
          ),
          for (final child in children) ...[
            const SizedBox(height: AppSpacing.s3),
            child,
          ],
        ],
      ),
    );
  }
}

class TranscodeHint extends StatelessWidget {
  const TranscodeHint(this.text, {super.key, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.texts.bodySmall?.copyWith(
      color: error ? context.colors.error : context.colors.onSurfaceVariant,
    ),
  );
}
