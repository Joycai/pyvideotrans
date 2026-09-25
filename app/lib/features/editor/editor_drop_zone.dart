import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import 'editor_open_form.dart';

/// 编辑页的拖放区：左半边落原文、右半边落译文。
///
/// 只认出第一个能打开的文件和落在哪一半，真正的替换交给 [onDrop] ——
/// 编辑页不直接改动正在编辑的会话，而是带去入口页确认配对。
class EditorDropZone extends StatefulWidget {
  const EditorDropZone({
    super.key,
    required this.hasTranslation,
    required this.onDrop,
    required this.child,
  });

  final bool hasTranslation;
  final void Function(String path, OpenSlot slot) onDrop;
  final Widget child;

  @override
  State<EditorDropZone> createState() => _EditorDropZoneState();
}

class _EditorDropZoneState extends State<EditorDropZone> {
  OpenSlot? _dropSlot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
            if (path != null) widget.onDrop(path, slot);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (_dropSlot != null)
                _DropOverlay(
                  slot: _dropSlot!,
                  hasTranslation: widget.hasTranslation,
                ),
            ],
          ),
        );
      },
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
          curve: AppEasing.standard,
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
