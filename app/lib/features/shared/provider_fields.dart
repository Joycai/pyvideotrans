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
/// 放在 features/shared/ 是因为它同时被 tasks / transcode / settings 三个 feature 用，
/// 不属于其中任何一个。

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
      child: ModelTextField(
        value: model ?? settings.endpointFor(info).model,
        hint: example.isEmpty ? '填写模型名' : '填写模型名，例 $example',
        onChanged: onChanged,
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

/// 自定义接口的模型名：没有候选可列，只能让用户自己写。
class ModelTextField extends StatefulWidget {
  const ModelTextField({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final ValueChanged<String?> onChanged;

  @override
  State<ModelTextField> createState() => _ModelTextFieldState();
}

class _ModelTextFieldState extends State<ModelTextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControlSurface(
    focused: _focus.hasFocus,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      style: context.texts.bodyMedium,
      decoration: bareInputDecoration(context, hint: widget.hint),
      onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
    ),
  );
}

/// 整行可点：设计稿里开关和「高级」标题的热区都是一整行，不是那个小控件。
class Tappable extends StatelessWidget {
  const Tappable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}

/// 设计稿里「去设置」「改用新建转写」都是链接，不是按钮。
class LinkText extends StatelessWidget {
  const LinkText({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    ),
  );
}


/// 左右两列等宽。
Widget twoColumn(Widget left, Widget right, {double gap = AppSpacing.s4}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );

/// 页面参数面板里的平铺段：上方 1px 分隔线 + 16px 内边距。
/// 对话框里每段是一张卡片（FormSection），页面里三段平铺、用分隔线隔开。
Widget flatSection(
  BuildContext context, {
  required List<Widget> children,
  double gap = AppSpacing.s3,
  bool divider = true,
  EdgeInsets padding = const EdgeInsets.all(AppSpacing.s4),
}) => Container(
  padding: padding,
  decoration: divider
      ? BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.outlineVariant)),
        )
      : null,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) SizedBox(height: gap),
        child,
      ],
    ],
  ),
);

/// 竖排单选的一行：圆点 + 文字 + 可选的尾随内容（比如已选目录）。
class RadioRow extends StatelessWidget {
  const RadioRow({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Tappable(
      onTap: onTap,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? cs.primary : cs.outline,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Text(label, style: context.texts.bodyMedium),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s1),
              Flexible(child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
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
