import 'package:flutter/material.dart';

import '../theme/app_extensions.dart';
import '../theme/tokens.dart';

/// 标签的三种语气。设计规范：字幕黄只用于「待校对」，其余一律中性描边。
enum TagTone {
  /// 待校对 —— 唯一允许用黄的标签。
  review,

  /// 服务/能力标签，用 secondaryContainer 实底。
  service,

  /// 中性描边（已校对、仅文本…）。
  neutral,

  /// 更弱的描边（未翻译、待下载…）。
  quiet,

  /// 灰底无边（设置页「第一期未实施」）：比描边更退后，不与「未配置」抢眼。
  muted,

  error,
  success,
}

class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.label,
    this.icon,
    this.tone = TagTone.neutral,
  });

  final String label;
  final IconData? icon;
  final TagTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (bg, fg, border) = switch (tone) {
      TagTone.review => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        Colors.transparent,
      ),
      TagTone.service => (
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        Colors.transparent,
      ),
      TagTone.neutral => (
        Colors.transparent,
        cs.onSurfaceVariant,
        cs.outlineVariant,
      ),
      TagTone.quiet => (Colors.transparent, cs.onSurfaceVariant, cs.outline),
      TagTone.muted => (
        cs.surfaceContainer,
        cs.onSurfaceVariant,
        Colors.transparent,
      ),
      TagTone.error => (
        cs.errorContainer,
        cs.onErrorContainer,
        Colors.transparent,
      ),
      TagTone.success => (
        ext.successContainer,
        ext.onSuccessContainer,
        Colors.transparent,
      ),
    };

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg, weight: 400),
            const SizedBox(width: AppSpacing.s1),
          ],
          Text(label, style: context.texts.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// 状态胶囊：24px 高、实底无边、图标 + 短词，贴左对齐。
///
/// 与 [StatusTag] 的区别：颜色由调用方按状态直接给，左边距收窄到 6 让图标贴边 ——
/// 文件表格的「状态」列和编码器卡片都用它，列宽固定，胶囊不该撑满单元格。
class StateChip extends StatelessWidget {
  const StateChip({
    super.key,
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      height: 24,
      padding: const EdgeInsets.only(left: 6, right: AppSpacing.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, weight: 400, color: fg),
          const SizedBox(width: AppSpacing.s1),
          Text(label, style: context.texts.labelMedium?.copyWith(color: fg)),
        ],
      ),
    ),
  );
}

/// 时间码文本：等宽 + tnum，列不会随数字宽度跳动。
class Timecode extends StatelessWidget {
  const Timecode(this.text, {super.key, this.color, this.fontSize});

  final String text;
  final Color? color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: kTimecodeStyle.copyWith(
      color: color ?? context.colors.onSurface,
      fontSize: fontSize,
    ),
  );
}

/// 蓝→紫渐变进度条。这是全应用唯一允许出现紫色的地方。
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({
    super.key,
    required this.value,
    this.width,
    this.height = 4,
  });

  /// 0..1。
  final double value;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: context.elevation.progressGradient,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态点（状态栏的连接指示）。圆形只用于 Switch 与状态点。
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
