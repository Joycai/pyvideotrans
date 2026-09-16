import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../services/local/local_backend.dart';
import '../../services/registry.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 本地模型服务：第一期未实施，用一张说明卡讲清楚「同一条链路」。
class LocalBackendSection extends StatelessWidget {
  const LocalBackendSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = context.texts.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return SettingsSection(
      section: SettingsSectionKey.local,
      tag: const StatusTag(label: '第一期未实施', tone: TagTone.muted),
      children: [
        Container(
          margin: const EdgeInsets.only(top: AppSpacing.s3),
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('本地后端与在线 API 走同一条链路', style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.s2 + 2),
              Text.rich(
                TextSpan(
                  style: muted,
                  children: [
                    const TextSpan(text: '后续版本会在本机启动一个 OpenAI 兼容服务，默认地址 '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Timecode(
                        Registry.asrInfo(LocalBackend.asrProviderId)
                                ?.defaultBaseUrl ??
                            'http://127.0.0.1:8765/v1',
                      ),
                    ),
                    const TextSpan(
                      text:
                          '。届时在上面两个「服务」下拉里直接选「本地模型服务」，'
                          '服务地址、模型、提示词这几行的含义完全一致，不需要另学一套设置。',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s2 + 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2 + 2,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.info,
                      size: 18,
                      weight: 400,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        '现在就想在本机跑翻译：到「翻译服务」里选 Ollama 或 LM Studio，填本机地址，不需要密钥。',
                        style: context.texts.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
