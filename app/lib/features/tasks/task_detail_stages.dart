import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';

class TaskStageTimings extends StatelessWidget {
  const TaskStageTimings({super.key, required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    return Column(
      children: [
        for (final stage in task.kind.stages)
          Builder(
            builder: (context) {
              final record = task.stages[stage]!;
              final (icon, color) = switch (record.state) {
                StageState.done => (Symbols.check_circle, ext.success),
                StageState.active => (Symbols.pending, cs.primary),
                StageState.failed => (Symbols.error, cs.error),
                StageState.cancelled => (Symbols.cancel, cs.onSurfaceVariant),
                StageState.skipped => (Symbols.remove, cs.outline),
                StageState.pending => (
                  Symbols.radio_button_unchecked,
                  cs.outline,
                ),
              };
              final dimmed =
                  record.state == StageState.pending ||
                  record.state == StageState.skipped;
              final textColor = dimmed ? cs.onSurfaceVariant : cs.onSurface;

              return Container(
                height: 32,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Icon(icon, size: 16, weight: 400, color: color),
                    ),
                    const SizedBox(width: AppSpacing.s2 + 2),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            stage.label,
                            style: context.texts.bodyMedium?.copyWith(
                              color: textColor,
                            ),
                          ),
                          if (record.note != null) ...[
                            const SizedBox(width: AppSpacing.s2),
                            Expanded(
                              child: Text(
                                record.note!,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Timecode(
                      record.duration == null
                          ? '—'
                          : Srt.formatTimecode(
                              record.duration!.inMilliseconds,
                            ).substring(0, 8),
                      color: textColor,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
