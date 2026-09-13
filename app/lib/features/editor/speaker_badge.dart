import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';

/// 说话人徽标（设计稿 C-SpeakerBadge）：方块里写名字首字，底色取说话人
/// 分类色。没起名的说话人用虚线框写编号，不填颜色。
class SpeakerBadge extends StatelessWidget {
  const SpeakerBadge({
    super.key,
    required this.id,
    required this.name,
    this.named = true,
    this.size = 20,
  });

  final int id;
  final String name;
  final bool named;

  /// 20（表格、菜单）或 28（说话人名单）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final large = size >= 28;
    final glyph = named && name.isNotEmpty
        ? String.fromCharCodes(name.runes.take(1))
        : '${id + 1}';
    final radius = BorderRadius.circular(large ? 8 : 6);
    final text = Text(
      glyph,
      maxLines: 1,
      style: TextStyle(
        fontSize: large ? 13 : 11,
        height: 1,
        fontWeight: FontWeight.w600,
        color: named ? cs.onSurface : cs.onSurfaceVariant,
      ),
    );
    return Tooltip(
      message: named ? name : '未命名说话人 ${id + 1}',
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox.square(
        dimension: size,
        child: named
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: context.ext.speaker(id),
                  borderRadius: radius,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Center(child: text),
              )
            : CustomPaint(
                painter: DashedRRectPainter(
                  color: cs.outline,
                  radius: large ? 8 : 6,
                ),
                child: Center(child: text),
              ),
      ),
    );
  }
}

/// 1px 虚线圆角框。落区、未命名徽标、空态输入框共用。
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
