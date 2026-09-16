import 'package:flutter/material.dart';

import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../services/settings.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 「语言」分区：源语言与目标语言。识别与翻译共用这一组。
class LanguageSection extends StatelessWidget {
  const LanguageSection({
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
    return SettingsSection(
      section: SettingsSectionKey.lang,
      note: '识别与翻译共用这一组语言设置，新建任务时可以临时改。',
      saved: saved,
      children: [
        SettingsRow(
          label: '源语言',
          note: '音频里说的语言。auto 让识别模型自己判断。',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppDropdown<String>(
                value: Languages.resolve(settings.sourceLanguage).code,
                groups: [
                  DropdownGroup(
                    entries: [
                      for (final l in Languages.source)
                        DropdownEntry(
                          value: l.code,
                          label: l.isAuto ? '自动检测（auto）' : '${l.name}（${l.code}）',
                        ),
                    ],
                  ),
                ],
                onChanged: (code) {
                  settings.sourceLanguage = code;
                  onChanged();
                },
              ),
            ),
          ),
        ),
        SettingsRow(
          label: '目标语言',
          note: '用自然语言写，会原样交给翻译模型',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SettingsTextField(
                value: settings.targetLanguage,
                hint: '例如「英文」「日文」「简体中文」',
                onChanged: (v) {
                  settings.targetLanguage = v;
                  onChanged(typed: true);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
