import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/task.dart';
import '../../pipeline/task_queue.dart';
import '../../services/ffmpeg.dart';
import '../../services/provider_api.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';

/// 状态栏要显示的一次快照。状态栏控件只画它，不自己去查服务。
class StatusSnapshot {
  const StatusSnapshot({
    required this.ffmpeg,
    required this.asr,
    required this.translation,
    this.runningTasks = 0,
    this.overallProgress = 0,
    this.etaText,
    this.note,
  });

  /// 按当前设置、ffmpeg 与队列拼出一份快照。[note] 由当前页面决定。
  factory StatusSnapshot.from({
    required AppSettings settings,
    required Ffmpeg media,
    required TaskQueue queue,
    String? note,
  }) {
    ({bool connected, String label}) service(ProviderInfo? info, String kind) {
      final ok = info != null && settings.isConfigured(info);
      return (
        connected: ok,
        label: info == null
            ? '$kind · 未选择'
            : '${info.name} · ${ok ? '已配置' : '未配置'}',
      );
    }

    final eta = queue.running?.eta;
    return StatusSnapshot(
      ffmpeg: media.available ? 'ffmpeg · 就绪' : 'ffmpeg · 未找到',
      asr: service(Registry.asrInfo(settings.asrProviderId), '识别'),
      translation: service(
        Registry.translationInfo(settings.translationProviderId),
        '翻译',
      ),
      runningTasks: queue.countWhere(
        (t) => t.status == TaskStatus.running || t.status == TaskStatus.queued,
      ),
      overallProgress: queue.overallProgress,
      etaText: eta == null ? null : '剩余约 ${eta.inMinutes} 分钟',
      note: note,
    );
  }

  /// 右侧附加的一句话，比如编辑器的「未保存 3 处修改」。
  final String? note;

  /// ffmpeg 找没找到。转写抽音频、转码都靠它。
  final String ffmpeg;

  /// 当前识别服务配没配好。
  final ({bool connected, String label}) asr;

  /// 当前翻译服务配没配好。
  final ({bool connected, String label}) translation;

  final int runningTasks;
  final double overallProgress;
  final String? etaText;

  static const idle = StatusSnapshot(
    ffmpeg: 'ffmpeg · 未找到',
    asr: (connected: false, label: '识别 · 未选择'),
    translation: (connected: false, label: '翻译 · 未选择'),
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
          Text(snapshot.ffmpeg, style: muted),
          _divider(cs),
          StatusDot(snapshot.asr.connected ? ext.success : cs.outline),
          const SizedBox(width: AppSpacing.s1 + 2),
          Text(snapshot.asr.label, style: muted),
          _divider(cs),
          StatusDot(snapshot.translation.connected ? ext.success : cs.outline),
          const SizedBox(width: AppSpacing.s1 + 2),
          Text(snapshot.translation.label, style: muted),
          const Spacer(),
          if (snapshot.note != null) ...[
            Text(snapshot.note!, style: muted),
            _divider(cs),
          ],
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
