import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'cue_table.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

/// 右侧 440px 检视面板：预览 + 当前条的编辑。
class Inspector extends StatelessWidget {
  const Inspector({
    super.key,
    required this.controller,
    required this.onRetranslate,
    this.onManageSpeakers,
    this.onMountTranslation,
  });

  final EditorController controller;
  final void Function(int index) onRetranslate;
  final VoidCallback? onManageSpeakers;
  final VoidCallback? onMountTranslation;

  @override
  Widget build(BuildContext context) {
    final cue = controller.current;
    return GlassPanel(
      child: cue == null
          ? Center(
              child: Text(
                '选择一条字幕开始校对',
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Preview(cue: cue, controller: controller),
                  _CueEditor(
                    controller: controller,
                    onRetranslate: onRetranslate,
                    onManageSpeakers: onManageSpeakers,
                    onMountTranslation: onMountTranslation,
                  ),
                ],
              ),
            ),
    );
  }
}

/// 预览区。
///
/// 第一期不做视频解码与播放（那要引入 media_kit / video_player 这类重依赖，
/// 与「音视频转字幕 + 字幕翻译」两项核心功能无关）。这里保留设计稿的版位，
/// 并在画面里明说尚未实施，而不是画一个看起来能点实际上不能用的播放器。
/// 本地字幕会话没有视频，版位压到 150px 高，只预览字幕样式。
class _Preview extends StatelessWidget {
  const _Preview({required this.cue, required this.controller});

  final Cue cue;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isFile = controller.session is FileSession;
    final showTranslation =
        cue.hasTranslation &&
        (controller.view == CueView.translation || cue.source.trim().isEmpty);

    final screen = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E11),
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: AppSpacing.s3,
            child: Text(
              isFile ? '未关联视频 · 只预览字幕样式' : '视频预览 · 第一期未实施',
              style: kTimecodeStyle.copyWith(
                fontSize: 11,
                color: const Color(0xFF8A9099),
              ),
            ),
          ),
          // 字幕样式预览用的是真实数据，这一块是有用的。
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2 + 2,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  showTranslation ? cue.translation! : cue.source,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF2CE4E),
                    fontSize: 16,
                    height: 24 / 16,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isFile)
            SizedBox(height: 150, child: screen)
          else
            AspectRatio(aspectRatio: 16 / 9, child: screen),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              IconActionButton(
                icon: Symbols.skip_previous,
                tooltip: '上一条',
                onPressed: () => controller.step(-1),
              ),
              IconActionButton(
                icon: Symbols.skip_next,
                tooltip: '下一条',
                onPressed: () => controller.step(1),
              ),
              const SizedBox(width: AppSpacing.s2),
              // 窄一点的字体下时间码会把标签挤出去，允许整组缩小。
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Timecode(Srt.formatTimecode(cue.startMs)),
                      Text(
                        ' / ',
                        style: kTimecodeStyle.copyWith(color: cs.outline),
                      ),
                      Timecode(
                        Srt.formatTimecode(
                          controller.document.duration.inMilliseconds,
                        ),
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              StatusTag(label: '${cue.durationMs / 1000}s', tone: TagTone.neutral),
            ],
          ),
        ],
      ),
    );
  }
}

class _CueEditor extends StatefulWidget {
  const _CueEditor({
    required this.controller,
    required this.onRetranslate,
    required this.onManageSpeakers,
    required this.onMountTranslation,
  });

  final EditorController controller;
  final void Function(int index) onRetranslate;
  final VoidCallback? onManageSpeakers;
  final VoidCallback? onMountTranslation;

  @override
  State<_CueEditor> createState() => _CueEditorState();
}

class _CueEditorState extends State<_CueEditor> {
  final _source = TextEditingController();
  final _translation = TextEditingController();
  final _sourceFocus = FocusNode();
  final _translationFocus = FocusNode();
  int? _boundIndex;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_CueEditor old) {
    super.didUpdateWidget(old);
    _bind();
  }

  /// 选中条变化时重填输入框；同一条被别处改了（撤销、合并、重新翻译）时，
  /// 只重填没在编辑的那一路 —— 正在打字的框重填会把光标顶回开头。
  void _bind() {
    final controller = widget.controller;
    final cue = controller.current;
    if (cue == null) return;
    final changedRow = _boundIndex != controller.selected;
    _boundIndex = controller.selected;
    if (changedRow || (!_sourceFocus.hasFocus && _source.text != cue.source)) {
      _source.text = cue.source;
    }
    final translation = cue.translation ?? '';
    if (changedRow ||
        (!_translationFocus.hasFocus && _translation.text != translation)) {
      _translation.text = translation;
    }
  }

  @override
  void dispose() {
    _source.dispose();
    _translation.dispose();
    _sourceFocus.dispose();
    _translationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final cs = context.colors;
    final controller = widget.controller;
    final session = controller.session;
    final cue = controller.current!;
    final busy = controller.translating.contains(controller.selected);
    final state = controller.displayState(cue);
    final isFile = session is FileSession;
    final singleFile = isFile && !controller.hasTranslations;
    final unpaired = state == CueState.unpaired;
    final last = controller.selected >= controller.document.cues.length - 1;

    final retranslate = QuietButton(
      label: busy ? '翻译中…' : '重新翻译此条',
      icon: Symbols.refresh,
      height: 24,
      onPressed: busy || cue.source.trim().isEmpty
          ? null
          : () => widget.onRetranslate(controller.selected),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s4,
        children: [
          Row(
            children: [
              Text('第 ', style: context.texts.titleSmall),
              Timecode(cue.index.toString().padLeft(3, '0')),
              Text(' 条', style: context.texts.titleSmall),
              const Spacer(),
              CueStateTag(state: state),
            ],
          ),
          Row(
            spacing: AppSpacing.s3,
            children: [
              Expanded(
                child: _TimecodeField(
                  label: '开始',
                  ms: cue.startMs,
                  onChanged: controller.editStart,
                ),
              ),
              Expanded(
                child: _TimecodeField(
                  label: '结束',
                  ms: cue.endMs,
                  onChanged: controller.editEnd,
                ),
              ),
            ],
          ),
          if (controller.document.hasSpeakers)
            _SpeakerField(
              controller: controller,
              onManageSpeakers: widget.onManageSpeakers,
            ),
          if (unpaired)
            _Labeled(
              label: '原文 · ${session.sourceLanguage.name}',
              child: _DashedBox(
                children: [
                  Text(
                    '这一条译文找不到对应的原文',
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      QuietButton(
                        label: '并入上一条',
                        height: 32,
                        onPressed: controller.selected == 0
                            ? null
                            : controller.mergeWithPrevious,
                      ),
                      QuietButton(
                        label: '并入下一条',
                        height: 32,
                        onPressed: last ? null : controller.mergeWithNext,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            _Field(
              label: '原文 · ${session.sourceLanguage.name}',
              trailing: switch (session) {
                FileSession(:final sourcePath) => _FileName(baseName(sourcePath)),
                _ when cue.confidence != null => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '置信度 ',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Timecode(
                      cue.confidence!.toStringAsFixed(2),
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                _ => null,
              },
              controller: _source,
              focusNode: _sourceFocus,
              focused: true,
              onSubmitted: controller.editSource,
            ),
          if (singleFile)
            _Labeled(
              label: '译文 · ${session.targetLanguage.name}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s2,
                children: [
                  _DashedBox(
                    center: true,
                    children: [
                      Text(
                        '这份字幕还没有译文',
                        style: context.texts.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    spacing: AppSpacing.s2,
                    children: [
                      ControlButton(
                        label: busy ? '翻译中…' : '翻译此条…',
                        icon: Symbols.translate,
                        dense: true,
                        onPressed: busy
                            ? null
                            : () => widget.onRetranslate(controller.selected),
                      ),
                      QuietButton(
                        label: '挂载译文文件',
                        height: 32,
                        onPressed: widget.onMountTranslation,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            _Field(
              label: '译文 · ${session.targetLanguage.name}',
              trailing: switch (session) {
                FileSession(:final mountedTranslationPath?) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: _FileName(baseName(mountedTranslationPath))),
                    const SizedBox(width: 10),
                    retranslate,
                  ],
                ),
                _ => retranslate,
              },
              controller: _translation,
              focusNode: _translationFocus,
              onSubmitted: controller.editTranslation,
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: AppSpacing.s2,
            children: [
              QuietButton(
                label: '拆分',
                icon: Symbols.call_split,
                onPressed: cue.source.length < 2 ? null : controller.split,
              ),
              QuietButton(
                label: '合并下一条',
                icon: Symbols.call_merge,
                onPressed: last ? null : controller.mergeWithNext,
              ),
              PrimaryButton(
                label: cue.reviewed ? '取消已校对' : '标记已校对',
                icon: Symbols.check,
                onPressed: controller.toggleReviewed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileName extends StatelessWidget {
  const _FileName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    ),
  );
}

/// 说话人字段与它的下拉：先定应用范围，再选人。
class _SpeakerField extends StatelessWidget {
  const _SpeakerField({required this.controller, this.onManageSpeakers});

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final doc = controller.document;
    final cue = controller.current!;
    final id = cue.speaker;
    final summary = controller.speakers.where((s) => s.id == id).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '说话人',
              style: context.texts.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (onManageSpeakers != null)
              InkWell(
                onTap: onManageSpeakers,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Row(
                  children: [
                    Icon(Symbols.group, size: 16, weight: 400, color: cs.primary),
                    const SizedBox(width: AppSpacing.s1),
                    Text(
                      '管理说话人',
                      style: context.texts.bodySmall?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        AnchoredPopover(
          matchAnchorWidth: true,
          anchor: (context, toggle, open) => ControlSurface(
            focused: open,
            onTap: toggle,
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Row(
              children: [
                if (id != null) ...[
                  SpeakerBadge(
                    id: id,
                    name: doc.speakerName(id),
                    named: doc.speakers.containsKey(id),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                ],
                Expanded(
                  child: Text(
                    id == null ? '无说话人' : doc.speakerName(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: id != null && doc.speakers.containsKey(id)
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (summary != null)
                  Text(
                    '${summary.cueCount} 条',
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                Icon(
                  open ? Symbols.expand_less : Symbols.expand_more,
                  size: 20,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
          popover: (context, close) =>
              _SpeakerMenu(controller: controller, close: close),
        ),
      ],
    );
  }
}

class _SpeakerMenu extends StatefulWidget {
  const _SpeakerMenu({required this.controller, required this.close});

  final EditorController controller;
  final VoidCallback close;

  @override
  State<_SpeakerMenu> createState() => _SpeakerMenuState();
}

class _SpeakerMenuState extends State<_SpeakerMenu> {
  bool _run = false;
  bool _adding = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _assign(int? id) {
    widget.controller.assignSpeaker(id, run: _run);
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final controller = widget.controller;
    final cue = controller.current;
    if (cue == null) return const SizedBox.shrink();
    final runLength = controller.currentRunLength;
    final range = controller.document.speakerRun(controller.selected);
    String n(int position) =>
        controller.document.cues[position].index.toString().padLeft(3, '0');

    return GlassMenu(
      children: [
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Row(
              children: [
                Text(
                  '应用范围',
                  style: context.texts.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                MiniSegmented<bool>(
                  height: 28,
                  value: _run && runLength > 1,
                  onChanged: (v) => setState(() => _run = v),
                  segments: [
                    (value: false, label: '这一条'),
                    if (runLength > 1)
                      (
                        value: true,
                        label: '连续 $runLength 条 · ${n(range.start)}–${n(range.end)}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const MenuDivider(),
        for (final s in controller.speakers)
          MenuRow(
            leading: SpeakerBadge(id: s.id, name: s.name, named: s.named),
            label: s.name,
            labelColor: s.named ? null : cs.onSurfaceVariant,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Timecode(
                  '${s.cueCount}',
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                SizedBox(
                  width: 26,
                  child: s.id == cue.speaker
                      ? Icon(Symbols.check, size: 18, weight: 400, color: cs.primary)
                      : null,
                ),
              ],
            ),
            onTap: () => _assign(s.id),
          ),
        const MenuDivider(),
        if (_adding)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: ControlSurface(
              focused: true,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: _name,
                autofocus: true,
                style: context.texts.bodyMedium,
                decoration: bareInputDecoration(context, hint: '名字，回车确定'),
                onSubmitted: (name) {
                  final id = controller.addSpeaker(name);
                  _assign(id);
                },
              ),
            ),
          )
        else
          MenuRow(
            leading: Icon(
              Symbols.person_add,
              size: 18,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            label: '新增说话人…',
            onTap: () => setState(() => _adding = true),
          ),
        MenuRow(
          leading: Icon(
            Symbols.person_off,
            size: 18,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          label: _run && runLength > 1 ? '清除这一段的说话人' : '清除这一条的说话人',
          onTap: () => _assign(null),
        ),
      ],
    );
  }
}

class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.children, this.center = false});

  final List<Widget> children;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return CustomPaint(
      painter: DashedRRectPainter(color: cs.outline, radius: AppRadius.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          spacing: AppSpacing.s2,
          children: children,
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.s1),
      child,
    ],
  );
}

class _TimecodeField extends StatelessWidget {
  const _TimecodeField({
    required this.label,
    required this.ms,
    required this.onChanged,
  });

  final String label;
  final int ms;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        SizedBox(
          height: 36,
          // key 绑在毫秒上：外部改了时间码，输入框要跟着刷新。
          child: TextFormField(
            key: ValueKey('$label$ms'),
            initialValue: Srt.formatTimecode(ms),
            style: kTimecodeStyle.copyWith(color: cs.onSurface),
            onFieldSubmitted: (text) {
              final parsed = Srt.parseTimecode(text);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.trailing,
    this.focused = false,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final Widget? trailing;

  /// 当前聚焦的那一路用 2px primary 描边，与设计稿一致。
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            const Spacer(),
            if (trailing != null) Flexible(flex: 4, child: trailing!),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
          minLines: 3,
          style: context.texts.bodyLarge,
          onChanged: onSubmitted,
          decoration: InputDecoration(
            enabledBorder: focused
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
