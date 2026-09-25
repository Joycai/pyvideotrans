import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/language.dart';
import '../../domain/paths.dart';
import 'editor_open_form.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

class EditorSwapSlotsButton extends StatelessWidget {
  const EditorSwapSlotsButton({super.key, required this.form});

  final EditorOpenForm form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = form.source != null && form.translation != null;
    return Tooltip(
      message: enabled ? '对换原文与译文' : '两份都添加后才能对换',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? cs.outlineVariant
                : cs.onSurface.withValues(
                    alpha: AppStateLayer.disabledContainer,
                  ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: context.elevation.controlGradient,
          ),
          boxShadow: enabled ? context.elevation.controlShadow : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? form.swap : null,
            child: Icon(
              Symbols.swap_horiz,
              size: 20,
              weight: 400,
              color: enabled
                  ? cs.onSurface
                  : cs.onSurface.withValues(
                      alpha: AppStateLayer.disabledContent,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个位置：空的时候是虚线落区，放了文件是卡片。只有被拖到的那一个位置亮起。
class EditorOpenSlot extends StatefulWidget {
  const EditorOpenSlot({super.key, required this.form, required this.slot});

  final EditorOpenForm form;
  final OpenSlot slot;

  @override
  State<EditorOpenSlot> createState() => _EditorOpenSlotState();
}

class _EditorOpenSlotState extends State<EditorOpenSlot> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final slot = widget.slot;
    final file = form.file(slot);
    return DropTarget(
      onDragEntered: (_) => setState(() => _hot = true),
      onDragExited: (_) => setState(() => _hot = false),
      onDragDone: (d) {
        setState(() => _hot = false);
        form.handleDrop([for (final f in d.files) f.path], slot: slot);
      },
      child: file == null
          ? _EmptySlot(form: form, slot: slot, hot: _hot)
          : _FilledSlot(form: form, slot: slot, hot: _hot),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.form, required this.slot, required this.hot});

  final EditorOpenForm form;
  final OpenSlot slot;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isSource = slot == OpenSlot.source;
    final error = form.error(slot);
    final title = hot
        ? (isSource ? '松开以放入原文' : '松开以放入译文')
        : (isSource ? '拖入原文字幕' : '拖入译文字幕');
    final sub = isSource ? '识别出来或听写的那一份，必须有' : '可选；不挂也能在编辑器里翻译';

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSource ? Symbols.subtitles : Symbols.translate,
            size: 40,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(title, style: context.texts.titleMedium),
          const SizedBox(height: 6),
          Text(
            error ?? sub,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium?.copyWith(
              color: error == null ? cs.onSurfaceVariant : cs.error,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          ControlButton(label: '选择文件…', onPressed: () => form.browse(slot)),
        ],
      ),
    );

    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: AppEasing.standard,
      decoration: BoxDecoration(
        color: hot ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: hot ? Border.all(color: cs.primary, width: 2) : null,
      ),
      child: hot
          ? content
          : CustomPaint(
              painter: DashedRRectPainter(
                color: cs.outline,
                radius: 14,
                strokeWidth: 1.5,
              ),
              child: SizedBox.expand(child: content),
            ),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.form,
    required this.slot,
    required this.hot,
  });

  final EditorOpenForm form;
  final OpenSlot slot;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final file = form.file(slot)!;
    final isSource = slot == OpenSlot.source;
    final language = form.language(slot);
    final label = hot
        ? (isSource ? '松开以替换原文' : '松开以替换译文')
        : (isSource ? '原文' : '译文');

    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: AppEasing.standard,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: hot
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hot ? cs.primary : cs.outlineVariant,
          width: hot ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Text(
                  label,
                  style: context.texts.titleSmall?.copyWith(
                    color: hot ? cs.primary : cs.onSurface,
                  ),
                ),
                const Spacer(),
                IconActionButton(
                  icon: Symbols.close,
                  tooltip: '移除',
                  size: 28,
                  iconSize: 18,
                  onPressed: () => form.remove(slot),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              const FileIconBox(Symbols.subtitles),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      dirName(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Timecode(
                '${file.cues.length} 条',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Timecode(
                EditorOpenForm.span(file),
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
          const Spacer(),
          AppDropdown<Language>(
            value: language,
            display: form.languageGuessed(slot)
                ? '${language.name} · 自动识别'
                : language.name,
            menuWidth: 240,
            onChanged: (l) => form.setLanguage(slot, l),
            groups: [
              DropdownGroup(
                entries: [
                  for (final l in Languages.all)
                    DropdownEntry(value: l, label: l.name),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
