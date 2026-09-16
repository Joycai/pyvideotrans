import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/registry.dart';

class TaskDetailHeader extends StatelessWidget {
  const TaskDetailHeader({super.key, required this.task, required this.onClose});

  final SubtitleTask task;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final asr = Registry.asrInfo(task.asrProviderId);
    final mt = Registry.translationInfo(task.translationProviderId);
    final runsLocally =
        (task.kind.needsRecognition ? asr : mt)?.runsLocally ?? false;
    final job = task.transcode;
    final length = task.mediaDuration != null
        ? Srt.formatDuration(task.mediaDuration!)
        : '${task.document.cues.length} 条';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s4,
        AppSpacing.s5,
        AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job != null
                          ? [
                              task.kind.label,
                              if (task.mediaDuration != null) length,
                              job.direction,
                            ].join(' · ')
                          : '${task.kind.label} · $length'
                                ' · ${task.sourceLanguage.name} → ${task.targetLanguage.name}',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconActionButton(
                icon: Symbols.close,
                tooltip: '收起详情',
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Wrap(
            spacing: AppSpacing.s1 + 2,
            runSpacing: AppSpacing.s1 + 2,
            children: [
              if (job != null)
                StatusTag(
                  label: switch (job.encoder) {
                    null => job.options.remux ? '仅重混流' : '复制视频流',
                    final e when e.backend.isHardware =>
                      '硬件编码 · ${e.backend.label}',
                    _ => 'CPU 编码',
                  },
                  icon: switch (job.encoder) {
                    null => Symbols.content_copy,
                    final e when e.backend.isHardware => Symbols.memory,
                    _ => Symbols.computer,
                  },
                  tone: TagTone.service,
                )
              else
                StatusTag(
                  label: runsLocally ? '本地' : '云端',
                  icon: runsLocally ? Symbols.computer : Symbols.cloud,
                  tone: TagTone.service,
                ),
              if (task.kind == TaskKind.transcribeAndTranslate)
                StatusTag(
                  label: '${mt?.name ?? ''} 翻译',
                  icon: Symbols.translate,
                  tone: TagTone.service,
                ),
              if (task.document.reviewCount > 0)
                StatusTag(
                  label: '待校对 ${task.document.reviewCount}',
                  icon: Symbols.flag,
                  tone: TagTone.review,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
