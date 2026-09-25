import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import 'transcribe_form.dart';

/// 页脚那行校验文案：图标 + 文字，阻断用 error 色。
class TranscribeFooterLine extends StatelessWidget {
  const TranscribeFooterLine({super.key, required this.form, this.line});

  final TranscribeFormController form;

  /// 页面在拖放拒收时用中性色的说明顶替控制器里的 error 版本。
  final ({String text, IconData icon, bool error})? line;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final foot = line ?? form.footer;
    final color = foot.error ? cs.error : cs.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(foot.icon, size: 16, weight: 400, color: color),
        const SizedBox(width: AppSpacing.s1 + 2),
        Expanded(
          child: Text(
            foot.text,
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 「开始转写」。页面上带数量，对话框不带 —— 对话框的文件区就在按钮上方。
class TranscribeStartButton extends StatelessWidget {
  const TranscribeStartButton({
    super.key,
    required this.form,
    required this.onStart,
    this.withCount = false,
  });

  final TranscribeFormController form;
  final VoidCallback onStart;
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final n = form.enqueueable.length;
    return PrimaryButton(
      label: withCount ? '开始转写 · $n' : '开始转写',
      icon: Symbols.mic,
      onPressed: form.canStart ? onStart : null,
    );
  }
}
