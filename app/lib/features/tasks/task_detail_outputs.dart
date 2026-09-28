import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/media_job.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/ffmpeg.dart';
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

    // 列哪几份、叫什么，跟流水线实际写出的走同一条规则：纯翻译任务不另写
    // 原文，格式也未必是 SRT。
    final fields = OutputNaming.fields(task.kind, task.options);
    final ext = task.options.format.extension.toUpperCase();
    final translation = fields.where((f) => f != SrtField.source).firstOrNull;

    final outputs = <TaskOutput>[
      if (fields.contains(SrtField.source))
        TaskOutput(
          name: '原文 $ext',
          meta: hasSource ? '${task.document.cues.length} 条' : '尚未生成',
          ready: hasSource && done,
        ),
      TaskOutput(
        name: '${translation?.isBilingual == true ? '双语' : '译文'} $ext',
        meta: translation == null
            ? '未选择翻译'
            : translatedCount == 0
            ? '尚未生成'
            : done
            ? '$translatedCount 条'
            : '生成中 · ${task.percentLabel}',
        ready: translation != null && done && translatedCount > 0,
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

/// 媒体任务的产物：一个视频文件（合并开了旁挂时再加一份 SRT）。完成后可以
/// 在文件管理器里定位它。
class TaskMediaOutput extends StatelessWidget {
  const TaskMediaOutput({super.key, required this.task, this.onReveal});

  final SubtitleTask task;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final job = task.media!;
    final done = task.status == TaskStatus.done;
    final path = job.outputPath;
    final meta = done && job.outputBytes != null
        ? MediaFileInfo(path: path ?? '', sizeBytes: job.outputBytes!).sizeLabel
        : task.status == TaskStatus.running && task.stage == job.workStage
        ? '${job.workStage.label}中 · ${task.percentLabel}'
        : '尚未生成';
    final video = _MediaFileRow(
      icon: Symbols.movie,
      name: path == null ? job.outputLabel : baseName(path),
      meta: meta,
      done: done,
      onReveal: onReveal,
    );
    return switch (job) {
      TranscodeJob() => video,
      MergeJob(:final sidecarPath) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          video,
          if (sidecarPath != null) ...[
            const SizedBox(height: AppSpacing.s1 + 2),
            _MediaFileRow(
              icon: Symbols.subtitles,
              name: baseName(sidecarPath),
              meta: done ? 'SRT' : '尚未生成',
              done: done,
              onReveal: null,
            ),
          ],
          if (_subtitleFate(job) case final fate?) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              fate,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    };
  }

  /// 字幕去向的一句话。准备阶段读完字幕之前说不准，不写。
  static String? _subtitleFate(MergeJob job) {
    final counts = job.segmentCues;
    if (counts == null) return null;
    final n = counts.nonNulls.fold(0, (a, b) => a + b);
    final o = job.options;
    if (!o.embedSubtitles && !o.sidecarSubtitles) {
      return '内嵌与旁挂都没开，成片不带字幕';
    }
    if (n == 0) return '没有可用的字幕，成片不带字幕';
    return switch ((o.embedSubtitles, o.sidecarSubtitles)) {
      (true, true) => '字幕作为软字幕轨写进视频，并在旁边另存一份 SRT（$n 条）',
      (true, false) => '字幕作为软字幕轨写进视频（$n 条）；没开旁挂 SRT',
      _ => '字幕只写成旁挂 SRT（$n 条），不进视频',
    };
  }
}

class _MediaFileRow extends StatelessWidget {
  const _MediaFileRow({
    required this.icon,
    required this.name,
    required this.meta,
    required this.done,
    required this.onReveal,
  });

  final IconData icon;
  final String name;
  final String meta;
  final bool done;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
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
          Icon(icon, size: 18, weight: 400, color: fg),
          const SizedBox(width: AppSpacing.s2 + 2),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.timecode.copyWith(
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
