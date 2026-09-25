import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/text_focus.dart';

/// 三个建任务工作台页（新建转写 / 翻译 / 转码）共用的页面状态。
///
/// 这几页不会关闭：跳去设置填密钥再回来，文件与参数还在；提交后列表清空、
/// 参数保留，方便一批接一批建。表单控制器由应用根节点持有并传进来，切换导航
/// 不会丢状态。各页只需说明表单是谁、怎么入队、两栏各放什么；拖放、入队横幅、
/// 快捷键与两栏布局都在这里。
///
/// 布局按设计稿：左列文件面板（自适应），右列参数面板（400px，窗口窄于 1100
/// 时 360，窄于 960 时上下堆叠）。
abstract class NewTaskPageState<W extends StatefulWidget> extends State<W> {
  bool _dragging = false;

  /// 提交后的横幅：入队了几个任务。6 秒后自动收起。
  int? _enqueued;
  Timer? _bannerTimer;

  /// 页面的表单控制器；它一通知，两栏整页重建。
  @protected
  Listenable get form;

  /// 把拖进来的路径交给表单。
  @protected
  void addDropped(List<String> paths);

  /// 提交表单、入队并清空列表，返回入队的任务数；表单不让提交时返回 null。
  @protected
  int? enqueue();

  @protected
  Widget buildFilePanel(BuildContext context);

  @protected
  Widget buildParamPanel(BuildContext context);

  /// 有文件正悬在页面上方。
  @protected
  bool get dragging => _dragging;

  /// 刚入队的条数，非 null 时文件面板顶上显示横幅。
  @protected
  int? get enqueued => _enqueued;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// 拖放要真实的平台事件才能触发，留个入口给测试。
  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    addDropped(paths);
  }

  /// 立即入队，列表清空，参数保留。不跳转任务页 —— 批量建任务的人往往
  /// 一批接一批，跳走反而打断；横幅里的「查看任务」是主动去看进度的入口。
  void start() {
    final count = enqueue();
    if (count == null) return;
    showEnqueuedBanner(count);
  }

  @visibleForTesting
  void showEnqueuedBanner(int count) {
    _bannerTimer?.cancel();
    setState(() => _enqueued = count);
    _bannerTimer = Timer(const Duration(seconds: 6), dismissBanner);
  }

  @protected
  void dismissBanner() {
    _bannerTimer?.cancel();
    if (mounted) setState(() => _enqueued = null);
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText => isEditingText(multiline: true);

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
          child: ListenableBuilder(
            listenable: form,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final files = buildFilePanel(context);
                final params = buildParamPanel(context);
                if (w < 960) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: files),
                      const SizedBox(height: AppSpacing.s3),
                      Expanded(child: params),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: files),
                    const SizedBox(width: AppSpacing.s3),
                    SizedBox(width: w < 1100 ? 360 : 400, child: params),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
