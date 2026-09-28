import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/mux/merge_options.dart';
import '../../domain/task_options.dart';
import '../../domain/transcode/codecs.dart';
import '../shared/command_block.dart';
import '../shared/new_task_panels.dart';
import '../shared/param_section.dart';
import 'merge_form.dart';

/// 合并页右列：输出、章节与字幕、方式、高级（命令预览）与页脚。
class MergeParamPanel extends StatelessWidget {
  const MergeParamPanel({super.key, required this.form, required this.onStart});

  final MergeFormController form;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return NewTaskParamPanel(
      onReset: form.reset,
      sections: [
        _OutputSection(form: form),
        _SubtitleSection(form: form),
        const ParamSection(
          title: '方式',
          children: [
            _NoteBlock(
              icon: Symbols.content_copy,
              text:
                  '不重新编码，原样复制音视频流，速度快、画质无损。各段的视频编码、分辨率、'
                  '帧率、像素格式与音频编码、采样率、声道要与第 1 段一致',
            ),
          ],
        ),
        _AdvancedSection(form: form),
      ],
      footer: form.footer,
      action: PrimaryButton(
        label: '开始合并',
        icon: Symbols.merge,
        onPressed: form.canStart ? onStart : null,
      ),
    );
  }
}

class _OutputSection extends StatelessWidget {
  const _OutputSection({required this.form});

  final MergeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final stem = o.outputStem.trim();
    final ext = o.container.extension;
    final hint = form.segments.isEmpty && stem.isEmpty
        ? '默认取第 1 段的文件名加 .merged'
        : stem.isEmpty
        ? '文件名不能为空'
        : o.sidecarSubtitles
        ? '写成 $stem.$ext 与 $stem.srt；同名文件已存在时自动加序号'
        : '写成 $stem.$ext；同名文件已存在时自动加序号';
    return ParamSection(
      title: '输出',
      first: true,
      children: [
        LabeledField(
          label: '容器',
          child: SegmentedToggle<OutputContainer>(
            fill: true,
            value: o.container,
            segments: [
              for (final c in MergeOptions.containers)
                (value: c, label: c.label, enabled: true),
            ],
            onChanged: form.setContainer,
          ),
        ),
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
                      (
                        value: l,
                        label: l == OutputLocation.besideSource
                            ? '与第 1 段同目录'
                            : l.label,
                        enabled: true,
                      ),
                  ],
                  onChanged: form.chooseOutputLocation,
                ),
              ),
              if (o.outputLocation == OutputLocation.custom) ...[
                const SizedBox(width: AppSpacing.s2),
                QuietButton(label: '选择…', onPressed: form.pickOutputDir),
              ],
            ],
          ),
        ),
        if (o.outputLocation == OutputLocation.custom && o.outputDir != null)
          Text(
            o.outputDir!,
            style: AppTextStyles.timecode.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
        LabeledField(
          label: '文件名',
          child: SingleLineField(
            key: const ValueKey('merge-stem'),
            value: o.outputStem,
            error: form.segments.isNotEmpty && stem.isEmpty,
            style: AppTextStyles.timecode.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: cs.onSurface,
            ),
            onChanged: form.setOutputStem,
          ),
        ),
        ParamHint(hint, error: form.segments.isNotEmpty && stem.isEmpty),
      ],
    );
  }
}

class _SubtitleSection extends StatelessWidget {
  const _SubtitleSection({required this.form});

  final MergeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final stem = o.outputStem.trim().isEmpty ? '<文件名>' : o.outputStem.trim();
    final n = form.segments.length;
    final subtitled = form.subtitledCount;
    final note = n == 0
        ? '添加视频时，旁边同名的 .srt / .vtt 会自动挂上，可以摘下或换一个'
        : subtitled == 0
        ? '还没有段挂字幕，内嵌与旁挂都不会产生字幕'
        : '$subtitled / $n 段挂了字幕；没挂的段不出字幕，但时长照算，后面各段的字幕照样平移';
    return ParamSection(
      title: '章节与字幕',
      children: [
        _SwitchRow(
          title: '添加章节',
          note: '每段一个章节，起点是前面各段时长之和，标题用左侧的「章节」',
          value: o.chapters,
          onChanged: form.setChapters,
        ),
        _SwitchRow(
          title: '内嵌字幕轨',
          note: '各段字幕平移后拼成一条软字幕轨（mov_text）写进视频，播放器里可开关',
          value: o.embedSubtitles,
          onChanged: form.setEmbedSubtitles,
        ),
        _SwitchRow(
          title: '旁挂 SRT',
          note: '在视频旁另写一份合并后的 $stem.srt',
          value: o.sidecarSubtitles,
          onChanged: form.setSidecarSubtitles,
        ),
        _NoteBlock(icon: Symbols.subtitles, text: note),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.texts.bodyMedium),
            ParamHint(note),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.s3),
      AppSwitch(value: value, onChanged: onChanged),
    ],
  );
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.form});

  final MergeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final open = form.advancedOpen;
    return ParamSection(
      title: '高级',
      leading: open ? Symbols.expand_more : Symbols.chevron_right,
      onTapTitle: () => form.advancedOpen = !open,
      trailing: open
          ? null
          : Text(
              '命令预览',
              textAlign: TextAlign.right,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      children: !open
          ? const []
          : [
              LabeledField(
                label: '命令预览',
                child: CommandBlock(
                  command: form.commandPreview,
                  maxHeight: 200,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: form.commandPreview));
                    ScaffoldMessenger.maybeOf(context)
                        ?.showSnackBar(const SnackBar(content: Text('命令已复制')));
                  },
                ),
              ),
              const ParamHint(
                'list.txt、chapters.txt、merged.srt 在开始时写进临时目录，合并完删掉',
              ),
            ],
    );
  }
}

/// 与 NoteBar 同样的外观，但说明能折行：这里的几句都比一行长，截断了就看不全。
class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 1,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, weight: 400, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
