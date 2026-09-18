import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../domain/paths.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';

/// 离开编辑器时主按钮做完写入之后要干什么。
enum LeaveIntent {
  open('写入并打开'),
  exit('写入并退出');

  const LeaveIntent(this.label);

  final String label;
}

/// 切换会话或退出应用前的询问（设计稿「编辑器保存模型」画板 4 ①）。
/// 返回 true 表示可以继续。
///
/// 修改已经在编辑进度里了，不写入也不会丢，所以「稍后再写」是中性的，
/// 不再是红色的「不保存」。
Future<bool> confirmLeaveEditor(
  BuildContext context,
  EditorController controller, {
  LeaveIntent intent = LeaveIntent.open,
}) async {
  // 先把排着的编辑进度写掉：撤销回原样后 300ms 内就切走，盘上还是
  // 撤销前的草稿，下次打开会把撤销掉的修改当成「恢复」。
  await controller.flushDraft();
  final edits = controller.unsavedEdits;
  if (edits == 0 || !context.mounted) return edits == 0;

  final files = [for (final p in controller.session.targetPaths) baseName(p)];
  final choice = await showDialog<_LeaveChoice>(
    context: context,
    builder: (context) {
      final cs = context.colors;
      void pick(_LeaveChoice c) => Navigator.of(context).pop(c);
      return GlassDialog(
        title: '先写入字幕文件？',
        message: files.isEmpty
            ? '${controller.session.title} 有 $edits 处修改还没写进字幕文件。'
            : '${controller.session.title} 有 $edits 处修改还没写进 '
                  '${files.join(' 和 ')}。',
        note: '不写入也不会丢：修改留在编辑进度里，下次打开会接着提示「未写入」。',
        leading: DialogTextAction(
          label: '稍后再写',
          color: cs.onSurfaceVariant,
          onTap: () => pick(_LeaveChoice.later),
        ),
        actions: [
          ControlButton(
            label: '取消',
            onPressed: () => pick(_LeaveChoice.cancel),
          ),
          PrimaryButton(
            label: intent.label,
            autofocus: true,
            onPressed: () => pick(_LeaveChoice.write),
          ),
        ],
      );
    },
  );

  switch (choice) {
    case _LeaveChoice.write:
      if (!context.mounted) return false;
      return writeSubtitleFiles(context, controller);
    case _LeaveChoice.later:
      return true;
    case _LeaveChoice.cancel || null:
      return false;
  }
}

enum _LeaveChoice { write, later, cancel }

/// ⌘S、「保存」按钮、离开时「写入并…」共用的写入流程。返回是否写成了。
///
/// 文件在外部被改过时先问（画板 4 ②）：覆盖、另存为或取消。写入失败不弹
/// 提示 —— 顶栏 chip 会变红并写明原因，修改也还在编辑进度里。
Future<bool> writeSubtitleFiles(
  BuildContext context,
  EditorController controller,
) async {
  try {
    await controller.save();
    return true;
  } on WriteConflict catch (conflict) {
    if (!context.mounted) return false;
    final choice = await _askConflict(context, controller, conflict);
    try {
      switch (choice) {
        case _ConflictChoice.overwrite:
          await controller.save(overwrite: true);
          return true;
        case _ConflictChoice.saveAs:
          final dir = await getDirectoryPath(
            initialDirectory: dirName(conflict.changes.first.path),
            confirmButtonText: '写到这里',
          );
          if (dir == null) return false;
          await controller.saveAs(dir);
          return true;
        case _ConflictChoice.cancel || null:
          return false;
      }
    } on Object catch (e) {
      // 本地会话写失败 chip 会变红；任务会话的另存为不改同步状态，
      // 不提示的话用户只会看到「点了没反应」。
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(e is TargetRejected ? e.reason : '另存失败：$e'),
          ),
        );
      }
      return false;
    }
  } on Object {
    return false;
  }
}

enum _ConflictChoice { overwrite, saveAs, cancel }

Future<_ConflictChoice?> _askConflict(
  BuildContext context,
  EditorController controller,
  WriteConflict conflict,
) {
  final changes = conflict.changes;
  final first = changes.first;
  final title = changes.length == 1
      ? '${baseName(first.path)} 在别处被改过'
      : '${changes.length} 个字幕文件在别处被改过';
  final remounts = controller.session is FileSession;
  return showDialog<_ConflictChoice>(
    context: context,
    builder: (context) {
      final cs = context.colors;
      void pick(_ConflictChoice c) => Navigator.of(context).pop(c);
      return GlassDialog(
        title: title,
        message:
            '上次读写是 ${friendlyTime(first.before.modified)}，'
            '文件在 ${friendlyTime(first.now.modified)} 被其他程序改过。'
            '直接写入会盖掉那边的改动。',
        note: remounts
            ? '想两边都留，选「另存为」写到另一个目录；编辑器之后就挂在新文件上。'
            : '想两边都留，选「另存为」把这次的修改写到另一个目录；任务的产物保持不动。',
        leading: DialogTextAction(
          label: '覆盖',
          color: cs.error,
          onTap: () => pick(_ConflictChoice.overwrite),
        ),
        actions: [
          ControlButton(
            label: '取消',
            onPressed: () => pick(_ConflictChoice.cancel),
          ),
          // 破坏性的是「覆盖」，默认焦点给「另存为」。
          PrimaryButton(
            label: '另存为…',
            autofocus: true,
            onPressed: () => pick(_ConflictChoice.saveAs),
          ),
        ],
      );
    },
  );
}
