import '../domain/media_job.dart';
import '../domain/task.dart';
import '../domain/transcode/command.dart';
import 'task_progress.dart';

/// 把 ffmpeg 的进度区块折算成任务进度、剩余时间、倍速与阶段备注。
/// 转码与合并都是「跑一条 ffmpeg、按已处理时长算进度」，共用这一份。
///
/// 总长取 `task.mediaDuration`（准备阶段填好）；读不到时只更新倍速与备注。
void Function(TranscodeProgress) ffmpegProgress({
  required SubtitleTask task,
  required MediaJob job,
  required void Function() onChange,
}) {
  final stage = job.workStage;
  final started = DateTime.now();
  final total = task.mediaDuration;
  var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  return (p) {
    job.speed = p.speed;
    if (total != null && total.inMilliseconds > 0) {
      task.progress = (p.position.inMilliseconds / total.inMilliseconds).clamp(
        0.0,
        1.0,
      );
      final speed = p.speed;
      task.eta = speed != null && speed > 0
          ? Duration(
              milliseconds: ((total - p.position).inMilliseconds / speed)
                  .round(),
            )
          : estimateRemaining(
              started,
              p.position.inMilliseconds,
              total.inMilliseconds,
            );
    }
    task.stages[stage] = task.stages[stage]!.copyWith(
      note: [
        if (p.frame != null) '帧 ${p.frame}',
        if (p.speed != null) '${p.speed}x',
      ].join(' · '),
    );
    // 进度区块每 0.5 秒一个，界面与写盘不必每个都跟。
    final now = DateTime.now();
    if (p.done || now.difference(lastPaint).inMilliseconds >= 400) {
      lastPaint = now;
      onChange();
    }
  };
}
