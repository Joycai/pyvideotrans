import 'dart:io';

import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/transcode/command.dart';
import '../domain/transcode/probe.dart';
import '../services/media.dart';
import '../services/provider_api.dart';
import '../services/transcoder.dart';
import 'task_progress.dart';
import 'task_stage_runner.dart';

/// 转码任务的准备、执行与收尾。TaskRunner 只负责选择任务分支和统一错误处理。
class TranscodeTaskPipeline {
  const TranscodeTaskPipeline({required this.transcoder, required this.stages});

  final Transcoder transcoder;
  final TaskStageRunner stages;

  Future<void> prepare(
    SubtitleTask task,
    void Function() onChange,
  ) => stages.run(task, TaskStage.prepare, onChange, () async {
    final job = task.transcode;
    if (job == null) {
      throw const ProviderException('转码任务缺少参数', hint: '删除这个任务后重新建。');
    }
    if (!File(task.sourcePath).existsSync()) {
      throw ProviderException(
        '源文件不存在',
        detail: task.sourcePath,
        hint: '文件可能已被移动或删除。重新选择文件。',
      );
    }
    final options = job.options;
    final problem = options.problem;
    if (problem != null) {
      throw ProviderException(problem, hint: '删除这个任务，改好参数后重新建。');
    }

    final probe = await transcoder.probe(task.sourcePath);
    task.mediaDuration = probe.duration;
    final v = probe.video.firstOrNull;
    final a = probe.audio.firstOrNull;
    job.sourceVideo = v == null ? null : MediaProbe.codecLabel(v.codec);
    job.sourceAudio = a == null ? null : MediaProbe.codecLabel(a.codec);

    final clash = probe.incompatibility(options);
    if (clash != null) {
      throw ProviderException(
        clash,
        hint: '把这一路改为重新编码，或换一个容器，然后从准备阶段继续。',
      );
    }
    if (probe.video.isEmpty) {
      task.note('源文件没有视频流，只处理音频', LogLevel.warn);
    }

    // 续跑沿用上次定下的路径（那里可能留着上次失败的半截文件，会被覆盖）。
    final output = job.outputPath ??= TranscodeCommand.outputPath(
      input: task.sourcePath,
      options: options,
      exists: (p) => File(p).existsSync(),
    );
    final args = TranscodeCommand.build(
      options: options,
      input: task.sourcePath,
      output: output,
      audioEncoder: transcoder.audioEncoder(options.effectiveAudio),
    );
    job.command = TranscodeCommand.display(args);
    task.stages[TaskStage.prepare] = task.stages[TaskStage.prepare]!.copyWith(
      note: 'ffprobe · ${probe.video.length + probe.audio.length} 路流',
    );
    task.note(
      '源文件：${[
        if (v != null) '${job.sourceVideo} ${v.shape}',
        if (a != null) '${job.sourceAudio} ${a.channels ?? '?'}ch',
        if (probe.duration != null) Srt.formatDuration(probe.duration!),
      ].join(' · ')}',
    );
    if (probe.subtitleCount > 0) {
      task.note('源文件里的 ${probe.subtitleCount} 路字幕不带入输出', LogLevel.warn);
    }
    task.note('输出：$output');
  });

  Future<void> run(
    SubtitleTask task,
    CancellationToken token,
    void Function() onChange,
  ) => stages.run(task, TaskStage.transcode, onChange, () async {
    final job = task.transcode!;
    final output = job.outputPath!;
    final partial = '$output.part';
    final args = TranscodeCommand.build(
      options: job.options,
      input: task.sourcePath,
      output: partial,
      audioEncoder: transcoder.audioEncoder(job.options.effectiveAudio),
      progress: true,
    );
    final encoderId = job.encoder?.id ?? 'copy';
    task.progress = 0;
    job.speed = null;
    task.note('开始转码 · $encoderId');
    await Directory(File(output).parent.path).create(recursive: true);

    final started = DateTime.now();
    final total = task.mediaDuration;
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await transcoder.run(
        args: args,
        encoderId: encoderId,
        token: token,
        onProgress: (p) {
          job.speed = p.speed;
          if (total != null && total.inMilliseconds > 0) {
            task.progress = (p.position.inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0);
            final speed = p.speed;
            task.eta = speed != null && speed > 0
                ? Duration(
                    milliseconds:
                        ((total - p.position).inMilliseconds / speed).round(),
                  )
                : estimateRemaining(
                    started,
                    p.position.inMilliseconds,
                    total.inMilliseconds,
                  );
          }
          task.stages[TaskStage.transcode] = task.stages[TaskStage.transcode]!
              .copyWith(
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
        },
      );
      await File(partial).rename(output);
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
    }
    task.progress = 1;
    task.eta = null;
  });

  Future<void> finish(SubtitleTask task, void Function() onChange) =>
      stages.run(task, TaskStage.finish, onChange, () async {
        final job = task.transcode!;
        final file = File(job.outputPath!);
        final size = file.existsSync() ? file.lengthSync() : 0;
        if (size == 0) {
          throw ProviderException(
            '产物为空',
            detail: job.outputPath,
            hint: '源文件可能没有可用的音视频流。从转码阶段继续重试一次。',
          );
        }
        job.outputBytes = size;
        task.stages[TaskStage.finish] = task.stages[TaskStage.finish]!.copyWith(
          note: MediaFileInfo(path: file.path, sizeBytes: size).sizeLabel,
        );
        task.note('已写出 ${job.outputPath}');
      });
}
