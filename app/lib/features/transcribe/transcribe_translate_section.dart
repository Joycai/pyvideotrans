import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../shared/provider_fields.dart';
import 'transcribe_form.dart';

/// 「翻译」段：开关 + 展开后的目标语言、服务、模型、每批条数、术语与风格。
class TranscribeTranslateSection extends StatelessWidget {
  const TranscribeTranslateSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranscribeFormController form;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final on = o.translate;
    final info = Registry.translationInfo(o.translationProviderId);
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final toggle = Tappable(
      onTap: () => form.update((o) => o.copyWith(translate: !on)),
      child: Row(
        children: [
          AppSwitch(
            value: on,
            onChanged: (v) => form.update((o) => o.copyWith(translate: v)),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('转写完成后继续翻译', style: context.texts.titleSmall),
                const SizedBox(height: 1),
                Text(
                  on
                      ? '任务类型为「转写并翻译」，翻译失败时原文字幕仍会保留'
                      : '关闭时任务类型为「转写」，之后也能在任务页单独发起翻译',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final target = LabeledField(
      label: '目标语言',
      child: AppDropdown<String>(
        value: o.targetLanguage.code,
        groups: [
          DropdownGroup(
            entries: [
              for (final l in Languages.target)
                DropdownEntry(value: l.code, label: l.name),
            ],
          ),
        ],
        onChanged: (code) => form.update(
          (o) => o.copyWith(targetLanguage: Languages.resolve(code)),
        ),
      ),
    );
    final service = LabeledField(
      label: '翻译服务',
      child: AppDropdown<String>(
        value: o.translationProviderId,
        error: form.translationReadiness.isBlocked,
        groups: providerGroups(
          Registry.translation,
          (id) => ProviderReadiness.translation(
            id,
            form.settings,
            model: id == o.translationProviderId ? o.translationModel : null,
          ),
        ),
        onChanged: form.selectTranslationProvider,
      ),
    );
    final model = modelField(
      info: info,
      model: o.translationModel,
      settings: form.settings,
      onChanged: (m) => form.update((o) => o.copyWith(translationModel: m)),
    );
    final batchHint = Text(
      '条数越大越省接口调用，出错时重试的范围也越大',
      style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    );
    final batch = NumberField(
      value: o.translationBatchSize,
      min: 1,
      max: 100,
      width: flat ? double.infinity : 88,
      onChanged: (v) => form.update((o) => o.copyWith(translationBatchSize: v)),
    );
    final guidance = LabeledField(
      label: '术语与风格（可选）',
      child: MultilineField(
        value: o.translationGuidance,
        hint: '保持人名与产品名不译：Flutter、SenseVoice。口语化，句子尽量短。',
        onChanged: (v) => form.update(
          (o) => o.copyWith(translationGuidance: v),
          notify: false,
        ),
      ),
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          toggle,
          if (on) ...[
            twoColumn(target, service, gap: gap),
            twoColumn(
              model,
              LabeledField(label: '每批条数', child: batch),
              gap: gap,
            ),
            batchHint,
            guidance,
          ],
        ],
      );
    }

    return FormSection(
      gap: 14,
      children: [
        toggle,
        if (on) ...[
          Container(height: 1, color: cs.outlineVariant),
          twoColumn(target, service),
          twoColumn(
            model,
            LabeledField(
              label: '每批条数',
              child: Row(
                children: [
                  batch,
                  const SizedBox(width: AppSpacing.s2 + 2),
                  Expanded(child: batchHint),
                ],
              ),
            ),
          ),
          guidance,
        ],
      ],
    );
  }
}
