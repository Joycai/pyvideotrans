import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/media_kinds.dart';
import '../../domain/task.dart';
import '../../pipeline/task_queue.dart';
import 'new_transcribe_dialog.dart';
import 'new_translate_dialog.dart';
import 'task_table.dart';
import 'tasks_board.dart';

/// 任务页：把队列接到 [TasksBoard] 上。展示逻辑都在 board 里。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.queue,
    required this.onOpenEditor,
    required this.onOpenSettings,
  });

  final TaskQueue queue;
  final ValueChanged<SubtitleTask> onOpenEditor;

  /// 对话框里发现服务没配好时，用它跳到设置页。
  final VoidCallback onOpenSettings;

  @override
  State<TasksPage> createState() => TasksPageState();
}

class TasksPageState extends State<TasksPage> {
  String _filter = 'all';
  String? _selectedId;

  static bool _matches(SubtitleTask task, String filter) => switch (filter) {
    'running' =>
      task.status == TaskStatus.running || task.status == TaskStatus.queued,
    'failed' =>
      task.status == TaskStatus.failed || task.status == TaskStatus.cancelled,
    'done' => task.status == TaskStatus.done,
    _ => true,
  };

  /// 拖进来的文件：音视频走「新建转写」，字幕走「新建翻译」。
  ///
  /// 不再用默认参数直接入队 —— 语言、服务、双语排版这些事值得在建任务前
  /// 确认一次，这正是两个对话框存在的理由。
  ///
  /// 两类混在一起时走文件多的那一边，整把原样转过去：另一类由对话框自己
  /// 列出并说明被忽略了。在这里就地丢掉的话，用户只会觉得文件没拖进去。
  Future<void> addFiles(List<String> paths) async {
    final subtitles = paths.where(MediaKinds.isSubtitle).length;
    final media = paths.where(MediaKinds.isMedia).length;
    if (subtitles == 0 && media == 0) return;
    if (subtitles >= media) {
      await newTranslate(paths: paths);
    } else {
      await newTranscribe(paths: paths);
    }
  }

  /// 顶栏的「新建转写」，也是拖入音视频后的落点。
  Future<void> newTranscribe({List<String> paths = const []}) async {
    final result = await showNewTranscribeDialog(
      context,
      settings: widget.queue.settings,
      initialPaths: paths,
      onOpenSettings: widget.onOpenSettings,
    );
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _selectFirst();
  }

  /// 顶栏的「新建翻译」，也是拖入字幕后的落点。
  Future<void> newTranslate({List<String> paths = const []}) async {
    final result = await showNewTranslateDialog(
      context,
      settings: widget.queue.settings,
      initialPaths: paths,
      onOpenSettings: widget.onOpenSettings,
      // 拖错了门的音视频，原样交给「新建转写」，不让用户再拖一次。
      onSwitchToTranscribe: (media) => newTranscribe(paths: media),
    );
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _selectFirst();
  }

  void _selectFirst() {
    if (!mounted || widget.queue.tasks.isEmpty) return;
    setState(() => _selectedId = widget.queue.tasks.first.id);
  }

  void _handleAction(SubtitleTask task, TaskAction action) {
    switch (action) {
      case TaskAction.cancel:
        widget.queue.cancel(task.id);
      case TaskAction.resume:
        widget.queue.resume(task.id);
      case TaskAction.prioritize:
        widget.queue.prioritize(task.id);
      case TaskAction.remove:
        widget.queue.remove(task.id);
        if (_selectedId == task.id) setState(() => _selectedId = null);
      case TaskAction.openEditor:
        widget.onOpenEditor(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.queue.tasks;
    return TasksBoard(
      tasks: all.where((t) => _matches(t, _filter)).toList(),
      filter: _filter,
      counts: {
        for (final key in ['all', 'running', 'failed', 'done'])
          key: all.where((t) => _matches(t, key)).length,
      },
      selectedId: _selectedId,
      onFilterChanged: (v) => setState(() => _filter = v),
      onSelect: (id) =>
          setState(() => _selectedId = _selectedId == id ? null : id),
      onAction: _handleAction,
      onFiles: addFiles,
      onBrowse: newTranscribe,
    );
  }
}

/// 顶栏右侧的两个操作。属于 PageChrome，所以放在页面外面。
class TasksPageActions extends StatelessWidget {
  const TasksPageActions({
    super.key,
    required this.onNewTranslate,
    required this.onNewTranscribe,
  });

  final VoidCallback onNewTranslate;
  final VoidCallback onNewTranscribe;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ControlButton(
        label: '新建翻译',
        icon: Icons.translate,
        onPressed: onNewTranslate,
      ),
      const SizedBox(width: AppSpacing.s3),
      PrimaryButton(
        label: '新建转写',
        icon: Icons.mic,
        onPressed: onNewTranscribe,
      ),
    ],
  );
}
