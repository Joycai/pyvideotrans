import 'package:flutter/material.dart';

import '../../pipeline/task_queue.dart';
import '../shared/new_task_page.dart';
import '../shared/new_task_panels.dart';
import '../shared/page_chrome.dart';
import 'transcode_file_panel.dart';
import 'transcode_form.dart';
import 'transcode_param_panel.dart';

/// 顶栏：标题、随文件变化的副标题、「上次参数」。
PageChrome transcodeChrome(TranscodeFormController form) => PageChrome(
  title: '转码',
  subtitle: form.summary,
  actions: [
    LastUsedButton(
      available: form.hasLastUsed,
      onApply: form.applyLastUsed,
    ),
  ],
);

/// 导航栏里的「转码」页：FFmpeg 的图形外壳。
///
/// 布局按设计稿 M-TranscodePage，与翻译页同构（见 [NewTaskPageState]）。
/// 建出的任务进同一个任务队列。
class TranscodePage extends StatefulWidget {
  const TranscodePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenTasks,
  });

  final TranscodeFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenTasks;

  @override
  State<TranscodePage> createState() => TranscodePageState();
}

class TranscodePageState extends NewTaskPageState<TranscodePage> {
  @override
  TranscodeFormController get form => widget.form;

  @override
  void initState() {
    super.initState();
    // 打开页面就开始检测编码器：卡片上的状态在加文件之前就该是真的。
    form.transcoder.ensureProbed();
  }

  @override
  void addDropped(List<String> paths) => form.handleDrop(paths);

  @override
  int? enqueue() {
    final result = form.submit();
    if (result == null) return null;
    widget.queue.enqueueTranscode(result.paths, options: result.options);
    form.clear();
    return result.paths.length;
  }

  @override
  Widget buildFilePanel(BuildContext context) => TranscodeFilePanel(
    form: form,
    dragging: dragging,
    enqueued: enqueued,
    onOpenTasks: widget.onOpenTasks,
    onDismissBanner: dismissBanner,
  );

  @override
  Widget buildParamPanel(BuildContext context) =>
      TranscodeParamPanel(form: form, onStart: start);
}
