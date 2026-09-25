import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/text_focus.dart';
import '../../domain/media_kinds.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_banners.dart';
import 'editor_controller.dart';
import 'editor_drop_zone.dart';
import 'editor_leave_dialog.dart';
import 'editor_open_form.dart';
import 'editor_widgets.dart';
import 'inspector.dart';
import 'preview_playback.dart';
import 'speaker_manager.dart';

/// 编辑器页：字幕表 + 检视面板。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.controller,
    this.onMountTranslation,
    this.onDropFiles,
    this.onDiscardDraft,
  });

  final EditorController controller;

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

  /// 检视面板的播放器；会话没有音视频时为 null。
  PreviewPlayback? _playback;

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    // 进页面就接管键盘，J/K 不用先点一下列表才生效。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _locateMedia();
  }

  @override
  void didUpdateWidget(EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      _closePlayback();
      _locateMedia();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _closePlayback();
    _focus.dispose();
    super.dispose();
  }

  void _closePlayback() {
    _playback?.dispose();
    _playback = null;
  }

  /// 找会话配套的音视频；找到就开播放器。异步的，找的期间先显示样式预览。
  /// 上次手动关联过的优先。
  Future<void> _locateMedia() async {
    final session = controller.session;
    final linked = await controller.store?.loadMediaLink(session.subtitlePath);
    final path = await session.locateMedia(linked: linked);
    if (!mounted || controller.session != session || path == null) return;
    _openPlayback(path);
  }

  void _openPlayback(String path) {
    _closePlayback();
    final playback = PreviewPlayback(controller: controller, mediaPath: path);
    _playback = playback;
    setState(() {});
    playback.open().catchError((Object e) {
      if (mounted && _playback == playback) {
        _report('打不开 ${baseName(path)}：$e');
      }
    });
  }

  /// 「关联视频…」：手动挑一个音视频文件给这个会话预览。
  Future<void> attachMedia() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList()),
      ],
    );
    if (picked == null || !mounted) return;
    final session = controller.session;
    session.mediaPath = picked.path;
    _openPlayback(picked.path);
    // 记下来，下次打开同一份字幕不用再选。写不进去也不影响这次预览。
    unawaited(
      controller.store
          ?.saveMediaLink(session.subtitlePath, picked.path)
          .catchError((Object _) {}),
    );
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
  String _describe(Object error) => error is ProviderException
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

  /// ⌘S / 「保存」：把修改写进字幕文件。写完的结果显示在状态栏与顶栏
  /// chip 上，不再弹 SnackBar 挡住表格。
  Future<void> save() async {
    if (!controller.canWrite) return;
    await writeSubtitleFiles(context, controller);
  }

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
      save();
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
      case LogicalKeyboardKey.space when _playback != null:
        _playback!.toggle();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft when _playback != null:
        _playback!.nudge(const Duration(seconds: -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight when _playback != null:
        _playback!.nudge(const Duration(seconds: 1));
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
            playback: _playback,
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
            onWrite: save,
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
