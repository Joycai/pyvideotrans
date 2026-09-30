import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/task.dart';

/// 阶段条：字幕任务六段，转码任务四段。一眼看出任务走到哪、哪一段出了事、
/// 哪一段被跳过。
///
/// 配色规则（与设计稿一致）：
/// - 任务整体完成 → 六段全绿
/// - 已完成的阶段 → 实心 primary
/// - 失败 → 灰底 + 红色填充
/// - 取消 → 灰底 + outline 填充到中断百分比
/// - 进行中 → 灰底 + 蓝紫渐变填充到当前百分比；排队中则整段 outline
/// - 跳过 → 虚线
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.task});

  final SubtitleTask task;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, stage) in task.kind.stages.indexed) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(child: _Segment(task: task, stage: stage)),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.task, required this.stage});

  final SubtitleTask task;
  final TaskStage stage;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final dim = cs.surfaceContainerHighest;
    final state = task.stages[stage]!.state;

    // 整体完成时六段全绿，比逐段蓝更容易一眼认出「这条不用管了」。
    if (task.status == TaskStatus.done) return _bar(color: ext.success);

    return switch (state) {
      StageState.done => _bar(color: cs.primary),
      StageState.failed => GradientProgressBar(
        value: 0.4,
        colors: [cs.error, cs.error],
      ),
      StageState.cancelled => GradientProgressBar(
        value: task.progress,
        colors: [cs.outline, cs.outline],
      ),
      StageState.active =>
        task.status == TaskStatus.queued
            ? _bar(color: cs.outline)
            : GradientProgressBar(value: task.progress),
      StageState.skipped => _DashedSegment(color: cs.outlineVariant),
      StageState.pending => _bar(color: dim),
    };
  }

  Widget _bar({required Color color}) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(height: 4, child: ColoredBox(color: color)),
  );
}

/// 跳过的阶段用虚线，不占视觉重量。
class _DashedSegment extends StatelessWidget {
  const _DashedSegment({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: CustomPaint(painter: _DashPainter(color)),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt;
    const dash = 3.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dash).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
