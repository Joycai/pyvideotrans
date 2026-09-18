import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/media_kinds.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_controller.dart';
import 'editor_leave_dialog.dart';
import 'editor_open_form.dart';
import 'editor_session.dart';
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

  /// 拖文件进来时悬停在哪一半；null 表示没在拖。
  OpenSlot? _dropSlot;

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
    controller.store
        ?.saveMediaLink(session.subtitlePath, picked.path)
        .catchError((Object _) {});
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
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != _focus && primary.context != null) {
      final isTextField = primary.context!.widget.runtimeType
          .toString()
          .contains('EditableText');
      if (isTextField) return KeyEventResult.ignored;
    }

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
        ? _LockedBanner(title: lockNote)
        : controller.recoveredEdits == 0
        ? null
        : _RecoveryBanner(
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
          : LayoutBuilder(
              builder: (context, constraints) {
                OpenSlot slotAt(Offset p) => p.dx < constraints.maxWidth / 2
                    ? OpenSlot.source
                    : OpenSlot.translation;
                return DropTarget(
                  onDragEntered: (d) =>
                      setState(() => _dropSlot = slotAt(d.localPosition)),
                  onDragUpdated: (d) {
                    final slot = slotAt(d.localPosition);
                    if (slot != _dropSlot) setState(() => _dropSlot = slot);
                  },
                  onDragExited: (_) => setState(() => _dropSlot = null),
                  onDragDone: (d) {
                    final slot = slotAt(d.localPosition);
                    setState(() => _dropSlot = null);
                    final path = d.files
                        .map((f) => f.path)
                        .where(EditorOpenForm.isOpenable)
                        .firstOrNull;
                    if (path != null) onDrop(path, slot);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      page,
                      if (_dropSlot != null)
                        _DropOverlay(
                          slot: _dropSlot!,
                          hasTranslation: controller.hasTranslations,
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 拖文件到编辑页上时的两块落区。
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.slot, required this.hasTranslation});

  final OpenSlot slot;
  final bool hasTranslation;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    Widget half(OpenSlot s, IconData icon, String title) {
      final hot = s == slot;
      return Expanded(
        child: AnimatedContainer(
          duration: AppDuration.medium,
          curve: kEasingStandard,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              cs.primary.withValues(alpha: hot ? 0.12 : 0.04),
              cs.surfaceContainerLowest,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hot ? cs.primary : cs.outlineVariant,
              width: hot ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: AppSpacing.s2,
            children: [
              Icon(
                icon,
                size: 40,
                weight: 400,
                color: hot ? cs.primary : cs.onSurfaceVariant,
              ),
              Text(title, style: context.texts.titleMedium),
              Text(
                '松开后先确认配对，不会立即写入',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          spacing: AppSpacing.s3,
          children: [
            half(OpenSlot.source, Symbols.subtitles, '替换原文'),
            half(
              OpenSlot.translation,
              Symbols.translate,
              hasTranslation ? '替换译文' : '挂载为译文',
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务排队或运行中打开编辑器时的横幅：说明为什么改不了、什么时候能改。
/// 与恢复横幅同形，用中性色 —— 这不是出了问题，只是还没轮到编辑。
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          spacing: AppSpacing.s3,
          children: [
            Icon(Symbols.lock, size: 20, weight: 400, color: cs.onSurfaceVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: context.texts.titleSmall),
                  Text(
                    '流水线会随时更新这份字幕，这时改动会和它互相覆盖。'
                    '跑完后自动解锁，字幕文件也会按最终结果写出。',
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑器只读时的说明；不只读时为 null。
String? editorLockNote(EditorController controller) {
  if (!controller.locked) return null;
  final session = controller.session;
  if (session is! TaskSession) return '编辑器暂时只读';
  final task = session.task;
  return task.status == TaskStatus.queued
      ? '任务在排队，编辑器暂时只读'
      : '任务正在${task.stage.label}，编辑器暂时只读';
}

/// 本地会话接着上次没写回文件的编辑进度打开时的横幅（画板 3）。
class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({
    required this.controller,
    required this.onWrite,
    this.onDiscard,
  });

  final EditorController controller;
  final Future<void> Function() onWrite;
  final Future<void> Function()? onDiscard;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = cs.onPrimaryContainer;
    final files = controller.session.targetPaths.map(baseName).join('、');
    final at = controller.recoveredAt;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          spacing: AppSpacing.s3,
          children: [
            Icon(Symbols.history, size: 20, weight: 400, color: fg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    '上次关闭时有 ${controller.recoveredEdits} 处修改没写回 $files，已接着显示',
                    style: context.texts.titleSmall?.copyWith(color: fg),
                  ),
                  if (at != null)
                    Text(
                      controller.recoveredOverChanged
                          ? '修改来自 ${friendlyTime(at)} 的编辑进度；文件在那之后被别的程序改过，写入前会先问你。'
                          : '修改来自 ${friendlyTime(at)} 的编辑进度；文件本身之后没有被改过。',
                      style: context.texts.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            if (controller.recoveredOverChanged && onDiscard != null)
              EditorTextAction(
                label: '丢弃，按文件重新打开',
                color: fg,
                onTap: onDiscard!,
              )
            else if (controller.canRevertToWritten)
              EditorTextAction(
                label: '丢弃，按文件重新打开',
                color: fg,
                onTap: () {
                  controller
                    ..revertToWritten()
                    ..dismissRecovery();
                },
              ),
            PrimaryButton(
              label: '写入文件',
              height: 30,
              onPressed: () async {
                await onWrite();
                if (controller.unsavedEdits == 0) controller.dismissRecovery();
              },
            ),
            IconActionButton(
              icon: Symbols.close,
              tooltip: '关闭提示',
              onPressed: controller.dismissRecovery,
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏副标题。
String editorSubtitle(EditorController controller) {
  final session = controller.session;
  final count = controller.document.cues.length;
  return switch (session) {
    FileSession(:final sourcePath) when !controller.hasTranslations =>
      '${baseName(sourcePath)} · $count 条 · ${session.sourceLanguage.name}',
    _ =>
      '${session.title} · $count 条 · '
          '${session.sourceLanguage.name} → ${session.targetLanguage.name}',
  };
}

/// 状态栏右侧：字幕文件落后多少、正在写、刚写了哪些（画板 1 的表）。
String? editorStatusNote(EditorController controller) =>
    controller.locked ? '任务跑完后会写出字幕文件' : switch (controller.sync) {
      SyncState.synced => null,
      SyncState.dirty => '字幕文件落后 ${controller.unsavedEdits} 处修改 · ⌘S 写入',
      SyncState.writing => '正在写入…',
      SyncState.written =>
        '已写入 ${controller.justWritten.map(baseName).join('、')}',
      SyncState.failed => '修改仍在编辑进度里，没有丢',
      SyncState.conflict => '保存前会先问怎么处理',
      SyncState.noOutput => '任务没有跑完，字幕文件还没生成 · ⌘S 生成',
    };
