import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../domain/providers/provider_catalog.dart';
import '../../services/readiness.dart';
import '../shared/glossary_chips.dart';
import '../shared/provider_fields.dart';
import 'transcribe_form.dart';

/// 「识别」段：语音语言、识别服务、模型、说话人分离、词表、就绪状态行。
class TranscribeRecognizeSection extends StatelessWidget {
  const TranscribeRecognizeSection({
    super.key,
    required this.form,
    this.onOpenSettings,
    this.onOpenGlossary,
    this.flat = false,
  });

  final TranscribeFormController form;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  /// 还没有词表时那个「去设置里建一个」，落到设置页的「词表」分区。
  final VoidCallback? onOpenGlossary;

  /// 平铺（页面）还是卡片（对话框）。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final info = ProviderCatalog.asrInfo(o.asrProviderId);
    final readiness = form.asrReadiness;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final language = LabeledField(
      label: '语音语言',
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
    );
    final service = LabeledField(
      label: '识别服务',
      child: AppDropdown<String>(
        value: o.asrProviderId,
        error: readiness.isBlocked,
        display: serviceLabel(info, o.asrModel),
        groups: providerGroups(
          ProviderCatalog.asr,
          (id) => ProviderReadiness.asr(id, form.settings),
        ),
        onChanged: form.selectAsrProvider,
      ),
    );
    final model = ModelField(
      key: ValueKey('asr-model-${form.revision}'),
      info: info,
      model: o.asrModel,
      settings: form.settings,
      onOpenSettings: onOpenSettings,
      onChanged: (m) => form.update((o) => o.copyWith(asrModel: m)),
    );
    final status = ReadinessLine(
      readiness: readiness,
      needsApiKey: info?.needsApiKey ?? true,
      onOpenSettings: onOpenSettings,
    );
    final capabilities = o.asrModel.capabilities;
    // 选中的模型能分离说话人才有这个开关；不能的连灰掉的都不给，免得
    // 用户去找原因。模型换成不能分离的那一刻，表单会把开关关掉
    // （[TranscribeFormController.normalize]），不会留下看不见又开着的。
    final diarize = capabilities.diarization
        ? _DiarizeToggle(form: form)
        : null;
    // 识别与接着的翻译共用这一行勾选。
    final glossary = GlossaryChips(
      glossaries: form.settings.glossaries,
      selectedIds: o.glossaryIds.toSet(),
      onToggle: form.toggleGlossary,
      onOpenSettings: onOpenGlossary,
      // 没开「继续翻译」时这次任务里没有翻译：词表要等之后在编辑器里
      // 补翻才用得上，别说成「接着翻译」。
      note: capabilities.contextPrompt
          ? null
          : o.translate
          ? '当前模型不接受上下文提示，识别时不会发送词表与识别提示；'
                '接着翻译时仍会用词表。'
          : '当前模型不接受上下文提示，识别时不会发送词表与识别提示；'
                '之后在编辑器里翻译时仍会用词表。',
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
            '识别',
            style: context.texts.titleSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          twoColumn(language, service, gap: gap),
          model,
          ?diarize,
          glossary,
          status,
        ],
      );
    }

    return FormSection(
      title: '识别',
      children: [
        twoColumn(language, service),
        const SizedBox(height: AppSpacing.s3),
        twoColumn(
          model,
          info != null && !info.implemented
              ? Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                    child: Text(
                      '模型随识别服务变化，自定义接口可自行填写模型名',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (diarize != null) ...[
          const SizedBox(height: AppSpacing.s3),
          diarize,
        ],
        const SizedBox(height: AppSpacing.s3),
        glossary,
        const SizedBox(height: AppSpacing.s2),
        status,
      ],
    );
  }
}

/// 说话人分离开关：开关 + 一句说明。样子照「转写完成后继续翻译」那一行。
class _DiarizeToggle extends StatelessWidget {
  const _DiarizeToggle({required this.form});

  final TranscribeFormController form;

  @override
  Widget build(BuildContext context) {
    final on = form.options.diarize;
    final cs = context.colors;
    return Tappable(
      onTap: () => form.update((o) => o.copyWith(diarize: !on)),
      child: Row(
        children: [
          AppSwitch(
            value: on,
            onChanged: (v) => form.update((o) => o.copyWith(diarize: v)),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('说话人分离', style: context.texts.titleSmall),
                const SizedBox(height: 1),
                Text(
                  // 时间码从哪来取自选中模型的能力，不写死某个模型的名字。
                  on
                      ? '按说话人切开字幕并标上「说话人1：」；多人会议、访谈适用。'
                            '时间码取自'
                            '${form.options.asrModel.capabilities.timing}。'
                      : '区分多位说话人，给每条字幕标上说话人编号',
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
  }
}
