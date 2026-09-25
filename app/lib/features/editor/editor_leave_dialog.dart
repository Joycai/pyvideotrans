import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../domain/file_stamp.dart';
import '../../domain/paths.dart';
import 'editor_prompts.dart';
import 'editor_widgets.dart';

/// [EditorPrompts] 的界面实现：「先写入字幕文件？」与外部修改冲突两个对话框
/// （设计稿「编辑器保存模型」画板 4 ① ②）、目录选择、SnackBar。
///
/// 只管问，不做决定 —— 写入流程在 `EditorController.confirmLeave` /
/// `writeFiles` 里。
class DialogEditorPrompts implements EditorPrompts {
  DialogEditorPrompts({required this.context, required this.onSay});

  /// 对话框要一个 MaterialApp 以下的 context，根节点自己没有，由装配层给。
  final BuildContext? Function() context;

  /// 轻提示的出口。
  final ValueChanged<String> onSay;

  BuildContext? get _mounted {
    final context = this.context();
    return context != null && context.mounted ? context : null;
  }

  /// 修改已经在编辑进度里了，不写入也不会丢，所以「稍后再写」是中性的，
  /// 不再是红色的「不保存」。没有能弹对话框的 context 时也按它放行。
  @override
  Future<LeaveChoice?> askLeave({
    required String title,
    required int edits,
    required List<String> files,
    required LeaveIntent intent,
  }) async {
    final context = _mounted;
    if (context == null) return LeaveChoice.later;
    return showDialog<LeaveChoice>(
      context: context,
      builder: (context) {
        final cs = context.colors;
        void pick(LeaveChoice c) => Navigator.of(context).pop(c);
        return GlassDialog(
          title: '先写入字幕文件？',
          message: files.isEmpty
              ? '$title 有 $edits 处修改还没写进字幕文件。'
              : '$title 有 $edits 处修改还没写进 ${files.join(' 和 ')}。',
          note: '不写入也不会丢：修改留在编辑进度里，下次打开会接着提示「未写入」。',
          leading: DialogTextAction(
            label: '稍后再写',
            color: cs.onSurfaceVariant,
            onTap: () => pick(LeaveChoice.later),
          ),
          actions: [
            ControlButton(
              label: '取消',
              onPressed: () => pick(LeaveChoice.cancel),
            ),
            PrimaryButton(
              label: intent.label,
              autofocus: true,
              onPressed: () => pick(LeaveChoice.write),
            ),
          ],
        );
      },
    );
  }

  @override
  Future<ConflictChoice?> askConflict(
    List<FileChange> changes, {
    required bool remounts,
  }) async {
    final context = _mounted;
    if (context == null) return null;
    final first = changes.first;
    final title = changes.length == 1
        ? '${baseName(first.path)} 在别处被改过'
        : '${changes.length} 个字幕文件在别处被改过';
    return showDialog<ConflictChoice>(
      context: context,
      builder: (context) {
        final cs = context.colors;
        void pick(ConflictChoice c) => Navigator.of(context).pop(c);
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
            onTap: () => pick(ConflictChoice.overwrite),
          ),
          actions: [
            ControlButton(
              label: '取消',
              onPressed: () => pick(ConflictChoice.cancel),
            ),
            // 破坏性的是「覆盖」，默认焦点给「另存为」。
            PrimaryButton(
              label: '另存为…',
              autofocus: true,
              onPressed: () => pick(ConflictChoice.saveAs),
            ),
          ],
        );
      },
    );
  }

  @override
  Future<String?> pickDir({
    required String initialDirectory,
    required String confirmText,
  }) => getDirectoryPath(
    initialDirectory: initialDirectory,
    confirmButtonText: confirmText,
  );

  @override
  void say(String message) => onSay(message);
}
