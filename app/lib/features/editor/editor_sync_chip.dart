import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/file_stamp.dart';
import '../../domain/paths.dart';
import '../../services/reveal.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';

/// 任务会话的保存状态 chip（设计稿「编辑器保存模型」画板 1、2）。
class EditorSyncChip extends StatelessWidget {
  const EditorSyncChip({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final EditorController controller;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final sync = controller.sync;
    final grey = cs.outline;
    // (文案, 圆点, 底色（null 为按钮渐变）, 描边, 文字)
    final (label, dot, fill, border, fg) = switch (sync) {
      SyncState.synced => (
        controller.session.writtenAt == null
            ? '已写入文件'
            : '已写入文件 · ${shortFriendlyTime(controller.session.writtenAt!)}',
        ext.success,
        null,
        cs.outlineVariant,
        cs.onSurfaceVariant,
      ),
      SyncState.dirty => (
        '${controller.unsavedEdits} 处修改未写入文件',
        cs.primary,
        null,
        cs.primary,
        cs.onPrimaryContainer,
      ),
      SyncState.writing => (
        '正在写入 ${controller.session.targetPaths.length} 个文件…',
        grey,
        null,
        cs.outlineVariant,
        cs.onSurfaceVariant,
      ),
      SyncState.written => (
        '已写入 ${controller.justWritten.length} 个文件',
        ext.success,
        ext.successContainer,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      SyncState.failed => (
        '写入失败 · ${controller.failure}',
        cs.error,
        cs.errorContainer,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
      SyncState.conflict => (
        '${baseName(controller.conflicts.first.path)} 在别处被改过',
        cs.onTertiaryContainer,
        cs.tertiaryContainer,
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
      ),
      SyncState.noOutput => (
        '还没有字幕文件',
        grey,
        null,
        cs.outlineVariant,
        cs.onSurfaceVariant,
      ),
    };

    return AnchoredPopover(
      width: 420,
      anchor: (context, toggle, open) => Semantics(
        button: true,
        label: '保存状态',
        child: Container(
          height: 28,
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.s2),
            border: Border.all(color: border),
            color: fill,
            gradient: fill != null
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: context.elevation.controlGradient,
                  ),
            boxShadow: fill != null ? null : context.elevation.controlShadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(AppSpacing.s2),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(dot, size: 6),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium?.copyWith(color: fg),
                      ),
                    ),
                    Icon(
                      open ? Symbols.expand_less : Symbols.expand_more,
                      size: 18,
                      weight: 400,
                      color: fg,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      popover: (context, close) =>
          _SyncPopover(controller: controller, onSave: onSave, close: close),
    );
  }
}

/// 保存状态弹层：把「编辑进度」与「字幕文件」两层分开讲清楚。
class _SyncPopover extends StatelessWidget {
  const _SyncPopover({required this.controller, this.onSave, this.close});

  final EditorController controller;
  final VoidCallback? onSave;
  final VoidCallback? close;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final session = controller.session;
    final paths = session.targetPaths;
    final edits = controller.unsavedEdits;
    final progress = controller.progressAt;
    final now = DateTime.now();
    final (fileStatus, fileColor) = switch (controller.sync) {
      SyncState.noOutput => ('还没有生成', cs.onSurfaceVariant),
      SyncState.failed => ('写入失败', cs.error),
      SyncState.conflict => ('在别处被改过', cs.onTertiaryContainer),
      SyncState.writing => ('正在写入…', cs.onSurfaceVariant),
      _ when edits > 0 => ('$edits 处修改未写入', cs.primary),
      _ => ('已是最新', ext.success),
    };

    Widget section({
      required IconData icon,
      required Color iconBg,
      required Color iconFg,
      required String title,
      required String status,
      required Color statusColor,
      required String body,
      List<Widget> extra = const [],
    }) => Padding(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.s3,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, weight: 500, color: iconFg),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s1,
              children: [
                Row(
                  spacing: AppSpacing.s2,
                  children: [
                    Text(title, style: context.texts.titleSmall),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  body,
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                ...extra,
              ],
            ),
          ),
        ],
      ),
    );

    final stamps = session.trackedStamps;
    return GlassMenu(
      padding: const EdgeInsets.all(AppSpacing.s1),
      children: [
        section(
          icon: Symbols.check,
          iconBg: ext.successContainer,
          iconFg: ext.success,
          title: '编辑进度',
          status: progress == null
              ? '自动保存'
              : now.difference(progress) < const Duration(minutes: 1)
              ? '自动保存 · 刚刚'
              : '自动保存 · ${shortFriendlyTime(progress)}',
          statusColor: cs.onSurfaceVariant,
          body: '每次改动都存进应用数据，关掉应用也不会丢；只在本应用里可见。',
        ),
        const MenuDivider(),
        section(
          icon: Symbols.description,
          iconBg: cs.primaryContainer,
          iconFg: cs.primary,
          title: '字幕文件',
          status: fileStatus,
          statusColor: fileColor,
          body: controller.sync == SyncState.noOutput
              ? '任务没有跑完，还没写出字幕文件；按 ⌘S 按任务参数生成，与完成时同名同路径。'
              : '播放器、剪辑软件读的是这 ${paths.length} 份文件，按 ⌘S 才会更新。',
          extra: [
            const SizedBox(height: AppSpacing.s1),
            for (final path in paths)
              SizedBox(
                height: 24,
                child: Row(
                  spacing: AppSpacing.s2,
                  children: [
                    StatusDot(
                      edits > 0 ? cs.primary : Colors.transparent,
                      size: 6,
                    ),
                    Expanded(
                      child: Text(
                        baseName(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      switch (stamps[path] ?? _fallback(session.writtenAt)) {
                        final s? when s.exists =>
                          '上次写入 ${shortFriendlyTime(s.modified)}',
                        // 旧版本写出的产物没记时间。
                        _ when session.hasOutputs => '写入时间未知',
                        _ => '还没写过',
                      },
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (paths.isNotEmpty)
              Text(
                dirName(paths.first),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const MenuDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s2,
            AppSpacing.s1,
            AppSpacing.s2,
            AppSpacing.s2,
          ),
          child: Row(
            spacing: AppSpacing.s2,
            children: [
              if (paths.isNotEmpty)
                EditorTextAction(
                  label: Reveal.label,
                  color: cs.primary,
                  onTap: () => Reveal.show(paths.first),
                ),
              const Spacer(),
              if (controller.canRevertToWritten)
                ControlButton(
                  label: '撤销到上次写入',
                  height: 30,
                  onPressed: () {
                    controller.revertToWritten();
                    close?.call();
                  },
                ),
              PrimaryButton(
                label: controller.sync == SyncState.noOutput
                    ? '生成文件 ⌘S'
                    : '写入文件 ⌘S',
                height: 30,
                onPressed: controller.canWrite && onSave != null
                    ? () {
                        close?.call();
                        onSave!();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 旧存档没记每个文件的时间戳，退而用整体的写入时间。
  static FileStamp? _fallback(DateTime? at) => at == null
      ? null
      : FileStamp(size: 0, modifiedMs: at.millisecondsSinceEpoch);
}
