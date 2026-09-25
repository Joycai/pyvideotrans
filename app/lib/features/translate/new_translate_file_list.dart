import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../domain/srt.dart';
import '../shared/provider_fields.dart';
import 'translate_file_notes.dart';
import 'translate_form.dart';

class NewTranslateFileList extends StatelessWidget {
  const NewTranslateFileList({
    super.key,
    required this.form,
    required this.dragging,
    this.onSwitchToTranscribe,
  });

  final TranslateFormController form;
  final bool dragging;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final files = form.files;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TranslateFileNotes(form: form, onSwitchToTranscribe: onSwitchToTranscribe),
          Flexible(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadius.md + 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _HeaderRow(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final file in files)
                          _FileRow(
                            file: file,
                            onRemove: () => form.remove(file),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            form.applyNote,
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            height: 44,
            child: CustomPaint(
              painter: DashedBorder(
                color: dragging ? cs.primary : cs.outline,
                radius: AppRadius.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.subtitles,
                    size: 20,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    dragging ? '松开以添加文件' : '继续拖入可追加文件',
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 表格列宽：图标 36 | 文件名 自适应 | 条数 80 | 时长 88 | 大小 80 | 状态 96 | 移除 36，间距 12。
const _kCols = (
  icon: 36.0,
  cues: 80.0,
  len: 88.0,
  size: 80.0,
  chip: 96.0,
  remove: 36.0,
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: _kCols.icon),
          const SizedBox(width: AppSpacing.s3),
          Expanded(child: Text('文件', style: style)),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.cues,
            child: Text('条数', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.len,
            child: Text('时长', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.size,
            child: Text('大小', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.chip,
            child: Text('状态', style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(width: _kCols.remove),
        ],
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({required this.file, required this.onRemove});

  final StagedSubtitle file;
  final VoidCallback onRemove;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final file = widget.file;
    final info = file.info;
    final state = file.state;
    final ready = state == StagedSubtitleState.ready;
    final bad = state == StagedSubtitleState.broken;
    final showRemove = _hovered || _focused;
    final numberColor = ready ? cs.onSurface : cs.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: _hovered
              ? cs.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: _kCols.icon,
              height: 36,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Icon(
                Symbols.subtitles,
                size: 20,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: bad ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bad ? '解析不出字幕内容，将跳过' : file.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: bad ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.cues,
              child: Text(
                file.cueCount == null ? '—' : grouped(file.cueCount!),
                textAlign: TextAlign.right,
                style: kTimecodeStyle.copyWith(color: numberColor),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.len,
              child: Text(
                ready && info?.duration != null
                    ? Srt.formatDuration(info!.duration!)
                    : '—',
                textAlign: TextAlign.right,
                style: kTimecodeStyle.copyWith(color: numberColor),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.size,
              child: Text(
                info?.sizeLabel ?? '',
                textAlign: TextAlign.right,
                style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.chip,
              child: _StateChip(state: state),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.remove,
              child: Focus(
                onFocusChange: (v) => setState(() => _focused = v),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: showRemove ? 1 : 0,
                  child: IconActionButton(
                    icon: Symbols.close,
                    tooltip: '移除',
                    iconSize: 18,
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final StagedSubtitleState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch (state) {
      StagedSubtitleState.ready => (
        '就绪',
        Symbols.check,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      StagedSubtitleState.parsing => (
        '解析中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      StagedSubtitleState.broken => (
        '无法解析',
        Symbols.error,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 6, right: AppSpacing.s2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, weight: 400, color: fg),
            const SizedBox(width: AppSpacing.s1),
            Text(label, style: context.texts.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
