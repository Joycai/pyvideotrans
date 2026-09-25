import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/task_options.dart';
import 'transcribe_form.dart';

/// 「高级」段：可折叠；识别提示词、每行字数、输出格式与位置。
class TranscribeAdvancedSection extends StatelessWidget {
  const TranscribeAdvancedSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranscribeFormController form;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final open = form.advancedOpen;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final header = Tappable(
      onTap: () => form.advancedOpen = !open,
      child: Row(
        children: [
          Icon(
            open ? Symbols.expand_more : Symbols.chevron_right,
            size: 18,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '高级',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (!open)
            Flexible(
              child: Text(
                flat ? form.compactAdvancedSummary : form.advancedSummary,
                textAlign: TextAlign.right,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    final prompt = LabeledField(
      label: '识别提示词（可选）',
      child: MultilineField(
        value: o.asrPrompt,
        minHeight: 56,
        hint: '列出专有名词，帮助识别固定写法。例：SenseVoice、字幕组、whisper-large-v3',
        onChanged: (v) =>
            form.update((o) => o.copyWith(asrPrompt: v), notify: false),
      ),
    );
    final lengths = twoColumn(
      LabeledField(
        label: '每行最大字符数 · 中日韩',
        child: NumberField(
          value: o.cjkLineLength,
          min: 4,
          max: 60,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(cjkLineLength: v)),
        ),
      ),
      LabeledField(
        label: '每行最大字符数 · 其他语言',
        child: NumberField(
          value: o.latinLineLength,
          min: 8,
          max: 120,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(latinLineLength: v)),
        ),
      ),
      gap: gap,
    );
    final format = LabeledField(
      label: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<SubtitleFormat>(
            value: o.format,
            onChanged: (f) => form.update((o) => o.copyWith(format: f)),
            segments: [
              for (final f in SubtitleFormat.values)
                (
                  value: f,
                  label: f.extension.toUpperCase(),
                  enabled: f.implemented,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            'ASS 需要一整套字幕样式配置，留到第二期。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          header,
          if (open) ...[
            prompt,
            lengths,
            format,
            _OutputLocationRadios(form: form),
          ],
        ],
      );
    }

    return FormSection(
      gap: 14,
      children: [
        header,
        if (open) ...[
          Container(height: 1, color: cs.outlineVariant),
          prompt,
          lengths,
          format,
          LabeledField(
            label: '输出位置',
            child: Row(
              children: [
                SegmentedToggle<OutputLocation>(
                  value: o.outputLocation,
                  onChanged: (v) {
                    form.update((o) => o.copyWith(outputLocation: v));
                    if (v == OutputLocation.custom &&
                        form.options.outputDir == null) {
                      form.pickOutputDir();
                    }
                  },
                  segments: [
                    for (final v in OutputLocation.values)
                      (value: v, label: v.label, enabled: true),
                  ],
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: GestureDetector(
                    onTap: form.pickOutputDir,
                    child: Text(
                      o.outputLocation == OutputLocation.custom
                          ? (o.outputDir ?? '点此选择目录…')
                          : '与源文件同一个文件夹',
                      style: AppTextStyles.timecode.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 页面版的「输出位置」：两个单选 + 命名规则说明。
/// 面板只有 400 宽，分段开关加路径挤不下，竖排的单选把路径放在自己那行。
class _OutputLocationRadios extends StatelessWidget {
  const _OutputLocationRadios({required this.form});

  final TranscribeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final custom = o.outputLocation == OutputLocation.custom;
    final mono = AppTextStyles.timecode.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '输出位置',
          style: context.texts.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        RadioRow(
          selected: !custom,
          label: OutputLocation.besideSource.label,
          onTap: () => form.update(
            (o) => o.copyWith(outputLocation: OutputLocation.besideSource),
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        RadioRow(
          selected: custom,
          label: OutputLocation.custom.label,
          trailing: custom
              ? GestureDetector(
                  onTap: form.pickOutputDir,
                  child: Text(
                    o.outputDir ?? '点此选择目录…',
                    style: mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          onTap: () {
            form.update(
              (o) => o.copyWith(outputLocation: OutputLocation.custom),
            );
            if (form.options.outputDir == null) form.pickOutputDir();
          },
        ),
        const SizedBox(height: AppSpacing.s2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: form.outputNameExample,
                style: mono,
              ),
              const TextSpan(text: '，同名文件会被覆盖'),
            ],
          ),
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
