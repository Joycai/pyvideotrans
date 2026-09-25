import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/text_focus.dart';
import '../../pipeline/task_queue.dart';
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
/// 与「新建翻译」对话框共用 [TranslateFormController]，不同的是它**不会关闭**：
/// 跳去设置填密钥再回来，文件与参数还在；提交后列表清空、参数保留，方便一批
/// 接一批建。表单控制器由应用根节点持有并传进来，切换导航不会丢状态。
///
/// 布局按设计稿 M-TranslatePage：左列字幕文件面板（自适应），右列参数面板
/// （400px，窗口窄于 1100 时 360，窄于 960 时上下堆叠）。
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

class NewTranslatePageState extends State<NewTranslatePage> {
  bool _dragging = false;

  /// 提交后的横幅：入队了几个任务。6 秒后自动收起。
  int? _enqueued;
  Timer? _bannerTimer;

  TranslateFormController get _form => widget.form;

  @override
  void initState() {
    super.initState();
    _form.addListener(_refresh);
  }

  @override
  void didUpdateWidget(NewTranslatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.form != widget.form) {
      oldWidget.form.removeListener(_refresh);
      widget.form.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _form.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 拖放要真实的平台事件才能触发，留个入口给测试。
  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    _form.handleDrop(paths);
  }

  /// 立即入队，列表清空，参数保留。不跳转任务页 —— 批量建任务的人往往
  /// 一批接一批，跳走反而打断；横幅里的「查看任务」是主动去看进度的入口。
  void start() {
    final result = _form.submit();
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _form.clear();
    showEnqueuedBanner(result.paths.length);
  }

  @visibleForTesting
  void showEnqueuedBanner(int count) {
    _bannerTimer?.cancel();
    setState(() => _enqueued = count);
    _bannerTimer = Timer(const Duration(seconds: 6), _dismissBanner);
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    if (mounted) setState(() => _enqueued = null);
  }

  /// 只有真能把文件带走时才给这条出路（对话框版没有下一页可跳）。
  VoidCallback? get _switchToTranscribeOrNull =>
      widget.onSwitchToTranscribe == null ? null : _switchToTranscribe;

  void _switchToTranscribe() {
    final media = _form.takeIgnoredMedia();
    widget.onSwitchToTranscribe?.call(media);
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText => isEditingText(multiline: true);

  /// 拖放拒收在页面上是中性说明（文件区里已经有一条行内提示），
  /// 不像对话框那样用 error 色。
  ({String text, IconData icon, bool error})? get _footerOverride {
    final note = _form.dropError;
    if (note == null) return null;
    return (text: note, icon: Symbols.block, error: false);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): start,
        // Esc 只清除焦点，不清空页面 —— 这里没有「关闭」可言。
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            FocusManager.instance.primaryFocus?.unfocus(),
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) => handleDrop(d.files.map((f) => f.path).toList()),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w < 960) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: NewTranslateFilePanel(
                        form: _form,
                        dragging: _dragging,
                        enqueued: _enqueued,
                        onSwitchToTranscribe: _switchToTranscribeOrNull,
                        onOpenTasks: widget.onOpenTasks,
                        onDismissBanner: _dismissBanner,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Expanded(
                      child: NewTranslateParamPanel(
                        form: _form,
                        footerOverride: _footerOverride,
                        onOpenSettings: widget.onOpenSettings,
                        onStart: start,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: NewTranslateFilePanel(
                      form: _form,
                      dragging: _dragging,
                      enqueued: _enqueued,
                      onSwitchToTranscribe: _switchToTranscribeOrNull,
                      onOpenTasks: widget.onOpenTasks,
                      onDismissBanner: _dismissBanner,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  SizedBox(
                    width: w < 1100 ? 360 : 400,
                    child: NewTranslateParamPanel(
                      form: _form,
                      footerOverride: _footerOverride,
                      onOpenSettings: widget.onOpenSettings,
                      onStart: start,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
