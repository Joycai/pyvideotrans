import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/media_kinds.dart';
import '../domain/task.dart';
import '../domain/task_options.dart';
import '../services/provider_api.dart';
import '../services/settings.dart';
import 'task_runner.dart';

/// 任务队列。串行执行 —— 识别和翻译都受服务端限流约束，并发跑只会更慢更容易被拒，
/// 而且本地模型阶段还要抢 GPU。
class TaskQueue extends ChangeNotifier {
  TaskQueue({required this.runner, required this.settings});

  final TaskRunner runner;
  final AppSettings settings;

  final List<SubtitleTask> _tasks = [];
  final Map<String, CancellationToken> _tokens = {};
  String? _runningId;

  /// [resumeAuto] 正在调 [resume]，别把刚打开的自动模式又关掉。
  bool _autoRequested = false;

  UnmodifiableListView<SubtitleTask> get tasks => UnmodifiableListView(_tasks);

  SubtitleTask? get running => _runningId == null ? null : byId(_runningId!);

  SubtitleTask? byId(String id) => _tasks.where((t) => t.id == id).firstOrNull;

  int countWhere(bool Function(SubtitleTask) test) => _tasks.where(test).length;

  /// 整体进度：进行中任务的平均值。没有进行中的任务时为 0。
  double get overallProgress {
    final active = _tasks.where((t) => t.status == TaskStatus.running);
    if (active.isEmpty) return 0;
    return active.map((t) => t.progress).reduce((a, b) => a + b) /
        active.length;
  }

  /// 把一批文件按同一份参数入队。「新建转写」一次选多个文件走的就是这里。
  ///
  /// 返回的顺序与 [paths] 一致，方便调用方选中第一个。
  List<SubtitleTask> enqueueAll(List<String> paths, {TaskOptions? options}) => [
    for (final path in paths) enqueue(sourcePath: path, options: options),
  ];

  /// 入队一个任务。
  ///
  /// [options] 省略时取设置里的默认值。任务类型由文件类型与
  /// [TaskOptions.translate] 共同决定：字幕文件只能翻译，音视频则看用户
  /// 有没有勾「转写完成后继续翻译」。
  SubtitleTask enqueue({
    required String sourcePath,
    TaskOptions? options,
    TaskKind? kind,
  }) {
    final opts = options ?? settings.defaultTaskOptions();
    final task = SubtitleTask(
      id: const Uuid().v4(),
      sourcePath: sourcePath,
      kind:
          kind ??
          (MediaKinds.isSubtitle(sourcePath) ? TaskKind.translate : opts.kind),
      options: opts,
    );
    task.note('任务已加入队列（位置 ${_tasks.where((t) => t.isActive).length + 1}）');
    _tasks.insert(0, task);
    notifyListeners();
    _pump();
    return task;
  }

  /// 取消进行中的任务。已完成阶段的结果保留。
  void cancel(String id) {
    _tokens[id]?.cancel();
    final task = byId(id);
    if (task != null && task.status == TaskStatus.queued) {
      task.status = TaskStatus.cancelled;
      task.note('排队中被取消', LogLevel.warn);
      notifyListeners();
    }
  }

  /// 自动重试并跳过失败段：识别阶段里失败的段自动重试，达到上限就跳过
  /// 继续；限流与断网不算失败，等恢复后再试。
  void resumeAuto(String id) {
    final task = byId(id);
    if (task == null || task.isActive) return;
    (task.recognition ??= RecognitionCheckpoint()).autoRetry = true;
    _autoRequested = true;
    task.note(
      '自动重试：失败的段最多重试 ${RecognitionCheckpoint.maxFailures} 次后跳过，'
      '限流时等待恢复',
    );
    resume(id);
  }

  /// 从中断处继续。已完成的阶段不会重做。
  ///
  /// 普通续跑关掉自动模式：用户每次点的是哪个按钮，就按哪个按钮的意思来。
  /// [resumeAuto] 先打开标记再调这里，所以用 [_autoRequested] 区分。
  void resume(String id) {
    final task = byId(id);
    if (task == null || task.isActive) return;
    if (!_autoRequested) task.recognition?.autoRetry = false;
    _autoRequested = false;
    task.status = TaskStatus.queued;
    task.error = null;
    // 把失败/取消的那一个阶段退回待执行，之前完成的保持 done。
    for (final entry in task.stages.entries) {
      if (entry.value.state == StageState.failed ||
          entry.value.state == StageState.cancelled ||
          entry.value.state == StageState.active) {
        task.stages[entry.key] = const StageRecord();
      }
    }
    final cp = task.recognition;
    task.note(
      cp != null && cp.doneCount > 0 && task.resumeStage == TaskStage.recognize
          ? '从识别阶段继续：${cp.doneCount} / ${cp.total ?? cp.length} 段已完成，只重试其余'
          : '从${task.resumeStage.label}阶段继续',
    );
    notifyListeners();
    _pump();
  }

  /// 插队。只对排队中的任务有意义。
  void prioritize(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0 || index == _tasks.length - 1) return;
    final task = _tasks[index];
    if (task.status != TaskStatus.queued) return;
    // The queue is stored newest-first, while _pump takes the last queued
    // item (FIFO). Move a prioritized item to the tail so it runs next.
    _tasks
      ..removeAt(index)
      ..add(task);
    notifyListeners();
  }

  void remove(String id) {
    cancel(id);
    _tasks.removeWhere((t) => t.id == id);
    _tokens.remove(id);
    notifyListeners();
  }

  /// 取下一个排队任务开跑。已有任务在跑时直接返回。
  Future<void> _pump() async {
    if (_runningId != null) return;

    // 队列尾部先进先出：列表头是最新加入的，所以从后往前找。
    final next = _tasks.lastWhereOrNull((t) => t.status == TaskStatus.queued);
    if (next == null) return;

    _runningId = next.id;
    final token = CancellationToken();
    _tokens[next.id] = token;

    await runner.run(next, token: token, onChange: notifyListeners);

    _tokens.remove(next.id);
    _runningId = null;
    notifyListeners();

    // 继续下一个。
    await _pump();
  }
}

extension _LastWhereOrNull<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
