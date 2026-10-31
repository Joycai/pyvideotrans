import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import 'editor_controller.dart';
import 'editor_keys.dart';
import 'inspector_speaker_field.dart';
import 'selection_ranges.dart';

/// 多选时的检视面板：只剩能批量做的事 —— 目前是改说话人。
class InspectorSelectionEditor extends StatelessWidget {
  const InspectorSelectionEditor({
    super.key,
    required this.controller,
    this.onManageSpeakers,
  });

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final cues = controller.document.cues;
    final numbers = [
      for (final p in controller.selectedPositions) cues[p].index,
    ];

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s4,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s1,
            children: [
              Row(
                children: [
                  Text(
                    '已选 ${numbers.length} 条字幕',
                    style: context.texts.titleSmall,
                  ),
                  const Spacer(),
                  QuietButton(
                    label: '取消多选',
                    icon: Symbols.close,
                    height: 24,
                    onPressed: controller.clearMultiSelection,
                  ),
                ],
              ),
              Text(
                selectionRanges(numbers),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.timecode.copyWith(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          InspectorSpeakerField(
            controller: controller,
            onManageSpeakers: onManageSpeakers,
          ),
          Text(
            'Shift+点击或 '
            '${EditorKeys.extendPrevious.label()} ${EditorKeys.extendNext.label()} '
            '选连续范围，${primaryModifierLabel()}+点击加选或取消；'
            '数字键 1–9 直接指派，'
            '${EditorKeys.exitMultiSelect.label()} 退出多选',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
