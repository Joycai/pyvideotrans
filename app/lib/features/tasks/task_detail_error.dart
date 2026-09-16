import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../domain/task.dart';

class TaskErrorBlock extends StatelessWidget {
  const TaskErrorBlock({
    super.key,
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
