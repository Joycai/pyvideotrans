import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/indicators.dart';
import '../shared/enqueued_banner.dart';
import '../shared/step_dots.dart';
import 'new_transcribe_file_list.dart';
import 'transcribe_form.dart';

class NewTranscribeFilePanel extends StatelessWidget {
  const NewTranscribeFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    this.enqueued,
    this.rejectNote,
    required this.onOpenTasks,
    required this.onDismissBanner,
  });

  final TranscribeFormController form;
  final bool dragging;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  /// 拖放拒收的中性说明。
  final String? rejectNote;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final files = form.files;

    // 整个面板就是落点：拖入时描边转 primary、底色 primary 6%。
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
                : EnqueuedBanner(
                    count: enqueued!,
                    onOpenTasks: onOpenTasks,
                    onDismiss: onDismissBanner,
                  ),
          ),
          Expanded(
            child: files.isEmpty
                ? _EmptyArea(form: form, dragging: dragging, enqueued: enqueued)
                : NewTranscribeFileList(
                    form: form,
                    dragging: dragging,
                    rejectNote: rejectNote,
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyArea extends StatelessWidget {
  const _EmptyArea({required this.form, required this.dragging, this.enqueued});

  final TranscribeFormController form;
  final bool dragging;
  final int? enqueued;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
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
                      Symbols.upload_file,
                      size: 40,
                      weight: 400,
                      color: dragging ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Text(
                      dragging ? '松开以添加文件' : '把音视频文件拖到这里',
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      'mp4 · mov · mkv · mp3 · m4a · wav，可一次选多个',
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
            labels: const ['添加文件', '确认右侧参数', '加入队列，进度在任务页'],
            current: enqueued != null ? 3 : 1,
          ),
        ],
      ),
    );
  }
}
