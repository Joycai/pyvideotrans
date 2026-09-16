import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/glass_panel.dart';
import 'editor_controller.dart';
import 'inspector_cue_editor.dart';
import 'inspector_preview.dart';
import 'preview_playback.dart';

/// 右侧 440px 检视面板：预览 + 当前条的编辑。
class Inspector extends StatelessWidget {
  const Inspector({
    super.key,
    required this.controller,
    required this.onRetranslate,
    this.onManageSpeakers,
    this.onMountTranslation,
    this.playback,
    this.onAttachMedia,
  });

  final EditorController controller;
  final void Function(int index) onRetranslate;
  final VoidCallback? onManageSpeakers;
  final VoidCallback? onMountTranslation;

  /// 会话有音视频时的播放器；没有就只预览字幕样式。
  final PreviewPlayback? playback;

  /// 「关联视频…」：让用户手动挑一个音视频文件。
  final VoidCallback? onAttachMedia;

  @override
  Widget build(BuildContext context) {
    final cue = controller.current;
    return GlassPanel(
      child: cue == null
          ? Center(
              child: Text(
                '选择一条字幕开始校对',
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InspectorPreview(
                    cue: cue,
                    controller: controller,
                    playback: playback,
                    onAttachMedia: onAttachMedia,
                  ),
                  InspectorCueEditor(
                    controller: controller,
                    onRetranslate: onRetranslate,
                    onManageSpeakers: onManageSpeakers,
                    onMountTranslation: onMountTranslation,
                  ),
                ],
              ),
            ),
    );
  }
}
