import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
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
/// 候选来自设置里逗号分隔的那串（[AppSettings.modelsFor]），没填才用登记表的
/// 常用列表。下拉的当前值与实际发出去的模型一致：任务里没覆盖时就是设置里
/// 的第一个 —— 之前这里显示登记表默认值，而请求却用设置里的值，两处对不上。
Widget modelField({
  required ProviderInfo? info,
  required String? model,
  required AppSettings settings,
  required ValueChanged<String?> onChanged,
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
  final candidates = settings.modelsFor(info);
  if (candidates.isEmpty) {
    final example = info.defaultModel ?? '';
    return LabeledField(
      label: '模型',
      // 自定义接口没有候选可列，只能让用户自己写；清空即回到设置里的默认模型。
      child: SingleLineField(
        value: model ?? settings.endpointFor(info).model,
        hint: example.isEmpty ? '填写模型名' : '填写模型名，例 $example',
        onChanged: (v) => onChanged(v.trim().isEmpty ? null : v.trim()),
      ),
    );
  }
  final current = resolvedModel(info, model, settings);
  // 「上次参数」可能带来一个已不在候选里的模型名：照样列出来，别让下拉崩掉。
  final entries = [if (!candidates.contains(current)) current, ...candidates];
  return LabeledField(
    label: '模型',
    child: AppDropdown<String>(
      value: current,
      groups: [
        DropdownGroup(
          entries: [for (final m in entries) DropdownEntry(value: m, label: m)],
        ),
      ],
      onChanged: onChanged,
    ),
  );
}

/// 这次任务实际会用的模型名：任务里覆盖的优先，否则是设置解析出来的。
String resolvedModel(ProviderInfo info, String? model, AppSettings settings) {
  final chosen = model?.trim() ?? '';
  return chosen.isNotEmpty ? chosen : settings.endpointFor(info).model;
}

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

String serviceLabel(ProviderInfo? info, String? model, AppSettings settings) {
  if (info == null) return '—';
  final chosen = resolvedModel(info, model, settings);
  return chosen.isEmpty ? info.name : '${info.name} · $chosen';
}
