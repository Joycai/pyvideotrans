import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import 'translate_footer.dart';
import 'translate_form.dart';

/// 文件区顶部的提示条：忽略了音视频（带「改用新建转写」）、不认识的格式（可关）。
class TranslateFileNotes extends StatelessWidget {
  const TranslateFileNotes({
    super.key,
    required this.form,
    this.onSwitchToTranscribe,
  });

  final TranslateFormController form;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ignored = form.ignoredNote;
    final rejected = form.dropError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ignored != null) ...[
          IgnoredMediaNote(
            text: ignored,
            onSwitchToTranscribe: onSwitchToTranscribe,
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        if (rejected != null) ...[
          Container(
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
                    rejected,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconActionButton(
                  icon: Symbols.close,
                  tooltip: '关闭',
                  size: 28,
                  iconSize: 16,
                  onPressed: form.clearDropError,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
      ],
    );
  }
}
