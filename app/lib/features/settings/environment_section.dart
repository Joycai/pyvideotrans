import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../services/ffmpeg.dart';
import '../../services/reveal.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 环境：ffmpeg 现在在哪，找不到时怎么补上。
///
/// 这里刻意不做成「填一个路径」的设置项。投放目录是固定的已知位置，用户只要
/// 点开它、把可执行文件拖进去就行 —— Windows 用户的卡点从来不是「填路径」，
/// 而是不知道该把文件放哪、也不会配环境变量。少一层心智负担，也省掉路径填错
/// 之后的一堆状态。
class EnvironmentSection extends StatefulWidget {
  const EnvironmentSection({
    super.key,
    required this.media,
    required this.stacked,
  });

  final Ffmpeg media;
  final bool stacked;

  @override
  State<EnvironmentSection> createState() => _EnvironmentSectionState();
}

class _EnvironmentSectionState extends State<EnvironmentSection> {
  late String? _path = widget.media.ffmpegOrNull;

  /// 用户刚把文件放进去，得让上次的查找结果作废再查一遍。
  void _recheck() {
    widget.media.reset();
    setState(() => _path = widget.media.ffmpegOrNull);
  }

  Future<void> _openDropIn() async {
    final dir = await Ffmpeg.ensureDropInDir();
    if (dir == null) return;
    await Reveal.openDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final found = _path != null;
    return SettingsSection(
      section: SettingsSectionKey.environment,
      note:
          '抽音与转码都要用 FFmpeg。没有的话，点「打开目录」把 '
          '${Ffmpeg.dropInNames.join(' 和 ')} 放进去即可，不用配环境变量。',
      children: [
        SettingsRow(
          label: 'FFmpeg',
          note: found ? '已找到' : '未找到',
          stacked: widget.stacked,
          child: Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 200,
                  // 与「输出目录」同一套算法：路径框吃掉按钮以外的宽度。
                  maxWidth: widget.stacked
                      ? double.infinity
                      : 880 - 180 - 24 - 96 - 88 - 16,
                ),
                child: ControlSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        found ? Symbols.check_circle : Symbols.error,
                        size: 18,
                        weight: 400,
                        color: found ? cs.primary : cs.error,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          _path ?? '未找到，放进目录后点重新检测',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kTimecodeStyle.copyWith(
                            color: found ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ControlButton(
                label: '打开目录',
                icon: Symbols.folder_open,
                onPressed: _openDropIn,
              ),
              QuietButton(
                label: '重新检测',
                icon: Symbols.refresh,
                onPressed: _recheck,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
