import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/task.dart';
import '../../services/editor_store.dart';
import '../shell/page_chrome.dart';
import 'editor_open_form.dart';
import 'editor_open_panels.dart';

/// 入口页的顶栏。有会话开着时右侧给「返回编辑器」。
PageChrome editorOpenChrome({VoidCallback? onBack}) => PageChrome(
  title: '编辑器',
  subtitle: '打开一份字幕开始校对',
  actions: [
    if (onBack != null)
      ControlButton(
        label: '返回编辑器',
        icon: Symbols.arrow_back,
        onPressed: onBack,
      ),
  ],
);

/// 编辑器入口页（设计稿 M-EditorOpen）：左栏挂本地原文与译文并检查配对，
/// 右栏从已完成的任务里挑一个。
class EditorOpenPage extends StatefulWidget {
  const EditorOpenPage({
    super.key,
    required this.form,
    required this.tasks,
    required this.recents,
    required this.onOpenFiles,
    required this.onOpenTask,
    required this.onOpenRecent,
    required this.onOpenTasks,
  });

  final EditorOpenForm form;

  /// 已完成、带字幕的任务，新的在前。
  final List<SubtitleTask> tasks;
  final List<RecentSession> recents;
  final VoidCallback onOpenFiles;
  final ValueChanged<SubtitleTask> onOpenTask;
  final ValueChanged<RecentSession> onOpenRecent;
  final VoidCallback onOpenTasks;

  @override
  State<EditorOpenPage> createState() => _EditorOpenPageState();
}

class _EditorOpenPageState extends State<EditorOpenPage> {
  EditorOpenForm get form => widget.form;

  @override
  void initState() {
    super.initState();
    form.addListener(_refresh);
  }

  @override
  void didUpdateWidget(EditorOpenPage old) {
    super.didUpdateWidget(old);
    if (old.form != widget.form) {
      old.form.removeListener(_refresh);
      widget.form.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    form.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: EditorOpenLocalPanel(
              form: form,
              recents: widget.recents,
              onOpenFiles: widget.onOpenFiles,
              onOpenRecent: widget.onOpenRecent,
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: constraints.maxWidth < 1100 ? 360 : 400,
            child: EditorOpenTaskPanel(
              tasks: widget.tasks,
              onOpenTask: widget.onOpenTask,
              onOpenTasks: widget.onOpenTasks,
            ),
          ),
        ],
      ),
    );
  }
}
