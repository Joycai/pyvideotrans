import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

/// 字幕列表：# / 开始 / 结束或说话人 / 原文 / 译文 / 状态。
///
/// 文档里有说话人时去掉「结束」列、加 104px 的说话人列 —— 表格区只有
/// 880px 宽，两列都放会把原文、译文挤到 150px 以下；结束时间在检视面板里有。
class CueTable extends StatelessWidget {
  const CueTable({
    super.key,
    required this.controller,
    this.onManageSpeakers,
    this.onMountTranslation,
  });

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  /// 只挂了原文时，译文表头上的「+ 挂载译文…」。
  final VoidCallback? onMountTranslation;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final visible = controller.visibleCues;
    final doc = controller.document;
    final speakers = doc.hasSpeakers;
    final isFile = controller.session is FileSession;
    final translated = controller.hasTranslations;
    final compact = isCompactEditor(context);
    final columns = !speakers
        ? _plainColumns
        : compact
        ? _compactSpeakerColumns
        : _speakerColumns;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          _Toolbar(
            controller: controller,
            speakers: speakers,
            showHint: !isFile && !speakers,
            onManageSpeakers: onManageSpeakers,
          ),
          _HeaderRow(
            columns: columns,
            speakers: speakers,
            compact: compact,
            onManageSpeakers: onManageSpeakers,
            onMountTranslation: isFile && !translated
                ? onMountTranslation
                : null,
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      doc.cues.isEmpty ? '这份字幕还没有内容' : '没有符合条件的字幕',
                      style: context.texts.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : _CueList(
                    controller: controller,
                    visible: visible,
                    columns: columns,
                    speakers: speakers,
                    compact: compact,
                    translated: translated,
                  ),
          ),
          _Footer(
            controller: controller,
            visibleCount: visible.length,
            showHint: isFile || speakers,
            canSave: isFile,
          ),
        ],
      ),
    );
  }
}

/// 字幕行列表。行高固定 40，选中条变化时（J/K、播放跟随）把它滚进视野；
/// 已经看得见就不动，免得点一下就跳。
class _CueList extends StatefulWidget {
  const _CueList({
    required this.controller,
    required this.visible,
    required this.columns,
    required this.speakers,
    required this.compact,
    required this.translated,
  });

  final EditorController controller;
  final List<Cue> visible;
  final List<double?> columns;
  final bool speakers;
  final bool compact;
  final bool translated;

  static const rowHeight = 40.0;

  @override
  State<_CueList> createState() => _CueListState();
}

class _CueListState extends State<_CueList> {
  final _scroll = ScrollController();
  int? _lastSelected;

  @override
  void didUpdateWidget(_CueList old) {
    super.didUpdateWidget(old);
    final selected = widget.controller.selected;
    if (selected == _lastSelected) return;
    _lastSelected = selected;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final cue = widget.controller.current;
    if (cue == null) return;
    final row = widget.visible.indexWhere((c) => c.index == cue.index);
    if (row < 0) return;
    final top = row * _CueList.rowHeight;
    final bottom = top + _CueList.rowHeight;
    final position = _scroll.position;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    if (top >= viewTop && bottom <= viewBottom) return;
    // 往下走时贴在底部，往上走时贴在顶部；跟着播放时每次只挪一行。
    final target = top < viewTop ? top : bottom - position.viewportDimension;
    _scroll.animateTo(
      target.clamp(0, position.maxScrollExtent).toDouble(),
      duration: AppDuration.short,
      curve: kEasingStandard,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final doc = controller.document;
    final visible = widget.visible;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemExtent: _CueList.rowHeight,
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final cue = visible[i];
        final position = doc.cues.indexWhere((c) => c.index == cue.index);
        // 连续说话人按看得见的上一行算：筛选后行与行不一定相邻。
        final previous = i > 0 ? visible[i - 1].speaker : null;
        return _CueRow(
          cue: cue,
          state: displayStateOf(cue, translated: widget.translated),
          columns: widget.columns,
          speakers: widget.speakers,
          compact: widget.compact,
          continuesSpeaker: cue.speaker != null && cue.speaker == previous,
          speakerName: cue.speaker == null
              ? null
              : doc.speakerName(cue.speaker!),
          speakerNamed:
              cue.speaker != null && doc.speakers.containsKey(cue.speaker),
          view: controller.view,
          selected: position == controller.selected,
          onTap: () => controller.select(position),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.speakers,
    required this.showHint,
    required this.onManageSpeakers,
  });

  final EditorController controller;
  final bool speakers;
  final bool showHint;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final compact = isCompactEditor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            // 窄窗口收到 150，给右侧的筛选 chip 多让出位置。
            width: compact
                ? 150
                : speakers
                ? 188
                : 240,
            height: 32,
            child: TextField(
              onChanged: controller.setSearch,
              style: context.texts.bodyMedium,
              decoration: InputDecoration(
                hintText: '搜索原文 / 译文',
                hintStyle: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Symbols.search,
                  size: 18,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 32,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FilterChipBar(
                value: controller.filter.name,
                onChanged: (name) =>
                    controller.setFilter(CueFilter.values.byName(name)),
                items: [
                  for (final f in CueFilter.values)
                    // 只挂原文时没有「未翻译」可筛；「未配对」只在真有对不上的行时出现。
                    // 窄窗口再藏掉数量为 0 的，「全部」与当前选中的除外。
                    if (switch (f) {
                          CueFilter.untranslated => controller.hasTranslations,
                          CueFilter.unpaired => controller.countOf(f) > 0,
                          _ => true,
                        } &&
                        (!compact ||
                            f == CueFilter.all ||
                            f == controller.filter ||
                            controller.countOf(f) > 0))
                      (key: f.name, label: f.label, count: controller.countOf(f)),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          if (speakers)
            _SpeakerFilterChip(
              controller: controller,
              onManageSpeakers: onManageSpeakers,
            )
          else if (showHint) ...[
            Icon(
              Symbols.keyboard,
              size: 16,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s1 + 2),
            Text(
              'J/K 上下条 · Enter 标记已校对 · ⌘Z 撤销',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具栏右侧的说话人筛选：多选，勾「全部」清空其余项。
class _SpeakerFilterChip extends StatelessWidget {
  const _SpeakerFilterChip({
    required this.controller,
    required this.onManageSpeakers,
  });

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final filter = controller.speakerFilter;
    final doc = controller.document;
    final label = switch (filter.length) {
      0 => '说话人 · 全部',
      1 when filter.single != null => '说话人 · ${doc.speakerName(filter.single!)}',
      1 => '说话人 · 无',
      _ => '说话人 · ${filter.length} 位',
    };

    // 窄窗口只留图标，给筛选 chip 让位；筛了人时底色变，文案进悬停提示。
    final compact = isCompactEditor(context);

    return AnchoredPopover(
      width: 268,
      alignRight: true,
      anchor: (context, toggle, open) => Tooltip(
        message: compact ? label : '',
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: filter.isEmpty ? null : cs.secondaryContainer,
            border: Border.all(
              color: filter.isEmpty ? cs.outlineVariant : Colors.transparent,
            ),
            gradient: filter.isEmpty
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: context.elevation.controlGradient,
                  )
                : null,
            boxShadow: filter.isEmpty ? context.elevation.controlShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.record_voice_over,
                      size: 18,
                      weight: 400,
                      color: cs.onSurfaceVariant,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: context.texts.labelLarge?.copyWith(
                          color: filter.isEmpty
                              ? cs.onSurfaceVariant
                              : cs.onSecondaryContainer,
                        ),
                      ),
                    ],
                    Icon(
                      open ? Symbols.expand_less : Symbols.expand_more,
                      size: 18,
                      weight: 400,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      popover: (context, close) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final filter = controller.speakerFilter;
          final unassigned = controller.document.cues
              .where((c) => c.speaker == null)
              .length;
          return GlassMenu(
            children: [
              MenuRow(
                leading: _Check(checked: filter.isEmpty),
                label: '全部',
                trailing: _count(context, controller.document.cues.length),
                onTap: () => controller.setSpeakerFilter({}),
              ),
              for (final s in controller.speakers)
                MenuRow(
                  leading: _Check(checked: filter.contains(s.id)),
                  label: s.name,
                  labelColor: s.named ? null : cs.onSurfaceVariant,
                  trailing: _count(context, s.cueCount),
                  onTap: () => controller.toggleSpeakerFilter(s.id),
                ),
              if (unassigned > 0)
                MenuRow(
                  leading: _Check(checked: filter.contains(null)),
                  label: '无说话人',
                  labelColor: cs.onSurfaceVariant,
                  trailing: _count(context, unassigned),
                  onTap: () => controller.toggleSpeakerFilter(null),
                ),
              const MenuDivider(),
              MenuRow(
                leading: Icon(
                  Symbols.group,
                  size: 18,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
                label: '管理说话人…',
                onTap: () {
                  close();
                  onManageSpeakers?.call();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _count(BuildContext context, int n) => Timecode(
    '$n',
    fontSize: 12,
    color: context.colors.onSurfaceVariant,
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked ? cs.primary : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: checked ? cs.primary : cs.outline),
      ),
      child: checked
          ? Icon(Symbols.check, size: 14, weight: 600, color: cs.onPrimary)
          : null,
    );
  }
}

/// 列宽与设计稿一致。null 为弹性列。
const _plainColumns = <double?>[52, 124, 124, null, null, 96];
const _speakerColumns = <double?>[52, 124, 104, null, null, 72];

/// 窄窗口：说话人列只留徽标，名字放进悬停提示。
const _compactSpeakerColumns = <double?>[52, 124, 44, null, null, 72];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.speakers,
    required this.compact,
    required this.onManageSpeakers,
    required this.onMountTranslation,
  });

  final List<double?> columns;
  final bool speakers;
  final bool compact;
  final VoidCallback? onManageSpeakers;
  final VoidCallback? onMountTranslation;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 13, right: AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: _Grid(
        columns: columns,
        children: [
          Text('#', style: style),
          Text('开始', style: style),
          if (speakers && compact)
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: '说话人 · 管理',
                child: InkWell(
                  onTap: onManageSpeakers,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Icon(
                    Symbols.record_voice_over,
                    size: 18,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else if (speakers)
            Row(
              children: [
                Text('说话人', style: style),
                const SizedBox(width: AppSpacing.s1),
                if (onManageSpeakers != null)
                  Tooltip(
                    message: '管理说话人',
                    child: InkWell(
                      onTap: onManageSpeakers,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: Icon(
                        Symbols.edit,
                        size: 16,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            )
          else
            Text('结束', style: style),
          Text('原文', style: style),
          Row(
            children: [
              Text('译文', style: style),
              if (onMountTranslation != null) ...[
                const SizedBox(width: AppSpacing.s2),
                Flexible(
                  child: InkWell(
                    onTap: onMountTranslation,
                    child: Text(
                      '+ 挂载译文…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text('状态', style: style),
        ],
      ),
    );
  }
}

class _CueRow extends StatefulWidget {
  const _CueRow({
    required this.cue,
    required this.state,
    required this.columns,
    required this.speakers,
    required this.compact,
    required this.continuesSpeaker,
    required this.speakerName,
    required this.speakerNamed,
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final Cue cue;
  final CueState state;
  final List<double?> columns;
  final bool speakers;
  final bool compact;

  /// 和上一行同一个人：只画竖线，不重复徽标与名字。
  final bool continuesSpeaker;

  /// 说话人显示名；没有说话人为 null。
  final String? speakerName;
  final bool speakerNamed;
  final CueView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CueRow> createState() => _CueRowState();
}

class _CueRowState extends State<_CueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final cue = widget.cue;
    final isReview = widget.state == CueState.review;
    final unpaired = widget.state == CueState.unpaired;

    // 待校对用字幕黄的左缘 —— 这是设计规范里黄色仅有的两个用途之一。
    final edge = isReview
        ? cs.tertiary
        : widget.selected
        ? cs.primary
        : Colors.transparent;

    final background = widget.selected
        ? cs.secondaryContainer
        : isReview
        ? cs.tertiaryContainer.withValues(alpha: 0.45)
        : _hovered
        ? cs.onSurface.withValues(alpha: AppStateLayer.hover)
        : Colors.transparent;

    // 没有说话人列的旧布局里（比如任务会话关掉了分离），说话人写在原文前面。
    final sourceText = unpaired
        ? '— 没有对应的原文'
        : !widget.speakers && widget.speakerName != null
        ? '[${widget.speakerName}] ${cue.source}'
        : cue.source;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(right: AppSpacing.s4),
          decoration: BoxDecoration(
            color: background,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant),
              left: BorderSide(color: edge, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _Grid(
              columns: widget.columns,
              children: [
                Timecode(
                  cue.index.toString().padLeft(3, '0'),
                  color: cs.onSurfaceVariant,
                ),
                Timecode(Srt.formatTimecode(cue.startMs)),
                if (widget.speakers)
                  _SpeakerCell(
                    id: cue.speaker,
                    name: widget.speakerName,
                    named: widget.speakerNamed,
                    continues: widget.continuesSpeaker,
                    badgeOnly: widget.compact,
                  )
                else
                  Timecode(Srt.formatTimecode(cue.endMs)),
                if (widget.view != CueView.translation)
                  Text(
                    sourceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: unpaired ? cs.onSurfaceVariant : null,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (widget.view != CueView.source)
                  Text(
                    cue.hasTranslation ? cue.translation! : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: cue.hasTranslation
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CueStateTag(state: widget.state),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeakerCell extends StatelessWidget {
  const _SpeakerCell({
    required this.id,
    required this.name,
    required this.named,
    required this.continues,
    required this.badgeOnly,
  });

  final int? id;
  final String? name;
  final bool named;
  final bool continues;
  final bool badgeOnly;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    if (id == null) return const SizedBox.shrink();
    if (continues) {
      // 徽标中线位置的 1px 竖线，上下贯通到行边界。
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 9.5),
          width: 1,
          height: 40,
          color: cs.outlineVariant,
        ),
      );
    }
    if (badgeOnly) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: name!,
          child: SpeakerBadge(id: id!, name: name!, named: named),
        ),
      );
    }
    return Row(
      children: [
        SpeakerBadge(id: id!, name: name!, named: named),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: Text(
            name!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium?.copyWith(
              color: named ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 状态标签。未配对用虚线框，其余沿用 [StatusTag]。
class CueStateTag extends StatelessWidget {
  const CueStateTag({super.key, required this.state});

  final CueState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    if (state == CueState.unpaired) {
      return CustomPaint(
        painter: DashedRRectPainter(
          color: cs.outline,
          radius: AppRadius.xs,
          dash: 3,
          gap: 2,
        ),
        child: SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Center(
              widthFactor: 1,
              child: Text(
                '未配对',
                style: context.texts.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final (label, tone) = switch (state) {
      CueState.review => ('待校对', TagTone.review),
      CueState.untranslated => ('未翻译', TagTone.quiet),
      _ => ('已校对', TagTone.neutral),
    };
    return StatusTag(label: label, tone: tone);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.controller,
    required this.visibleCount,
    required this.showHint,
    required this.canSave,
  });

  final EditorController controller;
  final int visibleCount;
  final bool showHint;
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final doc = controller.document;
    final translated = controller.hasTranslations;
    var ok = 0, review = 0, untranslated = 0, unpaired = 0;
    for (final cue in doc.cues) {
      switch (displayStateOf(cue, translated: translated)) {
        case CueState.ok:
          ok++;
        case CueState.review:
          review++;
        case CueState.untranslated:
          untranslated++;
        case CueState.unpaired:
          unpaired++;
      }
    }
    final hint = showHint
        ? ' · J/K 上下条 · Enter 校对${canSave ? ' · ⌘S 保存' : ''}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '显示 $visibleCount / ${doc.cues.length}$hint',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Timecode(
            [
              '已校对 $ok',
              '待校对 $review',
              if (translated) '未翻译 $untranslated',
              if (unpaired > 0) '未配对 $unpaired',
            ].join(' · '),
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final List<double?> columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(width: AppSpacing.s3),
        if (columns[i] == null)
          Expanded(child: child)
        else
          SizedBox(width: columns[i], child: child),
      ],
    ],
  );
}
