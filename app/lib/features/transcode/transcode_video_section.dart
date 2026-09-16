import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/transcode/codecs.dart';
import '../../domain/transcode/encoder_params.dart';
import '../../domain/transcode/options.dart';
import '../../services/transcoder.dart';
import 'transcode_form.dart';
import 'transcode_widgets.dart';

class TranscodeVideoSection extends StatelessWidget {
  const TranscodeVideoSection({super.key, required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final codec = o.videoCodec;
    final encoder = o.encoder;
    final transcoding = codec != VideoCodec.copy;
    final codecHint = switch (codec) {
      VideoCodec.av1 when o.container == OutputContainer.mov =>
        'MOV 装不下 AV1 视频，换成 MP4',
      VideoCodec.copy => '视频流原样复制，分辨率与帧率不能改',
      _ => null,
    };
    return TranscodeSection(
      title: '视频',
      children: [
        LabeledField(
          label: '编码',
          child: SegmentedToggle<VideoCodec>(
            fill: true,
            value: codec,
            segments: [
              for (final c in VideoCodec.values)
                (
                  value: c,
                  label: c.label,
                  enabled: c == VideoCodec.copy || o.container.acceptsVideo(c),
                ),
            ],
            onChanged: form.setVideoCodec,
          ),
        ),
        if (codecHint != null)
          TranscodeHint(codecHint, error: codec != VideoCodec.copy),
        if (transcoding) ...[
          _EncoderList(form: form),
          if (encoder != null) _EncoderParams(form: form, encoder: encoder),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: '分辨率',
                  child: AppDropdown<ResolutionLimit>(
                    value: o.resolution,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          for (final r in ResolutionLimit.values)
                            DropdownEntry(value: r, label: r.label),
                        ],
                      ),
                    ],
                    onChanged: (r) =>
                        form.update((o) => o.copyWith(resolution: r)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledField(
                  label: '帧率',
                  child: AppDropdown<int?>(
                    value: o.fps,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          const DropdownEntry(value: null, label: '保持原样'),
                          for (final f in TranscodeOptions.frameRates)
                            DropdownEntry(value: f, label: '$f'),
                        ],
                      ),
                    ],
                    onChanged: (f) => form.update((o) => o.copyWith(fps: f)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 编码器卡片列表。不可用的整张 38% 且不可点，右侧说明原因。
class _EncoderList extends StatelessWidget {
  const _EncoderList({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final transcoder = form.transcoder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '编码器',
          style: context.texts.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s1 + 2),
        for (final (encoder, status) in form.encoderChoices) ...[
          _EncoderCard(
            encoder: encoder,
            status: status,
            selected: encoder.id == form.options.encoderId,
            onTap: () => form.selectEncoder(encoder.id),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            QuietButton(
              label: transcoder.isProbing ? '检测中…' : '重新检测',
              icon: Symbols.refresh,
              height: 28,
              onPressed: transcoder.isProbing ? null : transcoder.refresh,
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                '检测方式：对每个硬件编码器试编码 1 帧',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EncoderCard extends StatelessWidget {
  const _EncoderCard({
    required this.encoder,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final VideoEncoder encoder;
  final EncoderStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    // 设计稿：检测中的卡片不变淡，但要等结果出来才能选。
    final enabled = status.state == EncoderState.available;
    final dimmed = status.state == EncoderState.notCompiled ||
        status.state == EncoderState.failed;
    final (chipBg, chipFg, chipIcon) = switch (status.state) {
      EncoderState.available => (
        ext.successContainer,
        ext.onSuccessContainer,
        Symbols.check,
      ),
      EncoderState.probing => (
        cs.surfaceContainer,
        cs.onSurfaceVariant,
        Symbols.progress_activity,
      ),
      EncoderState.notCompiled => (
        cs.surfaceContainer,
        cs.onSurfaceVariant,
        Symbols.block,
      ),
      EncoderState.failed => (
        cs.errorContainer,
        cs.onErrorContainer,
        Symbols.error,
      ),
    };
    final sub = [
      encoder.id,
      if (encoder.note != null) encoder.note!,
    ].join(' · ');

    final card = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          _Radio(selected: selected),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(encoder.title, style: context.texts.bodyMedium),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kTimecodeStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (status.state == EncoderState.failed &&
                    status.reason != null)
                  Text(
                    status.reason!,
                    style: context.texts.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Tooltip(
            message: status.reason ?? '',
            child: TranscodeChip(
              label: status.state.label,
              icon: chipIcon,
              bg: chipBg,
              fg: chipFg,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: dimmed ? AppStateLayer.disabledContent : 1,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? cs.primary : cs.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// 当前编码器自己的参数表。换编码器时整块换掉（key 带上编码器名），
/// 数字框里残留的输入不会串到另一家的同名参数上。
class _EncoderParams extends StatelessWidget {
  const _EncoderParams({required this.form, required this.encoder});

  final TranscodeFormController form;
  final VideoEncoder encoder;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final values = form.options.resolvedParams;
    final visible = encoder.params.where((p) => p.isVisible(values));
    // 设计稿：参数区是一块 surface-container-low 底的圆角块，与上面的编码器
    // 卡片区分开 —— 这一块的内容整个随编码器换。
    return Container(
      key: ValueKey('params-${encoder.id}'),
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('编码器参数', style: context.texts.titleSmall),
              const Spacer(),
              Text(
                encoder.id,
                style: kTimecodeStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          for (final param in visible) ...[
            const SizedBox(height: AppSpacing.s3),
            EncoderParamField(
              key: ValueKey('${encoder.id}.${param.key}'),
              param: param,
              value: values[param.key]!,
              onChanged: (v, {bool notify = true}) =>
                  form.setParam(param.key, v, notify: notify),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一项编码器参数的控件：选项少用分段、多用下拉，数值用数字框，开关用 Switch。
class EncoderParamField extends StatelessWidget {
  const EncoderParamField({
    super.key,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final EncoderParam param;
  final Object value;
  final void Function(Object value, {bool notify}) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final hint = param.hint;
    final Widget control = switch (param) {
      final ChoiceParam p when p.segmented => SegmentedToggle<String>(
        fill: true,
        value: value as String,
        segments: [
          for (final (v, label) in p.options)
            (value: v, label: label, enabled: true),
        ],
        onChanged: onChanged,
      ),
      final ChoiceParam p => AppDropdown<String>(
        value: value as String,
        menuWidth: 240,
        groups: [
          DropdownGroup(
            entries: [
              for (final (v, label) in p.options)
                DropdownEntry(value: v, label: label),
            ],
          ),
        ],
        onChanged: onChanged,
      ),
      final IntParam p => Row(
        children: [
          NumberField(
            value: value as int,
            min: p.min,
            max: p.max,
            width: 120,
            onChanged: (v) => onChanged(v),
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            [
              ?p.unit,
              '${p.min}–${p.max}',
            ].join(' · '),
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      BoolParam() => const SizedBox.shrink(),
    };

    if (param is BoolParam) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(param.label, style: context.texts.bodyMedium),
                if (hint != null)
                  Text(
                    hint,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppSwitch(value: value as bool, onChanged: onChanged),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(label: param.label, child: control),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.s1),
          TranscodeHint(hint),
        ],
      ],
    );
  }
}
