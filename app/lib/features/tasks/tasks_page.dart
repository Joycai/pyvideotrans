import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/task.dart';
import '../../pipeline/task_queue.dart';
import '../../services/reveal.dart';
import '../shared/enqueue_request.dart';
import '../shared/page_chrome.dart';
import 'task_resume_dialog.dart';
import 'task_table.dart';
import 'tasks_board.dart';
import 'tasks_controller.dart';

/// 任务页：把队列与 [TasksController] 接到 [TasksBoard] 上。展示逻辑都在
/// board 里，筛选与选中在 controller 里；这里只剩要 BuildContext 的建任务对话框。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.queue,
    required this.controller,
    required this.onOpenEditor,
    required this.showNewTranscribe,
    required this.showNewTranslate,
  });

  final TaskQueue queue;

  /// 筛选与选中。挂在根节点上，页面重建不丢。
  final TasksController controller;
  final ValueChanged<SubtitleTask> onOpenEditor;

  /// 「新建转写」对话框。它属于 transcribe feature，由装配层注入，
  /// 任务页不直接 import；返回 null 表示用户取消。
  final Future<EnqueueRequest?> Function(
    BuildContext context,
    List<String> paths,
  )
  showNewTranscribe;

  /// 「新建翻译」对话框，同上。[onSwitchToTranscribe] 接住拖错门的音视频。
  final Future<EnqueueRequest?> Function(
    BuildContext context,
    List<String> paths,
    ValueChanged<List<String>> onSwitchToTranscribe,
  )
  showNewTranslate;

  @override
  State<TasksPage> createState() => TasksPageState();
}

class TasksPageState extends State<TasksPage> {
  TasksController get _tasks => widget.controller;

  /// 拖进来的文件按 [TasksController.routeDrop] 分给两个对话框。
  ///
  /// 不再用默认参数直接入队 —— 语言、服务、双语排版这些事值得在建任务前
  /// 确认一次，这正是两个对话框存在的理由。
  Future<void> addFiles(List<String> paths) async {
    switch (TasksController.routeDrop(paths)) {
      case DropRoute.translate:
        await newTranslate(paths: paths);
      case DropRoute.transcribe:
        await newTranscribe(paths: paths);
      case DropRoute.none:
        break;
    }
  }

  /// 顶栏的「新建转写」，也是拖入音视频后的落点。
  Future<void> newTranscribe({List<String> paths = const []}) async {
    final result = await widget.showNewTranscribe(context, paths);
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _tasks.selectNewest();
  }

  /// 顶栏的「新建翻译」，也是拖入字幕后的落点。
  Future<void> newTranslate({List<String> paths = const []}) async {
    final result = await widget.showNewTranslate(
      context,
      paths,
      // 拖错了门的音视频，原样交给「新建转写」，不让用户再拖一次。
      (media) => newTranscribe(paths: media),
    );
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _tasks.selectNewest();
  }

  /// 续跑前：会重建文档、而编辑器里改过的，先问一句。
  Future<void> _resume(SubtitleTask task, VoidCallback resume) async {
    switch (await confirmResume(context, task)) {
      case ResumeChoice.proceed:
        resume();
      case ResumeChoice.openEditor:
        widget.onOpenEditor(task);
      case ResumeChoice.cancel:
        break;
    }
  }

  void _handleAction(SubtitleTask task, TaskAction action) {
    switch (action) {
      case TaskAction.cancel:
        widget.queue.cancel(task.id);
      case TaskAction.resume:
        _resume(task, () => widget.queue.resume(task.id));
      case TaskAction.resumeAuto:
        _resume(task, () => widget.queue.resumeAuto(task.id));
      case TaskAction.prioritize:
        widget.queue.prioritize(task.id);
      case TaskAction.remove:
        widget.queue.remove(task.id);
        _tasks.forget(task.id);
      case TaskAction.openEditor:
        widget.onOpenEditor(task);
      case TaskAction.reveal:
        if (task.transcode?.outputPath case final path?) Reveal.show(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TasksBoard(
      tasks: _tasks.visible,
      filter: _tasks.filter,
      counts: _tasks.counts,
      selectedId: _tasks.selectedId,
      onFilterChanged: _tasks.setFilter,
      onSelect: _tasks.toggleSelect,
      onAction: _handleAction,
      onFiles: addFiles,
      onBrowse: newTranscribe,
    );
  }
}

/// 任务页交给顶栏的内容。两个「新建」按钮落在 [TasksPageState] 上，
/// 由装配层经 GlobalKey 转交。
PageChrome tasksChrome(
  TaskQueue queue, {
  required VoidCallback onNewTranslate,
  required VoidCallback onNewTranscribe,
}) {
  final running = queue.countWhere((t) => t.status == TaskStatus.running);
  final failed = queue.countWhere((t) => t.status == TaskStatus.failed);
  return PageChrome(
    title: '任务',
    subtitle: '${queue.tasks.length} 个任务 · $running 个进行中 · $failed 个失败',
    actions: [
      TasksPageActions(
        onNewTranslate: onNewTranslate,
        onNewTranscribe: onNewTranscribe,
      ),
    ],
  );
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
