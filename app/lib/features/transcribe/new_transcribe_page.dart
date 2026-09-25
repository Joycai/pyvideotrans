import 'package:flutter/material.dart';

import '../../pipeline/task_queue.dart';
import '../shared/new_task_page.dart';
import '../shared/new_task_panels.dart';
import '../shared/page_chrome.dart';
import 'new_transcribe_file_panel.dart';
import 'new_transcribe_param_panel.dart';
import 'transcribe_form.dart';

/// 顶栏内容：标题、随文件变化的副标题、「上次参数」。
/// 放在这里而不是 main.dart，截图测试才能用同一份。
PageChrome newTranscribeChrome(TranscribeFormController form) {
  final n = form.enqueueable.length;
  return PageChrome(
    title: '新建转写',
    subtitle: form.files.isEmpty
        ? '从音视频生成字幕，可接着翻译'
        : '$n 个文件 · 总时长 ${_hms(form.totalDuration)} · '
              '将创建 $n 个${form.kindLabel}任务',
    actions: [
      LastUsedButton(
        available: form.hasLastUsed,
        onApply: form.applyLastUsed,
      ),
    ],
  );
}

/// 总时长固定写成 h:mm:ss —— 批量文件加起来经常过小时，位数稳定才好比较。
String _hms(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 导航栏里的「新建转写」页：常驻的工作台。
///
/// 与对话框共用 [TranscribeFormController]，不同的是它**不会关闭**；页面行为
/// 见 [NewTaskPageState]。布局按设计稿 NewTranscribePage。
class NewTranscribePage extends StatefulWidget {
  const NewTranscribePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenSettings,
    required this.onOpenTasks,
  });

  final TranscribeFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTasks;

  @override
  State<NewTranscribePage> createState() => NewTranscribePageState();
}

class NewTranscribePageState extends NewTaskPageState<NewTranscribePage> {
  @override
  TranscribeFormController get form => widget.form;

  @override
  void addDropped(List<String> paths) => form.handleDrop(paths);

  @override
  int? enqueue() {
    final result = form.submit();
    if (result == null) return null;
    widget.queue.enqueueAll(result.paths, options: result.options);
    form.clear();
    return result.paths.length;
  }

  /// 拖放拒收在页面上是中性说明（文件区里已经有一条行内提示），
  /// 不像对话框那样用 error 色。「新建翻译」在这里叫「翻译」—— 导航栏上就是这个名字。
  String? get _rejectNote => form.dropError?.replaceAll('「新建翻译」', '「翻译」');

  @override
  Widget buildFilePanel(BuildContext context) => NewTranscribeFilePanel(
    form: form,
    dragging: dragging,
    enqueued: enqueued,
    rejectNote: _rejectNote,
    onOpenTasks: widget.onOpenTasks,
    onDismissBanner: dismissBanner,
  );

  @override
  Widget buildParamPanel(BuildContext context) {
    final note = _rejectNote;
    return NewTranscribeParamPanel(
      form: form,
      footerOverride: note == null
          ? null
          : (text: note, tone: FooterTone.rejected),
      onOpenSettings: widget.onOpenSettings,
      onStart: start,
    );
  }
}
