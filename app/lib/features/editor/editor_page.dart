import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/srt.dart';
import '../../domain/subtitle_pairing.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_controller.dart';
import 'editor_open_form.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';
import 'inspector.dart';
import 'speaker_manager.dart';

/// 编辑器页：字幕表 + 检视面板。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.controller,
    this.onMountTranslation,
    this.onDropFiles,
  });

  final EditorController controller;

  /// 只挂了原文时「挂载译文」：由上层带去入口页配对。
  final VoidCallback? onMountTranslation;

  /// 把字幕文件拖到正在编辑的页面上：先交给入口页确认，不立即写入。
  final void Function(String path, OpenSlot slot)? onDropFiles;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  final _focus = FocusNode();

  /// 拖文件进来时悬停在哪一半；null 表示没在拖。
  OpenSlot? _dropSlot;

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    // 进页面就接管键盘，J/K 不用先点一下列表才生效。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> export() async {
    try {
      final written = await controller.export({
        SrtField.source,
        if (controller.hasTranslations) SrtField.translation,
      });
      _report(
        written.isEmpty ? '没有可导出的内容' : '已导出 ${written.length} 个文件到源文件目录',
      );
    } catch (e) {
      _report('导出失败：${_describe(e)}');
    }
  }

  Future<void> save() async {
    if (controller.session is! FileSession || controller.unsavedEdits == 0) {
      return;
    }
    try {
      final written = await controller.save();
      _report('已保存 ${written.map(baseName).join('、')}');
    } catch (e) {
      _report('保存失败：${_describe(e)}');
    }
  }

  void manageSpeakers() => showSpeakerManager(context, controller);

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
    final page = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CueTable(
            controller: controller,
            onManageSpeakers: manageSpeakers,
            onMountTranslation: widget.onMountTranslation,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        SizedBox(
          width: isCompactEditor(context) ? 380 : 440,
          child: Inspector(
            controller: controller,
            onRetranslate: retranslate,
            onManageSpeakers: manageSpeakers,
            onMountTranslation: widget.onMountTranslation,
          ),
        ),
      ],
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
              Icon(icon, size: 40, weight: 400, color: hot ? cs.primary : cs.onSurfaceVariant),
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

/// 顶栏右侧：视图切换 + 翻译未译 + 保存（本地会话）+ 导出。
class EditorPageActions extends StatelessWidget {
  const EditorPageActions({
    super.key,
    required this.controller,
    required this.onTranslateMissing,
    required this.onExport,
    this.onSave,
  });

  final EditorController controller;
  final VoidCallback onTranslateMissing;
  final VoidCallback onExport;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final missing = controller.missingTranslationCount;
    final dirty = controller.unsavedEdits > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCompactEditor(context))
          _ViewMenu(controller: controller)
        else
          SegmentedToggle<CueView>(
            value: controller.view,
            onChanged: controller.setView,
            segments: [
              for (final v in CueView.values)
                (value: v, label: _viewLabels[v]!, enabled: true),
            ],
          ),
        const SizedBox(width: AppSpacing.s3),
        ControlButton(
          label: missing == 0 ? '全部已翻译' : '翻译未译 $missing 条',
          icon: Symbols.translate,
          onPressed: missing == 0 ? null : onTranslateMissing,
        ),
        if (controller.session is FileSession) ...[
          const SizedBox(width: AppSpacing.s3),
          // 没有修改时禁用而不是隐藏，位置不跳。
          _SaveButton(dirty: dirty, dot: cs.primary, onPressed: dirty ? onSave : null),
        ],
        const SizedBox(width: AppSpacing.s3),
        PrimaryButton(
          label: '导出',
          icon: Symbols.download,
          onPressed: controller.document.cues.isEmpty ? null : onExport,
        ),
      ],
    );
  }
}

const _viewLabels = {
  CueView.source: '原文',
  CueView.translation: '译文',
  CueView.both: '双语',
};

/// 窄窗口下代替分段控件的「视图」下拉。
class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return AnchoredPopover(
      width: 160,
      anchor: (context, toggle, open) => ControlButton(
        label: '视图 · ${_viewLabels[controller.view]}',
        icon: open ? Symbols.expand_less : Symbols.expand_more,
        onPressed: toggle,
      ),
      popover: (context, close) => GlassMenu(
        children: [
          for (final v in CueView.values)
            MenuRow(
              label: _viewLabels[v]!,
              trailing: v == controller.view
                  ? Icon(Symbols.check, size: 18, weight: 500, color: cs.primary)
                  : null,
              onTap: () {
                controller.setView(v);
                close();
              },
            ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.dirty, required this.dot, this.onPressed});

  final bool dirty;
  final Color dot;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final enabled = onPressed != null;
    return Tooltip(
      message: '⌘S',
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: e.controlGradient,
                )
              : null,
          border: Border.all(
            color: enabled
                ? cs.outlineVariant
                : cs.onSurface.withValues(alpha: AppStateLayer.disabledContainer),
          ),
          boxShadow: enabled ? e.controlShadow : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.md),
            hoverColor: cs.primary.withValues(alpha: AppStateLayer.hover),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dirty) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '保存',
                    style: context.texts.labelLarge?.copyWith(
                      color: enabled
                          ? cs.onSurface
                          : cs.onSurface.withValues(
                              alpha: AppStateLayer.disabledContent,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏标题右侧：「待校对 N」+ 来源（本地会话是可点开的 chip，任务会话是
/// 一句「已自动保存」）。
class EditorTitleTrailing extends StatelessWidget {
  const EditorTitleTrailing({
    super.key,
    required this.controller,
    this.onReplace,
    this.onRepair,
    this.onOpenOther,
  });

  final EditorController controller;
  final ValueChanged<OpenSlot>? onReplace;
  final VoidCallback? onRepair;
  final VoidCallback? onOpenOther;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = controller.session;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        EditorReviewBadge(count: controller.countOf(CueFilter.review)),
        const SizedBox(width: AppSpacing.s3),
        switch (session) {
          FileSession() => _SourceChip(
            controller: controller,
            session: session,
            onReplace: onReplace,
            onRepair: onRepair,
            onOpenOther: onOpenOther,
          ),
          TaskSession() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.check, size: 16, weight: 400, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.s1),
              Text(
                '已自动保存',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        },
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.controller,
    required this.session,
    required this.onReplace,
    required this.onRepair,
    required this.onOpenOther,
  });

  final EditorController controller;
  final FileSession session;
  final ValueChanged<OpenSlot>? onReplace;
  final VoidCallback? onRepair;
  final VoidCallback? onOpenOther;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final translationPath = session.mountedTranslationPath;
    final fileCount = translationPath == null ? 1 : 2;

    return AnchoredPopover(
      width: 400,
      anchor: (context, toggle, open) => Container(
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.s2),
          border: Border.all(color: cs.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: context.elevation.controlGradient,
          ),
          boxShadow: context.elevation.controlShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: toggle,
            borderRadius: BorderRadius.circular(AppSpacing.s2),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.description, size: 16, weight: 400, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.s1),
                  Text('本地 · $fileCount 个文件', style: context.texts.labelMedium),
                  Icon(
                    open ? Symbols.expand_less : Symbols.expand_more,
                    size: 18,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      popover: (context, close) {
        final doc = controller.document;
        final pairing = session.pairing;
        Widget fileRow({
          required String head,
          required String path,
          required int count,
          required OpenSlot slot,
          VoidCallback? onDetach,
        }) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 2,
            children: [
              Text(
                head,
                style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Row(
                children: [
                  Icon(Symbols.subtitles, size: 18, weight: 400, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      baseName(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (onReplace != null)
                    _TextAction(
                      label: '替换…',
                      color: cs.primary,
                      onTap: () {
                        close();
                        onReplace!(slot);
                      },
                    ),
                  if (onDetach != null)
                    _TextAction(
                      label: '卸载',
                      color: cs.error,
                      onTap: () {
                        close();
                        onDetach();
                      },
                    ),
                ],
              ),
              Text(
                '${parentDir(path)} · $count 条',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );

        return GlassMenu(
          padding: const EdgeInsets.all(AppSpacing.s2),
          children: [
            fileRow(
              head: '原文 · ${session.sourceLanguage.name}',
              path: session.sourcePath,
              count: doc.cues.where((c) => c.source.trim().isNotEmpty).length,
              slot: OpenSlot.source,
            ),
            if (translationPath != null)
              fileRow(
                head: '译文 · ${session.targetLanguage.name}',
                path: translationPath,
                count: doc.cues.where((c) => c.hasTranslation).length,
                slot: OpenSlot.translation,
                onDetach: controller.unmountTranslation,
              ),
            const MenuDivider(),
            if (translationPath != null)
              SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                  child: Row(
                    children: [
                      Icon(Symbols.link, size: 18, weight: 400, color: cs.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          [
                            if (pairing != null)
                              pairing.mode == PairingMode.byIndex ? '按序号配对' : '按时间轴配对',
                            if (pairing != null) '${pairing.paired} 条',
                            if (doc.unpairedCount > 0) '${doc.unpairedCount} 条未配对',
                            if (pairing == null && doc.unpairedCount == 0) '已配对',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium,
                        ),
                      ),
                      if (onRepair != null)
                        _TextAction(
                          label: '重新配对…',
                          color: cs.primary,
                          onTap: () {
                            close();
                            onRepair!();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            MenuRow(
              leading: Icon(Symbols.folder_open, size: 18, weight: 400, color: cs.onSurfaceVariant),
              label: '打开其他字幕…',
              onTap: () {
                close();
                onOpenOther?.call();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                '⌘S 会覆盖上面 $fileCount 个文件。想保留原文件，请用「导出」。',
                style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.s2),
    hoverColor: color.withValues(alpha: AppStateLayer.hover),
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      alignment: Alignment.center,
      child: Text(label, style: context.texts.labelMedium?.copyWith(color: color)),
    ),
  );
}

/// 本地会话关掉前的询问（设计稿 6b）。返回 true 表示可以继续。
Future<bool> confirmLeaveEditor(
  BuildContext context,
  EditorController controller,
) async {
  final session = controller.session;
  final edits = controller.unsavedEdits;
  if (session is! FileSession || edits == 0) return true;

  final files = [
    baseName(session.sourcePath),
    if (session.mountedTranslationPath != null)
      baseName(session.mountedTranslationPath!),
  ];
  final choice = await showDialog<_LeaveChoice>(
    context: context,
    builder: (context) {
      final cs = context.colors;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 420,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.glass.glassStrong,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: context.glass.glassBorder),
              boxShadow: context.elevation.shadow3,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s3,
                children: [
                  Text('保存修改？', style: context.texts.titleLarge),
                  Text(
                    '${session.title} 有 $edits 处修改还没保存。保存会写回 ${files.join(' 和 ')}。',
                    style: context.texts.bodyMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '「已校对」标记和说话人名单不会写进 SRT，而是另存在应用数据里；下次打开这${files.length == 2 ? '两' : ''}个文件时会恢复。',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s1),
                    child: Row(
                      children: [
                        _TextAction(
                          label: '不保存',
                          color: cs.error,
                          onTap: () => Navigator.of(context).pop(_LeaveChoice.discard),
                        ),
                        const Spacer(),
                        ControlButton(
                          label: '取消',
                          onPressed: () => Navigator.of(context).pop(_LeaveChoice.cancel),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        PrimaryButton(
                          label: '保存并打开',
                          onPressed: () => Navigator.of(context).pop(_LeaveChoice.save),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  switch (choice) {
    case _LeaveChoice.save:
      try {
        await controller.save();
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
        }
        return false;
      }
    case _LeaveChoice.discard:
      return true;
    case _LeaveChoice.cancel || null:
      return false;
  }
}

enum _LeaveChoice { save, discard, cancel }

/// 顶栏标题右侧的「待校对 N」。
class EditorReviewBadge extends StatelessWidget {
  const EditorReviewBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.flag,
            size: 16,
            weight: 400,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '待校对 $count',
            style: context.texts.labelMedium?.copyWith(
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
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

/// 状态栏右侧的「未保存 3 处修改」。
String? editorStatusNote(EditorController controller) {
  final edits = controller.unsavedEdits;
  return edits == 0 ? null : '未保存 $edits 处修改';
}
