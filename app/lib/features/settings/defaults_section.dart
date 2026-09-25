import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../domain/task_options.dart';
import '../../services/settings.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 「任务默认值」分区：折行、断句、批大小与提示词。
class DefaultsSection extends StatelessWidget {
  const DefaultsSection({
    super.key,
    required this.settings,
    required this.stacked,
    required this.saved,
    required this.onChanged,
  });

  final AppSettings settings;

  /// 窄窗口下标签与控件上下堆叠。
  final bool stacked;

  /// 这一区刚改过，标题右侧显示「已保存」。
  final bool saved;

  /// 改动回报：页面据此显示「已保存」并刷新目录高亮；typed 表示是键盘输入。
  final void Function({bool typed}) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    Widget lineLength(String label, Widget field) => SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.texts.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          field,
        ],
      ),
    );

    return SettingsSection(
      section: SettingsSectionKey.defaults,
      note: '新建转写 / 翻译时的初始参数。对话框里改动只作用于当次任务。',
      saved: saved,
      children: [
        SettingsRow(
          label: '输出格式',
          note: 'srt 兼容性最好；ass 保留样式',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AppDropdown<SubtitleFormat>(
                value: settings.outputFormat,
                menuWidth: 240,
                groups: [
                  DropdownGroup(
                    entries: [
                      for (final f in SubtitleFormat.values)
                        DropdownEntry(
                          value: f,
                          label: f.extension,
                          enabled: f.implemented,
                          description: f.implemented
                              ? f.label
                              : '${f.label} · 第二期实施',
                        ),
                    ],
                  ),
                ],
                onChanged: (f) {
                  settings.outputFormat = f;
                  onChanged();
                },
              ),
            ),
          ),
        ),
        SettingsRow(
          label: '双语排版',
          note: '翻译任务里原文与译文的上下关系',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillSegments<BilingualLayout>(
              segments: const [
                (value: BilingualLayout.targetOnly, label: '单语', icon: null),
                (value: BilingualLayout.targetAbove, label: '译文在上', icon: null),
                (value: BilingualLayout.targetBelow, label: '原文在上', icon: null),
              ],
              value: settings.bilingual,
              onChanged: (v) {
                settings.bilingual = v;
                onChanged();
              },
            ),
          ),
        ),
        SettingsRow(
          label: '单行字数',
          note: '超过就断行。按文字类型分开设，中日韩按字数、拉丁按字符数。',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            children: [
              lineLength(
                '中日韩',
                NumberField(
                  key: ValueKey('cjk-${settings.cjkLineLength}'),
                  value: settings.cjkLineLength,
                  min: TaskOptions.cjkLineLengthRange.min,
                  max: TaskOptions.cjkLineLengthRange.max,
                  width: 132,
                  onChanged: (v) {
                    if (v == settings.cjkLineLength) return;
                    settings.cjkLineLength = v;
                    onChanged(typed: true);
                  },
                ),
              ),
              lineLength(
                '拉丁',
                NumberField(
                  key: ValueKey('latin-${settings.latinLineLength}'),
                  value: settings.latinLineLength,
                  min: TaskOptions.latinLineLengthRange.min,
                  max: TaskOptions.latinLineLengthRange.max,
                  width: 132,
                  onChanged: (v) {
                    if (v == settings.latinLineLength) return;
                    settings.latinLineLength = v;
                    onChanged(typed: true);
                  },
                ),
              ),
            ],
          ),
        ),
        SettingsRow(
          label: '字幕时长',
          note: '识别后断句：短于下限且紧跟上一条的并进去，长于上限的按标点拆开。',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            children: [
              lineLength(
                '最短（毫秒）',
                NumberField(
                  key: ValueKey('min-cue-${settings.minCueMs}'),
                  value: settings.minCueMs,
                  min: TaskOptions.minCueMsRange.min,
                  max: TaskOptions.minCueMsRange.max,
                  width: 132,
                  onChanged: (v) {
                    if (v == settings.minCueMs) return;
                    settings.minCueMs = v;
                    onChanged(typed: true);
                  },
                ),
              ),
              lineLength(
                '最长（秒）',
                NumberField(
                  key: ValueKey('max-cue-${settings.maxCueMs}'),
                  value: settings.maxCueMs ~/ 1000,
                  min: TaskOptions.maxCueMsRange.min ~/ 1000,
                  max: TaskOptions.maxCueMsRange.max ~/ 1000,
                  width: 132,
                  onChanged: (v) {
                    if (v * 1000 == settings.maxCueMs) return;
                    settings.maxCueMs = v * 1000;
                    onChanged(typed: true);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
