import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import 'editor_controller.dart';
import 'editor_open_form.dart';
import 'editor_session.dart';
import 'editor_source_chip.dart';
import 'editor_sync_chip.dart';

/// 顶栏标题右侧：「待校对 N」+ 来源 chip。
///
/// 任务会话的 chip 回答「播放器里看到的是不是最新的」，点开是保存状态弹层；
/// 本地会话的 chip 列出挂载的文件，有未写入的修改时在后面跟一句。
class EditorTitleTrailing extends StatelessWidget {
  const EditorTitleTrailing({
    super.key,
    required this.controller,
    this.onReplace,
    this.onRepair,
    this.onOpenOther,
    this.onSave,
  });

  final EditorController controller;
  final ValueChanged<OpenSlot>? onReplace;
  final VoidCallback? onRepair;
  final VoidCallback? onOpenOther;

  /// 写入字幕文件（与 ⌘S 同一个入口）。
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _EditorReviewBadge(count: controller.countOf(CueFilter.review)),
        const SizedBox(width: AppSpacing.s3),
        switch (session) {
          FileSession() => EditorSourceChip(
            controller: controller,
            session: session,
            onReplace: onReplace,
            onRepair: onRepair,
            onOpenOther: onOpenOther,
          ),
          TaskSession() => EditorSyncChip(
            controller: controller,
            onSave: onSave,
          ),
        },
      ],
    );
  }
}

/// 顶栏标题右侧的「待校对 N」。
class _EditorReviewBadge extends StatelessWidget {
  const _EditorReviewBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.flag,
            size: 16,
            weight: 400,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '待校对 $count',
            style: context.texts.labelMedium?.copyWith(
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
