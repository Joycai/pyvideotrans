import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'editor_controller.dart';

/// 字幕列表：# / 开始 / 结束 / 原文 / 译文 / 状态。
class CueTable extends StatelessWidget {
  const CueTable({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final visible = controller.visibleCues;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          _Toolbar(controller: controller),
          const _HeaderRow(),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      controller.document.cues.isEmpty
                          ? '这个任务还没有字幕'
                          : '没有符合条件的字幕',
                      style: context.texts.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final cue = visible[i];
                      final position = controller.document.cues.indexWhere(
                        (c) => c.index == cue.index,
                      );
                      return _CueRow(
                        cue: cue,
                        speakerName: cue.speaker == null
                            ? null
                            : controller.document.speakerName(cue.speaker!),
                        view: controller.view,
                        selected: position == controller.selected,
                        onTap: () => controller.select(position),
                      );
                    },
                  ),
          ),
          _Footer(controller: controller, visibleCount: visible.length),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
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
            width: 240,
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
          FilterChipBar(
            value: controller.filter.name,
            onChanged: (name) =>
                controller.setFilter(CueFilter.values.byName(name)),
            items: [
              // 「未配对」只在挂载本地原文与译文、且真有对不上的行时出现。
              for (final f in CueFilter.values)
                if (f != CueFilter.unpaired || controller.countOf(f) > 0)
                  (key: f.name, label: f.label, count: controller.countOf(f)),
            ],
          ),
          const Spacer(),
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
      ),
    );
  }
}

/// 列宽与设计稿一致。
const _columns = <double?>[52, 124, 124, null, null, 96];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

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
        children: [
          Text('#', style: style),
          Text('开始', style: style),
          Text('结束', style: style),
          Text('原文', style: style),
          Text('译文', style: style),
          Text('状态', style: style),
        ],
      ),
    );
  }
}

class _CueRow extends StatefulWidget {
  const _CueRow({
    required this.cue,
    required this.speakerName,
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final Cue cue;

  /// 说话人显示名；没有说话人为 null。
  final String? speakerName;
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
    final isReview = cue.state == CueState.review;

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

    final (tagLabel, tagTone) = switch (cue.state) {
      CueState.review => ('待校对', TagTone.review),
      CueState.untranslated => ('未翻译', TagTone.quiet),
      CueState.unpaired => ('未配对', TagTone.quiet),
      CueState.ok => ('已校对', TagTone.neutral),
    };

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
              children: [
                Timecode(
                  cue.index.toString().padLeft(3, '0'),
                  color: cs.onSurfaceVariant,
                ),
                Timecode(Srt.formatTimecode(cue.startMs)),
                Timecode(Srt.formatTimecode(cue.endMs)),
                if (widget.view != CueView.translation)
                  Text(
                    widget.speakerName == null
                        ? cue.source
                        : '[${widget.speakerName}] ${cue.source}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium,
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
                  child: StatusTag(label: tagLabel, tone: tagTone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.visibleCount});

  final EditorController controller;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final doc = controller.document;
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
          Text(
            '显示 $visibleCount / ${doc.cues.length}',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Timecode(
            '已校对 ${doc.okCount} · 待校对 ${doc.reviewCount} · '
            '未翻译 ${doc.untranslatedCount}',
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(width: AppSpacing.s3),
        if (_columns[i] == null)
          Expanded(child: child)
        else
          SizedBox(width: _columns[i], child: child),
      ],
    ],
  );
}
