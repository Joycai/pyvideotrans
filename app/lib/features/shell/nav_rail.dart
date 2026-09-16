import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';

enum AppSection {
  tasks(Symbols.list_alt, '任务'),
  newTranscribe(Symbols.mic, '新建转写'),
  newTranslate(Symbols.translate, '翻译'),
  transcode(Symbols.video_settings, '转码'),
  editor(Symbols.edit_note, '编辑器'),
  settings(Symbols.settings, '设置');

  const AppSection(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// 72px 宽的玻璃导航栏。设置固定在底部，与上面四项用弹性空间隔开。
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.current, required this.onSelect});

  final AppSection current;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    const primary = [
      AppSection.tasks,
      AppSection.newTranscribe,
      AppSection.newTranslate,
      AppSection.transcode,
      AppSection.editor,
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
      child: Column(
        children: [
          const _AppMark(),
          const SizedBox(height: AppSpacing.s3),
          for (final section in primary)
            _RailItem(
              section: section,
              selected: section == current,
              onTap: () => onSelect(section),
            ),
          const Spacer(),
          _RailItem(
            section: AppSection.settings,
            selected: current == AppSection.settings,
            onTap: () => onSelect(AppSection.settings),
          ),
        ],
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '字',
        style: context.texts.titleSmall?.copyWith(color: cs.onPrimary),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final selected = widget.selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 72,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 选中指示是 56×32 的胶囊，与 M3 NavigationRail 一致。
              AnimatedContainer(
                duration: AppDuration.short,
                curve: kEasingStandard,
                width: 56,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? cs.secondaryContainer
                      : _hovered
                      ? cs.onSurface.withValues(alpha: AppStateLayer.hover)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  widget.section.icon,
                  size: 22,
                  weight: 400,
                  fill: selected ? 1 : 0,
                  color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                widget.section.label,
                style: context.texts.labelMedium?.copyWith(
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
