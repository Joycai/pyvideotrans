import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../shared/provider_fields.dart' show LinkText;
import 'transcode_file_list.dart';
import 'transcode_form.dart';
import 'transcode_widgets.dart';

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
      curve: kEasingStandard,
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
            curve: kEasingStandard,
            alignment: Alignment.topCenter,
            child: enqueued == null
                ? const SizedBox(width: double.infinity)
                : _Banner(
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.count,
    required this.onOpenTasks,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final fg = ext.onSuccessContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.s2),
      decoration: BoxDecoration(
        color: ext.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Symbols.check_circle, size: 20, weight: 400, color: ext.success),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('已加入队列 ', style: context.texts.bodyMedium?.copyWith(color: fg)),
          Timecode('$count', color: fg),
          Text(
            ' 个任务，按列表顺序排队',
            style: context.texts.bodyMedium?.copyWith(color: fg),
          ),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('·', style: TextStyle(color: fg.withValues(alpha: 0.5))),
          const SizedBox(width: AppSpacing.s2 + 2),
          LinkText(label: '查看任务', color: fg, onTap: onOpenTasks),
          const Spacer(),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '关闭',
            iconSize: 18,
            onPressed: onDismiss,
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
            painter: TranscodeDashedBorder(
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
        _Steps(current: enqueued != null ? 3 : 1),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    const labels = ['添加视频', '选择编码与编码器', '加入队列，进度在任务页'];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s2,
      children: [
        for (final (i, label) in labels.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i + 1 == current ? cs.primary : cs.outlineVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Timecode(
                '${i + 1}',
                fontSize: 12,
                color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
