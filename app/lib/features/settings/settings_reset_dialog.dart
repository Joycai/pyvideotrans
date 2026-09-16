import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/buttons.dart';
import 'section_outline.dart';

enum ResetChoice { current, all }

/// 「恢复默认」的二次确认。沿用 20px 圆角的玻璃浮层。
class SettingsResetDialog extends StatelessWidget {
  const SettingsResetDialog({
    super.key,
    required this.current,
    required this.hasGroup,
  });

  final SettingsSectionKey current;

  /// 当前分区有没有可重置的东西（「本地服务」没有）。
  final bool hasGroup;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return AlertDialog(
      title: const Text('恢复默认设置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          '全部恢复会清掉所有服务的地址、模型与 API 密钥，并把语言、'
          '任务默认值、输出目录、主题都退回初始值。已排队的任务不受影响。',
          style: context.texts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      actions: [
        QuietButton(label: '取消', onPressed: () => Navigator.pop(context)),
        if (hasGroup)
          ControlButton(
            label: '仅「${current.title}」',
            onPressed: () => Navigator.pop(context, ResetChoice.current),
          ),
        ControlButton(
          label: '全部恢复',
          onPressed: () => Navigator.pop(context, ResetChoice.all),
        ),
      ],
    );
  }
}
