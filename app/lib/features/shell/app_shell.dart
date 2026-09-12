import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/wallpaper.dart';
import 'nav_rail.dart';
import 'status_bar.dart';

/// 每个页面提供给顶栏的内容：标题、副标题、标题右侧的标签、右侧操作区。
class PageChrome {
  const PageChrome({
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final List<Widget> actions;
}

/// 应用框架：72px 玻璃 Rail + 52px 顶栏 + 内容区 + 32px 状态栏，
/// 12px 外边距与间隙，底层透出壁纸。对应设计稿 1440×900 的栅格。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.chrome,
    required this.child,
    required this.status,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final PageChrome chrome;
  final Widget child;
  final StatusSnapshot status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppWallpaper(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 72,
                child: AppNavRail(
                  current: section,
                  onSelect: onSectionChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 52, child: _TopBar(chrome: chrome)),
                    const SizedBox(height: AppSpacing.s3),
                    Expanded(child: child),
                    const SizedBox(height: AppSpacing.s3),
                    SizedBox(
                      height: 32,
                      child: AppStatusBar(snapshot: status),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.chrome});

  final PageChrome chrome;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
      child: Row(
        children: [
          Flexible(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(chrome.title, style: context.texts.titleLarge),
                if (chrome.subtitle != null) ...[
                  const SizedBox(width: AppSpacing.s3),
                  Flexible(
                    child: Text(
                      chrome.subtitle!,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: context.texts.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (chrome.titleTrailing != null) ...[
                  const SizedBox(width: AppSpacing.s3),
                  chrome.titleTrailing!,
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          for (final (i, action) in chrome.actions.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s3),
            action,
          ],
        ],
      ),
    );
  }
}
