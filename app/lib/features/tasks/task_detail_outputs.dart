import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/paths.dart';
import '../../domain/task.dart';
import '../../services/media.dart';
import '../../services/reveal.dart';

class TaskOutputs extends StatelessWidget {
  const TaskOutputs({super.key, required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final done = task.status == TaskStatus.done;
    final hasSource = task.document.cues.isNotEmpty;
    final translatedCount =
        task.document.cues.length - task.document.untranslatedCount;

    final outputs = <TaskOutput>[
      TaskOutput(
        name: '原文 SRT',
        meta: hasSource ? '${task.document.cues.length} 条' : '尚未生成',
        ready: hasSource && done,
      ),
      TaskOutput(
        name: '译文 SRT',
        meta: !task.kind.needsTranslation
            ? '未选择翻译'
            : translatedCount == 0
            ? '尚未生成'
            : done
            ? '$translatedCount 条'
            : '生成中 · ${task.percentLabel}',
        ready: task.kind.needsTranslation && done && translatedCount > 0,
      ),
    ];

    return Column(
      children: [
        for (final output in outputs) ...[
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
            decoration: BoxDecoration(
              color: output.ready ? cs.surfaceContainerLowest : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Symbols.subtitles,
                  size: 18,
                  weight: 400,
                  color: output.ready ? cs.onSurface : cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.s2 + 2),
                Expanded(
                  child: Text(
                    output.name,
                    style: context.texts.bodyMedium?.copyWith(
                      color: output.ready
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  output.meta,
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
        ],
      ],
    );
  }
}

/// 转码任务的产物：一个视频文件。完成后可以在文件管理器里定位它。
class TaskTranscodeOutput extends StatelessWidget {
  const TaskTranscodeOutput({super.key, required this.task, this.onReveal});

  final SubtitleTask task;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final job = task.transcode!;
    final done = task.status == TaskStatus.done;
    final path = job.outputPath;
    final meta = done && job.outputBytes != null
        ? MediaFileInfo(path: path ?? '', sizeBytes: job.outputBytes!).sizeLabel
        : task.status == TaskStatus.running && task.stage == TaskStage.transcode
        ? '转码中 · ${task.percentLabel}'
        : '尚未生成';
    final fg = done ? cs.onSurface : cs.onSurfaceVariant;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: AppSpacing.s3, right: AppSpacing.s1),
      decoration: BoxDecoration(
        color: done ? cs.surfaceContainerLowest : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Symbols.movie, size: 18, weight: 400, color: fg),
          const SizedBox(width: AppSpacing.s2 + 2),
          Expanded(
            child: Text(
              path == null
                  ? '视频 · ${job.options.container.label}'
                  : baseName(path),
              overflow: TextOverflow.ellipsis,
              style: kTimecodeStyle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            meta,
            style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (done && onReveal != null)
            IconActionButton(
              icon: Symbols.folder_open,
              tooltip: Reveal.label,
              iconSize: 18,
              onPressed: onReveal,
            )
          else
            const SizedBox(width: AppSpacing.s2),
        ],
      ),
    );
  }
}
