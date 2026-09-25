import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../shared/new_task_file_table.dart';
import 'transcribe_form.dart';

class NewTranscribeFileList extends StatelessWidget {
  const NewTranscribeFileList({
    super.key,
    required this.form,
    required this.dragging,
  });

  final TranscribeFormController form;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final n = form.enqueueable.length;
    return NewTaskFileTable(
      columns: const [
        FileTableColumn('时长', 88, alignEnd: true),
        FileTableColumn('大小', 80, alignEnd: true),
        FileTableColumn('状态', 96),
      ],
      entries: [
        for (final file in form.files) _entry(cs, file),
      ],
      applyNote:
          '参数统一应用到每个文件；入队后按列表顺序生成 $n 个独立任务，单个失败不影响其余',
      appendIcon: Symbols.upload_file,
      dragging: dragging,
    );
  }

  FileTableEntry _entry(ColorScheme cs, StagedFile file) {
    final info = file.info;
    final state = file.state;
    return FileTableEntry(
      icon: file.isVideo ? Symbols.movie : Symbols.audio_file,
      fileName: file.fileName,
      directory: file.directory,
      problem: state == StagedFileState.unreadable
          ? '文件损坏或编码不受支持，将跳过'
          : null,
      cells: [
        Text(
          info?.duration == null ? '—' : Srt.formatDuration(info!.duration!),
          textAlign: TextAlign.right,
          style: AppTextStyles.timecode.copyWith(
            color: state == StagedFileState.ready
                ? cs.onSurface
                : cs.onSurfaceVariant,
          ),
        ),
        Text(
          info?.sizeLabel ?? '',
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
    return StateChip(label: label, icon: icon, bg: bg, fg: fg);
  }
}
