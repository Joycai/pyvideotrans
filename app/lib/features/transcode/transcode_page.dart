import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../pipeline/task_queue.dart';
import '../shell/page_chrome.dart';
import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'transcode_file_panel.dart';
import 'transcode_form.dart';
import 'transcode_param_panel.dart';

/// 顶栏：标题、随文件变化的副标题、「上次参数」。
PageChrome transcodeChrome(TranscodeFormController form) => PageChrome(
  title: '转码',
  subtitle: form.summary,
  actions: [
    ControlButton(
      label: '上次参数',
      icon: Symbols.history,
      onPressed: form.hasLastUsed ? form.applyLastUsed : null,
    ),
  ],
);

/// 导航栏里的「转码」页：FFmpeg 的图形外壳。
///
/// 布局按设计稿 M-TranscodePage，与翻译页同构：左列视频文件面板，右列参数面板
/// （400px，窄于 1100 时 360，窄于 960 时上下堆叠）。建出的任务进同一个任务队列。
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

class TranscodePageState extends State<TranscodePage> {
  bool _dragging = false;
  int? _enqueued;
  Timer? _bannerTimer;

  TranscodeFormController get _form => widget.form;

  @override
  void initState() {
    super.initState();
    _form.addListener(_refresh);
    // 打开页面就开始检测编码器：卡片上的状态在加文件之前就该是真的。
    _form.transcoder.ensureProbed();
  }

  @override
  void didUpdateWidget(TranscodePage oldWidget) {
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

  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    _form.handleDrop(paths);
  }

  /// 入队，列表清空，参数保留，不跳转 —— 与翻译页一致。
  void start() {
    final result = _form.submit();
    if (result == null) return;
    widget.queue.enqueueTranscode(result.paths, options: result.options);
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

  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): start,
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
                      child: TranscodeFilePanel(
                        form: _form,
                        dragging: _dragging,
                        enqueued: _enqueued,
                        onOpenTasks: widget.onOpenTasks,
                        onDismissBanner: _dismissBanner,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Expanded(
                      child: TranscodeParamPanel(form: _form, onStart: start),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TranscodeFilePanel(
                      form: _form,
                      dragging: _dragging,
                      enqueued: _enqueued,
                      onOpenTasks: widget.onOpenTasks,
                      onDismissBanner: _dismissBanner,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  SizedBox(
                    width: w < 1100 ? 360 : 400,
                    child: TranscodeParamPanel(form: _form, onStart: start),
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
