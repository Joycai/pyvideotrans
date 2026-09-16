import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'editor_controller.dart';
import 'speaker_badge.dart';

class CueTableHeader extends StatelessWidget {
  const CueTableHeader({
    super.key,
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
      child: CueTableGrid(
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

class CueTableRow extends StatefulWidget {
  const CueTableRow({
    super.key,
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
  State<CueTableRow> createState() => _CueRowState();
}

class _CueRowState extends State<CueTableRow> {
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
            child: CueTableGrid(
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

class CueTableGrid extends StatelessWidget {
  const CueTableGrid({
    super.key,
    required this.columns,
    required this.children,
  });

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
