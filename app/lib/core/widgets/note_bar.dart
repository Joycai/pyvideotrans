import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';
import 'buttons.dart';

/// 36px 的中性提示条：图标 + 单行说明，右侧可带一个动作或关闭按钮。
///
/// 用 surface-container 而不是 error 色 —— 放在这里的都是「告诉你发生了什么」
/// （拖错了门、格式不认识），不是出错。
class NoteBar extends StatelessWidget {
  const NoteBar({
    super.key,
    required this.text,
    this.icon = Symbols.block,
    this.action,
    this.onClose,
  });

  final String text;
  final IconData icon;

  /// 说明后面的动作（通常是一个文字链接），与正文隔 8px。
  final Widget? action;

  /// 给了就在最右放一个「关闭」。
  final VoidCallback? onClose;

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
          Icon(icon, size: 18, weight: 400, color: cs.onSurfaceVariant),
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
          if (action != null) ...[
            const SizedBox(width: AppSpacing.s2),
            action!,
          ],
          if (onClose != null)
            IconActionButton(
              icon: Symbols.close,
              tooltip: '关闭',
              size: 28,
              iconSize: 16,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
