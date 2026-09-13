import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';
import 'baked_backdrop.dart';

/// 窗口底层。真实场景下这里透出用户壁纸或视频画面；
/// 设计稿用三团低对比冷色光晕 + 竖向底色渐变代替。
///
/// 一层竖向渐变加三团全窗口径向光晕，逐帧画就是四次全窗口混合，
/// 在高 DPI 最大化窗口下光这一层就能吃掉几十毫秒。它只随主题变，
/// 所以交给 [BakedBackdrop] 烘成一张图，每帧只画一个纹理 quad。
class AppWallpaper extends StatelessWidget {
  const AppWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = context.elevation;
    return BakedBackdrop(
      // AppElevation 只有 light / dark 两个 const 实例，主题切换时
      // lerp 也只在二者间取一个，所以直接拿它当配方键即可。
      recipeKey: e,
      fallback: e.wallpaper.first,
      paint: (canvas, size) => paintWallpaper(canvas, size, e),
      child: child,
    );
  }

  /// 把壁纸画到 [size] 大小的画布上。与之前 DecoratedBox 的画法一致：
  /// 渐变的 createShader 同样按矩形短边算径向半径，烘焙尺寸保持窗口比例，
  /// 光晕就不会被拉成椭圆。
  static void paintWallpaper(Canvas canvas, Size size, AppElevation e) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.wallpaper,
        ).createShader(rect),
    );
    for (final glow in e.glows) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: glow.center,
            radius: glow.radiusX + glow.radiusY,
            colors: [glow.color, glow.color.withValues(alpha: 0)],
            stops: const [0, 0.65],
          ).createShader(rect),
      );
    }
  }
}
