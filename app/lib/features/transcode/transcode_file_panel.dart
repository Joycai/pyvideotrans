import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/note_bar.dart';
import '../shared/new_task_panels.dart';
import 'transcode_file_list.dart';
import 'transcode_form.dart';

class TranscodeFilePanel extends StatelessWidget {
  const TranscodeFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    required this.onOpenTasks,
    required this.onDismissBanner,
    this.enqueued,
  });

  final TranscodeFormController form;
  final bool dragging;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  @override
  Widget build(BuildContext context) {
    final files = form.files;
    final rejected = form.dropError;
    return NewTaskFilePanel(
      count: files.length,
      dragging: dragging,
      enqueued: enqueued,
      onClear: form.clear,
      onBrowse: form.browse,
      onOpenTasks: onOpenTasks,
      onDismissBanner: onDismissBanner,
      header: rejected == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NoteBar(text: rejected, onClose: form.clearDropError),
                const SizedBox(height: AppSpacing.s3),
              ],
            ),
      child: files.isEmpty
          ? FileDropEmptyState(
              icon: Symbols.movie,
              title: '把视频拖到这里',
              formats: 'MP4 · MOV · MKV · AVI · WebM · FLV · WMV · TS，可一次选多个',
              formatsAlign: TextAlign.center,
              steps: const ['添加视频', '选择编码与编码器', '加入队列，进度在任务页'],
              dragging: dragging,
              enqueued: enqueued,
              onBrowse: form.browse,
            )
          : TranscodeFileList(form: form, dragging: dragging),
    );
  }
}
