import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/transcode/probe.dart';
import '../shared/new_task_file_table.dart';
import 'transcode_form.dart';

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
    return NewTaskFileTable(
      // 窄窗口时先收掉视频、音频两列。
      columns: const [
        FileTableColumn('时长', 72, alignEnd: true),
        FileTableColumn('视频', 136, minRowWidth: 760),
        FileTableColumn('音频', 96, minRowWidth: 760),
        FileTableColumn('大小', 80, alignEnd: true),
        FileTableColumn('状态', 96),
      ],
      entries: [
        for (final file in form.files) _entry(cs, file),
      ],
      applyNote: form.applyNote,
      appendIcon: Symbols.movie,
      dragging: dragging,
    );
  }

  FileTableEntry _entry(ColorScheme cs, StagedVideo file) {
    final state = form.stateOf(file);
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
          style: AppTextStyles.timecode.copyWith(
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
            style: AppTextStyles.timecode.copyWith(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

    return FileTableEntry(
      icon: Symbols.movie,
      fileName: file.fileName,
      directory: file.directory,
      problem: form.problemOf(file),
      cells: [
        Text(
          file.durationLabel,
          textAlign: TextAlign.right,
          style: AppTextStyles.timecode.copyWith(color: numberColor),
        ),
        twoLines(
          video == null ? null : MediaProbe.codecLabel(video.codec),
          video?.shape,
        ),
        twoLines(
          audio == null ? null : MediaProbe.codecLabel(audio.codec),
          audio?.channels == null ? null : '${audio!.channels}ch',
        ),
        Text(
          file.sizeBytes > 0 ? file.sizeLabel : '',
          textAlign: TextAlign.right,
          style: AppTextStyles.timecode.copyWith(color: cs.onSurfaceVariant),
        ),
        _StateChip(state: state),
      ],
      onRemove: () => form.remove(file),
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
    return StateChip(label: label, icon: icon, bg: bg, fg: fg);
  }
}
