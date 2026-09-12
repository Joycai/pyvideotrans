import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../services/local/local_backend.dart';
import '../../services/provider_api.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';

/// 设置页：外观、识别服务、翻译服务、语言、输出目录、本地服务。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings get s => widget.settings;

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
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6,
          vertical: AppSpacing.s5,
        ),
        children: [
          // 内容列限宽并靠左：设置项是一行行的表单，跨满 1440px 会让眼睛来回扫；
          // 左边已经有导航栏了，再居中会把表单推得离视线起点太远。
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: '外观',
                    children: [
                      _Row(
                        label: '主题',
                        hint: '深色主题是单独调校的，不是浅色的反色',
                        child: _Choice(
                          value: s.themeMode,
                          options: const [
                            (value: 'system', label: '跟随系统'),
                            (value: 'light', label: '浅色'),
                            (value: 'dark', label: '深色'),
                          ],
                          onChanged: (v) => setState(() => s.themeMode = v),
                        ),
                      ),
                    ],
                  ),
                  _ProviderSection(
                    title: '识别服务',
                    subtitle: '音视频转字幕',
                    infos: Registry.asr,
                    selectedId: s.asrProviderId,
                    onSelect: (id) => setState(() => s.asrProviderId = id),
                    settings: s,
                    onChanged: () => setState(() {}),
                    extra: _MultilineRow(
                      label: '识别提示',
                      hint: '专有名词、人名、术语。填了能明显提高识别准确率。',
                      value: s.asrPrompt,
                      onChanged: (v) => s.asrPrompt = v,
                    ),
                  ),
                  _ProviderSection(
                    title: '翻译服务',
                    subtitle: '字幕翻译',
                    infos: Registry.translation,
                    selectedId: s.translationProviderId,
                    onSelect: (id) =>
                        setState(() => s.translationProviderId = id),
                    settings: s,
                    onChanged: () => setState(() {}),
                    extra: Column(
                      children: [
                        _Row(
                          label: '每批条数',
                          hint: '一次送给模型多少条字幕。太大模型容易合并或漏掉行，'
                              '太小则费 token。条数对不上时会自动减半重试。',
                          child: Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: s.translationBatchSize.toDouble(),
                                  min: 1,
                                  max: 50,
                                  divisions: 49,
                                  label: '${s.translationBatchSize}',
                                  onChanged: (v) => setState(
                                    () => s.translationBatchSize = v.round(),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                child: Timecode('${s.translationBatchSize}'),
                              ),
                            ],
                          ),
                        ),
                        _MultilineRow(
                          label: '翻译要求',
                          hint: '术语表、语气、人称。会作为补充要求加进提示词。',
                          value: s.translationGuidance,
                          onChanged: (v) => s.translationGuidance = v,
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    title: '语言',
                    children: [
                      _Row(
                        label: '源语言',
                        hint: '填 auto 交给服务端自动判定',
                        child: _Text(
                          value: s.sourceLanguage,
                          onChanged: (v) => s.sourceLanguage = v,
                        ),
                      ),
                      _Row(
                        label: '目标语言',
                        hint: '用自然语言写，例如「英文」「日文」「简体中文」',
                        child: _Text(
                          value: s.targetLanguage,
                          onChanged: (v) => s.targetLanguage = v,
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: '输出',
                    children: [
                      _Row(
                        label: '输出目录',
                        hint: '留空则写到源文件所在目录',
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.outputDir ?? '源文件所在目录',
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: s.outputDir == null
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s2),
                            TextButton(
                              onPressed: () async {
                                final dir = await getDirectoryPath();
                                if (dir != null) {
                                  setState(() => s.outputDir = dir);
                                }
                              },
                              child: const Text('选择…'),
                            ),
                            if (s.outputDir != null)
                              TextButton(
                                onPressed: () =>
                                    setState(() => s.outputDir = null),
                                child: const Text('清除'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const _LocalBackendSection(),
                  const SizedBox(height: AppSpacing.s8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个服务分区：选服务 + 填地址/模型/密钥。
class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.title,
    required this.subtitle,
    required this.infos,
    required this.selectedId,
    required this.onSelect,
    required this.settings,
    required this.onChanged,
    this.extra,
  });

  final String title;
  final String subtitle;
  final List<ProviderInfo> infos;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final AppSettings settings;
  final VoidCallback onChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final info = infos.where((i) => i.id == selectedId).firstOrNull ?? infos.first;
    final config = settings.configFor(info.id);
    final configured = settings.isConfigured(info);

    return _Section(
      title: title,
      subtitle: subtitle,
      trailing: info.implemented
          ? StatusTag(
              label: configured ? '已配置' : '未配置',
              icon: configured ? Symbols.check_circle : Symbols.error,
              tone: configured ? TagTone.success : TagTone.quiet,
            )
          : const StatusTag(label: '第一期未实施', tone: TagTone.quiet),
      children: [
        _Row(
          label: '服务',
          child: DropdownButtonFormField<String>(
            initialValue: info.id,
            isDense: true,
            items: [
              for (final i in infos)
                DropdownMenuItem(
                  value: i.id,
                  child: Row(
                    children: [
                      Icon(
                        i.runsLocally ? Symbols.computer : Symbols.cloud,
                        size: 16,
                        weight: 400,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Text(i.name),
                      if (!i.implemented)
                        Text(
                          ' · 未实施',
                          style: context.texts.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onSelect(v);
            },
          ),
        ),
        _Row(
          label: '服务地址',
          hint: '填到 /v1 为止',
          child: _Text(
            key: ValueKey('${info.id}-url'),
            value: config.baseUrl ?? info.defaultBaseUrl ?? '',
            onChanged: (v) {
              settings.setConfig(info.id, config.copyWith(baseUrl: v));
              onChanged();
            },
          ),
        ),
        _Row(
          label: '模型',
          hint: info.models.isEmpty ? null : '常用：${info.models.join('、')}',
          child: _Text(
            key: ValueKey('${info.id}-model'),
            value: config.model ?? info.defaultModel ?? '',
            onChanged: (v) {
              settings.setConfig(info.id, config.copyWith(model: v));
              onChanged();
            },
          ),
        ),
        if (info.needsApiKey)
          _Row(
            label: 'API 密钥',
            hint: '目前以明文存在本机配置里，还没接系统钥匙串',
            child: _Text(
              key: ValueKey('${info.id}-key'),
              value: config.apiKey ?? '',
              obscure: true,
              onChanged: (v) {
                settings.setConfig(info.id, config.copyWith(apiKey: v));
                onChanged();
              },
            ),
          ),
        ?extra,
      ],
    );
  }
}

class _LocalBackendSection extends StatelessWidget {
  const _LocalBackendSection();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return _Section(
      title: '本地模型服务',
      subtitle: '在自己的机器上跑识别与翻译',
      trailing: const StatusTag(label: '第一期未实施', tone: TagTone.quiet),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本地模型由一个独立的 Python 后端提供服务，对外暴露 OpenAI 兼容接口。'
                '客户端走的是与在线 API 完全相同的链路 —— 不存在「本地」和「在线」'
                '两套代码，流水线、进度、断点续跑、取消、日志全部复用。',
                style: context.texts.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                '启用后只需把服务地址指向本地进程（默认 '
                '${LocalBackend.asrProviderId == 'local_backend' ? 'http://127.0.0.1:8765/v1' : ''}），'
                '再在上面两个分区里选中「本地模型服务」即可。'
                '完整方案见 docs/local-backend.md。',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                children: [
                  Icon(
                    Symbols.info,
                    size: 16,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      '现在就想在本机跑翻译：装 Ollama 或 LM Studio，'
                      '在「翻译服务」里选它们 —— 它们说的也是 OpenAI 兼容协议，已经可用。',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: context.texts.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(width: AppSpacing.s3),
                Text(
                  subtitle!,
                  style: context.texts.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: AppSpacing.s3),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.hint});

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.texts.titleSmall),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint!,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MultilineRow extends StatelessWidget {
  const _MultilineRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
    label: label,
    hint: hint,
    child: TextFormField(
      initialValue: value,
      maxLines: 3,
      minLines: 2,
      style: context.texts.bodyMedium,
      onChanged: onChanged,
    ),
  );
}

class _Text extends StatelessWidget {
  const _Text({
    super.key,
    required this.value,
    required this.onChanged,
    this.obscure = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool obscure;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value,
    obscureText: obscure,
    style: context.texts.bodyMedium,
    onChanged: onChanged,
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SegmentedButton<String>(
      segments: [
        for (final o in options)
          ButtonSegment(value: o.value, label: Text(o.label)),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
    ),
  );
}
