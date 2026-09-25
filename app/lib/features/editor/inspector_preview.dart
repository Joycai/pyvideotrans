import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'preview_playback.dart';

/// 预览区。
///
/// 会话找得到音视频（转写任务的源文件、字幕旁边的同名文件、用户手动关联的
/// 文件）时是真的播放器：画面上叠当前字幕，播放头与选中条双向联动。
/// 找不到时只预览字幕样式，本地会话版位压到 150px 高。
class InspectorPreview extends StatelessWidget {
  const InspectorPreview({
    super.key,
    required this.cue,
    required this.controller,
    required this.playback,
    required this.onAttachMedia,
  });

  final Cue cue;
  final EditorController controller;
  final PreviewPlayback? playback;
  final VoidCallback? onAttachMedia;

  @override
  Widget build(BuildContext context) {
    final playback = this.playback;
    if (playback == null) return _buildStatic(context);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => _buildPlayer(context, playback),
    );
  }

  /// 字幕在画面上的样子。播放中显示播放头所在的那一条；停在字幕之间的
  /// 空白时什么也不显示。
  Widget _caption(Cue? shown) {
    if (shown == null) return const SizedBox.shrink();
    final showTranslation =
        shown.hasTranslation &&
        (controller.view == CueView.translation || shown.source.trim().isEmpty);
    final text = showTranslation ? shown.translation! : shown.source;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s2 + 2,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF2CE4E),
              fontSize: 16,
              height: 24 / 16,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _screenLabel(String text) => Positioned(
    top: 10,
    left: AppSpacing.s3,
    right: AppSpacing.s3,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.timecode.copyWith(
        fontSize: 11,
        color: const Color(0xFF8A9099),
      ),
    ),
  );

  Widget _screen(List<Widget> children) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF0C0E11),
      borderRadius: BorderRadius.circular(AppRadius.md + 2),
    ),
    child: Stack(fit: StackFit.expand, children: children),
  );

  Widget _wrap(BuildContext context, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s4,
      AppSpacing.s4,
      AppSpacing.s4,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _buildStatic(BuildContext context) {
    final cs = context.colors;
    final isFile = controller.session is FileSession;
    final screen = _screen([
      _screenLabel(isFile ? '未关联视频 · 只预览字幕样式' : '找不到源文件 · 只预览字幕样式'),
      if (onAttachMedia != null)
        Positioned(
          top: 4,
          right: 4,
          child: _ScreenAction(label: '关联视频…', onTap: onAttachMedia!),
        ),
      _caption(cue),
    ]);

    return _wrap(context, [
      if (isFile)
        SizedBox(height: 150, child: screen)
      else
        AspectRatio(aspectRatio: 16 / 9, child: screen),
      const SizedBox(height: AppSpacing.s2),
      _Transport(
        controller: controller,
        cue: cue,
        positionMs: cue.startMs,
        durationMs: controller.document.duration.inMilliseconds,
        timecodeColor: cs.onSurfaceVariant,
      ),
    ]);
  }

  Widget _buildPlayer(BuildContext context, PreviewPlayback playback) {
    final cs = context.colors;
    final error = playback.error;
    final shown = playback.loaded ? playback.cueAtPlayhead : cue;
    final screen = _screen([
      Video(
        controller: playback.video,
        controls: NoVideoControls,
        fit: BoxFit.contain,
        fill: const Color(0xFF0C0E11),
      ),
      if (!playback.hasVideo)
        Center(
          child: Icon(
            playback.isAudio ? Symbols.graphic_eq : Symbols.movie,
            size: 40,
            weight: 300,
            color: const Color(0xFF3A4048),
          ),
        ),
      _screenLabel(error != null ? '播放出错 · $error' : playback.fileName),
      if (onAttachMedia != null)
        Positioned(
          top: 4,
          right: 4,
          child: _ScreenAction(label: '换一个…', onTap: onAttachMedia!),
        ),
      _caption(shown),
    ]);

    return _wrap(context, [
      AspectRatio(aspectRatio: 16 / 9, child: screen),
      const SizedBox(height: AppSpacing.s2),
      _SeekBar(
        position: playback.position,
        duration: playback.duration,
        onSeek: (ms) => playback.seekTo(ms),
      ),
      const SizedBox(height: AppSpacing.s2),
      _Transport(
        controller: controller,
        cue: cue,
        positionMs: playback.position.inMilliseconds,
        durationMs: playback.loaded
            ? playback.duration.inMilliseconds
            : controller.document.duration.inMilliseconds,
        timecodeColor: cs.onSurfaceVariant,
        leading: IconActionButton(
          icon: playback.playing ? Symbols.pause : Symbols.play_arrow,
          tooltip: playback.playing ? '暂停 · 空格' : '播放 · 空格',
          fill: true,
          onPressed: playback.loaded ? playback.toggle : null,
        ),
      ),
    ]);
  }
}

/// 预览下方那一排：上一条 / 下一条、播放头位置 / 总长、当前条时长。
class _Transport extends StatelessWidget {
  const _Transport({
    required this.controller,
    required this.cue,
    required this.positionMs,
    required this.durationMs,
    required this.timecodeColor,
    this.leading,
  });

  final EditorController controller;
  final Cue cue;
  final int positionMs;
  final int durationMs;
  final Color timecodeColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.s1)],
        IconActionButton(
          icon: Symbols.skip_previous,
          tooltip: '上一条',
          onPressed: () => controller.step(-1),
        ),
        IconActionButton(
          icon: Symbols.skip_next,
          tooltip: '下一条',
          onPressed: () => controller.step(1),
        ),
        const SizedBox(width: AppSpacing.s2),
        // 窄一点的字体下时间码会把标签挤出去，允许整组缩小。
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Timecode(Srt.formatTimecode(positionMs)),
                Text(
                  ' / ',
                  style: AppTextStyles.timecode.copyWith(color: cs.outline),
                ),
                Timecode(Srt.formatTimecode(durationMs), color: timecodeColor),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        StatusTag(label: '${cue.durationMs / 1000}s', tone: TagTone.neutral),
      ],
    );
  }
}

/// 画面右上角的小动作（关联视频 / 换一个）。
class _ScreenAction extends StatelessWidget {
  const _ScreenAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      hoverColor: Colors.white.withValues(alpha: AppStateLayer.hover),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: AppTextStyles.timecode.copyWith(
            fontSize: 11,
            color: const Color(0xFFB8C0CC),
          ),
        ),
      ),
    ),
  );
}

/// 4px 高的进度条，点击或拖动定位。
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) {
          if (total <= 0) return;
          final f = (dx / constraints.maxWidth).clamp(0.0, 1.0);
          onSeek((f * total).round());
        }

        return MouseRegion(
          cursor: total > 0
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 12,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: cs.surfaceContainerHighest),
                        FractionallySizedBox(
                          widthFactor: fraction,
                          child: Container(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
