import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/task.dart';
import '../../domain/task_filter.dart';
import 'drop_zone.dart';
import 'task_detail_panel.dart';
import 'task_table.dart';

/// 任务页的纯展示层：拖放区 + 过滤 + 表格 + 详情面板。
///
/// 不碰队列，只认传进来的列表 —— 这样截图与测试可以用固定数据渲染，
/// 不必真的跑一遍流水线。
class TasksBoard extends StatelessWidget {
  const TasksBoard({
    super.key,
    required this.tasks,
    required this.filter,
    required this.counts,
    required this.selectedId,
    required this.onFilterChanged,
    required this.onSelect,
    required this.onAction,
    required this.onFiles,
    required this.onBrowse,
  });

  final List<SubtitleTask> tasks;
  final TaskFilter filter;
  final Map<TaskFilter, int> counts;
  final String? selectedId;
  final ValueChanged<TaskFilter> onFilterChanged;
  final ValueChanged<String> onSelect;
  final void Function(SubtitleTask, TaskAction) onAction;
  final ValueChanged<List<String>> onFiles;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final selected = selectedId == null
        ? null
        : tasks.where((t) => t.id == selectedId).firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.s4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TaskDropZone(onFiles: onFiles, onBrowse: onBrowse),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    FilterChipBar(
                      value: filter.name,
                      onChanged: (name) =>
                          onFilterChanged(TaskFilter.values.byName(name)),
                      items: [
                        for (final f in TaskFilter.values)
                          (key: f.name, label: f.label, count: counts[f] ?? 0),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '失败的任务会保留已完成阶段的结果，重试从中断处继续',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Expanded(
                  child: TaskTable(
                    tasks: tasks,
                    selectedId: selectedId,
                    onSelect: onSelect,
                    onAction: onAction,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 未选中时面板宽度与间隙一起收掉，与设计稿的 0px 宽度一致。
        AnimatedSize(
          duration: AppDuration.medium,
          curve: AppEasing.emphasized,
          child: selected == null
              ? const SizedBox(height: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s3),
                  child: SizedBox(
                    width: 400,
                    child: TaskDetailPanel(
                      task: selected,
                      onClose: () => onSelect(selected.id),
                      onResume: () => onAction(selected, TaskAction.resume),
                      onResumeAuto: () =>
                          onAction(selected, TaskAction.resumeAuto),
                      onOpenEditor: () =>
                          onAction(selected, TaskAction.openEditor),
                      onReveal: () => onAction(selected, TaskAction.reveal),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
