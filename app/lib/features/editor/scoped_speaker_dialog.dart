import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/cue.dart';
import 'editor_controller.dart';
import 'selection_ranges.dart';
import 'speaker_badge.dart';

Future<void> showScopedSpeakerDialog(
  BuildContext context,
  EditorController controller,
) async {
  final count = await showDialog<int>(
    context: context,
    builder: (_) => ScopedSpeakerDialog(controller: controller),
  );
  if (!context.mounted || count == null) return;
  final hidden =
      controller.visiblePositions.length < controller.document.cues.length;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('已修改 $count 条字幕${hidden ? '；部分字幕可能不在当前筛选结果中' : ''}'),
      action: hidden
          ? SnackBarAction(
              label: '清除筛选',
              onPressed: () {
                controller.setSpeakerFilter({});
                controller.setSearch('');
                controller.setFilter(CueFilter.all);
              },
            )
          : null,
    ),
  );
}

class ScopedSpeakerDialog extends StatefulWidget {
  const ScopedSpeakerDialog({super.key, required this.controller});
  final EditorController controller;

  @override
  State<ScopedSpeakerDialog> createState() => _ScopedSpeakerDialogState();
}

class _ScopedSpeakerDialogState extends State<ScopedSpeakerDialog> {
  late final SubtitleDocument original = widget.controller.document;
  late final List<int> positions = [...widget.controller.selectedPositions]
    ..sort();
  late final counts = <int?, int>{
    for (final p in positions) original.cues[p].speaker: 0,
  };
  final mapping = <int?, int?>{};
  final names = <int, String>{};
  final selected = <int?>{};
  bool details = false;

  @override
  void initState() {
    super.initState();
    for (final p in positions) {
      final id = original.cues[p].speaker;
      counts[id] = counts[id]! + 1;
    }
  }

  String label(int? id) => id == null
      ? '无说话人'
      : '${names[id] ?? original.speakerName(id)} · 编号 ${id + 1}';

  int get changed => positions.where((p) {
    final id = original.cues[p].speaker;
    return mapping.containsKey(id) && mapping[id] != id;
  }).length;

  Future<void> choose(Set<int?> sources) async {
    final target = await showDialog<({int? id, String? name})>(
      context: context,
      builder: (_) => _TargetDialog(original: original, names: names),
    );
    if (!mounted || target == null) return;
    setState(() {
      var id = target.id;
      if (target.name != null) {
        id = original.nextSpeakerId;
        while (names.containsKey(id)) {
          id = id! + 1;
        }
        names[id!] = target.name!;
      }
      for (final source in sources) {
        mapping[source] = id;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final valid =
          !widget.controller.locked &&
          identical(original, widget.controller.document);
      final numbers = positions.map((p) => original.cues[p].index).toList();
      final nonContinuous =
          positions.isNotEmpty &&
          positions.last - positions.first + 1 != positions.length;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassPanel(
          strong: true,
          expand: false,
          radius: AppRadius.xl,
          shadow: context.elevation.shadow3,
          child: SizedBox(
            width: 720,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('整理选区说话人', style: context.texts.titleLarge),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    '已选 ${positions.length} 条 · ${nonContinuous ? '非连续选区' : '连续选区'}',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: QuietButton(
                      label: details ? '收起行号范围' : '查看行号范围',
                      onPressed: () => setState(() => details = !details),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 64),
                    child: SingleChildScrollView(child: Text(
                      selectionRanges(numbers,
                        maxRuns: details ? numbers.length : 6),
                      style: AppTextStyles.timecode.copyWith(
                        color: context.colors.onSurfaceVariant),
                    )),
                  ),
                  if (positions.isNotEmpty)
                    Text(
                      '${_time(original.cues[positions.first].startMs)}–${_time(original.cues[positions.last].endMs)}',
                    ),
                  const Text('仅处理选中的可见字幕，不包含被筛选隐藏的字幕。'),
                  const SizedBox(height: AppSpacing.s3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ControlButton(
                      label: '合并为…（已选 ${selected.length} 位）',
                      onPressed: valid && selected.length > 1
                          ? () => choose({...selected})
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final entry in counts.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Material(
                                    type: MaterialType.transparency,
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      title: Row(
                                        children: [
                                          if (entry.key != null) ...[
                                            SpeakerBadge(
                                              id: entry.key!,
                                              name: original.speakerName(
                                                entry.key!,
                                              ),
                                              named: original.speakers
                                                  .containsKey(entry.key),
                                            ),
                                            const SizedBox(width: AppSpacing.s2),
                                          ],
                                          Expanded(
                                            child: Text(
                                              '${label(entry.key)} · ${entry.value} 条',
                                            ),
                                          ),
                                        ],
                                      ),
                                      value: selected.contains(entry.key),
                                      onChanged: valid
                                          ? (on) => setState(() {
                                              if (on!) {
                                                selected.add(entry.key);
                                              } else {
                                                selected.remove(entry.key);
                                              }
                                            })
                                          : null,
                                    ),
                                  ),
                                  Wrap(
                                    spacing: AppSpacing.s2,
                                    runSpacing: AppSpacing.s2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        mapping.containsKey(entry.key)
                                            ? '→ ${mapping[entry.key] == null ? '清除说话人' : label(mapping[entry.key])}'
                                            : '保持不变',
                                      ),
                                      ControlButton(
                                        label: '命名 / 替换…',
                                        onPressed: valid
                                            ? () => choose({entry.key})
                                            : null,
                                      ),
                                      if (mapping.containsKey(entry.key))
                                        QuietButton(
                                          label: '重置',
                                          onPressed: valid
                                              ? () => setState(() {
                                                  mapping.remove(entry.key);
                                                })
                                              : null,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  Text(
                    !valid
                        ? '字幕已发生变化或任务正在运行，请关闭后重新选择。'
                        : changed == 0
                        ? '请选择处理方式'
                        : '将修改 $changed 条字幕，新增 ${names.keys.where((id) => mapping.values.contains(id)).length} 位说话人',
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
                    children: [
                      ControlButton(
                        label: '取消',
                        onPressed: () => Navigator.pop(context),
                      ),
                      PrimaryButton(
                        label: '应用到 $changed 条字幕',
                        onPressed: valid && changed > 0
                            ? () {
                                if (widget.controller.applySpeakerMapping(
                                  original,
                                  positions,
                                  mapping,
                                  newSpeakers: names,
                                )) {
                                  Navigator.pop(context, changed);
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

String _time(int ms) =>
    '${(ms ~/ 3600000).toString().padLeft(2, '0')}:'
    '${(ms ~/ 60000 % 60).toString().padLeft(2, '0')}:'
    '${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}';

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.original, required this.names});
  final SubtitleDocument original;
  final Map<int, String> names;
  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  String name = '';
  String search = '';

  @override
  Widget build(BuildContext context) {
    final ids = {...widget.original.speakerIds, ...widget.names.keys};
    String label(int id) => widget.names[id] ?? widget.original.speakerName(id);
    final duplicate = ids.any((id) => label(id) == name.trim());
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassPanel(
        strong: true,
        expand: false,
        radius: AppRadius.xl,
        shadow: context.elevation.shadow3,
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s3,
              children: [
                Text('选择目标说话人', style: context.texts.titleLarge),
                LabeledField(
                  label: '命名为新说话人',
                  child: SingleLineField(
                    value: name,
                    hint: '输入新名字',
                    onChanged: (v) => setState(() => name = v),
                  ),
                ),
                if (duplicate)
                  const InlineNote(text: '已有同名说话人，可在下方选择替换；新建会保留为不同身份。'),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrimaryButton(
                    label: '使用新名字',
                    onPressed: name.trim().isEmpty ? null : () =>
                        Navigator.pop(context, (id: null, name: name.trim())),
                  ),
                ),
                LabeledField(
                  label: '替换为已有说话人',
                  child: SingleLineField(
                    value: search,
                    hint: '搜索已有说话人',
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: Material(
                  type: MaterialType.transparency,
                  child: Column(children: [
                    for (final id in ids)
                      if ('${label(id)} ${id + 1}'.toLowerCase().contains(search.trim().toLowerCase()))
                        ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                          title: Text(label(id), style: context.texts.bodyMedium),
                          subtitle: Text(
                            '编号 ${id + 1}${widget.names.containsKey(id) ? ' · 本次新建' : ''}',
                            style: context.texts.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant)),
                          onTap: () => Navigator.pop(context, (id: id, name: null)),
                        ),
                  ]),
                ))),
                const Divider(),
                Wrap(alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.s2, runSpacing: AppSpacing.s2,
                  children: [
                    QuietButton(label: '清除说话人', onPressed: () =>
                      Navigator.pop(context, (id: null, name: null))),
                    ControlButton(label: '取消', onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
