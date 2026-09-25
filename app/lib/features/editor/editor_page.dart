import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/text_focus.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/task_control.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_banners.dart';
import 'editor_controller.dart';
import 'editor_drop_zone.dart';
import 'editor_open_form.dart';
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
  final _focus = FocusNode();

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _listen(controller);
    // 进页面就接管键盘，J/K 不用先点一下列表才生效。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
    _focus.dispose();
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    if (command && event.logicalKey == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }

    // 输入框获得焦点时不抢 J/K 与数字，否则打不了字。
    if (isEditingText()) return KeyEventResult.ignored;

    final digit = _digits[event.logicalKey];
    if (digit != null && !command) {
      final speakers = controller.speakers;
      if (digit > speakers.length) return KeyEventResult.ignored;
      controller.assignSpeaker(
        speakers[digit - 1].id,
        run: keyboard.isShiftPressed,
      );
      return KeyEventResult.handled;
    }

    final playback = controller.media.playback;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.arrowDown:
        controller.step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyK:
      case LogicalKeyboardKey.arrowUp:
        controller.step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        controller.toggleReviewed();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyZ when command:
        controller.undo();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space when playback != null:
        playback.toggle();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft when playback != null:
        playback.nudge(const Duration(seconds: -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight when playback != null:
        playback.nudge(const Duration(seconds: 1));
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static final _digits = {
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
  };

  @override
  Widget build(BuildContext context) {
    final table = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CueTable(
            controller: controller,
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
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: onDrop == null
          ? page
          : EditorDropZone(
              hasTranslation: controller.hasTranslations,
              onDrop: onDrop,
              child: page,
            ),
    );
  }
}
