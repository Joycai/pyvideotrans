import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/glossary.dart';

/// 建任务时勾选词表的一行筹码（设计稿 C-TaskFields · GlossaryChips），
/// 转写与翻译共用。
///
/// 勾的是「用哪几份」，不是内容：条目在提交那一刻才展开进任务参数，
/// 取的就是提交时词表里的内容。
class GlossaryChips extends StatelessWidget {
  const GlossaryChips({
    super.key,
    required this.glossaries,
    required this.selectedIds,
    required this.onToggle,
    this.note,
    this.onOpenSettings,
  });

  /// 设置里的全部词表。空的也列出来（数字是 0）：用户可能正要往里加。
  final List<Glossary> glossaries;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  /// 筹码下面的一句说明（当前模型不接受提示）。筹码不因此禁用 ——
  /// 接着的翻译仍然会用。
  final String? note;

  /// 还没有词表时那个「去设置里建一个」。为 null 时整句是纯文字。
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final open = onOpenSettings;
    return LabeledField(
      label: '词表',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glossaries.isEmpty)
            open == null
                ? Text('还没有词表，可在设置里新建', style: muted)
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('还没有词表 · ', style: muted),
                      LinkText(
                        label: '去设置里建一个',
                        color: cs.primary,
                        onTap: open,
                      ),
                    ],
                  )
          else
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s2,
              children: [
                for (final glossary in glossaries)
                  FilterChipButton(
                    label: glossary.name,
                    count: glossary.entries.length,
                    selected: selectedIds.contains(glossary.id),
                    onTap: () => onToggle(glossary.id),
                  ),
              ],
            ),
          if (note case final note? when glossaries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s1 + 2),
            InlineNote(text: note),
          ],
        ],
      ),
    );
  }
}
