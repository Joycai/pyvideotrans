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
import '../../services/media.dart';
import '../../services/registry.dart';
import '../../services/reveal.dart';

/// 右侧 400px 详情面板：标签、错误、各阶段耗时、产物、日志。
class TaskDetailPanel extends StatefulWidget {
  const TaskDetailPanel({
    super.key,
    required this.task,
    required this.onClose,
    required this.onResume,
    required this.onOpenEditor,
    this.onResumeAuto,
    this.onReveal,
  });

  final SubtitleTask task;
  final VoidCallback onClose;
  final VoidCallback onResume;
  final VoidCallback onOpenEditor;

  /// 在文件管理器里显示产物。只有转码任务用。
  final VoidCallback? onReveal;

  /// 「自动重试并跳过失败段」。只对识别阶段有意义，为 null 就不显示。
  final VoidCallback? onResumeAuto;

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
                onResumeAuto: widget.onResumeAuto,
              ),
            _Section(
              title: '各阶段耗时',
              child: _StageTimings(task: task),
            ),
            _Section(
              title: '产物',
              child: task.transcode == null
                  ? _Outputs(task: task)
                  : _TranscodeOutput(task: task, onReveal: widget.onReveal),
            ),
            if (task.transcode?.command case final command?)
              _Section(
                title: 'FFmpeg 命令',
                trailing: QuietButton(
                  label: '复制',
                  height: 24,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: command));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                ),
                child: CommandBlock(command: command),
              ),
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

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.task,
    required this.onResume,
    this.onResumeAuto,
  });

  final SubtitleTask task;
  final VoidCallback onResume;
  final VoidCallback? onResumeAuto;

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
          // 识别阶段多一个「自动重试」：失败的段自动重试、到上限跳过，
          // 限流时等待恢复，不用人盯着一次次点。
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: [
              _ErrorButton(
                label: '从${task.resumeStage.label}阶段继续',
                icon: Symbols.replay,
                onPressed: onResume,
              ),
              if (onResumeAuto != null &&
                  task.resumeStage == TaskStage.recognize)
                _ErrorButton(
                  label: '自动重试并跳过失败段',
                  icon: Symbols.autorenew,
                  onPressed: onResumeAuto!,
                ),
            ],
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

/// 转码任务的产物：一个视频文件。完成后可以在文件管理器里定位它。
class _TranscodeOutput extends StatelessWidget {
  const _TranscodeOutput({required this.task, this.onReveal});

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
                  : path.split(RegExp(r'[/\\]')).last,
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

/// 等宽的命令块。可选中复制，自动换行。
class CommandBlock extends StatelessWidget {
  const CommandBlock({super.key, required this.command, this.maxHeight = 140});

  final String command;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          command,
          style: kTimecodeStyle.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: cs.onSurface,
          ),
        ),
      ),
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
