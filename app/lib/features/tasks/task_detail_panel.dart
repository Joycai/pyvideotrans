import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/registry.dart';

/// 右侧 400px 详情面板：标签、错误、各阶段耗时、产物、日志。
class TaskDetailPanel extends StatefulWidget {
  const TaskDetailPanel({
    super.key,
    required this.task,
    required this.onClose,
    required this.onResume,
    required this.onOpenEditor,
  });

  final SubtitleTask task;
  final VoidCallback onClose;
  final VoidCallback onResume;
  final VoidCallback onOpenEditor;

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  bool _logOpen = true;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return GlassPanel(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(task: task, onClose: widget.onClose),
            if (task.error != null)
              _ErrorBlock(
                task: task,
                onResume: widget.onResume,
              ),
            _Section(
              title: '各阶段耗时',
              child: _StageTimings(task: task),
            ),
            _Section(title: '产物', child: _Outputs(task: task)),
            _Section(
              title: '日志 ${task.log.length}',
              leading: _logOpen ? Symbols.expand_more : Symbols.chevron_right,
              onTapTitle: () => setState(() => _logOpen = !_logOpen),
              trailing: QuietButton(
                label: '复制全部',
                height: 24,
                onPressed: task.log.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(
                            text: task.log
                                .map((l) => '${l.clock} ${l.message}')
                                .join('\n'),
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('日志已复制')),
                        );
                      },
              ),
              child: _logOpen ? _LogView(task: task) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.task, required this.onClose});

  final SubtitleTask task;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final asr = Registry.asrInfo(task.asrProviderId);
    final mt = Registry.translationInfo(task.translationProviderId);
    final runsLocally =
        (task.kind.needsRecognition ? asr : mt)?.runsLocally ?? false;

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
                      '${task.kind.label} · '
                      '${task.mediaDuration != null ? Srt.formatDuration(task.mediaDuration!) : '${task.document.cues.length} 条'}'
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

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.task, required this.onResume});

  final SubtitleTask task;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final error = task.error!;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s4,
        AppSpacing.s5,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Symbols.error,
                size: 18,
                weight: 400,
                color: cs.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.s1 + 2),
              Expanded(
                child: Text(
                  error.title,
                  style: context.texts.titleSmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          SelectableText(
            error.detail,
            style: kTimecodeStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: cs.onErrorContainer.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            '建议：${error.hint}',
            style: context.texts.bodyMedium?.copyWith(
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          // 主操作就是续跑 —— 用户最担心的是「重试是不是要从头再来」。
          Align(
            alignment: Alignment.centerLeft,
            child: _ErrorButton(
              label: '从${task.resumeStage.label}阶段继续',
              icon: Symbols.replay,
              onPressed: onResume,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorButton extends StatelessWidget {
  const _ErrorButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Material(
      color: cs.onErrorContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, weight: 400, color: cs.errorContainer),
              const SizedBox(width: AppSpacing.s1),
              Text(
                label,
                style: context.texts.labelMedium?.copyWith(
                  color: cs.errorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageTimings extends StatelessWidget {
  const _StageTimings({required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    return Column(
      children: [
        for (final stage in TaskStage.values)
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

class _Outputs extends StatelessWidget {
  const _Outputs({required this.task});

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

class _LogView extends StatelessWidget {
  const _LogView({required this.task});

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
                        style: kTimecodeStyle.copyWith(
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

class _Section extends StatelessWidget {
  const _Section({
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
