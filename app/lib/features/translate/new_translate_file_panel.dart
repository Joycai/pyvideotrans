import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../shared/new_task_panels.dart';
import 'new_translate_file_list.dart';
import 'translate_file_notes.dart';
import 'translate_form.dart';

class NewTranslateFilePanel extends StatelessWidget {
  const NewTranslateFilePanel({
    super.key,
    required this.form,
    required this.dragging,
    this.enqueued,
    this.onSwitchToTranscribe,
    required this.onOpenTasks,
    required this.onDismissBanner,
  });

  final TranslateFormController form;
  final bool dragging;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  /// 拖错门的音视频：交给「新建转写」页。
  final VoidCallback? onSwitchToTranscribe;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  @override
  Widget build(BuildContext context) {
    final files = form.files;
    return NewTaskFilePanel(
      count: files.length,
      dragging: dragging,
      enqueued: enqueued,
      onClear: form.clear,
      onBrowse: form.browse,
      onOpenTasks: onOpenTasks,
      onDismissBanner: onDismissBanner,
      // 空态也要显示：用户只拖了音视频进来时列表是空的，但得知道文件去了哪儿。
      header: TranslateFileNotes(
        form: form,
        onSwitchToTranscribe: onSwitchToTranscribe,
      ),
      child: files.isEmpty
          ? FileDropEmptyState(
              icon: Symbols.subtitles,
              title: '把字幕文件拖到这里',
              formats: 'SRT · VTT · ASS · SSA，可一次选多个；音视频请用「新建转写」',
              steps: const ['添加字幕文件', '确认语言与服务', '加入队列，进度在任务页'],
              dragging: dragging,
              enqueued: enqueued,
              onBrowse: form.browse,
            )
          : NewTranslateFileList(form: form, dragging: dragging),
    );
  }
}
