import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';
import 'speaker_badge.dart';

/// 说话人字段与它的下拉：先定应用范围，再选人。
class InspectorSpeakerField extends StatelessWidget {
  const InspectorSpeakerField({
    super.key,
    required this.controller,
    this.onManageSpeakers,
  });

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final doc = controller.document;
    final cue = controller.current!;
    // 多选且各条说话人不同：锚点控件只写「多个说话人」，计数是选中条数。
    final mixed = controller.multiSelected && controller.selectionMixedSpeakers;
    final id = mixed ? null : cue.speaker;
    final summary = controller.speakers.where((s) => s.id == id).firstOrNull;
    final count = controller.multiSelected
        ? controller.selectionCount
        : summary?.cueCount;

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
                    mixed
                        ? '多个说话人'
                        : id == null
                        ? '无说话人'
                        : doc.speakerName(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: id != null && doc.speakers.containsKey(id)
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count 条',
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

  /// 打着对勾的那一行。人多时列表会滚，打开时把它滚进视野。
  final _checkedRow = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _checkedRow.currentContext;
      if (mounted && row != null) {
        Scrollable.ensureVisible(row, alignment: 0.5);
      }
    });
  }

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
    final multi = controller.multiSelected;
    // 对勾只打在「选中的都是这个人」上；各不相同时一个都不打。
    final checked = multi && controller.selectionMixedSpeakers
        ? -1
        : cue.speaker;

    return GlassMenu(
      children: [
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Row(
              children: [
                Text(
                  multi ? '应用到已选 ${controller.selectionCount} 条' : '应用范围',
                  style: context.texts.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (!multi)
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
        MenuScrollSection(
          children: [
            for (final s in controller.speakers)
              MenuRow(
                key: s.id == checked ? _checkedRow : null,
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
                      child: s.id == checked
                          ? Icon(Symbols.check, size: 18, weight: 400, color: cs.primary)
                          : null,
                    ),
                  ],
                ),
                onTap: () => _assign(s.id),
              ),
          ],
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
                  controller.assignNewSpeaker(name, run: _run);
                  widget.close();
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
          label: multi
              ? '清除已选各条的说话人'
              : _run && runLength > 1
              ? '清除这一段的说话人'
              : '清除这一条的说话人',
          onTap: () => _assign(null),
        ),
      ],
    );
  }
}
