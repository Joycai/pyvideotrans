import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/registry.dart';
import 'stage_bar.dart';

/// 列宽与设计稿一致：文件占剩余宽度，其余固定。
const _columns = <double?>[null, 80, 168, 128, 48, 84, 158];

class TaskTable extends StatelessWidget {
  const TaskTable({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.onAction,
  });

  final List<SubtitleTask> tasks;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final void Function(SubtitleTask, TaskAction) onAction;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          const _HeaderRow(),
          Expanded(
            child: tasks.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: tasks.length,
                    itemBuilder: (context, i) => _TaskRow(
                      task: tasks[i],
                      selected: tasks[i].id == selectedId,
                      onSelect: () => onSelect(tasks[i].id),
                      onAction: (a) => onAction(tasks[i], a),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

enum TaskAction { cancel, resume, resumeAuto, prioritize, remove, openEditor }

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 13, right: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: _Grid(
        children: [
          Text('文件', style: style),
          Text('类型', style: style),
          Text('服务 / 模型', style: style),
          Text('阶段', style: style),
          Align(
            alignment: Alignment.centerRight,
            child: Text('进度', style: style),
          ),
          Text('剩余', style: style),
          Text('操作', style: style),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final SubtitleTask task;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<TaskAction> onAction;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final task = widget.task;
    final failed = task.status == TaskStatus.failed;

    // 失败用红色左缘，即使没被选中也一眼能找到。
    final edge = failed
        ? cs.error
        : widget.selected
        ? cs.primary
        : Colors.transparent;

    final background = widget.selected
        ? cs.secondaryContainer
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.06)
        : Colors.transparent;

    final stageColor = switch (task.status) {
      TaskStatus.failed => cs.error,
      TaskStatus.done => task.document.reviewCount > 0
          ? cs.onTertiaryContainer
          : ext.success,
      TaskStatus.running => cs.onSurface,
      _ => cs.onSurfaceVariant,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(right: AppSpacing.s3),
          decoration: BoxDecoration(
            color: background,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant),
              left: BorderSide(color: edge, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _Grid(
              children: [
                _FileCell(task: task),
                Text(task.kind.label, style: context.texts.bodySmall),
                _ServiceCell(task: task),
                _StageCell(task: task, color: stageColor),
                Align(
                  alignment: Alignment.centerRight,
                  child: Timecode(
                    task.percentLabel,
                    color: switch (task.status) {
                      TaskStatus.failed => cs.error,
                      TaskStatus.running => cs.primary,
                      _ => cs.onSurfaceVariant,
                    },
                  ),
                ),
                Text(
                  _eta(task),
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                _ActionsCell(task: task, onAction: widget.onAction),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _eta(SubtitleTask task) => switch (task.status) {
    TaskStatus.running when task.eta != null =>
      '约 ${_humanize(task.eta!)}',
    TaskStatus.queued => '排队中',
    _ => '—',
  };

  static String _humanize(Duration d) => d.inMinutes >= 1
      ? '${d.inMinutes} 分钟'
      : '${d.inSeconds} 秒';
}

class _FileCell extends StatelessWidget {
  const _FileCell({required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final icon = MediaKinds.isSubtitle(task.sourcePath)
        ? Symbols.subtitles
        : MediaKinds.extensionOf(task.sourcePath) == 'mp3' ||
              MediaKinds.extensionOf(task.sourcePath) == 'm4a' ||
              MediaKinds.extensionOf(task.sourcePath) == 'wav'
        ? Symbols.audio_file
        : Symbols.movie;

    final length = task.mediaDuration != null
        ? Srt.formatDuration(task.mediaDuration!)
        : task.document.cues.isNotEmpty
        ? '${task.document.cues.length} 条'
        : '—';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, weight: 400, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.s1 + 2),
            Expanded(
              child: Text(
                task.fileName,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            children: [
              Timecode(length, fontSize: 12, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  '${task.sourceLanguage.name} → ${task.targetLanguage.name}',
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceCell extends StatelessWidget {
  const _ServiceCell({required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final asr = Registry.asrInfo(task.asrProviderId);
    final mt = Registry.translationInfo(task.translationProviderId);

    final primary = task.kind.needsRecognition ? asr : mt;
    final secondary = task.kind == TaskKind.transcribeAndTranslate
        ? '→ ${mt?.name ?? ''} 翻译'
        : task.kind == TaskKind.translate
        ? (mt?.defaultModel ?? '')
        : task.sourceLanguage.name;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              (primary?.runsLocally ?? false) ? Symbols.computer : Symbols.cloud,
              size: 14,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s1),
            Expanded(
              child: Text(
                primary?.name ?? '—',
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            secondary,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StageCell extends StatelessWidget {
  const _StageCell({required this.task, required this.color});

  final SubtitleTask task;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StageBar(task: task),
        const SizedBox(height: AppSpacing.s1 + 2),
        Text(
          task.stageLabel,
          overflow: TextOverflow.ellipsis,
          style: context.texts.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ActionsCell extends StatelessWidget {
  const _ActionsCell({required this.task, required this.onAction});

  final SubtitleTask task;
  final ValueChanged<TaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    // 失败/取消/暂停的第一操作是「从 X 阶段继续」—— 用文字按钮，因为这是
    // 用户此刻最需要知道的事：重试不会从头再来。暂停来自应用重启时恢复的
    // 未完成任务。
    if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled ||
        task.status == TaskStatus.paused) {
      return Row(
        children: [
          Flexible(
            child: ControlButton(
              label: '从${task.resumeStage.label}阶段继续',
              icon: Symbols.replay,
              dense: true,
              onPressed: () => onAction(TaskAction.resume),
            ),
          ),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '删除任务',
            onPressed: () => onAction(TaskAction.remove),
          ),
        ],
      );
    }

    if (task.status == TaskStatus.done) {
      return Row(
        children: [
          Flexible(
            child: ControlButton(
              label: '打开编辑器',
              icon: Symbols.edit_note,
              dense: true,
              onPressed: () => onAction(TaskAction.openEditor),
            ),
          ),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '删除任务',
            onPressed: () => onAction(TaskAction.remove),
          ),
        ],
      );
    }

    return Row(
      children: [
        if (task.status == TaskStatus.queued)
          IconActionButton(
            icon: Symbols.arrow_upward,
            tooltip: '优先执行',
            onPressed: () => onAction(TaskAction.prioritize),
          ),
        IconActionButton(
          icon: Symbols.close,
          tooltip: '取消',
          onPressed: () => onAction(TaskAction.cancel),
        ),
        IconActionButton(
          icon: Symbols.edit_note,
          tooltip: '打开编辑器',
          onPressed: task.document.cues.isEmpty
              ? null
              : () => onAction(TaskAction.openEditor),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.inbox,
            size: 32,
            weight: 400,
            color: cs.outline,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            '还没有任务',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            '把音视频或字幕文件拖进来开始',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 表头与数据行共用的栅格，保证列永远对齐。
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          if (_columns[i] == null)
            Expanded(child: child)
          else
            SizedBox(width: _columns[i], child: child),
        ],
      ],
    );
  }
}
