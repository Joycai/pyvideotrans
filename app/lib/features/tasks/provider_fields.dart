import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/fields.dart';
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/settings.dart';

/// 「新建转写」与「新建翻译」共用的几个零件。
///
/// 两个对话框的服务下拉、模型字段、链接文字长得完全一样，各写一份必然会走形 ——
/// 改了一边忘了另一边，用户就会看到两个本该相同的控件表现不一致。

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

/// 模型选择。能列模型的给下拉，自定义接口给输入框，不能换模型的灰掉并说明。
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
  if (info.models.isEmpty) {
    final example = info.defaultModel ?? '';
    return LabeledField(
      label: '模型',
      child: ModelTextField(
        value: model ?? settings.configFor(info.id).model ?? '',
        hint: example.isEmpty ? '填写模型名' : '填写模型名，例 $example',
        onChanged: onChanged,
      ),
    );
  }
  final current = model ?? info.defaultModel ?? info.models.first;
  return LabeledField(
    label: '模型',
    child: AppDropdown<String>(
      value: current,
      groups: [
        DropdownGroup(
          entries: [
            for (final m in info.models) DropdownEntry(value: m, label: m),
          ],
        ),
      ],
      onChanged: onChanged,
    ),
  );
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

/// 千位分隔。字幕动辄上千条，`2416` 和 `2,416` 的可读性差得很远。
String grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
