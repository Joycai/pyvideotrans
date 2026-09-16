import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/language.dart';
import '../../domain/subtitle_pairing.dart';
import '../../domain/task.dart';
import '../../services/editor_store.dart';
import '../shell/page_chrome.dart';
import 'editor_open_form.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

/// 入口页的顶栏。有会话开着时右侧给「返回编辑器」。
PageChrome editorOpenChrome({VoidCallback? onBack}) => PageChrome(
  title: '编辑器',
  subtitle: '打开一份字幕开始校对',
  actions: [
    if (onBack != null)
      ControlButton(
        label: '返回编辑器',
        icon: Symbols.arrow_back,
        onPressed: onBack,
      ),
  ],
);

/// 编辑器入口页（设计稿 M-EditorOpen）：左栏挂本地原文与译文并检查配对，
/// 右栏从已完成的任务里挑一个。
class EditorOpenPage extends StatefulWidget {
  const EditorOpenPage({
    super.key,
    required this.form,
    required this.tasks,
    required this.recents,
    required this.onOpenFiles,
    required this.onOpenTask,
    required this.onOpenRecent,
    required this.onOpenTasks,
  });

  final EditorOpenForm form;

  /// 已完成、带字幕的任务，新的在前。
  final List<SubtitleTask> tasks;
  final List<RecentSession> recents;
  final VoidCallback onOpenFiles;
  final ValueChanged<SubtitleTask> onOpenTask;
  final ValueChanged<RecentSession> onOpenRecent;
  final VoidCallback onOpenTasks;

  @override
  State<EditorOpenPage> createState() => _EditorOpenPageState();
}

class _EditorOpenPageState extends State<EditorOpenPage> {
  EditorOpenForm get form => widget.form;

  @override
  void initState() {
    super.initState();
    form.addListener(_refresh);
  }

  @override
  void didUpdateWidget(EditorOpenPage old) {
    super.didUpdateWidget(old);
    if (old.form != widget.form) {
      old.form.removeListener(_refresh);
      widget.form.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    form.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _LocalPanel(page: this)),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: constraints.maxWidth < 1100 ? 360 : 400,
            child: _TaskPanel(page: this),
          ),
        ],
      ),
    );
  }
}

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

class _LocalPanel extends StatelessWidget {
  const _LocalPanel({required this.page});

  final _EditorOpenPageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page.form;
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
                  child: _Slot(form: form, slot: OpenSlot.source),
                ),
                const SizedBox(width: AppSpacing.s3),
                Center(child: _SwapButton(form: form)),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: _Slot(form: form, slot: OpenSlot.translation),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _PairingBlock(form: form),
        ),
        if (form.speakerLabels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _SpeakerLabelSwitch(form: form),
          ),
        Expanded(child: _Recents(page: page)),
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
              onPressed: form.canOpen ? page.widget.onOpenFiles : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.form});

  final EditorOpenForm form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = form.source != null && form.translation != null;
    return Tooltip(
      message: enabled ? '对换原文与译文' : '两份都添加后才能对换',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? cs.outlineVariant
                : cs.onSurface.withValues(
                    alpha: AppStateLayer.disabledContainer,
                  ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: context.elevation.controlGradient,
          ),
          boxShadow: enabled ? context.elevation.controlShadow : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? form.swap : null,
            child: Icon(
              Symbols.swap_horiz,
              size: 20,
              weight: 400,
              color: enabled
                  ? cs.onSurface
                  : cs.onSurface.withValues(
                      alpha: AppStateLayer.disabledContent,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个位置：空的时候是虚线落区，放了文件是卡片。只有被拖到的那一个位置亮起。
class _Slot extends StatefulWidget {
  const _Slot({required this.form, required this.slot});

  final EditorOpenForm form;
  final OpenSlot slot;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final slot = widget.slot;
    final file = form.file(slot);
    return DropTarget(
      onDragEntered: (_) => setState(() => _hot = true),
      onDragExited: (_) => setState(() => _hot = false),
      onDragDone: (d) {
        setState(() => _hot = false);
        form.handleDrop([for (final f in d.files) f.path], slot: slot);
      },
      child: file == null
          ? _EmptySlot(form: form, slot: slot, hot: _hot)
          : _FilledSlot(form: form, slot: slot, hot: _hot),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.form, required this.slot, required this.hot});

  final EditorOpenForm form;
  final OpenSlot slot;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isSource = slot == OpenSlot.source;
    final error = form.error(slot);
    final title = hot
        ? (isSource ? '松开以放入原文' : '松开以放入译文')
        : (isSource ? '拖入原文字幕' : '拖入译文字幕');
    final sub = isSource ? '识别出来或听写的那一份，必须有' : '可选；不挂也能在编辑器里翻译';

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSource ? Symbols.subtitles : Symbols.translate,
            size: 40,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(title, style: context.texts.titleMedium),
          const SizedBox(height: 6),
          Text(
            error ?? sub,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium?.copyWith(
              color: error == null ? cs.onSurfaceVariant : cs.error,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          ControlButton(label: '选择文件…', onPressed: () => form.browse(slot)),
        ],
      ),
    );

    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: kEasingStandard,
      decoration: BoxDecoration(
        color: hot ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: hot ? Border.all(color: cs.primary, width: 2) : null,
      ),
      child: hot
          ? content
          : CustomPaint(
              painter: DashedRRectPainter(
                color: cs.outline,
                radius: 14,
                strokeWidth: 1.5,
              ),
              child: SizedBox.expand(child: content),
            ),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.form,
    required this.slot,
    required this.hot,
  });

  final EditorOpenForm form;
  final OpenSlot slot;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final file = form.file(slot)!;
    final isSource = slot == OpenSlot.source;
    final language = form.language(slot);
    final label = hot
        ? (isSource ? '松开以替换原文' : '松开以替换译文')
        : (isSource ? '原文' : '译文');

    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: kEasingStandard,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: hot
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hot ? cs.primary : cs.outlineVariant,
          width: hot ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Text(
                  label,
                  style: context.texts.titleSmall?.copyWith(
                    color: hot ? cs.primary : cs.onSurface,
                  ),
                ),
                const Spacer(),
                IconActionButton(
                  icon: Symbols.close,
                  tooltip: '移除',
                  size: 28,
                  iconSize: 18,
                  onPressed: () => form.remove(slot),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              const FileIconBox(Symbols.subtitles),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      parentDir(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Timecode(
                '${file.cues.length} 条',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Timecode(
                EditorOpenForm.span(file),
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
          const Spacer(),
          AppDropdown<Language>(
            value: language,
            display: form.languageGuessed(slot)
                ? '${language.name} · 自动识别'
                : language.name,
            menuWidth: 240,
            onChanged: (l) => form.setLanguage(slot, l),
            groups: [
              DropdownGroup(
                entries: [
                  for (final l in Languages.all)
                    DropdownEntry(value: l, label: l.name),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairingBlock extends StatelessWidget {
  const _PairingBlock({required this.form});

  final EditorOpenForm form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final p = form.pairing;
    if (p == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Symbols.link,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '两份都添加后，会在这里检查能不能逐条对上',
                style: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final alarm = !p.plausible;
    final note = form.pairingNote;
    final stats = [
      (p.paired, '条逐条对上'),
      (p.sourceOnly, '条原文没有译文，显示为「未翻译」'),
      (p.translationOnly, '条译文找不到原文，单独成行，标「未配对」'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Text('配对', style: context.texts.titleSmall),
              const Spacer(),
              MiniSegmented<PairingMode>(
                value: p.mode,
                onChanged: form.setMode,
                segments: const [
                  (value: PairingMode.byTime, label: '按时间轴'),
                  (value: PairingMode.byIndex, label: '按序号'),
                ],
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (n, label)) in stats.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.s4),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Timecode(
                        '$n',
                        fontSize: 20,
                        color: i == 0 && alarm ? cs.error : cs.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: context.texts.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (p.mergedTranslations > 0)
            Text(
              '其中 ${p.mergedTranslations} 条译文并进了同一条原文',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (alarm)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.s2),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.error,
                    size: 18,
                    weight: 400,
                    color: cs.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      '时间轴基本对不上，可能不是同一个视频的字幕',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (note != null)
            Text(
              note,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
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
  const _Recents({required this.page});

  final _EditorOpenPageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final recents = page.widget.recents;
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
                          onTap: () => page.widget.onOpenRecent(r),
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

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.page});

  final _EditorOpenPageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tasks = page.widget.tasks;
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
                        onOpen: () => page.widget.onOpenTask(t),
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
            QuietButton(label: '去任务页 →', onPressed: page.widget.onOpenTasks),
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
