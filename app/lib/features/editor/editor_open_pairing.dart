import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/subtitle_pairing.dart';
import 'editor_open_form.dart';
import 'editor_widgets.dart';

class EditorPairingBlock extends StatelessWidget {
  const EditorPairingBlock({super.key, required this.form});

  final EditorOpenForm form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final p = form.pairing;
    if (p == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Symbols.link,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '两份都添加后，会在这里检查能不能逐条对上',
                style: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final alarm = !p.plausible;
    final note = form.pairingNote;
    final stats = [
      (p.paired, '条逐条对上'),
      (p.sourceOnly, '条原文没有译文，显示为「未翻译」'),
      (p.translationOnly, '条译文找不到原文，单独成行，标「未配对」'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Text('配对', style: context.texts.titleSmall),
              const Spacer(),
              MiniSegmented<PairingMode>(
                value: p.mode,
                onChanged: form.setMode,
                segments: const [
                  (value: PairingMode.byTime, label: '按时间轴'),
                  (value: PairingMode.byIndex, label: '按序号'),
                ],
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (n, label)) in stats.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Timecode(
                        '$n',
                        fontSize: 20,
                        color: i == 0 && alarm ? cs.error : cs.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: context.texts.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (p.mergedTranslations > 0)
            Text(
              '其中 ${p.mergedTranslations} 条译文并进了同一条原文',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (alarm)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.s2),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.error,
                    size: 18,
                    weight: 400,
                    color: cs.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      '时间轴基本对不上，可能不是同一个视频的字幕',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (note != null)
            Text(
              note,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
