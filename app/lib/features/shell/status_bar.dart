import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';

/// 状态栏要显示的一次快照。由上层按真实状态填充，避免这里自己去查服务。
class StatusSnapshot {
  const StatusSnapshot({
    required this.localEngine,
    required this.cloud,
    required this.localBackend,
    this.runningTasks = 0,
    this.overallProgress = 0,
    this.etaText,
  });

  /// 本地识别：第一期未实施，显示为「未启用」。
  final String localEngine;

  /// 云端连通性与延迟。
  final ({bool connected, String label}) cloud;

  /// 本地后端（Ollama / 自建 Python 服务）。
  final ({bool connected, String label}) localBackend;

  final int runningTasks;
  final double overallProgress;
  final String? etaText;

  static const idle = StatusSnapshot(
    localEngine: '本地识别 · 未启用',
    cloud: (connected: false, label: '云端 · 未配置'),
    localBackend: (connected: false, label: '本地服务 · 未连接'),
  );
}

/// 32px 高的玻璃状态栏。文案规则：进度与错误必须给出可行动信息。
class AppStatusBar extends StatelessWidget {
  const AppStatusBar({super.key, required this.snapshot});

  final StatusSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return GlassPanel(
      radius: AppRadius.md + 2,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Row(
        children: [
          Icon(Symbols.memory, size: 16, weight: 400, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.s1 + 2),
          Text(snapshot.localEngine, style: muted),
          _divider(cs),
          StatusDot(
            snapshot.cloud.connected ? ext.success : cs.outline,
          ),
          const SizedBox(width: AppSpacing.s1 + 2),
          Text(snapshot.cloud.label, style: muted),
          _divider(cs),
          StatusDot(
            snapshot.localBackend.connected ? ext.success : cs.outline,
          ),
          const SizedBox(width: AppSpacing.s1 + 2),
          Text(snapshot.localBackend.label, style: muted),
          const Spacer(),
          if (snapshot.runningTasks > 0) ...[
            Text('后台任务 ', style: muted),
            Timecode(
              '${snapshot.runningTasks}',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s2),
            GradientProgressBar(value: snapshot.overallProgress, width: 96),
            const SizedBox(width: AppSpacing.s2),
            Timecode(
              '${(snapshot.overallProgress * 100).round()}%',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
            if (snapshot.etaText != null)
              Text(' · ${snapshot.etaText}', style: muted),
          ] else
            Text('后台任务 0', style: muted),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
    child: Container(width: 1, height: 14, color: cs.outlineVariant),
  );
}
