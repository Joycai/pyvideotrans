import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/note_bar.dart';
import '../shared/new_task_panels.dart';
import 'new_transcribe_file_list.dart';
import 'transcribe_form.dart';

class NewTranscribeFilePanel extends StatelessWidget {
  const NewTranscribeFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    this.enqueued,
    this.rejectNote,
    required this.onOpenTasks,
    required this.onDismissBanner,
  });

  final TranscribeFormController form;
  final bool dragging;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  /// 拖放拒收的中性说明。只在列表上方显示 —— 空态时页脚已经说了。
  final String? rejectNote;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  @override
  Widget build(BuildContext context) {
    final files = form.files;
    // 字段不参与类型提升，取个局部变量才能在 if 里当非空用。
    final note = rejectNote;
    return NewTaskFilePanel(
      count: files.length,
      dragging: dragging,
      enqueued: enqueued,
      onClear: form.clear,
      onBrowse: form.browse,
      onOpenTasks: onOpenTasks,
      onDismissBanner: onDismissBanner,
      header: files.isEmpty || note == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NoteBar(text: note, onClose: form.clearDropError),
                const SizedBox(height: AppSpacing.s3),
              ],
            ),
      child: files.isEmpty
          ? FileDropEmptyState(
              icon: Symbols.upload_file,
              title: '把音视频文件拖到这里',
              formats: 'mp4 · mov · mkv · mp3 · m4a · wav，可一次选多个',
              steps: const ['添加文件', '确认右侧参数', '加入队列，进度在任务页'],
              dragging: dragging,
              enqueued: enqueued,
              onBrowse: form.browse,
            )
          : NewTranscribeFileList(form: form, dragging: dragging),
    );
  }
}
