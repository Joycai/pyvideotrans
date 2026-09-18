import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';

/// 顶栏右侧：视图切换 + 翻译未译 + 保存 + 导出…。
///
/// 两种会话都有「保存」：它写的是播放器读的那几份字幕文件，编辑进度本身
/// 一直在自动存。「导出…」是另存到别处。
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
    final sync = controller.sync;
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
        const SizedBox(width: AppSpacing.s3),
        // 没有修改时禁用而不是隐藏，位置不跳。
        _SaveButton(
          label: switch (sync) {
            SyncState.noOutput => '生成文件',
            SyncState.failed => '重试',
            SyncState.conflict => '保存…',
            _ => '保存',
          },
          dirty: sync == SyncState.dirty || sync == SyncState.failed,
          dot: cs.primary,
          onPressed: controller.canWrite ? onSave : null,
        ),
        const SizedBox(width: AppSpacing.s3),
        PrimaryButton(
          label: '导出…',
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
                  ? Icon(
                      Symbols.check,
                      size: 18,
                      weight: 500,
                      color: cs.primary,
                    )
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
  const _SaveButton({
    required this.label,
    required this.dirty,
    required this.dot,
    this.onPressed,
  });

  final String label;
  final bool dirty;
  final Color dot;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final enabled = onPressed != null;
    return Tooltip(
      message: '写入字幕文件 ⌘S',
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
                : cs.onSurface.withValues(
                    alpha: AppStateLayer.disabledContainer,
                  ),
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
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
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
