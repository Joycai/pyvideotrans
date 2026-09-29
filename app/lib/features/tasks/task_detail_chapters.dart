import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../domain/media_job.dart';
import '../../domain/mux/merge_rules.dart';
import '../../domain/srt.dart';

/// 合并任务详情里的「章节」分区：每段一行，起点 · 章节标题 · 字幕条数。
///
/// 关掉章节时分区叫「分段」，内容不变 —— 起点仍有意义，字幕按它平移。
/// 起点来自准备阶段探测的各段时长，准备之前写「—」。
class TaskMergeChapters extends StatelessWidget {
  const TaskMergeChapters({super.key, required this.job});

  final MergeJob job;

  static String titleOf(MergeJob job) => job.options.chapters ? '章节' : '分段';

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final segments = job.options.segments;
    final durations = job.segmentDurations;
    final starts = durations == null ? null : offsets(durations);
    final cues = job.segmentCues;
    final usesSubtitles =
        job.options.embedSubtitles || job.options.sidecarSubtitles;
    final mono = AppTextStyles.timecode.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in segments.indexed)
          SizedBox(
            height: 28,
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    starts == null
                        ? '—'
                        : Srt.formatTimecode(starts[i].inMilliseconds)
                              .split(',')
                              .first,
                    style: mono,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    s.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  switch (cues?[i]) {
                    final n? => '字幕 $n 条',
                    // 准备阶段读完字幕之前只知道挂没挂；两个字幕开关都关时字幕
                    // 用不上，流水线也不读，直接算没有。
                    null
                        when s.subtitlePath != null &&
                            cues == null &&
                            usesSubtitles =>
                      '有字幕',
                    null => '无字幕',
                  },
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
