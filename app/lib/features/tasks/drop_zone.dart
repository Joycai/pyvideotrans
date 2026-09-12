import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';

/// 按扩展名判断拖进来的是媒体还是字幕 —— 这决定了建什么类型的任务。
abstract final class MediaKinds {
  static const media = {
    'mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv',
    'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'opus',
  };
  static const subtitle = {'srt', 'vtt', 'ass', 'ssa'};

  static String extensionOf(String path) =>
      path.split('.').last.toLowerCase();

  static bool isMedia(String path) => media.contains(extensionOf(path));
  static bool isSubtitle(String path) => subtitle.contains(extensionOf(path));
  static bool isSupported(String path) => isMedia(path) || isSubtitle(path);
}

/// 拖放区。平时是一条 40px 的提示；拖动进入时展开成 128px 的两半，
/// 明确告诉用户「音视频建转写、SRT 建翻译」，落点不用猜。
class TaskDropZone extends StatefulWidget {
  const TaskDropZone({
    super.key,
    required this.onFiles,
    required this.onBrowse,
  });

  final ValueChanged<List<String>> onFiles;
  final VoidCallback onBrowse;

  @override
  State<TaskDropZone> createState() => _TaskDropZoneState();
}

class _TaskDropZoneState extends State<TaskDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        final paths = details.files
            .map((f) => f.path)
            .where(MediaKinds.isSupported)
            .toList();
        if (paths.isNotEmpty) widget.onFiles(paths);
      },
      child: AnimatedSize(
        duration: AppDuration.medium,
        curve: kEasingEmphasized,
        alignment: Alignment.topCenter,
        child: _dragging ? const _Expanded() : _Collapsed(onBrowse: widget.onBrowse),
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  const _Collapsed({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.upload_file,
            size: 20,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text(
            '拖入音视频新建转写，拖入 SRT 新建翻译',
            style: context.texts.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          QuietButton(label: '选择文件…', height: 32, onPressed: onBrowse),
        ],
      ),
    );
  }
}

class _Expanded extends StatelessWidget {
  const _Expanded();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 128,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: cs.primary.withValues(alpha: 0.06),
        border: Border.all(color: cs.primary, width: 2),
      ),
      child: Row(
        children: [
          const Expanded(
            child: _DropHalf(
              icon: Symbols.movie,
              title: '音视频 → 新建转写任务',
              subtitle: 'mp4 · mov · mkv · mp3 · m4a · wav',
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Container(width: 1, color: cs.outlineVariant),
          const SizedBox(width: AppSpacing.s4),
          const Expanded(
            child: _DropHalf(
              icon: Symbols.subtitles,
              title: 'SRT → 新建翻译任务',
              subtitle: 'srt · vtt · ass',
            ),
          ),
        ],
      ),
    );
  }
}

class _DropHalf extends StatelessWidget {
  const _DropHalf({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 32, weight: 400, color: cs.primary),
        const SizedBox(height: AppSpacing.s1 + 2),
        Text(title, style: context.texts.titleSmall),
        const SizedBox(height: AppSpacing.s1 + 2),
        Text(
          subtitle,
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
