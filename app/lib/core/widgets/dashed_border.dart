import 'package:flutter/material.dart';

/// 1px 虚线圆角框。Flutter 的 Border 没有 dashed，自己画。
class DashedBorder extends CustomPainter {
  const DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 4.0, space = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + space;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorder old) =>
      old.color != color || old.radius != radius;
}

// ═══════════════════════════════════════════════════════════════════════
// 参数面板
// ═══════════════════════════════════════════════════════════════════════
