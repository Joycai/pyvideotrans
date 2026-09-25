import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/paths.dart';
import '../../domain/task.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';

/// 任务排队或运行中打开编辑器时的横幅：说明为什么改不了、什么时候能改。
/// 与恢复横幅同形，用中性色 —— 这不是出了问题，只是还没轮到编辑。
class EditorLockedBanner extends StatelessWidget {
  const EditorLockedBanner({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          spacing: AppSpacing.s3,
          children: [
            Icon(
              Symbols.lock,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: context.texts.titleSmall),
                  Text(
                    '流水线会随时更新这份字幕，这时改动会和它互相覆盖。'
                    '跑完后自动解锁，字幕文件也会按最终结果写出。',
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑器只读时的说明；不只读时为 null。
String? editorLockNote(EditorController controller) {
  if (!controller.locked) return null;
  final session = controller.session;
  if (session is! TaskSession) return '编辑器暂时只读';
  final task = session.task;
  return task.status == TaskStatus.queued
      ? '任务在排队，编辑器暂时只读'
      : '任务正在${task.stage.label}，编辑器暂时只读';
}

/// 本地会话接着上次没写回文件的编辑进度打开时的横幅（画板 3）。
class EditorRecoveryBanner extends StatelessWidget {
  const EditorRecoveryBanner({
    super.key,
    required this.controller,
    required this.onWrite,
    this.onDiscard,
  });

  final EditorController controller;
  final Future<void> Function() onWrite;
  final Future<void> Function()? onDiscard;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = cs.onPrimaryContainer;
    final files = controller.session.targetPaths.map(baseName).join('、');
    final at = controller.recoveredAt;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          spacing: AppSpacing.s3,
          children: [
            Icon(Symbols.history, size: 20, weight: 400, color: fg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    '上次关闭时有 ${controller.recoveredEdits} 处修改没写回 $files，已接着显示',
                    style: context.texts.titleSmall?.copyWith(color: fg),
                  ),
                  if (at != null)
                    Text(
                      controller.recoveredOverChanged
                          ? '修改来自 ${friendlyTime(at)} 的编辑进度；文件在那之后被别的程序改过，写入前会先问你。'
                          : '修改来自 ${friendlyTime(at)} 的编辑进度；文件本身之后没有被改过。',
                      style: context.texts.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            if (controller.recoveredOverChanged && onDiscard != null)
              EditorTextAction(
                label: '丢弃，按文件重新打开',
                color: fg,
                onTap: onDiscard!,
              )
            else if (controller.canRevertToWritten)
              EditorTextAction(
                label: '丢弃，按文件重新打开',
                color: fg,
                onTap: () {
                  controller
                    ..revertToWritten()
                    ..dismissRecovery();
                },
              ),
            PrimaryButton(
              label: '写入文件',
              height: 30,
              onPressed: () async {
                await onWrite();
                if (controller.unsavedEdits == 0) controller.dismissRecovery();
              },
            ),
            IconActionButton(
              icon: Symbols.close,
              tooltip: '关闭提示',
              onPressed: controller.dismissRecovery,
            ),
          ],
        ),
      ),
    );
  }
}
