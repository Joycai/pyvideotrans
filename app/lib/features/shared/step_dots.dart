import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';

/// 三步说明。是真实顺序，所以用了编号；当前步骤的点是 primary。
///
/// 用 Wrap 而不是 Row：转码页的侧栏窄，文案长了要能换行。
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.labels, required this.current});

  /// 三步说明的文案，各页自己给。
  final List<String> labels;

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s2,
      children: [
        for (final (i, label) in labels.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i + 1 == current ? cs.primary : cs.outlineVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Timecode(
                '${i + 1}',
                fontSize: 12,
                color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
