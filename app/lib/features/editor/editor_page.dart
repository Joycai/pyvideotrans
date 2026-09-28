import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/task_control.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_banners.dart';
import 'editor_controller.dart';
import 'editor_drop_zone.dart';
import 'editor_open_form.dart';
import 'editor_shortcuts.dart';
import 'editor_widgets.dart';
import 'inspector.dart';
import 'speaker_manager.dart';

/// 编辑器页：字幕表 + 检视面板。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.controller,
    this.onSave,
    this.onMountTranslation,
    this.onDropFiles,
    this.onDiscardDraft,
  });

  final EditorController controller;

  /// ⌘S 与恢复横幅「写入」：写字幕文件的流程（冲突询问、另存为）在上层。
  final Future<void> Function()? onSave;

  /// 只挂了原文时「挂载译文」：由上层带去入口页配对。
  final VoidCallback? onMountTranslation;

  /// 把字幕文件拖到正在编辑的页面上：先交给入口页确认，不立即写入。
  final void Function(String path, OpenSlot slot)? onDropFiles;

  /// 恢复横幅「丢弃，按文件重新打开」：文件在草稿之后被改过时，存下的
  /// 旧版本已经不是文件里的内容，只能由上层按文件重新打开会话。
  final Future<void> Function()? onDiscardDraft;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  /// 字幕列表的焦点：单键快捷键只在它有焦点时生效。
  final _tableFocus = FocusNode(debugLabel: 'CueTable');

  /// 编辑页自己的焦点作用域。输入框点外面会 unfocus，焦点落到最近的作用域
  /// 上：没有这一层就落到路由上，在编辑页的快捷键之外，⌘S、Esc 全都收不到。
  /// 焦点落到作用域本身时转给字幕列表。
  final _pageScope = FocusScopeNode(debugLabel: 'EditorPage');

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _listen(controller);
    _pageScope.addListener(_forwardToTable);
    // 进页面就让字幕列表拿焦点，J/K 不用先点一下列表才生效。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tableFocus.requestFocus(),
    );
  }

  @override
  void didUpdateWidget(EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unlisten(oldWidget.controller);
      _listen(widget.controller);
    }
  }

  @override
  void dispose() {
    _unlisten(controller);
    // 播放器随 controller 留着，页面收起时只暂停，回来还在原位置。
    unawaited(controller.media.pause());
    _pageScope
      ..removeListener(_forwardToTable)
      ..dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  // 播放器由 controller 的 media 持有，找到音视频时它通知，页面跟着换上。
  void _listen(EditorController c) => c
    ..addListener(_refresh)
    ..media.addListener(_refresh);

  void _unlisten(EditorController c) => c
    ..removeListener(_refresh)
    ..media.removeListener(_refresh);

  /// 「关联视频…」：手动挑一个音视频文件给这个会话预览。
  Future<void> attachMedia() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList()),
      ],
    );
    if (picked == null || !mounted) return;
    await controller.media.attach(picked.path);
  }

  void _forwardToTable() {
    if (_pageScope.hasPrimaryFocus) _tableFocus.requestFocus();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// provider 的报错本来就带 hint，直接原样展示给用户。
  String _describe(Object error) => error is ActionableException
      ? [error.message, if (error.hint != null) error.hint!].join(' · ')
      : '$error';

  Future<void> retranslate(int index) async {
    try {
      await controller.retranslate(index);
    } catch (e) {
      _report(_describe(e));
    }
  }

  Future<void> translateMissing() async {
    try {
      final n = await controller.translateMissing();
      _report(n == 0 ? '没有未翻译的条目' : '已翻译 $n 条');
    } catch (e) {
      _report(_describe(e));
    }
  }

  /// 「导出…」：挑一个目录另存一份。不改变字幕文件的同步状态 ——
  /// 想更新播放器读的那几份文件用「保存」。
  Future<void> export() async {
    final dir = await getDirectoryPath(
      initialDirectory: controller.session.exportDir,
      confirmButtonText: '导出到这里',
    );
    if (dir == null) return;
    try {
      final written = await controller.export({
        SrtField.source,
        if (controller.hasTranslations) SrtField.translation,
      }, dir: dir);
      _report(written.isEmpty ? '没有可导出的内容' : '已导出 ${written.length} 个文件到 $dir');
    } catch (e) {
      _report('导出失败：${_describe(e)}');
    }
  }

  Future<void> _save() async => widget.onSave?.call();

  void manageSpeakers() {
    if (!controller.locked) showSpeakerManager(context, controller);
  }

  @override
  Widget build(BuildContext context) {
    final table = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CueTable(
            controller: controller,
            focusNode: _tableFocus,
            onManageSpeakers: controller.locked ? null : manageSpeakers,
            onMountTranslation: widget.onMountTranslation,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        SizedBox(
          width: isCompactEditor(context) ? 380 : 440,
          child: Inspector(
            controller: controller,
            onRetranslate: retranslate,
            onManageSpeakers: controller.locked ? null : manageSpeakers,
            onMountTranslation: widget.onMountTranslation,
            playback: controller.media.playback,
            onAttachMedia: attachMedia,
          ),
        ),
      ],
    );
    final lockNote = editorLockNote(controller);
    final banner = lockNote != null
        ? EditorLockedBanner(title: lockNote)
        : controller.recoveredEdits == 0
        ? null
        : EditorRecoveryBanner(
            controller: controller,
            onWrite: _save,
            onDiscard: widget.onDiscardDraft,
          );
    final page = banner == null
        ? table
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s3,
            children: [banner, Expanded(child: table)],
          );

    final onDrop = widget.onDropFiles;
    return EditorPageShortcuts(
      controller: controller,
      tableFocus: _tableFocus,
      onSave: _save,
      child: FocusScope(
        node: _pageScope,
        child: onDrop == null
            ? page
            : EditorDropZone(
                hasTranslation: controller.hasTranslations,
                onDrop: onDrop,
                child: page,
              ),
      ),
    );
  }
}
