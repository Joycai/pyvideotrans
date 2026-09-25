import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

/// 打开说话人名单（设计稿 C-SpeakerManager）。
Future<void> showSpeakerManager(
  BuildContext context,
  EditorController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => SpeakerManager(controller: controller),
);

class SpeakerManager extends StatelessWidget {
  const SpeakerManager({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final cs = context.colors;
          final speakers = controller.speakers;
          final total = controller.document.cues.length;
          return GlassPanel(
            strong: true,
            radius: AppRadius.xl,
            expand: false,
            shadow: context.elevation.shadow3,
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpacing.s1,
                      children: [
                        Text('说话人', style: context.texts.titleLarge),
                        Text(
                          '共 ${speakers.length} 位。名字只影响显示和导出时的标签，不会改动字幕文本。',
                          style: context.texts.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final s in speakers)
                          _SpeakerRow(
                            key: ValueKey(s.id),
                            controller: controller,
                            speaker: s,
                            others: [
                              for (final o in speakers)
                                if (o.id != s.id) o,
                            ],
                            note: _suspicion(s, total, speakers.length),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Row(
                      children: [
                        QuietButton(
                          label: '新增说话人',
                          icon: Symbols.person_add,
                          onPressed: () => controller.addSpeaker(''),
                        ),
                        const Spacer(),
                        Text(
                          '导出标签',
                          style: context.texts.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        MiniSegmented<bool>(
                          value: controller.document.speakerLabels,
                          onChanged: controller.setSpeakerLabels,
                          segments: const [
                            (value: false, label: '不写'),
                            (value: true, label: '写名字'),
                          ],
                        ),
                        const SizedBox(width: 10),
                        PrimaryButton(
                          label: '完成',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 条数很少、平均很短的说话人多半是识别服务把应答声切成了一个人。
  /// 只给理由，不自动合并。
  static String? _suspicion(SpeakerSummary s, int total, int speakerCount) {
    if (speakerCount < 2 || s.cueCount == 0 || total == 0) return null;
    final average = s.durationMs / s.cueCount;
    if (s.cueCount >= total * 0.03 || average >= 1200) return null;
    final seconds = (average / 1000).toStringAsFixed(1);
    return '只有 ${s.cueCount} 条，平均每条 $seconds 秒，多半是识别服务把应答声'
        '单独分成了一个人。可以把这一位合并到其他人。';
  }
}

/// 「142 条 · 18:32」。
String _speakerStat(SpeakerSummary s) {
  final total = s.durationMs ~/ 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${s.cueCount} 条 · ${two(total ~/ 60)}:${two(total % 60)}';
}

class _SpeakerRow extends StatefulWidget {
  const _SpeakerRow({
    super.key,
    required this.controller,
    required this.speaker,
    required this.others,
    required this.note,
  });

  final EditorController controller;
  final SpeakerSummary speaker;
  final List<SpeakerSummary> others;
  final String? note;

  @override
  State<_SpeakerRow> createState() => _SpeakerRowState();
}

class _SpeakerRowState extends State<_SpeakerRow> {
  late final _text = TextEditingController(
    text: widget.speaker.named ? widget.speaker.name : '',
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_SpeakerRow old) {
    super.didUpdateWidget(old);
    // 撤销等外部改动：没在编辑时跟着刷新。
    final name = widget.speaker.named ? widget.speaker.name : '';
    if (!_focus.hasFocus && _text.text != name) _text.text = name;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() =>
      widget.controller.renameSpeaker(widget.speaker.id, _text.text);

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final s = widget.speaker;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.note == null ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  SpeakerBadge(
                    id: s.id,
                    name: s.name,
                    named: s.named,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: ControlSurface(
                      focused: _focus.hasFocus,
                      padding: const EdgeInsets.only(left: 12, right: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              style: context.texts.bodyMedium,
                              decoration: bareInputDecoration(
                                context,
                                hint: '说话人${s.id + 1}',
                              ),
                              onSubmitted: (_) => _commit(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s2),
                          Text(
                            s.named ? '原为 说话人${s.id + 1}' : '未命名',
                            style: context.texts.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  SizedBox(
                    width: 116,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Timecode(
                        _speakerStat(s),
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  IconActionButton(
                    icon: Symbols.filter_alt,
                    tooltip: '在列表里只看这位',
                    iconSize: 18,
                    onPressed: () => _onlyThis(context),
                  ),
                  AnchoredPopover(
                    width: 264,
                    alignRight: true,
                    anchor: (context, toggle, open) => IconActionButton(
                      icon: Symbols.more_vert,
                      tooltip: '更多',
                      iconSize: 18,
                      selected: open,
                      onPressed: toggle,
                    ),
                    popover: (context, close) => GlassMenu(
                      children: [
                        if (widget.others.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                            child: Text(
                              '把「${s.name}」的 ${s.cueCount} 条合并到',
                              style: context.texts.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final o in widget.others)
                            MenuRow(
                              leading: SpeakerBadge(
                                id: o.id,
                                name: o.name,
                                named: o.named,
                              ),
                              label: o.name,
                              trailing: Timecode(
                                '${o.cueCount} 条',
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              onTap: () {
                                close();
                                widget.controller.mergeSpeaker(s.id, o.id);
                              },
                            ),
                          const MenuDivider(),
                        ],
                        MenuRow(
                          leading: Icon(
                            Symbols.filter_alt,
                            size: 18,
                            weight: 400,
                            color: cs.onSurfaceVariant,
                          ),
                          label: '在列表里只看这位',
                          onTap: () {
                            close();
                            _onlyThis(context);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(60, 2, 20, 0),
              child: Text(
                widget.note!,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onlyThis(BuildContext context) {
    widget.controller.setSpeakerFilter({widget.speaker.id});
    Navigator.of(context).pop();
  }
}
