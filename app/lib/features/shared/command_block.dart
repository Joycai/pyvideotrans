import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';

/// 等宽的命令块。可选中复制，自动换行。
///
/// 设计稿里两处样式不同：转码页的预览是 surface-container 底、复制按钮压在
/// 右上角（传 [onCopy]）；详情面板里是 surface-container-lowest 底、复制放在
/// 分区标题行。
class CommandBlock extends StatelessWidget {
  const CommandBlock({
    super.key,
    required this.command,
    this.maxHeight = 140,
    this.onCopy,
    this.lowest = false,
  });

  final String command;
  final double maxHeight;
  final VoidCallback? onCopy;
  final bool lowest;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s2 + 2,
            onCopy == null ? AppSpacing.s3 : 40,
            AppSpacing.s2 + 2,
          ),
          decoration: BoxDecoration(
            color: lowest ? cs.surfaceContainerLowest : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              command,
              style: kTimecodeStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        if (onCopy != null)
          Positioned(
            top: 3,
            right: 3,
            child: IconActionButton(
              icon: Symbols.content_copy,
              tooltip: '复制命令',
              size: 32,
              iconSize: 18,
              onPressed: onCopy,
            ),
          ),
      ],
    );
  }
}
