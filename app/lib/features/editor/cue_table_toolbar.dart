import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';

class CueTableToolbar extends StatelessWidget {
  const CueTableToolbar({
    super.key,
    required this.controller,
    required this.speakers,
    required this.showHint,
    required this.onManageSpeakers,
  });

  final EditorController controller;
  final bool speakers;
  final bool showHint;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final compact = isCompactEditor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            // 窄窗口收到 150，给右侧的筛选 chip 多让出位置。
            width: compact
                ? 150
                : speakers
                ? 188
                : 240,
            height: 32,
            child: TextField(
              onChanged: controller.setSearch,
              style: context.texts.bodyMedium,
              decoration: InputDecoration(
                hintText: '搜索原文 / 译文',
                hintStyle: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Symbols.search,
                  size: 18,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 32,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FilterChipBar(
                value: controller.filter.name,
                onChanged: (name) =>
                    controller.setFilter(CueFilter.values.byName(name)),
                items: [
                  for (final f in CueFilter.values)
                    // 只挂原文时没有「未翻译」可筛；「未配对」只在真有对不上的行时出现。
                    // 窄窗口再藏掉数量为 0 的，「全部」与当前选中的除外。
                    if (switch (f) {
                          CueFilter.untranslated => controller.hasTranslations,
                          CueFilter.unpaired ||
                          CueFilter.edited => controller.countOf(f) > 0,
                          _ => true,
                        } &&
                        (!compact ||
                            f == CueFilter.all ||
                            f == controller.filter ||
                            controller.countOf(f) > 0))
                      (key: f.name, label: f.label, count: controller.countOf(f)),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          if (speakers)
            _SpeakerFilterChip(
              controller: controller,
              onManageSpeakers: onManageSpeakers,
            )
          else if (showHint) ...[
            Icon(
              Symbols.keyboard,
              size: 16,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s1 + 2),
            Text(
              'J/K 上下条 · Enter 标记已校对 · ⌘Z 撤销',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具栏右侧的说话人筛选：多选，勾「全部」清空其余项。
class _SpeakerFilterChip extends StatelessWidget {
  const _SpeakerFilterChip({
    required this.controller,
    required this.onManageSpeakers,
  });

  final EditorController controller;
  final VoidCallback? onManageSpeakers;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final filter = controller.speakerFilter;
    final doc = controller.document;
    final label = switch (filter.length) {
      0 => '说话人 · 全部',
      1 when filter.single != null => '说话人 · ${doc.speakerName(filter.single!)}',
      1 => '说话人 · 无',
      _ => '说话人 · ${filter.length} 位',
    };

    // 窄窗口只留图标，给筛选 chip 让位；筛了人时底色变，文案进悬停提示。
    final compact = isCompactEditor(context);

    return AnchoredPopover(
      width: 268,
      alignRight: true,
      anchor: (context, toggle, open) => Tooltip(
        message: compact ? label : '',
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: filter.isEmpty ? null : cs.secondaryContainer,
            border: Border.all(
              color: filter.isEmpty ? cs.outlineVariant : Colors.transparent,
            ),
            gradient: filter.isEmpty
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: context.elevation.controlGradient,
                  )
                : null,
            boxShadow: filter.isEmpty ? context.elevation.controlShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: toggle,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.record_voice_over,
                      size: 18,
                      weight: 400,
                      color: cs.onSurfaceVariant,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: context.texts.labelLarge?.copyWith(
                          color: filter.isEmpty
                              ? cs.onSurfaceVariant
                              : cs.onSecondaryContainer,
                        ),
                      ),
                    ],
                    Icon(
                      open ? Symbols.expand_less : Symbols.expand_more,
                      size: 18,
                      weight: 400,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      popover: (context, close) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final filter = controller.speakerFilter;
          final unassigned = controller.document.cues
              .where((c) => c.speaker == null)
              .length;
          return GlassMenu(
            children: [
              MenuRow(
                leading: _Check(checked: filter.isEmpty),
                label: '全部',
                trailing: _count(context, controller.document.cues.length),
                onTap: () => controller.setSpeakerFilter({}),
              ),
              for (final s in controller.speakers)
                MenuRow(
                  leading: _Check(checked: filter.contains(s.id)),
                  label: s.name,
                  labelColor: s.named ? null : cs.onSurfaceVariant,
                  trailing: _count(context, s.cueCount),
                  onTap: () => controller.toggleSpeakerFilter(s.id),
                ),
              if (unassigned > 0)
                MenuRow(
                  leading: _Check(checked: filter.contains(null)),
                  label: '无说话人',
                  labelColor: cs.onSurfaceVariant,
                  trailing: _count(context, unassigned),
                  onTap: () => controller.toggleSpeakerFilter(null),
                ),
              const MenuDivider(),
              MenuRow(
                leading: Icon(
                  Symbols.group,
                  size: 18,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
                label: '管理说话人…',
                onTap: () {
                  close();
                  onManageSpeakers?.call();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _count(BuildContext context, int n) => Timecode(
    '$n',
    fontSize: 12,
    color: context.colors.onSurfaceVariant,
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked ? cs.primary : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: checked ? cs.primary : cs.outline),
      ),
      child: checked
          ? Icon(Symbols.check, size: 14, weight: 600, color: cs.onPrimary)
          : null,
    );
  }
}
