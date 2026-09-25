import 'package:flutter/material.dart';

import '../shared/new_task_panels.dart';
import 'translate_advanced_section.dart';
import 'translate_footer.dart';
import 'translate_form.dart';
import 'translate_language_section.dart';

class NewTranslateParamPanel extends StatelessWidget {
  const NewTranslateParamPanel({
    super.key,
    required this.form,
    required this.footerOverride,
    required this.onOpenSettings,
    required this.onStart,
  });

  final TranslateFormController form;

  /// 页面在拖放拒收时用中性色的说明顶替控制器里的 error 版本。
  final FooterMessage? footerOverride;
  final VoidCallback onOpenSettings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => NewTaskParamPanel(
    onReset: form.reset,
    sections: [
      TranslateLanguageSection(
        form: form,
        flat: true,
        onOpenSettings: onOpenSettings,
      ),
      TranslateAdvancedSection(form: form, flat: true),
    ],
    footer: footerOverride ?? form.footer,
    action: TranslateStartButton(form: form, onStart: onStart, withCount: true),
  );
}
