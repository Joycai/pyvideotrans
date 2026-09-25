import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/paths.dart';
import '../../domain/subtitle_pairing.dart';
import 'editor_controller.dart';
import 'editor_open_form.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';

/// 本地会话的来源 chip：列出挂载的文件，点开是来源浮层（替换、挂载译文、重新配对）。
class EditorSourceChip extends StatelessWidget {
  const EditorSourceChip({
    super.key,
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
                  Icon(
                    Symbols.description,
                    size: 16,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s1),
                  Text('本地 · $fileCount 个文件', style: context.texts.labelMedium),
                  ?_localSuffix(context, controller),
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
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Row(
                children: [
                  Icon(
                    Symbols.subtitles,
                    size: 18,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
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
                    EditorTextAction(
                      label: '替换…',
                      color: cs.primary,
                      onTap: () {
                        close();
                        onReplace!(slot);
                      },
                    ),
                  if (onDetach != null)
                    EditorTextAction(
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
                '${dirName(path)} · $count 条',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.link,
                        size: 18,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          [
                            if (pairing != null)
                              pairing.mode == PairingMode.byIndex
                                  ? '按序号配对'
                                  : '按时间轴配对',
                            if (pairing != null) '${pairing.paired} 条',
                            if (doc.unpairedCount > 0)
                              '${doc.unpairedCount} 条未配对',
                            if (pairing == null && doc.unpairedCount == 0)
                              '已配对',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium,
                        ),
                      ),
                      if (onRepair != null)
                        EditorTextAction(
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
              leading: Icon(
                Symbols.folder_open,
                size: 18,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
              label: '打开其他字幕…',
              onTap: () {
                close();
                onOpenOther?.call();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                '⌘S 会覆盖上面 $fileCount 个文件。想保留原文件，请用「导出…」。',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 本地会话 chip 后面跟的一句状态；已同步时不显示。
Widget? _localSuffix(BuildContext context, EditorController controller) {
  final cs = context.colors;
  final (label, color) = switch (controller.sync) {
    SyncState.synced || SyncState.noOutput => (null, cs.primary),
    SyncState.dirty => ('${controller.unsavedEdits} 处未写入', cs.primary),
    SyncState.writing => ('写入中…', cs.onSurfaceVariant),
    SyncState.written => ('已写入', context.ext.success),
    SyncState.failed => ('写入失败 · ${controller.failure}', cs.error),
    SyncState.conflict => ('在别处被改过', cs.onTertiaryContainer),
  };
  if (label == null) return null;
  return Padding(
    padding: const EdgeInsets.only(left: AppSpacing.s2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        StatusDot(color, size: 6),
        Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: color == cs.primary ? cs.onPrimaryContainer : color,
          ),
        ),
      ],
    ),
  );
}
