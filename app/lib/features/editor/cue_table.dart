import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import 'cue_table_rows.dart';
import 'cue_table_toolbar.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_shortcuts.dart';
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
    required this.focusNode,
    this.onManageSpeakers,
    this.onMountTranslation,
  });

  final EditorController controller;

  /// 字幕列表的焦点。单键快捷键挂在它上面，见 [CueTableShortcuts]。
  final FocusNode focusNode;
  final VoidCallback? onManageSpeakers;

  /// 只挂了原文时，译文表头上的「+ 挂载译文…」。
  final VoidCallback? onMountTranslation;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final visible = controller.visiblePositions;
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

    final radius = BorderRadius.circular(AppRadius.lg);
    // 列表有焦点时描一圈主色：单键快捷键此刻生效。画在前景上，不挤内容。
    final table = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          CueTableToolbar(
            controller: controller,
            speakers: speakers,
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
            child: CueTableShortcuts(
              controller: controller,
              focusNode: focusNode,
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
                    focusNode: focusNode,
                    visible: visible,
                    columns: columns,
                    speakers: speakers,
                    compact: compact,
                    translated: translated,
                  ),
            ),
          ),
          _Footer(
            controller: controller,
            visibleCount: visible.length,
            tableFocus: focusNode,
          ),
        ],
      ),
    );
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) => AnimatedContainer(
        duration: AppDuration.short,
        curve: AppEasing.standard,
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: focusNode.hasFocus ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
      child: table,
    );
  }
}

/// 字幕行列表。行高固定 40，选中条变化时（J/K、播放跟随）把它滚进视野；
/// 已经看得见就不动，免得点一下就跳。
class _CueList extends StatefulWidget {
  const _CueList({
    required this.controller,
    required this.focusNode,
    required this.visible,
    required this.columns,
    required this.speakers,
    required this.compact,
    required this.translated,
  });

  final EditorController controller;
  final FocusNode focusNode;

  /// 看得见的行在文档里的下标，按显示顺序。
  final List<int> visible;
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
    final row = widget.visible.indexOf(widget.controller.selected);
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
    // 一次算好选中集合，别让每一行各算一遍。
    final chosen = controller.selectedPositions.toSet();
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemExtent: _CueList.rowHeight,
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final position = visible[i];
        final cue = doc.cues[position];
        // 连续说话人按看得见的上一行算：筛选后行与行不一定相邻。
        final previous = i > 0 ? doc.cues[visible[i - 1]].speaker : null;
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
          selected: chosen.contains(position),
          focused: position == controller.selected,
          onTap: () {
            // 点行就让列表拿焦点：单键快捷键跟着生效。
            widget.focusNode.requestFocus();
            // Shift 优先：主修饰键 + Shift 也按扩选处理。主修饰键按平台区分，
            // macOS 上的 Ctrl+点击是系统右键。
            controller.selectWith(
              position,
              extend: HardwareKeyboard.instance.isShiftPressed,
              toggle: isPrimaryModifierPressed(),
            );
          },
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.controller,
    required this.visibleCount,
    required this.tableFocus,
  });

  final EditorController controller;
  final int visibleCount;

  /// 提示跟着列表有没有焦点变，自己听它，不靠上层重建。
  final FocusNode tableFocus;

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
            child: ListenableBuilder(
              listenable: tableFocus,
              builder: (context, _) => Text(
                '显示 $visibleCount / ${doc.cues.length} · '
                '${editorFooterHint(controller, tableFocused: tableFocus.hasFocus)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Tooltip(
            message: editorShortcutSheet(),
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s3),
              child: Icon(
                Symbols.keyboard,
                size: 16,
                weight: 400,
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
