import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/wallpaper.dart';
import '../shared/page_chrome.dart';
import 'nav_rail.dart';
import 'status_bar.dart';

/// 应用框架：72px 玻璃 Rail + 52px 顶栏 + 内容区 + 32px 状态栏，
/// 12px 外边距与间隙，底层透出壁纸。对应设计稿 1440×900 的栅格。
///
/// 顶栏与状态栏的内容随任务进度变，所以用 [live] 局部驱动它们重建，
/// 而不是让每一次进度回调都从应用根节点重建整棵树。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.chrome,
    required this.child,
    required this.status,
    this.live,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;

  /// 每次 [live] 通知后重新取一份顶栏内容。
  final PageChrome Function() chrome;
  final Widget child;

  /// 每次 [live] 通知后重新取一份状态栏快照。
  final StatusSnapshot Function() status;

  /// 顶栏与状态栏依赖的数据源（任务队列、编辑器…）。为空则只在自身重建时刷新。
  final Listenable? live;

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
                    SizedBox(
                      height: 52,
                      child: _Live(
                        live,
                        builder: () => _TopBar(chrome: chrome()),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Expanded(child: child),
                    const SizedBox(height: AppSpacing.s3),
                    SizedBox(
                      height: 32,
                      child: _Live(
                        live,
                        builder: () => AppStatusBar(snapshot: status()),
                      ),
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

/// 有数据源就跟着它重建，没有就直接构建一次。
class _Live extends StatelessWidget {
  const _Live(this.live, {required this.builder});

  final Listenable? live;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    final live = this.live;
    if (live == null) return builder();
    return ListenableBuilder(listenable: live, builder: (_, _) => builder());
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
