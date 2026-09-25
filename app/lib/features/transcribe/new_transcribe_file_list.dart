import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../domain/srt.dart';
import 'transcribe_form.dart';

class NewTranscribeFileList extends StatelessWidget {
  const NewTranscribeFileList({
    super.key,
    required this.form,
    required this.dragging,
    this.rejectNote,
  });

  final TranscribeFormController form;
  final bool dragging;

  /// 拖放拒收的中性说明。
  final String? rejectNote;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final files = form.files;
    // 字段不参与类型提升，取个局部变量才能在 if 里当非空用。
    final note = rejectNote;
    final n = form.enqueueable.length;
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
          if (note != null) ...[
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.block,
                    size: 18,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      note,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconActionButton(
                    icon: Symbols.close,
                    tooltip: '关闭',
                    size: 28,
                    iconSize: 16,
                    onPressed: form.clearDropError,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
          ],
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
            '参数统一应用到每个文件；入队后按列表顺序生成 $n 个独立任务，单个失败不影响其余',
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
                    Symbols.upload_file,
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

/// 表格列宽：图标 36 | 文件名 自适应 | 时长 88 | 大小 80 | 状态 96 | 移除 36，间距 12。
const _kCols = (icon: 36.0, len: 88.0, size: 80.0, chip: 96.0, remove: 36.0);

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

  final StagedFile file;
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
    final bad = state == StagedFileState.unreadable;
    final showRemove = _hovered || _focused;
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
                file.isVideo ? Symbols.movie : Symbols.audio_file,
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
                    bad ? '文件损坏或编码不受支持，将跳过' : file.directory,
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
              width: _kCols.len,
              child: Text(
                info?.duration == null
                    ? '—'
                    : Srt.formatDuration(info!.duration!),
                textAlign: TextAlign.right,
                style: AppTextStyles.timecode.copyWith(
                  color: state == StagedFileState.ready
                      ? cs.onSurface
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.size,
              child: Text(
                info?.sizeLabel ?? '',
                textAlign: TextAlign.right,
                style: AppTextStyles.timecode.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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

  final StagedFileState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch (state) {
      StagedFileState.ready => (
        '就绪',
        Symbols.check,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      StagedFileState.probing => (
        '探测中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      StagedFileState.unreadable => (
        '无法读取',
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
