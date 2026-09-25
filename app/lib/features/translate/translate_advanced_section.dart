import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/task_options.dart';
import 'translate_form.dart';

/// 「高级」段：可折叠；输出格式、字幕排版（带预览）、每行字数、输出位置。
class TranslateAdvancedSection extends StatelessWidget {
  const TranslateAdvancedSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranslateFormController form;
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
                form.advancedSummary,
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
    final format = LabeledField(
      label: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<SubtitleFormat>(
            value: o.format,
            fill: flat,
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
            'ASS 需要一整套字幕样式配置，第二期提供。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final lengths = twoColumn(
      LabeledField(
        label: '每行最大字符数 · 中日韩',
        child: NumberField(
          value: o.cjkLineLength,
          min: TaskOptions.cjkLineLengthRange.min,
          max: TaskOptions.cjkLineLengthRange.max,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(cjkLineLength: v)),
        ),
      ),
      LabeledField(
        label: '每行最大字符数 · 其他语言',
        child: NumberField(
          value: o.latinLineLength,
          min: TaskOptions.latinLineLengthRange.min,
          max: TaskOptions.latinLineLengthRange.max,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(latinLineLength: v)),
        ),
      ),
      gap: gap,
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          header,
          if (open) ...[
            format,
            _LayoutField(form: form, fill: true),
            lengths,
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
          format,
          _LayoutField(form: form, fill: false),
          lengths,
          _OutputLocationSegments(form: form),
        ],
      ],
    );
  }
}

/// 字幕排版 + 预览。纯文本没有「两行」的概念，这时整组灰掉并回落到「仅译文」。
class _LayoutField extends StatelessWidget {
  const _LayoutField({required this.form, required this.fill});

  final TranslateFormController form;

  /// 页面里撑满面板宽度；对话框里按内容宽。
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final plain = o.format == SubtitleFormat.txt;
    final layout = o.resolvedBilingual;
    return LabeledField(
      label: '字幕排版',
      enabled: !plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedToggle<BilingualLayout>(
            value: layout,
            fill: fill,
            onChanged: (v) => form.update((o) => o.copyWith(bilingual: v)),
            segments: [
              for (final v in BilingualLayout.values)
                (value: v, label: v.label, enabled: !plain),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          _LayoutPreview(layout: layout),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            plain ? '纯文本不保留双语排版，已回落到「仅译文」' : '双语指同一条字幕里两行文字，不是两个文件。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 排版预览。纯展示，随选择实时变化 —— 让用户不用试跑就知道会得到什么。
/// 仅译文一行，双语两行按所选顺序。
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.layout});

  final BilingualLayout layout;

  static const target = '我们从第二章开始';
  static const source = "We'll start from chapter two";

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = AppTextStyles.timecode.copyWith(
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    final body = AppTextStyles.timecode.copyWith(fontWeight: FontWeight.w400);
    final lines = switch (layout) {
      BilingualLayout.targetOnly => const [target],
      BilingualLayout.targetAbove => const [target, source],
      BilingualLayout.targetBelow => const [source, target],
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('12', style: muted),
          Text('00:01:23,450 --> 00:01:26,100', style: muted),
          for (final line in lines) Text(line, style: body),
        ],
      ),
    );
  }
}

/// 页面版的「输出位置」：两个单选 + 命名规则说明。面板只有 400 宽，
/// 分段开关加路径挤不下，竖排的单选把路径放在自己那行。
class _OutputLocationRadios extends StatelessWidget {
  const _OutputLocationRadios({required this.form});

  final TranslateFormController form;

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
    final small = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
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
          onTap: () => form.chooseOutputLocation(OutputLocation.besideSource),
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
          onTap: () => form.chooseOutputLocation(OutputLocation.custom),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '译文写成 '),
              TextSpan(text: form.outputNameExample, style: mono),
              const TextSpan(text: '，不覆盖原文件'),
            ],
          ),
          style: small,
        ),
        const SizedBox(height: AppSpacing.s1),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '双语时语言段写成 '),
              TextSpan(text: 'en-zh', style: mono),
              const TextSpan(text: '，原文为自动检测时写成 '),
              TextSpan(text: 'src', style: mono),
            ],
          ),
          style: small,
        ),
      ],
    );
  }
}

/// 对话框版的「输出位置」：分段开关，指定目录时给路径框与「选择…」。
class _OutputLocationSegments extends StatelessWidget {
  const _OutputLocationSegments({required this.form});

  final TranslateFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final custom = o.outputLocation == OutputLocation.custom;
    return LabeledField(
      label: '输出位置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<OutputLocation>(
            value: o.outputLocation,
            onChanged: form.chooseOutputLocation,
            segments: [
              for (final v in OutputLocation.values)
                (value: v, label: v.label, enabled: true),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          if (custom)
            Row(
              children: [
                Expanded(
                  child: ControlSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        o.outputDir ?? '点此选择目录…',
                        style: AppTextStyles.timecode.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2 + 2),
                ControlButton(label: '选择…', onPressed: form.pickOutputDir),
              ],
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '译文写成 '),
                  TextSpan(
                    text: form.outputNameExample,
                    style: AppTextStyles.timecode.copyWith(
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const TextSpan(text: '，不覆盖原文件。'),
                ],
              ),
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
