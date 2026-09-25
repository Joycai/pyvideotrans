import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../shared/provider_fields.dart';
import 'transcribe_form.dart';

/// 「识别」段：语音语言、识别服务、模型、就绪状态行。
class TranscribeRecognizeSection extends StatelessWidget {
  const TranscribeRecognizeSection({
    super.key,
    required this.form,
    this.onOpenSettings,
    this.flat = false,
  });

  final TranscribeFormController form;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  /// 平铺（页面）还是卡片（对话框）。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final info = Registry.asrInfo(o.asrProviderId);
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
        display: serviceLabel(info, o.asrModel, form.settings),
        groups: providerGroups(
          Registry.asr,
          (id) => ProviderReadiness.asr(id, form.settings),
        ),
        onChanged: form.selectAsrProvider,
      ),
    );
    final model = modelField(
      info: info,
      model: o.asrModel,
      settings: form.settings,
      onChanged: (m) => form.update((o) => o.copyWith(asrModel: m)),
    );
    final status = ReadinessLine(
      readiness: readiness,
      needsApiKey: info?.needsApiKey ?? true,
      onOpenSettings: onOpenSettings,
    );
    // 只有支持的服务才有这个开关；不支持的连灰掉的都不给，免得用户去找原因。
    final diarize = info != null && info.supportsDiarization
        ? _DiarizeToggle(form: form)
        : null;

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
                  on
                      ? '按说话人切开字幕并标上「说话人1：」；多人会议、访谈适用。'
                            '需选 qwen-audio-3.0-asr-flash-filetrans 模型。'
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
