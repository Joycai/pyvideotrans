import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';

/// 入队成功的横幅：三个建任务页共用一份。
///
/// 用 success 而不是 primary —— 这一步是「已经排上了」，不是「继续往下走」。
class EnqueuedBanner extends StatelessWidget {
  const EnqueuedBanner({
    super.key,
    required this.count,
    required this.onOpenTasks,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final fg = ext.onSuccessContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.s2),
      decoration: BoxDecoration(
        color: ext.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Symbols.check_circle, size: 20, weight: 400, color: ext.success),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('已加入队列 ', style: context.texts.bodyMedium?.copyWith(color: fg)),
          Timecode('$count', color: fg),
          Text(
            ' 个任务，按列表顺序排队',
            style: context.texts.bodyMedium?.copyWith(color: fg),
          ),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('·', style: TextStyle(color: fg.withValues(alpha: 0.5))),
          const SizedBox(width: AppSpacing.s2 + 2),
          LinkText(label: '查看任务', color: fg, onTap: onOpenTasks),
          const Spacer(),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '关闭',
            iconSize: 18,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
