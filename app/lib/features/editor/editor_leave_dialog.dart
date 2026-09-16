import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/paths.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';

/// 本地会话关掉前的询问（设计稿 6b）。返回 true 表示可以继续。
Future<bool> confirmLeaveEditor(
  BuildContext context,
  EditorController controller,
) async {
  final session = controller.session;
  final edits = controller.unsavedEdits;
  if (session is! FileSession || edits == 0) return true;

  final files = [
    baseName(session.sourcePath),
    if (session.mountedTranslationPath != null)
      baseName(session.mountedTranslationPath!),
  ];
  final choice = await showDialog<_LeaveChoice>(
    context: context,
    builder: (context) {
      final cs = context.colors;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 420,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.glass.glassStrong,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: context.glass.glassBorder),
              boxShadow: context.elevation.shadow3,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s3,
                children: [
                  Text('保存修改？', style: context.texts.titleLarge),
                  Text(
                    '${session.title} 有 $edits 处修改还没保存。保存会写回 ${files.join(' 和 ')}。',
                    style: context.texts.bodyMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      '「已校对」标记和说话人名单不会写进 SRT，而是另存在应用数据里；下次打开这${files.length == 2 ? '两' : ''}个文件时会恢复。',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s1),
                    child: Row(
                      children: [
                        EditorTextAction(
                          label: '不保存',
                          color: cs.error,
                          onTap: () =>
                              Navigator.of(context).pop(_LeaveChoice.discard),
                        ),
                        const Spacer(),
                        ControlButton(
                          label: '取消',
                          onPressed: () =>
                              Navigator.of(context).pop(_LeaveChoice.cancel),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        PrimaryButton(
                          label: '保存并打开',
                          onPressed: () =>
                              Navigator.of(context).pop(_LeaveChoice.save),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  switch (choice) {
    case _LeaveChoice.save:
      try {
        await controller.save();
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('保存失败：$e')));
        }
        return false;
      }
    case _LeaveChoice.discard:
      return true;
    case _LeaveChoice.cancel || null:
      return false;
  }
}

enum _LeaveChoice { save, discard, cancel }
