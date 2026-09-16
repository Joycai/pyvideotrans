import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/task.dart';
import '../shared/command_block.dart';
import 'task_detail_error.dart';
import 'task_detail_header.dart';
import 'task_detail_log.dart';
import 'task_detail_outputs.dart';
import 'task_detail_section.dart';
import 'task_detail_stages.dart';

/// 右侧 400px 详情面板：标签、错误、各阶段耗时、产物、日志。
class TaskDetailPanel extends StatefulWidget {
  const TaskDetailPanel({
    super.key,
    required this.task,
    required this.onClose,
    required this.onResume,
    required this.onOpenEditor,
    this.onResumeAuto,
    this.onReveal,
  });

  final SubtitleTask task;
  final VoidCallback onClose;
  final VoidCallback onResume;
  final VoidCallback onOpenEditor;

  /// 在文件管理器里显示产物。只有转码任务用。
  final VoidCallback? onReveal;

  /// 「自动重试并跳过失败段」。只对识别阶段有意义，为 null 就不显示。
  final VoidCallback? onResumeAuto;

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  bool _logOpen = true;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return GlassPanel(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskDetailHeader(task: task, onClose: widget.onClose),
            if (task.error != null)
              TaskErrorBlock(
                task: task,
                onResume: widget.onResume,
                onResumeAuto: widget.onResumeAuto,
              ),
            TaskDetailSection(
              title: '各阶段耗时',
              child: TaskStageTimings(task: task),
            ),
            TaskDetailSection(
              title: '产物',
              child: task.transcode == null
                  ? TaskOutputs(task: task)
                  : TaskTranscodeOutput(task: task, onReveal: widget.onReveal),
            ),
            if (task.transcode?.command case final command?)
              TaskDetailSection(
                title: 'FFmpeg 命令',
                trailing: QuietButton(
                  label: '复制',
                  height: 24,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: command));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                ),
                child: CommandBlock(command: command, lowest: true),
              ),
            TaskDetailSection(
              title: '日志 ${task.log.length}',
              leading: _logOpen ? Symbols.expand_more : Symbols.chevron_right,
              onTapTitle: () => setState(() => _logOpen = !_logOpen),
              trailing: QuietButton(
                label: '复制全部',
                height: 24,
                onPressed: task.log.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(
                            text: task.log
                                .map((l) => '${l.clock} ${l.message}')
                                .join('\n'),
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('日志已复制')),
                        );
                      },
              ),
              child: _logOpen ? TaskLogView(task: task) : null,
            ),
          ],
        ),
      ),
    );
  }
}
