import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import 'cue_table_rows.dart';
import 'editor_controller.dart';
import 'editor_session.dart';
import 'inspector_speaker_field.dart';
import 'speaker_badge.dart';

class InspectorCueEditor extends StatefulWidget {
  const InspectorCueEditor({
    super.key,
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
  State<InspectorCueEditor> createState() => _InspectorCueEditorState();
}

class _InspectorCueEditorState extends State<InspectorCueEditor> {
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
  void didUpdateWidget(InspectorCueEditor old) {
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
    // 只读时框里的字只可能来自流水线，焦点还在也照样重填。
    final locked = controller.locked;
    if (changedRow ||
        ((locked || !_sourceFocus.hasFocus) && _source.text != cue.source)) {
      _source.text = cue.source;
    }
    final translation = cue.translation ?? '';
    if (changedRow ||
        ((locked || !_translationFocus.hasFocus) &&
            _translation.text != translation)) {
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
            InspectorSpeakerField(
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
            style: AppTextStyles.timecode.copyWith(color: cs.onSurface),
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
