import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';

/// 玻璃面板：半透明底 + 1px 亮边 + 顶部 1px 内高光 + 柔和投影。
///
/// 按设计规范**不做背景模糊**（桌面上 BackdropFilter 代价高且会让表格文字发糊），
/// 层次感来自半透明与高光本身。只用于导航与浮层，内容区请用不透明容器。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.padding,
    this.strong = false,
    this.shadow,
    this.expand = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// 浮层（Dialog / 菜单）用更实的一档，保证上方文字可读。
  final bool strong;

  /// 覆盖默认投影。Dialog 这种真正浮起来的层用 shadow3。
  final List<BoxShadow>? shadow;

  /// 是否撑满父级给的空间。固定高度的容器（顶栏、状态栏）必须撑满，
  /// 否则内容会被钉在顶部；由内容决定尺寸的浮层要关掉它，不然会长满屏幕。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? glass.glassStrong : glass.glass,
        borderRadius: borderRadius,
        border: Border.all(color: glass.glassBorder),
        boxShadow: shadow ?? context.elevation.shadow2,
      ),
      // fit 必须是 expand：Stack 默认 loose + topStart，会把内容钉在面板顶部
      // 而不是撑满（顶栏、状态栏这种固定高度的容器里，文字就会整体偏上）。
      child: Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        children: [
          // 顶部 1px 高光：贴着内边框走，模拟玻璃的上缘反光。
          Positioned(
            top: 0,
            left: radius * 0.5,
            right: radius * 0.5,
            child: Container(height: 1, color: glass.glassHighlight),
          ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}

/// 不透明内容容器：surfaceContainerLowest + 1px outlineVariant，不用阴影。
class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.padding,
    this.clip = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}
