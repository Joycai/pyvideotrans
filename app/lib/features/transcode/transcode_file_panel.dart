import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/indicators.dart';
import '../shared/enqueued_banner.dart';
import '../shared/step_dots.dart';
import 'transcode_file_list.dart';
import 'transcode_form.dart';

class TranscodeFilePanel extends StatelessWidget {
  const TranscodeFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    required this.onOpenTasks,
    required this.onDismissBanner,
    this.enqueued,
  });

  final TranscodeFormController form;
  final bool dragging;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final files = form.files;
    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: AppEasing.standard,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dragging
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: dragging ? cs.primary : cs.outlineVariant,
          width: dragging ? 2 : 1,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Row(
                children: [
                  Text('文件', style: context.texts.titleMedium),
                  const SizedBox(width: AppSpacing.s2),
                  Timecode('${files.length}', color: cs.onSurfaceVariant),
                  const Spacer(),
                  if (files.isNotEmpty) ...[
                    QuietButton(label: '清空', onPressed: form.clear),
                    const SizedBox(width: AppSpacing.s2),
                    ControlButton(
                      label: '添加文件…',
                      icon: Symbols.add,
                      onPressed: form.browse,
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDuration.medium,
            curve: AppEasing.standard,
            alignment: Alignment.topCenter,
            child: enqueued == null
                ? const SizedBox(width: double.infinity)
                : EnqueuedBanner(
                    count: enqueued!,
                    onOpenTasks: onOpenTasks,
                    onDismiss: onDismissBanner,
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (form.dropError != null) ...[
                    _DropNote(form: form),
                    const SizedBox(height: AppSpacing.s3),
                  ],
                  Expanded(
                    child: files.isEmpty
                        ? _EmptyArea(form: form, dragging: dragging, enqueued: enqueued)
                        : TranscodeFileList(form: form, dragging: dragging),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropNote extends StatelessWidget {
  const _DropNote({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Symbols.block, size: 18, weight: 400, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              form.dropError!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '关闭',
            size: 28,
            iconSize: 16,
            onPressed: form.clearDropError,
          ),
        ],
      ),
    );
  }
}

class _EmptyArea extends StatelessWidget {
  const _EmptyArea({
    required this.form,
    required this.dragging,
    required this.enqueued,
  });

  final TranscodeFormController form;
  final bool dragging;
  final int? enqueued;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: DashedBorder(
              color: dragging ? cs.primary : cs.outline,
              radius: AppRadius.md,
            ),
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.movie,
                    size: 40,
                    weight: 400,
                    color: dragging ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    dragging ? '松开以添加文件' : '把视频拖到这里',
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    'MP4 · MOV · MKV · AVI · WebM · FLV · WMV · TS，可一次选多个',
                    textAlign: TextAlign.center,
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  ControlButton(label: '选择文件…', onPressed: form.browse),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        StepDots(
          labels: const ['添加视频', '选择编码与编码器', '加入队列，进度在任务页'],
          current: enqueued != null ? 3 : 1,
        ),
      ],
    );
  }
}
