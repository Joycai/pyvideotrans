import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';

/// 窗口底层。真实场景下这里透出用户壁纸或视频画面；
/// 设计稿用三团低对比冷色光晕 + 竖向底色渐变代替。
class AppWallpaper extends StatelessWidget {
  const AppWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = context.elevation;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceDim,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.wallpaper,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final glow in e.glows)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: glow.center,
                  radius: glow.radiusX + glow.radiusY,
                  colors: [glow.color, glow.color.withValues(alpha: 0)],
                  stops: const [0, 0.65],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
