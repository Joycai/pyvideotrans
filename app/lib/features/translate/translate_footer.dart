import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../shared/provider_fields.dart';
import 'translate_form.dart';

/// 文件区顶部那条中性提示：忽略了几个音视频，右侧「改用新建转写」把它们带走。
/// 用 surface-container 而不是 error —— 拖错门不是错误。
class IgnoredMediaNote extends StatelessWidget {
  const IgnoredMediaNote({
    super.key,
    required this.text,
    this.onSwitchToTranscribe,
  });

  final String text;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.block,
            size: 18,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onSwitchToTranscribe != null) ...[
            const SizedBox(width: AppSpacing.s2),
            LinkText(
              label: '改用新建转写',
              color: cs.primary,
              onTap: onSwitchToTranscribe!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 页脚那行校验文案：图标 + 文字，阻断用 error 色。
class TranslateFooterLine extends StatelessWidget {
  const TranslateFooterLine({super.key, required this.form, this.line});

  final TranslateFormController form;

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

/// 「开始翻译」。页面上带数量，对话框不带 —— 对话框的文件区就在按钮上方。
class TranslateStartButton extends StatelessWidget {
  const TranslateStartButton({
    super.key,
    required this.form,
    required this.onStart,
    this.withCount = false,
  });

  final TranslateFormController form;
  final VoidCallback onStart;
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final n = form.enqueueable.length;
    return PrimaryButton(
      label: withCount ? '开始翻译 · $n' : '开始翻译',
      icon: Symbols.translate,
      onPressed: form.canStart ? onStart : null,
    );
  }
}
