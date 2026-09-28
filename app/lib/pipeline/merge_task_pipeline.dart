import 'dart:io';

import '../domain/cue.dart';
import '../domain/media_job.dart';
import '../domain/mux/merge_options.dart';
import '../domain/mux/merge_rules.dart';
import '../domain/mux/mux_plan.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_control.dart';
import '../domain/transcode/command.dart';
import '../domain/transcode/probe.dart';
import '../services/ffmpeg.dart';
import '../services/file_io.dart';
import '../services/transcoder.dart';
import 'ffmpeg_progress.dart';
import 'task_stage_runner.dart';

/// 合并任务的准备、执行与收尾：几段视频用 concat demuxer 无转码拼成一个，
/// 写每段一个章节，各段字幕按起点平移后拼成一份（内嵌和 / 或旁挂）。
///
/// 结构照 [TranscodeTaskPipeline]：准备阶段把关并定下产物路径，合并阶段整段
/// 跑一次 ffmpeg（不能续写半个文件，续跑就重来），完成阶段核对产物。
class MergeTaskPipeline {
  const MergeTaskPipeline({required this.transcoder, required this.stages});

  final Transcoder transcoder;
  final TaskStageRunner stages;

  /// 命令里临时文件的占位名。详情面板与合并页的命令预览用同一套，
  /// 真正执行时换成临时目录里的路径。
  static const listName = 'list.txt';
  static const chaptersName = 'chapters.txt';
  static const subtitlesName = 'merged.srt';

  Future<void> prepare(
    SubtitleTask task,
    void Function() onChange,
  ) => stages.run(task, TaskStage.prepare, onChange, () async {
    final job = task.media;
    if (job is! MergeJob) {
      throw const ActionableException('合并任务缺少参数', hint: '删除这个任务后重新建。');
    }
    final options = job.options;
    if (options.problem case final problem?) {
      throw ActionableException(problem, hint: '删除这个任务，回合并页改好后重新建。');
    }
    final segments = options.segments;
    for (final (i, s) in segments.indexed) {
      for (final (path, what) in [
        (s.videoPath, '文件'),
        if (s.subtitlePath case final sub?) (sub, '字幕'),
      ]) {
        if (!File(path).existsSync()) {
          throw ActionableException(
            '第 ${i + 1} 段的$what找不到了',
            detail: path,
            hint: '把$what放回原处后从准备阶段继续；想换掉这一段，回合并页重新建任务。',
          );
        }
      }
    }

    // 入队后文件可能被换过，页面上的探测结果不能直接信，这里再把一次关。
    final probes = <MediaProbe>[];
    for (final (i, s) in segments.indexed) {
      try {
        probes.add(await transcoder.probe(s.videoPath));
      } on ActionableException catch (e) {
        throw ActionableException(
          '第 ${i + 1} 段：${e.message}',
          detail: e.detail ?? s.videoPath,
          hint: e.hint,
        );
      }
    }
    for (final (i, issue) in mergeIssues(probes, options.container).indexed) {
      if (issue == null) continue;
      throw ActionableException(
        issue.field == null
            ? '第 ${i + 1} 段：${issue.message}'
            : '第 ${i + 1} 段的${issue.field}与第 1 段不同',
        detail: issue.message,
        hint: '无转码拼接要求各段参数一致。回合并页换掉这一段，或先用「转码」统一参数。',
      );
    }
    final durations = [for (final p in probes) p.duration!];
    job.segmentDurations = durations;
    task.mediaDuration = durations.fold<Duration>(
      Duration.zero,
      (a, b) => a + b,
    );

    final cues = await _readCues(segments);
    job.segmentCues = [for (final c in cues) c?.length];
    final subtitled = cues.nonNulls.length;
    final cueCount = cues.nonNulls.fold(0, (n, c) => n + c.length);

    // 续跑沿用上次定下的路径（那里可能留着上次失败的半截文件，会被覆盖）。
    if (job.outputPath == null) {
      final paths = mergeOutputPath(
        options,
        exists: (p) => File(p).existsSync(),
      );
      job.outputPath = paths.video;
      job.sidecarPath = subtitled > 0 ? paths.sidecar : null;
    }
    job.command = TranscodeCommand.display(
      plan(
        options,
        list: listName,
        chapters: chaptersName,
        subtitles: subtitlesName,
        hasCues: cueCount > 0,
      ).args(job.outputPath!),
    );

    task.stages[TaskStage.prepare] = task.stages[TaskStage.prepare]!.copyWith(
      note: [
        'ffprobe · ${segments.length} 段参数一致',
        if (subtitled > 0) '字幕 $subtitled 份 $cueCount 条',
      ].join(' · '),
    );
    task.note(
      '共 ${segments.length} 段 · ${Srt.formatDuration(task.mediaDuration!)}',
    );
    task.note('输出：${job.outputPath}');
    if (job.sidecarPath case final sidecar?) task.note('旁挂字幕：$sidecar');
  });

  Future<void> run(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => stages.run(task, TaskStage.merge, onChange, () async {
    final job = task.media! as MergeJob;
    final options = job.options;
    final output = job.outputPath!;
    final partial = '$output.part';
    final durations = job.segmentDurations!;
    final starts = offsets(durations);
    final cues = concatCues([
      for (final (i, c) in (await _readCues(options.segments)).indexed)
        (cues: c, offset: starts[i], length: durations[i]),
    ]);
    final srt = cues.isEmpty ? null : Srt.serialize(cues);
    // 字幕全落在段外被丢光时，没有旁挂可写，别在详情里留一个不存在的路径。
    if (srt == null) job.sidecarPath = null;

    task.progress = 0;
    job.speed = null;
    task.note('开始合并 · ${options.segments.length} 段');
    await Directory(File(output).parent.path).create(recursive: true);

    final tmp = await Directory.systemTemp.createTemp('merge_');
    try {
      final list = '${tmp.path}/$listName';
      final chapters = '${tmp.path}/$chaptersName';
      final subtitles = '${tmp.path}/$subtitlesName';
      await File(list).writeAsString(
        concatList([for (final s in options.segments) s.videoPath], durations),
      );
      if (options.chapters) {
        await File(chapters).writeAsString(
          ffmetadata([
            for (final s in options.segments) s.chapterTitle,
          ], durations),
        );
      }
      if (srt != null && options.embedSubtitles) {
        await File(subtitles).writeAsString(srt);
      }
      await transcoder.run(
        args: plan(
          options,
          list: list,
          chapters: chapters,
          subtitles: subtitles,
          hasCues: srt != null,
        ).args(partial, progress: true),
        encoderId: null,
        action: '合并',
        token: token,
        onProgress: ffmpegProgress(task: task, job: job, onChange: onChange),
      );
      await File(partial).rename(output);
      if (srt != null && job.sidecarPath != null) {
        await writeFileAtomically(job.sidecarPath!, srt);
      }
    } catch (_) {
      try {
        await File(partial).delete();
      } on FileSystemException {
        // 没生成过临时文件。
      }
      rethrow;
    } finally {
      // 失败或取消后重试时，别让上一次的速度残留在任务行上。
      job.speed = null;
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
    task.progress = 1;
    task.eta = null;
    if (srt != null) task.note('字幕 ${cues.length} 条');
  });

  Future<void> finish(
    SubtitleTask task,
    void Function() onChange,
  ) => stages.run(task, TaskStage.finish, onChange, () async {
    final job = task.media! as MergeJob;
    final file = File(job.outputPath!);
    final size = file.existsSync() ? file.lengthSync() : 0;
    if (size == 0) {
      throw ActionableException(
        '产物为空',
        detail: job.outputPath,
        hint: '从合并阶段继续重试一次；仍然为空时查看日志里 FFmpeg 的输出。',
      );
    }
    final durations = job.segmentDurations;
    final actual = (await transcoder.probe(file.path)).duration;
    if (durations != null &&
        actual != null &&
        looksTruncated(actual, durations)) {
      throw ActionableException(
        '合并结果比各段加起来短，可能有一段没拼进去',
        detail:
            '产物 ${Srt.formatDuration(actual)}，'
            '各段合计 ${Srt.formatDuration(task.mediaDuration!)}\n${job.outputPath}',
        hint: '查看日志里 FFmpeg 的输出，确认各段文件都还能打开，然后从合并阶段继续。',
      );
    }
    job.outputBytes = size;
    task.stages[TaskStage.finish] = task.stages[TaskStage.finish]!.copyWith(
      note: MediaFileInfo(path: file.path, sizeBytes: size).sizeLabel,
    );
    task.note('已写出 ${job.outputPath}');
  });

  /// 这份参数对应的封装计划。[list] 等是三个临时文件的路径（或占位名）；
  /// 没有字幕可内嵌、没开章节时对应的输入不出现。
  static MuxPlan plan(
    MergeOptions options, {
    required String list,
    required String chapters,
    required String subtitles,
    required bool hasCues,
  }) => MuxPlan.merge(
    concatList: list,
    chapters: options.chapters ? chapters : null,
    subtitles: options.embedSubtitles && hasCues ? subtitles : null,
    container: options.container,
  );

  /// 读各段字幕，没挂的为 null。读不出或一条都没有时指明是第几段。
  static Future<List<List<Cue>?>> _readCues(List<MergeSegment> segments) async {
    final out = <List<Cue>?>[];
    for (final (i, s) in segments.indexed) {
      final path = s.subtitlePath;
      if (path == null) {
        out.add(null);
        continue;
      }
      final List<Cue> cues;
      try {
        cues = Srt.parse(await readSubtitleText(path));
      } on FileSystemException catch (e) {
        throw ActionableException(
          '第 ${i + 1} 段的字幕读不出来',
          detail: '$path\n${e.message}',
          hint: '确认文件还在、有读取权限，然后从准备阶段继续。',
        );
      }
      if (cues.isEmpty) {
        throw ActionableException(
          '第 ${i + 1} 段的字幕读不出来',
          detail: path,
          hint: '确认文件是 SRT / VTT 且时间码格式正确；或回合并页摘下这份字幕重新建任务。',
        );
      }
      out.add(cues);
    }
    return out;
  }
}
