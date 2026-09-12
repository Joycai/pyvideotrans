import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/task.dart';
import '../../pipeline/task_queue.dart';
import 'drop_zone.dart';
import 'task_table.dart';
import 'tasks_board.dart';

/// 任务页：把队列接到 [TasksBoard] 上。展示逻辑都在 board 里。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.queue,
    required this.onOpenEditor,
  });

  final TaskQueue queue;
  final ValueChanged<SubtitleTask> onOpenEditor;

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

  /// 拖进来的文件按扩展名决定任务类型：音视频建转写，字幕建翻译。
  void addFiles(List<String> paths) {
    for (final path in paths) {
      widget.queue.enqueue(
        sourcePath: path,
        kind: MediaKinds.isSubtitle(path)
            ? TaskKind.translate
            : TaskKind.transcribeAndTranslate,
      );
    }
    if (paths.isNotEmpty) {
      setState(() => _selectedId = widget.queue.tasks.first.id);
    }
  }

  /// 顶栏的「新建转写」。
  Future<void> browseMedia() => _browse(subtitlesOnly: false);

  /// 顶栏的「新建翻译」。
  Future<void> browseSubtitles() => _browse(subtitlesOnly: true);

  Future<void> _browse({bool subtitlesOnly = false}) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        subtitlesOnly
            ? const XTypeGroup(label: '字幕', extensions: ['srt', 'vtt', 'ass'])
            : const XTypeGroup(
                label: '音视频',
                extensions: [
                  'mp4', 'mov', 'mkv', 'avi', 'webm',
                  'mp3', 'm4a', 'wav', 'flac', 'aac',
                ],
              ),
      ],
    );
    if (files.isNotEmpty) addFiles(files.map((f) => f.path).toList());
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
      onBrowse: browseMedia,
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
