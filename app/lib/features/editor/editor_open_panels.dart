import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/task.dart';
import '../../services/editor_store.dart';
import 'editor_open_form.dart';
import 'editor_open_pairing.dart';
import 'editor_open_slots.dart';
import 'editor_widgets.dart';

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: Row(children: children),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 本地字幕
// ═══════════════════════════════════════════════════════════════════════

class EditorOpenLocalPanel extends StatelessWidget {
  const EditorOpenLocalPanel({
    super.key,
    required this.form,
    required this.recents,
    required this.onOpenFiles,
    required this.onOpenRecent,
  });

  final EditorOpenForm form;
  final List<RecentSession> recents;
  final VoidCallback onOpenFiles;
  final ValueChanged<RecentSession> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final footer = form.footer;
    final footColor = footer.error ? cs.error : cs.onSurfaceVariant;

    return _Panel(
      children: [
        SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('本地字幕', style: context.texts.titleMedium),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SRT · VTT，可以只打开原文',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (form.hasAny)
                  QuietButton(label: '清空', onPressed: form.clear),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 232,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: EditorOpenSlot(form: form, slot: OpenSlot.source),
                ),
                const SizedBox(width: AppSpacing.s3),
                Center(child: EditorSwapSlotsButton(form: form)),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: EditorOpenSlot(form: form, slot: OpenSlot.translation),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: EditorPairingBlock(form: form),
        ),
        if (form.speakerLabels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _SpeakerLabelSwitch(form: form),
          ),
        Expanded(child: _Recents(recents: recents, onOpenRecent: onOpenRecent)),
        _Footer(
          children: [
            Icon(
              footer.empty
                  ? Symbols.add_circle
                  : footer.error
                  ? Symbols.error
                  : Symbols.info,
              size: 16,
              weight: 400,
              color: footColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                footer.text,
                style: context.texts.bodySmall?.copyWith(color: footColor),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            PrimaryButton(
              label: '打开编辑器',
              icon: Symbols.edit_note,
              onPressed: form.canOpen ? onOpenFiles : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _SpeakerLabelSwitch extends StatelessWidget {
  const _SpeakerLabelSwitch({required this.form});

  final EditorOpenForm form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final labels = form.speakerLabels;
    final shown = labels.take(4).map((l) => '「$l：」').join('');
    final more = labels.length > 4 ? ' 等' : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppSwitch(
            value: form.readSpeakerLabels,
            onChanged: form.setReadSpeakerLabels,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('读取行首的说话人标签', style: context.texts.bodyMedium),
              Text(
                form.readSpeakerLabels
                    ? '原文里有 ${labels.length} 种标签：$shown$more。打开后标签会从文本中去掉，变成说话人名单，可以改名。'
                    : '标签会原样留在字幕文本里。',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Recents extends StatelessWidget {
  const _Recents({required this.recents, required this.onOpenRecent});

  final List<RecentSession> recents;
  final ValueChanged<RecentSession> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '最近打开',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Expanded(
            child: recents.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s2),
                    child: Text(
                      '还没有打开过字幕',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final r in recents)
                        _RecentRow(
                          recent: r,
                          onTap: () => onOpenRecent(r),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.recent, required this.onTap});

  final RecentSession recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final r = recent;
    final name = r.isTask
        ? r.title
        : [
            baseName(r.sourcePath!),
            if (r.translationPath != null) baseName(r.translationPath!),
          ].join(' + ');
    final dir = r.isTask ? '任务' : parentDir(r.sourcePath!);
    final stat = [
      '${r.cueCount} 条',
      if (r.speakerCount > 0) '${r.speakerCount} 位说话人',
    ].join(' · ');
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: cs.onSurface.withValues(alpha: 0.06),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              FileIconBox(r.isTask ? Symbols.translate : Symbols.subtitles),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      dir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              SizedBox(
                width: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusTag(label: r.isTask ? '任务' : '本地'),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              SizedBox(
                width: 150,
                child: Text(
                  stat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              SizedBox(
                width: 76,
                child: Text(
                  friendlyTime(r.openedAt),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 从任务打开
// ═══════════════════════════════════════════════════════════════════════

class EditorOpenTaskPanel extends StatelessWidget {
  const EditorOpenTaskPanel({
    super.key,
    required this.tasks,
    required this.onOpenTask,
    required this.onOpenTasks,
  });

  final List<SubtitleTask> tasks;
  final ValueChanged<SubtitleTask> onOpenTask;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return _Panel(
      children: [
        SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
            child: Row(
              children: [
                Text('从任务打开', style: context.texts.titleMedium),
                const SizedBox(width: AppSpacing.s2),
                Timecode('${tasks.length}', color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    '还没有完成的任务',
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final t in tasks)
                      _TaskRow(
                        task: t,
                        onOpen: () => onOpenTask(t),
                      ),
                  ],
                ),
        ),
        _Footer(
          children: [
            Expanded(
              child: Text(
                '只列出已完成、带字幕的任务',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            QuietButton(label: '去任务页 →', onPressed: onOpenTasks),
          ],
        ),
      ],
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({required this.task, required this.onOpen});

  final SubtitleTask task;
  final VoidCallback onOpen;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final task = widget.task;
    final doc = task.document;
    final speakers = doc.speakerIds.length;
    final sub = [
      '${doc.cues.length} 条',
      if (task.kind.needsTranslation)
        '${task.sourceLanguage.name} → ${task.targetLanguage.name}'
      else
        '${task.sourceLanguage.name} · 仅转写',
      if (speakers > 0) '$speakers 位说话人',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: widget.onOpen,
        child: Container(
          height: 64,
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
          color: _hover ? cs.onSurface.withValues(alpha: 0.06) : null,
          child: Row(
            children: [
              FileIconBox(
                task.kind == TaskKind.translate
                    ? Symbols.translate
                    : Symbols.mic,
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              if (_hover)
                ControlButton(
                  label: '打开',
                  dense: true,
                  onPressed: widget.onOpen,
                )
              else
                Text(
                  friendlyTime(task.createdAt),
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
