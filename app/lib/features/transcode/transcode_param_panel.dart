import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/task_options.dart';
import '../../domain/transcode/codecs.dart';
import '../../domain/transcode/options.dart';
import '../shared/command_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'transcode_form.dart';
import 'transcode_video_section.dart';
import 'transcode_widgets.dart';

class TranscodeParamPanel extends StatelessWidget {
  const TranscodeParamPanel({
    super.key,
    required this.form,
    required this.onStart,
  });

  final TranscodeFormController form;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final footer = form.footer;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.s4,
                right: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Text('参数', style: context.texts.titleMedium),
                  const Spacer(),
                  QuietButton(label: '重置为默认', onPressed: form.reset),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OutputSection(form: form),
                  if (o.remux)
                    TranscodeSection(
                      title: '音视频',
                      children: [
                        TranscodeHint(
                          '不重新编码，原样复制音视频流到新容器，速度快、画质无损；字幕轨不带入',
                        ),
                      ],
                    )
                  else ...[
                    TranscodeVideoSection(form: form),
                    _AudioSection(form: form),
                  ],
                  _AdvancedSection(form: form),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        footer.icon,
                        size: 16,
                        weight: 400,
                        color: footer.error ? cs.error : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          footer.text,
                          style: context.texts.bodySmall?.copyWith(
                            color: footer.error
                                ? cs.error
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                PrimaryButton(
                  label: '开始转码 · ${form.enqueueable.length}',
                  icon: Symbols.video_settings,
                  onPressed: form.canStart ? onStart : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputSection extends StatelessWidget {
  const _OutputSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    return TranscodeSection(
      title: '输出',
      first: true,
      children: [
        LabeledField(
          label: '方式',
          child: SegmentedToggle<TranscodeMode>(
            fill: true,
            value: o.mode,
            segments: [
              for (final m in TranscodeMode.values)
                (value: m, label: m.label, enabled: true),
            ],
            onChanged: (m) => form.update((o) => o.copyWith(mode: m)),
          ),
        ),
        LabeledField(
          label: '容器',
          child: SegmentedToggle<OutputContainer>(
            fill: true,
            value: o.container,
            segments: [
              for (final c in OutputContainer.values)
                (value: c, label: c.label, enabled: true),
            ],
            onChanged: form.setContainer,
          ),
        ),
      ],
    );
  }
}

class _AudioSection extends StatelessWidget {
  const _AudioSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final hint = switch (o.audioCodec) {
      AudioCodec.opus when o.container == OutputContainer.mov =>
        'MOV 装不下 Opus，换成 MP4 或 AAC',
      _ when o.container == OutputContainer.mov => 'Opus 放不进 MOV，已禁用',
      _ => null,
    };
    return TranscodeSection(
      title: '音频',
      children: [
        LabeledField(
          label: '编码',
          child: SegmentedToggle<AudioCodec>(
            fill: true,
            value: o.audioCodec,
            segments: [
              for (final c in AudioCodec.values)
                (
                  value: c,
                  label: c.label,
                  enabled: c == AudioCodec.copy || o.container.acceptsAudio(c),
                ),
            ],
            onChanged: (c) => form.update((o) => o.copyWith(audioCodec: c)),
          ),
        ),
        if (hint != null)
          TranscodeHint(hint, error: !o.container.acceptsAudio(o.audioCodec)),
        if (o.audioCodec != AudioCodec.copy)
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: '码率',
                  child: AppDropdown<int>(
                    value: o.audioBitrate,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          for (final b in TranscodeOptions.bitrates)
                            DropdownEntry(value: b, label: '$b kbps'),
                        ],
                      ),
                    ],
                    onChanged: (b) =>
                        form.update((o) => o.copyWith(audioBitrate: b)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledField(
                  label: '声道',
                  child: AppDropdown<int?>(
                    value: o.audioChannels,
                    menuWidth: 200,
                    groups: const [
                      DropdownGroup(
                        entries: [
                          DropdownEntry(value: null, label: '保持'),
                          DropdownEntry(value: 2, label: '立体声'),
                          DropdownEntry(value: 1, label: '单声道'),
                        ],
                      ),
                    ],
                    onChanged: (c) =>
                        form.update((o) => o.copyWith(audioChannels: c)),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final open = form.advancedOpen;
    final example = form.outputNameFor(
      form.files.firstOrNull?.fileName ?? 'interview_ep12.mkv',
    );
    return TranscodeSection(
      title: '高级',
      leading: open ? Symbols.expand_more : Symbols.chevron_right,
      onTapTitle: () => form.advancedOpen = !open,
      trailing: open
          ? null
          : Text(
              form.advancedSummary,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      children: !open
          ? const []
          : [
              LabeledField(
                label: '输出位置',
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedToggle<OutputLocation>(
                        fill: true,
                        value: o.outputLocation,
                        segments: [
                          for (final l in OutputLocation.values)
                            (value: l, label: l.label, enabled: true),
                        ],
                        onChanged: (l) {
                          if (l == OutputLocation.custom &&
                              (o.outputDir?.isEmpty ?? true)) {
                            form.pickOutputDir();
                          } else {
                            form.update((o) => o.copyWith(outputLocation: l));
                          }
                        },
                      ),
                    ),
                    if (o.outputLocation == OutputLocation.custom) ...[
                      const SizedBox(width: AppSpacing.s2),
                      QuietButton(label: '选择…', onPressed: form.pickOutputDir),
                    ],
                  ],
                ),
              ),
              if (o.outputLocation == OutputLocation.custom &&
                  o.outputDir != null)
                Text(
                  o.outputDir!,
                  style: kTimecodeStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              LabeledField(
                label: '文件名后缀',
                child: _TextInput(
                  key: const ValueKey('suffix'),
                  value: o.suffix ?? '',
                  hint: o.remux ? 'remux' : o.effectiveVideo.suffix,
                  onChanged: (v) => form.update(
                    (o) => o.copyWith(suffix: v.trim().isEmpty ? null : v),
                  ),
                ),
              ),
              TranscodeHint('写成 $example；同名文件已存在时自动加序号'),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('快速启动（moov 前置）', style: context.texts.bodyMedium),
                        const TranscodeHint('便于网页边下边播'),
                      ],
                    ),
                  ),
                  AppSwitch(
                    value: o.faststart,
                    onChanged: (v) =>
                        form.update((o) => o.copyWith(faststart: v)),
                  ),
                ],
              ),
              LabeledField(
                label: '额外参数',
                child: _TextInput(
                  key: const ValueKey('extra'),
                  value: o.extraArgs,
                  hint: '-x265-params aq-mode=3',
                  mono: true,
                  onChanged: (v) => form.update((o) => o.copyWith(extraArgs: v)),
                ),
              ),
              const TranscodeHint('原样追加在输出文件前，参数错误会在任务日志里看到 FFmpeg 的报错'),
              LabeledField(
                label: '命令预览',
                child: CommandBlock(
                  command: form.commandPreview,
                  maxHeight: 200,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: form.commandPreview));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                ),
              ),
            ],
    );
  }
}

/// 单行输入。外观同 [ControlSurface]。
class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.mono = false,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool mono;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 「重置为默认」「上次参数」从外面改了值，没在输入时同步进来。
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControlSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    focused: _focus.hasFocus,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      style: widget.mono
          ? kTimecodeStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.colors.onSurface,
            )
          : context.texts.bodyMedium,
      decoration: bareInputDecoration(context, hint: widget.hint),
      onChanged: widget.onChanged,
    ),
  );
}
