import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/note_bar.dart';
import '../../domain/mux/merge_rules.dart';
import '../../domain/srt.dart';
import '../shared/new_task_file_table.dart';
import '../shared/new_task_panels.dart';
import 'merge_form.dart';

/// 合并页左列：「分段」面板。空时是落区与三步说明，有段时是有序段列表、
/// 章节起点条与追加落区。
class MergeSegmentsPanel extends StatelessWidget {
  const MergeSegmentsPanel({
    super.key,
    required this.form,
    required this.dragging,
    required this.onOpenTasks,
    required this.onDismissBanner,
    this.enqueued,
  });

  final MergeFormController form;
  final bool dragging;
  final VoidCallback onOpenTasks;
  final VoidCallback onDismissBanner;

  /// 刚入队的条数，非 null 时显示横幅。
  final int? enqueued;

  @override
  Widget build(BuildContext context) {
    final segments = form.segments;
    final rejected = form.rejected;
    return NewTaskFilePanel(
      title: '分段',
      browseLabel: '添加视频…',
      count: segments.length,
      dragging: dragging,
      enqueued: enqueued,
      onClear: form.clear,
      onBrowse: form.browse,
      onOpenTasks: onOpenTasks,
      onDismissBanner: onDismissBanner,
      header: rejected == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NoteBar(text: rejected, onClose: form.clearRejected),
                const SizedBox(height: AppSpacing.s3),
              ],
            ),
      child: segments.isEmpty
          ? FileDropEmptyState(
              icon: Symbols.merge,
              title: '把要合并的视频拖到这里',
              formats: '至少 2 段，按添加顺序首尾相接 · MP4 · MOV · MKV · TS · M2TS',
              formatsAlign: TextAlign.center,
              note: '视频旁有同名的 .srt / .vtt 会一起挂上；也可以把字幕单独拖进来',
              steps: const ['添加视频（2 段以上）', '排好顺序、挂上字幕', '加入队列，进度在任务页'],
              dragging: dragging,
              enqueued: enqueued,
              onBrowse: form.browse,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 列表是里面唯一的弹性项：随行数长高，放不下时在表内滚动；
                // 外层的 Expanded 让追加落区始终贴底。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(child: MergeSegmentList(form: form)),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        '按列表顺序首尾相接，第 1 段是参数基准；拖动左侧把手或点箭头调整顺序',
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      MergeTimelineStrip(form: form),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                FileAppendStrip(
                  icon: Symbols.movie,
                  dragging: dragging,
                  label: '继续拖入视频追加为新段；拖入字幕会配给同名、还没挂字幕的段',
                ),
              ],
            ),
    );
  }
}

/// 列宽：把手 | 序号 | 文件·章节·字幕 | 时长 | 视频 | 音频 | 状态 | 操作。
const _handleW = 20.0;
const _indexW = 24.0;
const _durationW = 56.0;
const _videoW = 128.0;
const _audioW = 104.0;
const _stateW = 84.0;
const _actionsW = 92.0;
const _gap = 10.0;

/// 行宽低于这个值时收起时长、音频两列，写进文件那一格的第二行。
const _wideRow = 760.0;

/// 有序段列表：表头 + 可拖动排序的行。行多了在表内滚动。
class MergeSegmentList extends StatelessWidget {
  const MergeSegmentList({super.key, required this.form});

  final MergeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final segments = form.segments;
    final issues = form.issues;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth - AppSpacing.s3 * 2 >= _wideRow;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(wide: wide),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  itemCount: segments.length,
                  onReorderItem: form.reorder,
                  // 拖起的行画在 Overlay 里，上面没有 Material，行内的输入框
                  // 会断言失败；默认代理自带 Material，换成自定义时要补上。
                  proxyDecorator: (child, _, _) => Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        boxShadow: context.elevation.shadow2,
                      ),
                      child: child,
                    ),
                  ),
                  itemBuilder: (context, i) => MergeSegmentRow(
                    key: ValueKey(segments[i].id),
                    form: form,
                    index: i,
                    issue: issues[i],
                    wide: wide,
                    last: i == segments.length - 1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    Widget cell(double w, String text, {bool end = false}) => SizedBox(
      width: w,
      child: Text(text, style: style, textAlign: end ? TextAlign.right : null),
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _handleW + _gap),
          cell(_indexW, '#'),
          const SizedBox(width: _gap),
          Expanded(child: Text('文件 · 章节 · 字幕', style: style)),
          if (wide) ...[
            const SizedBox(width: _gap),
            cell(_durationW, '时长', end: true),
          ],
          const SizedBox(width: _gap),
          cell(_videoW, '视频'),
          if (wide) ...[const SizedBox(width: _gap), cell(_audioW, '音频')],
          const SizedBox(width: _gap),
          cell(_stateW, '状态'),
          const SizedBox(width: _gap + _actionsW),
        ],
      ),
    );
  }
}

/// 一段：第一行是文件与探测结果，第二行是章节与字幕，出问题时第三行说明。
class MergeSegmentRow extends StatefulWidget {
  const MergeSegmentRow({
    super.key,
    required this.form,
    required this.index,
    required this.issue,
    required this.wide,
    required this.last,
  });

  final MergeFormController form;
  final int index;
  final MergeIssue? issue;
  final bool wide;
  final bool last;

  @override
  State<MergeSegmentRow> createState() => _MergeSegmentRowState();
}

class _MergeSegmentRowState extends State<MergeSegmentRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = widget.form;
    final i = widget.index;
    final s = form.segments[i];
    final issue = widget.issue;
    final problem = s.probeError != null
        ? '读不出音视频流：${s.probeError}'
        : issue?.message;
    final bad = problem != null;
    final n = form.segments.length;

    final mono = AppTextStyles.timecode.copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    Color? flag(MergeIssueKind k) =>
        issue?.kind == k || issue?.kind == MergeIssueKind.streams
        ? cs.error
        : null;
    Widget twoLines(String? top, String? bottom, {Color? color}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono.copyWith(
            color: color ?? cs.onSurface,
            fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        if (bottom != null && bottom.isNotEmpty)
          Text(
            bottom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono.copyWith(
              color: color,
              fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
      ],
    );
    final duration = s.duration == null ? '—' : Srt.formatDuration(s.duration!);

    final firstLine = SizedBox(
      height: 40,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: i,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Icon(
                Symbols.drag_indicator,
                size: _handleW,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: _gap),
          Container(
            width: _indexW,
            height: _indexW,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text('${i + 1}', style: mono.copyWith(color: cs.onSurface)),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Tooltip(
              message: s.videoPath,
              waitDuration: const Duration(milliseconds: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // 窄行收起了时长、音频两列，写在这一行；放在目录前面，
                  // 截断时先丢的是目录（完整路径在 tooltip 里）。
                  Text.rich(
                    TextSpan(
                      children: [
                        if (!widget.wide) ...[
                          TextSpan(text: '$duration · '),
                          TextSpan(
                            text:
                                '${[s.audioCodecLabel ?? '—', s.audioShape].nonNulls.join(' ')} · ',
                            style: switch (flag(MergeIssueKind.audio)) {
                              final c? => TextStyle(
                                color: c,
                                fontWeight: FontWeight.w600,
                              ),
                              null => null,
                            },
                          ),
                        ],
                        TextSpan(text: s.directory),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.wide) ...[
            const SizedBox(width: _gap),
            SizedBox(
              width: _durationW,
              child: Text(duration, textAlign: TextAlign.right, style: mono),
            ),
          ],
          const SizedBox(width: _gap),
          SizedBox(
            width: _videoW,
            child: twoLines(
              s.videoCodecLabel,
              s.videoShape,
              color: flag(MergeIssueKind.video),
            ),
          ),
          if (widget.wide) ...[
            const SizedBox(width: _gap),
            SizedBox(
              width: _audioW,
              child: twoLines(
                s.audioCodecLabel,
                s.audioShape,
                color: flag(MergeIssueKind.audio),
              ),
            ),
          ],
          const SizedBox(width: _gap),
          SizedBox(
            width: _stateW,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SegmentChip(segment: s, issue: issue),
            ),
          ),
          const SizedBox(width: _gap),
          SizedBox(
            width: _actionsW,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconActionButton(
                  icon: Symbols.arrow_upward,
                  tooltip: '上移',
                  size: 28,
                  iconSize: 18,
                  onPressed: i == 0 ? null : () => form.moveUp(i),
                ),
                IconActionButton(
                  icon: Symbols.arrow_downward,
                  tooltip: '下移',
                  size: 28,
                  iconSize: 18,
                  onPressed: i == n - 1 ? null : () => form.moveDown(i),
                ),
                IconActionButton(
                  icon: Symbols.close,
                  tooltip: '移除',
                  size: 28,
                  iconSize: 18,
                  onPressed: () => form.remove(i),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    const indent = _handleW + _gap + _indexW + _gap;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: _hover ? cs.onSurface.withValues(alpha: 0.06) : null,
          border: Border(
            left: BorderSide(
              color: bad ? cs.error : Colors.transparent,
              width: 3,
            ),
            bottom: widget.last
                ? BorderSide.none
                : BorderSide(color: cs.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s3 - 3,
          AppSpacing.s2 + 2,
          AppSpacing.s3,
          AppSpacing.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            firstLine,
            const SizedBox(height: AppSpacing.s2),
            Padding(
              padding: const EdgeInsets.only(left: indent),
              child: Wrap(
                spacing: AppSpacing.s5,
                runSpacing: AppSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ChapterField(form: form, index: i, wide: widget.wide),
                  _SubtitleBlock(form: form, index: i),
                ],
              ),
            ),
            if (problem != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Padding(
                padding: const EdgeInsets.only(left: indent),
                child: Row(
                  children: [
                    Icon(Symbols.error, size: 16, weight: 400, color: cs.error),
                    const SizedBox(width: AppSpacing.s1 + 2),
                    Expanded(
                      child: Text(
                        problem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall?.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.segment, required this.issue});

  final StagedSegment segment;
  final MergeIssue? issue;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch ((segment, issue)) {
      (StagedSegment(probing: true), _) => (
        '读取中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      (StagedSegment(probeError: _?), _) ||
      (
        _,
        MergeIssue(kind: MergeIssueKind.duration),
      ) => ('无法读取', Symbols.error, cs.errorContainer, cs.onErrorContainer),
      (_, MergeIssue(kind: MergeIssueKind.container)) => (
        '不兼容',
        Symbols.block,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
      (_, _?) => ('不一致', Symbols.error, cs.errorContainer, cs.onErrorContainer),
      _ => ('就绪', Symbols.check, ext.successContainer, ext.onSuccessContainer),
    };
    return StateChip(label: label, icon: icon, bg: bg, fg: fg);
  }
}

class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.texts.labelMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    ),
  );
}

/// 章节标题：输入即写回，清空后失焦回填默认。关掉「添加章节」时禁用。
class _ChapterField extends StatelessWidget {
  const _ChapterField({
    required this.form,
    required this.index,
    required this.wide,
  });

  final MergeFormController form;
  final int index;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final enabled = form.options.chapters;
    final s = form.segments[index];
    Widget field = SizedBox(
      width: 232,
      height: 32,
      child: Focus(
        // 只借它收「失焦」，自己不当 Tab 停靠点。
        skipTraversal: true,
        onFocusChange: (focused) {
          if (!focused) form.commitChapterTitle(index);
        },
        child: SingleLineField(
          key: ValueKey('chapter-${s.id}'),
          value: s.chapterTitle,
          onChanged: (v) => form.setChapterTitle(index, v),
        ),
      ),
    );
    if (!enabled) {
      field = Tooltip(
        message: '添加章节已关闭',
        child: ExcludeFocus(
          child: IgnorePointer(child: Opacity(opacity: 0.38, child: field)),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BlockLabel('章节'),
        const SizedBox(width: AppSpacing.s2),
        field,
      ],
    );
  }
}

/// 字幕：已挂（条数 / 读取中 / 读不出）或「挂字幕…」。
class _SubtitleBlock extends StatelessWidget {
  const _SubtitleBlock({required this.form, required this.index});

  final MergeFormController form;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final s = form.segments[index];
    final path = s.subtitlePath;
    final Widget body;
    if (path == null) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QuietButton(
            label: '挂字幕…',
            icon: Symbols.add,
            height: 32,
            onPressed: () => form.browseSubtitle(index),
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            '这一段不出字幕，时长照算',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    } else {
      final failed = s.subtitleError != null;
      final fg = failed ? cs.onErrorContainer : cs.onSurface;
      final count = s.subtitleParsing
          ? '读取中'
          : failed
          ? '读不出字幕'
          : '${s.subtitleCues} 条';
      body = Tooltip(
        message: s.subtitleError ?? path,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: failed ? cs.errorContainer : cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => form.browseSubtitle(index),
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.subtitles, size: 18, weight: 400, color: fg),
                    const SizedBox(width: AppSpacing.s1 + 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        s.subtitlePath!.split(RegExp(r'[/\\]')).last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(color: fg),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Text(
                      count,
                      style: AppTextStyles.timecode.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: failed ? fg : cs.onSurfaceVariant,
                      ),
                    ),
                    if (s.subtitleAuto) ...[
                      const SizedBox(width: AppSpacing.s2),
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s1 + 2,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          '同名自动挂上',
                          style: context.texts.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    IconActionButton(
                      icon: Symbols.close,
                      tooltip: '摘下字幕',
                      size: 24,
                      iconSize: 16,
                      onPressed: () => form.detachSubtitle(index),
                    ),
                    const SizedBox(width: AppSpacing.s1),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BlockLabel('字幕'),
        const SizedBox(width: AppSpacing.s2),
        Flexible(child: body),
      ],
    );
  }
}

/// 章节起点条：每段一块，宽度按时长，写起点。与章节、字幕平移用的是同一份偏移。
class MergeTimelineStrip extends StatelessWidget {
  const MergeTimelineStrip({super.key, required this.form});

  final MergeFormController form;

  static const minBlock = 112.0;
  static const _spacing = 3.0;

  /// 还没读出时长的段按 10 分钟占位。
  static const _placeholder = Duration(minutes: 10);

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final segments = form.segments;
    if (segments.isEmpty) return const SizedBox.shrink();
    final offsets = form.offsets;
    final issues = form.issues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: '章节起点',
            style: context.texts.labelMedium,
            children: [
              TextSpan(
                text: ' · 字幕按同样的起点平移',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        SizedBox(
          height: 36,
          child: LayoutBuilder(
            builder: (context, c) {
              final weights = [
                for (final s in segments)
                  (s.duration ?? _placeholder).inMilliseconds.toDouble(),
              ];
              final avail = c.maxWidth - _spacing * (segments.length - 1);
              final widths = _widths(weights, avail);
              final blocks = [
                for (final (i, s) in segments.indexed)
                  _Block(
                    width: widths?[i] ?? minBlock,
                    number: i + 1,
                    start: offsets[i],
                    // 前面（含自己）还有段在读，起点才是「读取中」；
                    // 否则是前面有段读不出，起点永远算不出来。
                    pending: segments.take(i + 1).any((s) => s.probing),
                    segment: s,
                    bad: s.probeError != null || issues[i] != null,
                  ),
              ];
              final row = Row(
                children: [
                  for (final (i, b) in blocks.indexed) ...[
                    if (i > 0) const SizedBox(width: _spacing),
                    b,
                  ],
                ],
              );
              // 放不下时改成等宽块、横向滚动。
              return widths == null
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: row,
                    )
                  : row;
            },
          ),
        ),
      ],
    );
  }

  /// 按时长分配宽度，太短的补到 [minBlock]，其余按比例分剩下的。
  /// 所有块都按最小宽也放不下时返回 null。
  static List<double>? _widths(List<double> weights, double avail) {
    if (weights.length * minBlock > avail) return null;
    final fixed = <int>{};
    while (true) {
      final rest = avail - fixed.length * minBlock;
      final total = [
        for (final (i, w) in weights.indexed)
          if (!fixed.contains(i)) w,
      ].fold(0.0, (a, b) => a + b);
      // 剩下的都是零时长（读不出时长的段）时平分，别每块都占满整条。
      final free = weights.length - fixed.length;
      var changed = false;
      final out = <double>[];
      for (final (i, w) in weights.indexed) {
        if (fixed.contains(i)) {
          out.add(minBlock);
          continue;
        }
        final width = total <= 0 ? rest / free : rest * w / total;
        if (width < minBlock) {
          fixed.add(i);
          changed = true;
        }
        out.add(width);
      }
      if (!changed) return out;
    }
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.pending,
    required this.number,
    required this.start,
    required this.segment,
    required this.bad,
  });

  final double width;
  final bool pending;
  final int number;
  final Duration? start;
  final StagedSegment segment;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final probing = segment.probing;
    final unknown = probing || start == null;
    final unknownLabel = pending ? '读取中' : '—';
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      child: Row(
        children: [
          Text(
            '#$number',
            style: AppTextStyles.timecode.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.s1 + 2),
          Expanded(
            child: unknown
                ? Text(
                    unknownLabel,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: context.texts.bodySmall,
                  )
                : Text(
                    Srt.formatTimecode(start!.inMilliseconds).split(',').first,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: AppTextStyles.timecode.copyWith(
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                  ),
          ),
          if (segment.cues != null)
            Icon(
              Symbols.subtitles,
              size: 16,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );
    final tooltip = [
      '第 $number 段',
      segment.fileName,
      if (segment.duration != null) Srt.formatDuration(segment.duration!),
    ].join(' · ');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: width,
        height: 36,
        child: probing
            ? CustomPaint(
                painter: DashedBorder(color: cs.outline, radius: AppRadius.sm),
                child: content,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: bad
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: bad ? cs.error : cs.outlineVariant),
                ),
                child: content,
              ),
      ),
    );
  }
}
