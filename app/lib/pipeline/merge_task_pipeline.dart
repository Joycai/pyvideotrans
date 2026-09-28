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

  /// 合并阶段还没做完时，每次开跑都重跑准备：入队后、上次失败后文件都可能被
  /// 换过，各段时长、章节起点、字幕平移都得按现在的文件重算，一致性也得重新把关。
  /// 探测很便宜；产物路径照样沿用，不会越跑越多 `-2`。
  Future<void> prepare(SubtitleTask task, void Function() onChange) {
    if (task.stages[TaskStage.merge]!.state != StageState.done) {
      task.stages[TaskStage.prepare] = const StageRecord();
    }
    return _prepare(task, onChange);
  }

  Future<void> _prepare(
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

    // 两个字幕开关都关时字幕用不上，不读，也不因为坏字幕拦下合并。
    final raw = options.embedSubtitles || options.sidecarSubtitles
        ? await _readCues(segments)
        : List<List<Cue>?>.filled(segments.length, null);
    final starts = offsets(durations);
    // 条数、要不要带字幕输入、要不要写旁挂，都按平移截尾之后的结果定，
    // 与合并阶段真正写出的一致。
    final merged = concatCues([
      for (final (i, c) in raw.indexed)
        (cues: c, offset: starts[i], length: durations[i]),
    ]);
    job.mergedCues = merged;
    job.segmentCues = [
      for (final (i, c) in raw.indexed)
        c == null
            ? null
            : concatCues([
                (cues: c, offset: Duration.zero, length: durations[i]),
              ]).length,
    ];
    final subtitled = raw.nonNulls.length;
    final dropped =
        raw.nonNulls.fold(0, (n, c) => n + c.length) - merged.length;

    // 续跑沿用上次定下的路径：失败 / 取消时 .part 已删，完成阶段判为不能用的
    // 产物也删了，那里不会有我们自己的文件。若已经有文件，就是期间别的任务或
    // 别人放的，不能盖掉，重新避让。
    bool taken(String p) => File(p).existsSync();
    final previous = job.outputPath;
    if (previous == null ||
        taken(previous) ||
        (options.sidecarSubtitles && taken(sidecarPathFor(previous)))) {
      job.outputPath = mergeOutputPath(options, exists: taken).video;
      if (previous != null) {
        task.note('上次定下的产物位置已有文件，改写到 ${job.outputPath}', LogLevel.warn);
      }
    }
    job.sidecarPath = options.sidecarSubtitles && merged.isNotEmpty
        ? sidecarPathFor(job.outputPath!)
        : null;
    job.command = TranscodeCommand.display(
      plan(
        options,
        list: listName,
        chapters: chaptersName,
        subtitles: subtitlesName,
        hasCues: merged.isNotEmpty,
      ).args(job.outputPath!),
    );

    task.stages[TaskStage.prepare] = task.stages[TaskStage.prepare]!.copyWith(
      note: [
        'ffprobe · ${segments.length} 段参数一致',
        if (subtitled > 0) '字幕 $subtitled 份 ${merged.length} 条',
      ].join(' · '),
    );
    task.note(
      '共 ${segments.length} 段 · ${Srt.formatDuration(task.mediaDuration!)}',
    );
    if (dropped > 0) {
      task.note('$dropped 条字幕起点在所属段的时长之外，已丢掉', LogLevel.warn);
    }
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
    // 准备阶段在同一次开跑里刚算好（合并没做完时准备总会重跑）。
    final cues = job.mergedCues!;
    final srt = cues.isEmpty ? null : Srt.serialize(cues);

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
      await _discardOutput(task, job);
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
      await _discardOutput(task, job);
      throw ActionableException(
        '合并结果比各段加起来短，可能有一段没拼进去',
        detail:
            '产物 ${Srt.formatDuration(actual)}，'
            '各段合计 ${Srt.formatDuration(task.mediaDuration!)}\n${job.outputPath}',
        hint: '不完整的产物已删掉。查看日志里 FFmpeg 的输出，确认各段文件都还能打开，然后从合并阶段继续。',
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

  /// 完成阶段发现产物不能用：删掉它（与旁挂字幕），并把合并阶段退回待执行 ——
  /// 否则续跑只会重做完成阶段的检查，永远过不去；留着它，续跑时准备阶段又会
  /// 当成别人的文件而避让到 `-2`。
  static Future<void> _discardOutput(SubtitleTask task, MergeJob job) async {
    for (final path in [job.outputPath, job.sidecarPath].nonNulls) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // 本来就没有。
      }
    }
    task.stages[TaskStage.merge] = const StageRecord();
  }

  /// 读各段字幕，没挂的为 null。读不出或一条都没有时指明是第几段。
  /// 只在准备阶段调用，所以 hint 都说「从准备阶段继续」。
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
      } on FormatException {
        // 不按 Latin-1 兜底：GBK / Big5 字幕会静默变成乱码写进成片。
        throw ActionableException(
          '第 ${i + 1} 段的字幕不是 UTF-8 编码',
          detail: path,
          hint: '用文本编辑器把它另存为 UTF-8，然后从准备阶段继续。',
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
