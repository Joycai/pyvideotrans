import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/widgets/buttons.dart';
import '../../pipeline/task_queue.dart';
import '../shared/new_task_page.dart';
import '../shared/page_chrome.dart';
import 'new_translate_file_panel.dart';
import 'new_translate_param_panel.dart';
import 'translate_form.dart';

/// 顶栏内容：标题、随文件变化的副标题、「上次参数」。
/// 放在这里而不是 main.dart，截图测试才能用同一份。
PageChrome newTranslateChrome(TranslateFormController form) => PageChrome(
  title: '翻译',
  subtitle: form.summary,
  actions: [
    ControlButton(
      label: '上次参数',
      icon: Symbols.history,
      onPressed: form.hasLastUsed ? form.applyLastUsed : null,
    ),
  ],
);

/// 导航栏里的「翻译」页：常驻的工作台。
///
/// 与「新建翻译」对话框共用 [TranslateFormController]，不同的是它**不会关闭**；
/// 页面行为见 [NewTaskPageState]。布局按设计稿 M-TranslatePage。
class NewTranslatePage extends StatefulWidget {
  const NewTranslatePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenSettings,
    required this.onOpenTasks,
    this.onSwitchToTranscribe,
  });

  final TranslateFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTasks;

  /// 用户把音视频拖错了门：把这些文件交给「新建转写」页。
  final ValueChanged<List<String>>? onSwitchToTranscribe;

  @override
  State<NewTranslatePage> createState() => NewTranslatePageState();
}

class NewTranslatePageState extends NewTaskPageState<NewTranslatePage> {
  @override
  TranslateFormController get form => widget.form;

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

  /// 只有真能把文件带走时才给这条出路（对话框版没有下一页可跳）。
  VoidCallback? get _switchToTranscribeOrNull =>
      widget.onSwitchToTranscribe == null ? null : _switchToTranscribe;

  void _switchToTranscribe() {
    final media = form.takeIgnoredMedia();
    widget.onSwitchToTranscribe?.call(media);
  }

  @override
  Widget buildFilePanel(BuildContext context) => NewTranslateFilePanel(
    form: form,
    dragging: dragging,
    enqueued: enqueued,
    onSwitchToTranscribe: _switchToTranscribeOrNull,
    onOpenTasks: widget.onOpenTasks,
    onDismissBanner: dismissBanner,
  );

  /// 拖放拒收在页面上是中性说明（文件区里已经有一条行内提示），
  /// 不像对话框那样用 error 色。
  @override
  Widget buildParamPanel(BuildContext context) {
    final note = form.dropError;
    return NewTranslateParamPanel(
      form: form,
      footerOverride: note == null
          ? null
          : (text: note, icon: Symbols.block, error: false),
      onOpenSettings: widget.onOpenSettings,
      onStart: start,
    );
  }
}
