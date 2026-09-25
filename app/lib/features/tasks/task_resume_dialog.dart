import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../domain/task.dart';

/// 续跑前的检查结果。
enum ResumeChoice { proceed, openEditor, cancel }

/// 改过的任务被「继续」时的询问（设计稿「编辑器保存模型」画板 4 ③）。
/// 不会覆盖修改时直接返回 [ResumeChoice.proceed]，不问。
Future<ResumeChoice> confirmResume(
  BuildContext context,
  SubtitleTask task,
) async {
  if (!task.resumeOverwritesEdits) return ResumeChoice.proceed;
  final reviewed = task.document.cues.where((c) => c.reviewed).length;
  final stage = task.resumeStage;
  final choice = await showDialog<ResumeChoice>(
    context: context,
    builder: (context) {
      void pick(ResumeChoice c) => Navigator.of(context).pop(c);
      return GlassDialog(
        title: '继续会覆盖编辑器里的修改',
        message:
            '这个任务在编辑器里改过 ${task.editorEdits} 处'
            '${reviewed > 0 ? '（其中 $reviewed 条已校对）' : ''}。'
            '从「${stage.label}」阶段继续会重新生成全部字幕，这些修改会被覆盖。',
        note: '只想补翻没有译文的条目，用编辑器里的「翻译未译」，不会动已有的修改。',
        leading: DialogTextAction(
          label: '仍然继续',
          color: context.colors.error,
          onTap: () => pick(ResumeChoice.proceed),
        ),
        actions: [
          ControlButton(
            label: '取消',
            onPressed: () => pick(ResumeChoice.cancel),
          ),
          PrimaryButton(
            label: '去编辑器',
            autofocus: true,
            onPressed: () => pick(ResumeChoice.openEditor),
          ),
        ],
      );
    },
  );
  return choice ?? ResumeChoice.cancel;
}
