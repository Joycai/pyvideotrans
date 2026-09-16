import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/transcode/probe.dart';
import 'transcode_form.dart';
import 'transcode_widgets.dart';

class TranscodeFileList extends StatelessWidget {
  const TranscodeFileList({
    super.key,
    required this.form,
    required this.dragging,
  });

  final TranscodeFormController form;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                      for (final file in form.files)
                        _FileRow(
                          file: file,
                          form: form,
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
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const Spacer(),
        const SizedBox(height: AppSpacing.s3),
        SizedBox(
          height: 44,
          child: CustomPaint(
            painter: TranscodeDashedBorder(
              color: dragging ? cs.primary : cs.outline,
              radius: AppRadius.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.movie,
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
    );
  }
}

/// 表格列宽：图标 36 | 文件 自适应 | 时长 72 | 视频 136 | 音频 96 | 大小 80 | 状态 96 | 移除 36。
const _kCols = (
  icon: 36.0,
  len: 72.0,
  video: 136.0,
  audio: 96.0,
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
    Widget cell(double w, String t, {bool right = false}) => SizedBox(
      width: w,
      child: Text(t, textAlign: right ? TextAlign.right : null, style: style),
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: _Cols(
        icon: const SizedBox(),
        name: Text('文件', style: style),
        len: cell(_kCols.len, '时长', right: true),
        video: cell(_kCols.video, '视频'),
        audio: cell(_kCols.audio, '音频'),
        size: cell(_kCols.size, '大小', right: true),
        chip: cell(_kCols.chip, '状态'),
        remove: const SizedBox(),
      ),
    );
  }
}

/// 表头与数据行共用的列排布；窄窗口时先收掉视频、音频两列。
class _Cols extends StatelessWidget {
  const _Cols({
    required this.icon,
    required this.name,
    required this.len,
    required this.video,
    required this.audio,
    required this.size,
    required this.chip,
    required this.remove,
  });

  final Widget icon, name, len, video, audio, size, chip, remove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final roomy = c.maxWidth >= 760;
        Widget fixed(double w, Widget child) =>
            SizedBox(width: w, child: child);
        const gap = SizedBox(width: AppSpacing.s3);
        return Row(
          children: [
            fixed(_kCols.icon, icon),
            gap,
            Expanded(child: name),
            gap,
            fixed(_kCols.len, len),
            if (roomy) ...[
              gap,
              fixed(_kCols.video, video),
              gap,
              fixed(_kCols.audio, audio),
            ],
            gap,
            fixed(_kCols.size, size),
            gap,
            fixed(_kCols.chip, chip),
            gap,
            fixed(_kCols.remove, remove),
          ],
        );
      },
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.form,
    required this.onRemove,
  });

  final StagedVideo file;
  final TranscodeFormController form;
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
    final state = widget.form.stateOf(file);
    final problem = widget.form.problemOf(file);
    final ready = state == StagedVideoState.ready;
    final numberColor = ready ? cs.onSurface : cs.onSurfaceVariant;
    final video = file.video;
    final audio = file.audio;

    Widget twoLines(String? top, String? bottom) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: kTimecodeStyle.copyWith(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w500,
            color: numberColor,
          ),
        ),
        if (bottom != null && bottom.isNotEmpty)
          Text(
            bottom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kTimecodeStyle.copyWith(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

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
        child: _Cols(
          icon: Container(
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            child: Icon(
              Symbols.movie,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
          ),
          name: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                file.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: problem != null ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                problem ?? file.directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: problem != null ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          len: Text(
            file.durationLabel,
            textAlign: TextAlign.right,
            style: kTimecodeStyle.copyWith(color: numberColor),
          ),
          video: twoLines(
            video == null ? null : MediaProbe.codecLabel(video.codec),
            video?.shape,
          ),
          audio: twoLines(
            audio == null ? null : MediaProbe.codecLabel(audio.codec),
            audio?.channels == null ? null : '${audio!.channels}ch',
          ),
          size: Text(
            file.sizeBytes > 0 ? file.sizeLabel : '',
            textAlign: TextAlign.right,
            style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
          ),
          chip: _StateChip(state: state),
          remove: Focus(
            onFocusChange: (v) => setState(() => _focused = v),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered || _focused ? 1 : 0,
              child: IconActionButton(
                icon: Symbols.close,
                tooltip: '移除',
                iconSize: 18,
                onPressed: widget.onRemove,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final StagedVideoState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch (state) {
      StagedVideoState.ready => (
        '就绪',
        Symbols.check,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      StagedVideoState.probing => (
        '读取中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      StagedVideoState.incompatible => (
        '不兼容',
        Symbols.block,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
      StagedVideoState.broken => (
        '无法读取',
        Symbols.error,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return TranscodeChip(label: label, icon: icon, bg: bg, fg: fg);
  }
}
