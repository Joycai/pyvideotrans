import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../shared/provider_fields.dart';
import 'translate_form.dart';

/// 「翻译」段：语言对（可对换）、翻译服务、模型、每批条数、术语表、就绪状态行。
class TranslateLanguageSection extends StatelessWidget {
  const TranslateLanguageSection({
    super.key,
    required this.form,
    this.onOpenSettings,
    this.flat = false,
  });

  final TranslateFormController form;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字。
  final VoidCallback? onOpenSettings;

  /// 平铺（页面）还是卡片（对话框）。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final info = Registry.translationInfo(o.translationProviderId);
    final readiness = form.readiness;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    // 原文 ⇄ 目标放同一行，中间一个对换按钮：这是整段最该被一眼看懂的信息。
    final languages = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: '原文语言',
            child: AppDropdown<String>(
              value: o.sourceLanguage.code,
              groups: [
                DropdownGroup(
                  entries: [
                    for (final l in Languages.source)
                      DropdownEntry(value: l.code, label: l.name),
                  ],
                ),
              ],
              onChanged: (code) => form.update(
                (o) => o.copyWith(sourceLanguage: Languages.resolve(code)),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2 + 2),
        _SwapLanguagesButton(form: form),
        const SizedBox(width: AppSpacing.s2 + 2),
        Expanded(
          child: LabeledField(
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
          ),
        ),
      ],
    );
    final service = LabeledField(
      label: '翻译服务',
      child: AppDropdown<String>(
        value: o.translationProviderId,
        error: readiness.isBlocked,
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
      '一次送给模型的字幕条数。调大省 token，但更容易漏条或合并。范围 1–100。',
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
      label: '术语表与风格（可选）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MultilineField(
            value: o.translationGuidance,
            hint: 'Ballistic Missile Defense=反导系统\n保持口语，不要书面化',
            onChanged: (v) => form.update(
              (o) => o.copyWith(translationGuidance: v),
              notify: false,
            ),
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            '术语一行一条，写成「原文=译文」；其余行当作风格要求。仅用于本次任务。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final status = ReadinessLine(
      readiness: readiness,
      needsApiKey: info?.needsApiKey ?? true,
      onOpenSettings: onOpenSettings,
    );

    if (flat) {
      return flatSection(
        context,
        divider: false,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s1,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        children: [
          Text(
            '翻译',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          languages,
          twoColumn(service, model, gap: gap),
          LabeledField(
            label: '每批条数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                batch,
                const SizedBox(height: AppSpacing.s1 + 2),
                batchHint,
              ],
            ),
          ),
          guidance,
          status,
        ],
      );
    }

    return FormSection(
      title: '翻译',
      gap: 14,
      children: [
        languages,
        twoColumn(service, model),
        LabeledField(
          label: '每批条数',
          child: Row(
            children: [
              batch,
              const SizedBox(width: AppSpacing.s3),
              Expanded(child: batchHint),
            ],
          ),
        ),
        guidance,
        status,
      ],
    );
  }
}

/// 原文 ⇄ 目标的对换按钮。原文为「自动检测」时禁用并说明原因。
class _SwapLanguagesButton extends StatelessWidget {
  const _SwapLanguagesButton({required this.form});

  final TranslateFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = form.canSwapLanguages;
    return Tooltip(
      message: enabled ? '对换原文与目标语言' : '原文为自动检测时不能对换',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? cs.outlineVariant
                  : cs.onSurface.withValues(
                      alpha: AppStateLayer.disabledContainer,
                    ),
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? form.swapLanguages : null,
            child: Ink(
              decoration: enabled
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: context.elevation.controlGradient,
                      ),
                      boxShadow: context.elevation.controlShadow,
                    )
                  : null,
              child: Icon(
                Symbols.swap_horiz,
                size: 20,
                weight: 400,
                color: enabled
                    ? cs.onSurface
                    : cs.onSurface.withValues(
                        alpha: AppStateLayer.disabledContent,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
