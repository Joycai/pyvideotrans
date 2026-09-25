import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/task.dart';

class TaskLogView extends StatelessWidget {
  const TaskLogView({super.key, required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    if (task.log.isEmpty) {
      return Text(
        '暂无日志',
        style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in task.log)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Timecode(
                        entry.clock,
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: AppTextStyles.timecode.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: switch (entry.level) {
                            LogLevel.error => cs.error,
                            LogLevel.warn => cs.onTertiaryContainer,
                            LogLevel.info => cs.onSurfaceVariant,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
