import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/note_bar.dart';
import 'translate_form.dart';

/// 文件区顶部的提示条：忽略了音视频（带「改用新建转写」）、不认识的格式（可关）。
class TranslateFileNotes extends StatelessWidget {
  const TranslateFileNotes({
    super.key,
    required this.form,
    this.onSwitchToTranscribe,
  });

  final TranslateFormController form;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) {
    final ignored = form.ignoredNote;
    final rejected = form.dropError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ignored != null) ...[
          IgnoredMediaNote(
            text: ignored,
            onSwitchToTranscribe: onSwitchToTranscribe,
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        if (rejected != null) ...[
          NoteBar(text: rejected, onClose: form.clearDropError),
          const SizedBox(height: AppSpacing.s3),
        ],
      ],
    );
  }
}

/// 忽略了几个音视频，右侧「改用新建转写」把它们带走。拖错门不是错误，所以是中性提示条。
class IgnoredMediaNote extends StatelessWidget {
  const IgnoredMediaNote({
    super.key,
    required this.text,
    this.onSwitchToTranscribe,
  });

  final String text;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) => NoteBar(
    text: text,
    action: onSwitchToTranscribe == null
        ? null
        : LinkText(
            label: '改用新建转写',
            color: context.colors.primary,
            onTap: onSwitchToTranscribe!,
          ),
  );
}
