import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/indicators.dart';
import '../shared/enqueued_banner.dart';
import '../shared/step_dots.dart';
import 'new_translate_file_list.dart';
import 'translate_file_notes.dart';
import 'translate_form.dart';

class NewTranslateFilePanel extends StatelessWidget {
  const NewTranslateFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    this.enqueued,
    this.onSwitchToTranscribe,
    required this.onOpenTasks,
    required this.onDismissBanner,
  });

  final TranslateFormController form;
  final bool dragging;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  /// 拖错门的音视频：交给「新建转写」页。
  final VoidCallback? onSwitchToTranscribe;
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
                ? _EmptyArea(
                    form: form,
                    dragging: dragging,
                    enqueued: enqueued,
                    onSwitchToTranscribe: onSwitchToTranscribe,
                  )
                : NewTranslateFileList(
                    form: form,
                    dragging: dragging,
                    onSwitchToTranscribe: onSwitchToTranscribe,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 空态：虚线落区 + 三步说明。上方若有「已忽略音视频」的提示也在这里显示 ——
/// 用户只拖了音视频进来时列表是空的，但得知道文件去了哪儿。
class _EmptyArea extends StatelessWidget {
  const _EmptyArea({
    required this.form,
    required this.dragging,
    this.enqueued,
    this.onSwitchToTranscribe,
  });

  final TranslateFormController form;
  final bool dragging;
  final int? enqueued;
  final VoidCallback? onSwitchToTranscribe;

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
          TranslateFileNotes(form: form, onSwitchToTranscribe: onSwitchToTranscribe),
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
                      Symbols.subtitles,
                      size: 40,
                      weight: 400,
                      color: dragging ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Text(
                      dragging ? '松开以添加文件' : '把字幕文件拖到这里',
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      'SRT · VTT · ASS · SSA，可一次选多个；音视频请用「新建转写」',
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
            labels: const ['添加字幕文件', '确认语言与服务', '加入队列，进度在任务页'],
            current: enqueued != null ? 3 : 1,
          ),
        ],
      ),
    );
  }
}
