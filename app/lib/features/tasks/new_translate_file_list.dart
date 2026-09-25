import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../shared/new_task_file_table.dart';
import '../shared/provider_fields.dart';
import 'translate_form.dart';

class NewTranslateFileList extends StatelessWidget {
  const NewTranslateFileList({
    super.key,
    required this.form,
    required this.dragging,
  });

  final TranslateFormController form;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return NewTaskFileTable(
      columns: const [
        FileTableColumn('条数', 80, alignEnd: true),
        FileTableColumn('时长', 88, alignEnd: true),
        FileTableColumn('大小', 80, alignEnd: true),
        FileTableColumn('状态', 96),
      ],
      entries: [
        for (final file in form.files) _entry(cs, file),
      ],
      applyNote: form.applyNote,
      appendIcon: Symbols.subtitles,
      dragging: dragging,
    );
  }

  FileTableEntry _entry(ColorScheme cs, StagedSubtitle file) {
    final info = file.info;
    final ready = file.state == StagedSubtitleState.ready;
    final numberColor = ready ? cs.onSurface : cs.onSurfaceVariant;
    return FileTableEntry(
      icon: Symbols.subtitles,
      fileName: file.fileName,
      directory: file.directory,
      problem: file.state == StagedSubtitleState.broken
          ? '解析不出字幕内容，将跳过'
          : null,
      cells: [
        Text(
          file.cueCount == null ? '—' : grouped(file.cueCount!),
          textAlign: TextAlign.right,
          style: kTimecodeStyle.copyWith(color: numberColor),
        ),
        Text(
          ready && info?.duration != null
              ? Srt.formatDuration(info!.duration!)
              : '—',
          textAlign: TextAlign.right,
          style: kTimecodeStyle.copyWith(color: numberColor),
        ),
        Text(
          info?.sizeLabel ?? '',
          textAlign: TextAlign.right,
          style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
        ),
        _StateChip(state: file.state),
      ],
      onRemove: () => form.remove(file),
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
    return StateChip(label: label, icon: icon, bg: bg, fg: fg);
  }
}
