import 'package:subtitle_studio/domain/media_job.dart';
import 'package:subtitle_studio/domain/mux/merge_options.dart';
import 'package:subtitle_studio/domain/task.dart';

import 'helpers.dart';

/// 任务页里的三个合并任务（设计稿 P6f）：进行中、完成、准备失败。
/// 日志写死时间戳：详情面板会显示出来，用 DateTime.now() 截图就每天对不上。

const _dir = '/Users/mia/Movies/采访';

MergeOptions _options({bool sidecar = false}) => MergeOptions(
  segments: const [
    MergeSegment(
      videoPath: '$_dir/interview_ep12_part1.mp4',
      subtitlePath: '$_dir/interview_ep12_part1.srt',
      chapterTitle: '开场与嘉宾介绍',
    ),
    MergeSegment(
      videoPath: '$_dir/interview_ep12_part2.mp4',
      chapterTitle: 'interview_ep12_part2',
    ),
    MergeSegment(
      videoPath: '$_dir/interview_ep12_part3.mp4',
      subtitlePath: '$_dir/interview_ep12_part3.srt',
      chapterTitle: 'interview_ep12_part3',
    ),
  ],
  sidecarSubtitles: sidecar,
  outputStem: 'interview_ep12_part1.merged',
);

const _durations = [
  Duration(minutes: 32, seconds: 10),
  Duration(minutes: 24, seconds: 36),
  Duration(minutes: 11, seconds: 46),
];

const _command =
    'ffmpeg -hide_banner -nostdin -y -f concat -safe 0 -i list.txt '
    '-i chapters.txt -i merged.srt -map 0:V? -map 0:a? -map 2:s '
    '-map_metadata 1 -map_chapters 1 -c copy -c:s mov_text -f mp4 '
    '$_dir/interview_ep12_part1.merged.mp4';

SubtitleTask mergeRunning() =>
    SubtitleTask(
        id: 'mg1',
        sourcePath: '$_dir/interview_ep12_part1.mp4',
        kind: TaskKind.merge,
        options: testOptions(),
        status: TaskStatus.running,
        stage: TaskStage.merge,
        progress: 0.62,
        mediaDuration: const Duration(hours: 1, minutes: 8, seconds: 32),
        eta: const Duration(seconds: 20),
        media: MergeJob(
          options: _options(),
          segmentDurations: _durations,
          segmentCues: const [402, null, 311],
          outputPath: '$_dir/interview_ep12_part1.merged.mp4',
          command: _command,
        )..speed = 38,
      )
      ..stages[TaskStage.queued] = const StageRecord(state: StageState.done)
      ..stages[TaskStage.prepare] = const StageRecord(
        state: StageState.done,
        duration: Duration(seconds: 1),
        note: 'ffprobe · 3 段参数一致 · 字幕 2 份 713 条',
      )
      ..stages[TaskStage.merge] = const StageRecord(
        state: StageState.active,
        note: '38.0x',
      )
      ..log.add(
        LogEntry(DateTime(2026, 9, 29, 14, 2, 11), LogLevel.info, '开始合并 · 3 段'),
      );

SubtitleTask mergeDone() {
  final task = SubtitleTask(
    id: 'mg2',
    sourcePath: '$_dir/interview_ep12_part1.mp4',
    kind: TaskKind.merge,
    options: testOptions(),
    status: TaskStatus.done,
    stage: TaskStage.finish,
    progress: 1,
    mediaDuration: const Duration(hours: 1, minutes: 8, seconds: 32),
    media: MergeJob(
      options: _options(sidecar: true),
      segmentDurations: _durations,
      segmentCues: const [402, null, 311],
      outputPath: '$_dir/interview_ep12_part1.merged.mp4',
      sidecarPath: '$_dir/interview_ep12_part1.merged.srt',
      command: _command,
      outputBytes: 2254857830,
    ),
  );
  for (final s in TaskKind.merge.stages) {
    task.stages[s] = const StageRecord(state: StageState.done);
  }
  task.log.add(
    LogEntry(DateTime(2026, 9, 29, 13, 40, 2), LogLevel.info, '任务完成'),
  );
  return task;
}

SubtitleTask mergeFailed() =>
    SubtitleTask(
        id: 'mg3',
        sourcePath: '/Users/mia/Movies/课程/lecture_week3_a.mp4',
        kind: TaskKind.merge,
        options: testOptions(),
        status: TaskStatus.failed,
        stage: TaskStage.prepare,
        media: MergeJob(
          options: const MergeOptions(
            segments: [
              MergeSegment(
                videoPath: '/Users/mia/Movies/课程/lecture_week3_a.mp4',
                chapterTitle: 'lecture_week3_a',
              ),
              MergeSegment(
                videoPath: '/Users/mia/Movies/课程/lecture_week3_b.mp4',
                chapterTitle: 'lecture_week3_b',
              ),
            ],
            chapters: false,
            outputStem: 'lecture_week3_a.merged',
          ),
        ),
        error: const TaskError(
          title: '第 2 段的文件找不到了',
          detail: '/Users/mia/Movies/课程/lecture_week3_b.mp4',
          hint: '把文件放回原处后从准备阶段继续；想换掉这一段，回合并页重新建任务。',
        ),
      )
      ..stages[TaskStage.queued] = const StageRecord(state: StageState.done)
      ..stages[TaskStage.prepare] = const StageRecord(
        state: StageState.failed,
        note: '第 2 段的文件找不到了',
      );
