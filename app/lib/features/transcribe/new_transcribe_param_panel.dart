import 'package:flutter/material.dart';

import '../shared/new_task_panels.dart';
import 'transcribe_advanced_section.dart';
import 'transcribe_footer.dart';
import 'transcribe_form.dart';
import 'transcribe_recognize_section.dart';
import 'transcribe_translate_section.dart';

class NewTranscribeParamPanel extends StatelessWidget {
  const NewTranscribeParamPanel({
    super.key,
    required this.form,
    required this.footerOverride,
    required this.onOpenSettings,
    required this.onStart,
  });

  final TranscribeFormController form;

  /// 页面在拖放拒收时用中性色的说明顶替控制器里的 error 版本。
  final FooterMessage? footerOverride;
  final VoidCallback onOpenSettings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => NewTaskParamPanel(
    onReset: form.reset,
    sections: [
      TranscribeRecognizeSection(
        form: form,
        flat: true,
        onOpenSettings: onOpenSettings,
      ),
      TranscribeTranslateSection(form: form, flat: true),
      TranscribeAdvancedSection(form: form, flat: true),
    ],
    footer: footerOverride ?? form.footer,
    action: TranscribeStartButton(
      form: form,
      onStart: onStart,
      withCount: true,
    ),
  );
}
