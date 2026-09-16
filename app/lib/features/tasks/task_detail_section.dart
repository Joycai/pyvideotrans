import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';

class TaskDetailSection extends StatelessWidget {
  const TaskDetailSection({
    super.key,
    required this.title,
    this.child,
    this.leading,
    this.trailing,
    this.onTapTitle,
  });

  final String title;
  final Widget? child;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTapTitle;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s4,
        AppSpacing.s5,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapTitle,
            behavior: HitTestBehavior.opaque,
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
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          ?child,
        ],
      ),
    );
  }
}
