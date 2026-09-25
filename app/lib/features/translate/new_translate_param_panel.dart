import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
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
  final ({String text, IconData icon, bool error})? footerOverride;
  final VoidCallback onOpenSettings;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.s4,
                right: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Text('参数', style: context.texts.titleMedium),
                  const Spacer(),
                  QuietButton(label: '重置为默认', onPressed: form.reset),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TranslateLanguageSection(
                    form: form,
                    flat: true,
                    onOpenSettings: onOpenSettings,
                  ),
                  TranslateAdvancedSection(form: form, flat: true),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TranslateFooterLine(
                    form: form,
                    line: footerOverride,
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                TranslateStartButton(
                  form: form,
                  onStart: onStart,
                  withCount: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
