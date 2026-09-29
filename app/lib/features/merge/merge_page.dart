import 'package:flutter/material.dart';

import '../../pipeline/task_queue.dart';
import '../shared/new_task_page.dart';
import '../shared/page_chrome.dart';
import 'merge_form.dart';
import 'merge_param_panel.dart';
import 'merge_segment_list.dart';

/// 顶栏：标题与随段落变化的副标题。不放「上次参数」：合并的参数只有容器与
/// 三个开关，直接记住上次的值当默认。
PageChrome mergeChrome(MergeFormController form) =>
    PageChrome(title: '合并', subtitle: form.summary);

/// 导航栏里的「合并」页：几段视频无转码首尾相接，写章节、拼字幕。
///
/// 布局按设计稿 M-Merge，与转码页同构（见 [NewTaskPageState]）。建出的任务
/// 进同一个任务队列，一次只建一个。
class MergePage extends StatefulWidget {
  const MergePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenTasks,
  });

  final MergeFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenTasks;

  @override
  State<MergePage> createState() => MergePageState();
}

class MergePageState extends NewTaskPageState<MergePage> {
  @override
  MergeFormController get form => widget.form;

  @override
  void addDropped(List<String> paths) => form.addPaths(paths);

  @override
  int? enqueue() {
    final options = form.submit();
    if (options == null) return null;
    widget.queue.enqueueMerge(options);
    return 1;
  }

  @override
  Widget buildFilePanel(BuildContext context) => MergeSegmentsPanel(
    form: form,
    dragging: dragging,
    enqueued: enqueued,
    onOpenTasks: widget.onOpenTasks,
    onDismissBanner: dismissBanner,
  );

  @override
  Widget buildParamPanel(BuildContext context) =>
      MergeParamPanel(form: form, onStart: start);
}
