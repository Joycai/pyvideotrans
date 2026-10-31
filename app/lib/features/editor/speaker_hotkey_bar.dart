import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/speaker_hotkeys.dart';
import 'editor_controller.dart';

String hotkeyTargetLabel(EditorController c, int? id) => id == null
    ? '清除说话人'
    : id == -2
    ? '选择说话人'
    : !c.document.speakerIds.contains(id)
    ? '目标已失效'
    : c.document.speakerName(id);

void assignSpeakerHotkey(BuildContext context, EditorController c, String key) {
  final label = hotkeyTargetLabel(c, c.speakerHotkeys[key]);
  final count = c.assignHotkey(key);
  if (count == 0) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('已修改 $count 条字幕：$label'),
      duration: const Duration(seconds: 2),
    ),
  );
}

class SpeakerHotkeyBar extends StatelessWidget {
  const SpeakerHotkeyBar({
    super.key,
    required this.controller,
    required this.tableFocus,
  });
  final EditorController controller;
  final FocusNode tableFocus;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        spacing: AppSpacing.s2,
        children: [
          Text('快捷分配', style: context.texts.labelMedium),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: AppSpacing.s2,
                children: [
                  if (c.speakerHotkeys.isEmpty)
                    Text('配置字母键，一键分配选中字幕', style: context.texts.bodySmall),
                  for (final e in c.speakerHotkeys.entries)
                    Tooltip(
                      message:
                          '${e.key.toUpperCase()} · ${hotkeyTargetLabel(c, e.value)}',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: ControlButton(
                          label:
                              '${e.key.toUpperCase()}  ${hotkeyTargetLabel(c, e.value)}',
                          onPressed: c.canAssignHotkey(e.key)
                              ? () {
                                  assignSpeakerHotkey(context, c, e.key);
                                  tableFocus.requestFocus();
                                }
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Text(
            '已选 ${c.selectedPositions.length} 条',
            style: context.texts.bodySmall,
          ),
          QuietButton(
            label: '配置…',
            onPressed: c.locked
                ? null
                : () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => SpeakerHotkeyDialog(controller: c),
                    );
                    if (context.mounted) tableFocus.requestFocus();
                  },
          ),
        ],
      ),
    );
  }
}

class SpeakerHotkeyDialog extends StatefulWidget {
  const SpeakerHotkeyDialog({super.key, required this.controller});
  final EditorController controller;
  @override
  State<SpeakerHotkeyDialog> createState() => _SpeakerHotkeyDialogState();
}

class _SpeakerHotkeyDialogState extends State<SpeakerHotkeyDialog> {
  late final entries = widget.controller.speakerHotkeys.isEmpty
      ? <String, int?>{
          for (final key in ['a', 'b', 'c', 'd']) key: -2,
        }
      : {...widget.controller.speakerHotkeys};

  @override
  Widget build(BuildContext context) => _HotkeyDialogShell(
    title: '说话人快捷分配',
    children: [
      const Text('仅用于当前会话。选中字幕后按字母键；J/K 保留给上下条。'),
      Flexible(
        child: SingleChildScrollView(
          child: Column(
            spacing: AppSpacing.s2,
            children: [
              for (final e in entries.entries)
                Row(
                  spacing: AppSpacing.s2,
                  children: [
                    SizedBox(
                      width: 88,
                      child: AppDropdown<String>(
                        value: e.key,
                        groups: [
                          DropdownGroup(
                            entries: [
                              for (final key in speakerHotkeyLetters.split(''))
                                DropdownEntry(
                                  value: key,
                                  label: key.toUpperCase(),
                                  enabled:
                                      key == e.key || !entries.containsKey(key),
                                  description:
                                      key != e.key && entries.containsKey(key)
                                      ? '该键已配置'
                                      : null,
                                ),
                            ],
                          ),
                        ],
                        onChanged: (key) => setState(() {
                          final next = {
                            for (final old in entries.entries)
                              old.key == e.key ? key : old.key: old.value,
                          };
                          entries
                            ..clear()
                            ..addAll(next);
                        }),
                      ),
                    ),
                    Expanded(
                      child: ControlButton(
                        label: hotkeyTargetLabel(widget.controller, e.value),
                        onPressed: () async {
                          final id = await showDialog<int>(
                            context: context,
                            builder: (_) => _HotkeyTargetPicker(
                              controller: widget.controller,
                            ),
                          );
                          if (id != null && mounted) {
                            setState(
                              () => entries[e.key] = id == -3 ? null : id,
                            );
                          }
                        },
                      ),
                    ),
                    QuietButton(
                      label: '移除',
                      onPressed: () => setState(() => entries.remove(e.key)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          QuietButton(
            label: '添加快捷键',
            onPressed: entries.length == speakerHotkeyLetters.length
                ? null
                : () {
                    final key = speakerHotkeyLetters
                        .split('')
                        .firstWhere((k) => !entries.containsKey(k));
                    setState(() => entries[key] = -2);
                  },
          ),
          const Spacer(),
          ControlButton(label: '取消', onPressed: () => Navigator.pop(context)),
          const SizedBox(width: AppSpacing.s2),
          PrimaryButton(
            label: '应用',
            onPressed: () {
              widget.controller.setSpeakerHotkeys({
                for (final e in entries.entries)
                  if (e.value != -2) e.key: e.value,
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ],
  );
}

class _HotkeyTargetPicker extends StatefulWidget {
  const _HotkeyTargetPicker({required this.controller});
  final EditorController controller;
  @override
  State<_HotkeyTargetPicker> createState() => _HotkeyTargetPickerState();
}

class _HotkeyTargetPickerState extends State<_HotkeyTargetPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.speakers
        .where(
          (s) => '${s.name} ${s.id + 1}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return _HotkeyDialogShell(
      title: '选择说话人',
      children: [
        SingleLineField(
          value: query,
          hint: '搜索名称或编号',
          onChanged: (v) => setState(() => query = v),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s2,
              children: [
                ControlButton(
                  label: '清除说话人',
                  onPressed: () => Navigator.pop(context, -3),
                ),
                for (final s in matches)
                  ControlButton(
                    label: '${s.name} · 编号 ${s.id + 1}',
                    onPressed: () => Navigator.pop(context, s.id),
                  ),
                if (matches.isEmpty) const Text('没有匹配的说话人；可在“管理全部说话人”中添加。'),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: QuietButton(
            label: '取消',
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}

class _HotkeyDialogShell extends StatelessWidget {
  const _HotkeyDialogShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: GlassPanel(
      strong: true,
      radius: AppRadius.xl,
      shadow: context.elevation.shadow3,
      expand: false,
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s3,
            children: [
              Text(title, style: context.texts.titleLarge),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}
