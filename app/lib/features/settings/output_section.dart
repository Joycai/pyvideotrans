import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../services/settings.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 「输出」分区：产物格式、双语排版与输出目录。
class OutputSection extends StatelessWidget {
  const OutputSection({
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
    final dir = settings.outputDir;
    return SettingsSection(
      section: SettingsSectionKey.output,
      saved: saved,
      children: [
        SettingsRow(
          label: '输出目录',
          note: '清除后字幕写回源文件所在目录',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 200,
                  // 路径框吃掉一行里按钮以外的全部宽度；换行时退到 200。
                  maxWidth: stacked
                      ? double.infinity
                      : 880 - 180 - 24 - 84 - 64 - 16,
                ),
                child: ControlSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.folder,
                        size: 18,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          dir ?? '源文件所在目录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.timecode.copyWith(
                            color: dir == null
                                ? cs.onSurfaceVariant
                                : cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ControlButton(
                label: '选择…',
                onPressed: () async {
                  final picked = await getDirectoryPath();
                  if (picked == null || !context.mounted) return;
                  settings.outputDir = picked;
                  onChanged();
                },
              ),
              QuietButton(
                label: '清除',
                onPressed: dir == null
                    ? null
                    : () {
                        settings.outputDir = null;
                        onChanged();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
