import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import 'cue_table_rows.dart';
import 'cue_table_toolbar.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';

/// 列宽与设计稿一致。null 为弹性列。
const _plainColumns = <double?>[52, 124, 124, null, null, 96];
const _speakerColumns = <double?>[52, 124, 104, null, null, 72];

/// 窄窗口：说话人列只留徽标，名字放进悬停提示。
const _compactSpeakerColumns = <double?>[52, 124, 44, null, null, 72];

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
          CueTableToolbar(
            controller: controller,
            speakers: speakers,
            showHint: !isFile && !speakers,
            onManageSpeakers: onManageSpeakers,
          ),
          CueTableHeader(
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
      curve: AppEasing.standard,
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
        return CueTableRow(
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
          edited: controller.isEdited(cue),
          selected: position == controller.selected,
          onTap: () => controller.select(position),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.controller,
    required this.visibleCount,
    required this.showHint,
  });

  final EditorController controller;
  final int visibleCount;
  final bool showHint;

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
        // 两种会话都能 ⌘S：写的是字幕文件，编辑进度本来就在自动存。
        ? ' · J/K 上下条 · Enter 校对 · ⌘S 保存到文件'
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
