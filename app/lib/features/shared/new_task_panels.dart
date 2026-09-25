import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/indicators.dart';
import 'enqueued_banner.dart';
import 'step_dots.dart';

/// 页脚那行校验文案：图标 + 文字，阻断时 [error] 为真。
typedef FooterMessage = ({String text, IconData icon, bool error});

/// 建任务页左列的外框：标题行（文件数、清空、添加）、入队横幅、正文。
///
/// 整个面板就是落点：拖入时描边转 primary、底色 primary 6%。
/// 正文（空态或文件表）由各页给，外框统一留出左右下 16px。
class NewTaskFilePanel extends StatelessWidget {
  const NewTaskFilePanel({
    super.key,
    required this.count,
    required this.dragging,
    required this.onClear,
    required this.onBrowse,
    required this.onOpenTasks,
    required this.onDismissBanner,
    required this.child,
    this.enqueued,
    this.header,
  });

  /// 列表里的文件数，显示在标题旁；为 0 时不给「清空」「添加文件…」。
  final int count;
  final bool dragging;
  final VoidCallback onClear;
  final VoidCallback onBrowse;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  /// 正文上方的提示条（拖放拒收、忽略了音视频），自带与正文的间距。
  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
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
                  Timecode('$count', color: cs.onSurfaceVariant),
                  const Spacer(),
                  if (count > 0) ...[
                    QuietButton(label: '清空', onPressed: onClear),
                    const SizedBox(width: AppSpacing.s2),
                    ControlButton(
                      label: '添加文件…',
                      icon: Symbols.add,
                      onPressed: onBrowse,
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
              child: header == null
                  ? child
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header!,
                        Expanded(child: child),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件面板的空态：虚线落区（图标、标题、支持的格式、「选择文件…」）+ 三步说明。
class FileDropEmptyState extends StatelessWidget {
  const FileDropEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.formats,
    required this.steps,
    required this.dragging,
    required this.onBrowse,
    this.enqueued,
    this.formatsAlign,
  });

  final IconData icon;

  /// 没在拖放时的标题；拖放中统一换成「松开以添加文件」。
  final String title;

  /// 标题下那行格式说明。
  final String formats;

  /// 格式说明折行时的对齐。转码页侧栏窄、格式多，会折成两行，要居中。
  final TextAlign? formatsAlign;

  /// 三步说明的文案。
  final List<String> steps;
  final bool dragging;
  final VoidCallback onBrowse;

  /// 刚入过队时三步说明停在第三步。
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
                    icon,
                    size: 40,
                    weight: 400,
                    color: dragging ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    dragging ? '松开以添加文件' : title,
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    formats,
                    textAlign: formatsAlign,
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  ControlButton(label: '选择文件…', onPressed: onBrowse),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        StepDots(labels: steps, current: enqueued != null ? 3 : 1),
      ],
    );
  }
}

/// 建任务页右列的外框：标题行（「重置为默认」）、可滚动的参数段、页脚（校验文案 + 开始按钮）。
class NewTaskParamPanel extends StatelessWidget {
  const NewTaskParamPanel({
    super.key,
    required this.onReset,
    required this.sections,
    required this.footer,
    required this.action,
  });

  final VoidCallback onReset;
  final List<Widget> sections;
  final FooterMessage footer;

  /// 页脚右侧的开始按钮。
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.s4,
                right: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Text('参数', style: context.texts.titleMedium),
                  const Spacer(),
                  QuietButton(label: '重置为默认', onPressed: onReset),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(child: TaskFooterLine(footer)),
                const SizedBox(width: AppSpacing.s3),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 页脚那行校验文案：图标 + 文字，阻断用 error 色。建任务页与对话框共用。
class TaskFooterLine extends StatelessWidget {
  const TaskFooterLine(this.message, {super.key});

  final FooterMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final color = message.error ? cs.error : cs.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(message.icon, size: 16, weight: 400, color: color),
        const SizedBox(width: AppSpacing.s1 + 2),
        Expanded(
          child: Text(
            message.text,
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
