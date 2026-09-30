import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/providers/model_spec.dart';
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/settings.dart';

/// 跨页面共用的「选服务 / 填模型」零件。
///
/// 新建转写、新建翻译、转码页与设置页的服务下拉、模型字段、链接文字长得完全一样，
/// 各写一份必然会走形 —— 改了一边忘了另一边，用户就会看到两个本该相同的控件表现不一致。
/// 放在 features/shared/ 是因为它同时被 transcribe / translate / settings 几个 feature 用，
/// 不属于其中任何一个。整行可点、链接文字、单选行这类不带业务语义的零件在
/// core/widgets/form_layout.dart。

/// 服务下拉分两组：可用的在上，未实施的在下并说明原因。
///
/// 本机跑的服务标一个「本机」——「不花钱、不出网」是用户真正在意的区别。
List<DropdownGroup<String>> providerGroups(
  List<ProviderInfo> all,
  Readiness Function(String id) check,
) {
  DropdownEntry<String> entry(ProviderInfo info) {
    final readiness = check(info.id);
    return DropdownEntry(
      value: info.id,
      label: info.name,
      enabled: info.implemented,
      badge: info.runsLocally ? '本机' : null,
      badgeIcon: info.runsLocally ? Symbols.computer : null,
      description: info.implemented
          ? readiness.isBlocked
                ? readiness.message
                : (info.defaultBaseUrl ?? '').isEmpty
                ? '自行填写地址与模型名'
                : null
          : readiness.hint,
    );
  }

  final available = all.where((i) => i.implemented).map(entry).toList();
  final pending = all.where((i) => !i.implemented).map(entry).toList();
  return [
    DropdownGroup(title: pending.isEmpty ? null : '可用', entries: available),
    if (pending.isNotEmpty) DropdownGroup(title: '第二期未实施', entries: pending),
  ];
}

/// 模型选择。有候选的给下拉，没有候选的给输入框，不能换模型的灰掉并说明。
///
/// 候选是设置里这家服务的模型声明（[AppSettings.modelChoices]）；选中的是整份
/// 声明，不只是名字 —— 接入方式与参数跟着它一起进任务。
Widget modelField<T extends ModelSpec>({
  required ProviderInfo? info,
  required T model,
  required AppSettings settings,
  required ValueChanged<T> onChanged,
}) {
  if (info == null || !info.implemented) {
    return LabeledField(
      label: '模型',
      enabled: false,
      child: AppDropdown<String>(
        value: '',
        enabled: false,
        display: '该服务暂不支持切换模型',
        groups: const [],
        onChanged: (_) {},
      ),
    );
  }
  // 识别服务配识别模型、翻译服务配翻译模型：[info] 与 [T] 由调用方成对给，
  // 这里按 T 取一遍，种类对不上的声明不会混进候选。
  final candidates = settings.modelChoices(info).whereType<T>().toList();
  if (_typedByHand(info, candidates, settings)) {
    final example = info.presets.firstOrNull?.name ?? '';
    return LabeledField(
      label: '模型',
      // 没有候选可列，只能让用户自己写；清空即回到设置里的默认模型。
      child: SingleLineField(
        value: model.name,
        hint: example.isEmpty ? '填写模型名' : '填写模型名，例 $example',
        onChanged: (v) {
          final typed = v.trim().isEmpty
              ? settings.defaultModel(info)
              : info.guess(v);
          if (typed is T) onChanged(typed);
        },
      ),
    );
  }
  // 「上次参数」可能带来一个已不在候选里的模型：照样列出来，别让下拉崩掉。
  final entries = [
    if (!candidates.any((m) => m.name == model.name)) model,
    ...candidates,
  ];
  return LabeledField(
    label: '模型',
    child: AppDropdown<String>(
      value: model.name,
      groups: [
        DropdownGroup(
          entries: [
            for (final m in entries)
              DropdownEntry(
                value: m.name,
                label: m.isUnset ? '未选择' : m.name,
              ),
          ],
        ),
      ],
      onChanged: (name) =>
          onChanged(entries.firstWhere((m) => m.name == name)),
    ),
  );
}

/// 这家服务的模型是不是靠手填。
///
/// 自定义接口、LM Studio 没有候选，只能手填。另有一种过渡情形：硅基流动
/// 翻译、OpenRouter、Ollama 只登记了一个预置，那只是个例子，模型本来就是
/// 用户自己挑的 —— 用户没在设置里配过时照旧给输入框，否则下拉里只有那一项，
/// 想换模型得先绕去设置。下拉有了「其他模型…」之后这一条去掉。
bool _typedByHand(
  ProviderInfo info,
  List<ModelSpec> candidates,
  AppSettings settings,
) =>
    candidates.isEmpty ||
    (info is ChatProviderInfo &&
        candidates.length == 1 &&
        !settings.hasOwnModels(info.id));

/// 服务就绪状态行：图标 + 一句话，阻断时 error 色并附「去设置」。
class ReadinessLine extends StatelessWidget {
  const ReadinessLine({
    super.key,
    required this.readiness,
    required this.needsApiKey,
    this.onOpenSettings,
  });

  final Readiness readiness;

  /// 就绪时用来区分「已配置密钥」与「无需密钥」两句。
  final bool needsApiKey;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final error = readiness.isBlocked;
    final color = error ? cs.error : cs.onSurfaceVariant;
    final icon = switch (readiness.level) {
      ReadinessLevel.ready => Symbols.check_circle,
      ReadinessLevel.advisory => Symbols.schedule,
      ReadinessLevel.blocked => Symbols.error,
    };
    return Row(
      children: [
        Icon(icon, size: 16, weight: 400, color: color),
        const SizedBox(width: AppSpacing.s1 + 2),
        Flexible(
          child: Text(
            readiness.isReady
                ? needsApiKey
                      ? '已配置密钥，可直接开始'
                      : '无需密钥，可直接开始'
                : [
                    readiness.message,
                    if (!error) readiness.hint,
                  ].nonNulls.join('。'),
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
        if (error && onOpenSettings != null) ...[
          const SizedBox(width: AppSpacing.s2),
          LinkText(label: '去设置', color: color, onTap: onOpenSettings!),
        ],
      ],
    );
  }
}

/// 服务下拉上显示的「服务 · 模型」。还没选模型时只有服务名。
String serviceLabel(ProviderInfo? info, ModelSpec model) {
  if (info == null) return '—';
  return model.isUnset ? info.name : '${info.name} · ${model.name}';
}
