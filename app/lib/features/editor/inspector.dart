import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/cue.dart';
import '../../domain/srt.dart';
import 'editor_controller.dart';

/// 右侧 440px 检视面板：预览 + 当前条的编辑。
class Inspector extends StatelessWidget {
  const Inspector({
    super.key,
    required this.controller,
    required this.onRetranslate,
  });

  final EditorController controller;
  final void Function(int index) onRetranslate;

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
class _Preview extends StatelessWidget {
  const _Preview({required this.cue, required this.controller});

  final Cue cue;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
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
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
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
                      '视频预览 · 第一期未实施',
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
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s2 + 2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          controller.view == CueView.translation &&
                                  cue.hasTranslation
                              ? cue.translation!
                              : cue.source,
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
            ),
          ),
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
              const Spacer(),
              StatusTag(
                label: '${cue.durationMs / 1000}s',
                tone: TagTone.neutral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CueEditor extends StatefulWidget {
  const _CueEditor({required this.controller, required this.onRetranslate});

  final EditorController controller;
  final void Function(int index) onRetranslate;

  @override
  State<_CueEditor> createState() => _CueEditorState();
}

class _CueEditorState extends State<_CueEditor> {
  late final TextEditingController _source;
  late final TextEditingController _translation;
  int? _boundIndex;

  @override
  void initState() {
    super.initState();
    _source = TextEditingController();
    _translation = TextEditingController();
    _bind();
  }

  @override
  void didUpdateWidget(_CueEditor old) {
    super.didUpdateWidget(old);
    _bind();
  }

  /// 选中条变化时才重填输入框 —— 每次 build 都重填会把光标顶回开头。
  void _bind() {
    final controller = widget.controller;
    final cue = controller.current;
    if (cue == null || _boundIndex == controller.selected) return;
    _boundIndex = controller.selected;
    _source.text = cue.source;
    _translation.text = cue.translation ?? '';
  }

  @override
  void dispose() {
    _source.dispose();
    _translation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final cs = context.colors;
    final controller = widget.controller;
    final cue = controller.current!;
    final busy = controller.translating.contains(controller.selected);

    final (tagLabel, tagTone) = switch (cue.state) {
      CueState.review => ('待校对', TagTone.review),
      CueState.untranslated => ('未翻译', TagTone.quiet),
      CueState.ok => ('已校对', TagTone.neutral),
    };

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
              StatusTag(label: tagLabel, tone: tagTone),
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
          _Field(
            label: '原文 · ${controller.task.sourceLanguage.name}',
            trailing: cue.confidence == null
                ? null
                : Row(
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
            controller: _source,
            focused: true,
            onSubmitted: controller.editSource,
          ),
          _Field(
            label: '译文 · ${controller.task.targetLanguage.name}',
            trailing: QuietButton(
              label: busy ? '翻译中…' : '重新翻译此条',
              icon: Symbols.refresh,
              height: 24,
              onPressed: busy
                  ? null
                  : () => widget.onRetranslate(controller.selected),
            ),
            controller: _translation,
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
                onPressed:
                    controller.selected >= controller.document.cues.length - 1
                    ? null
                    : controller.mergeWithNext,
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
    required this.onSubmitted,
    this.trailing,
    this.focused = false,
  });

  final String label;
  final TextEditingController controller;
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
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        TextField(
          controller: controller,
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
