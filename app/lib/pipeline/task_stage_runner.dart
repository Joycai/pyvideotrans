import '../domain/task.dart';

/// 所有流水线阶段共用的执行壳：断点跳过、开始/完成状态、耗时与界面通知。
class TaskStageRunner {
  const TaskStageRunner();

  Future<void> run(
    SubtitleTask task,
    TaskStage stage,
    void Function() onChange,
    Future<void> Function() body, {
    bool skip = false,
    String? skipNote,
  }) async {
    final existing = task.stages[stage]!;
    if (existing.state == StageState.done ||
        existing.state == StageState.skipped) {
      return;
    }

    task.stage = stage;

    if (skip) {
      task.stages[stage] = existing.copyWith(
        state: StageState.skipped,
        note: skipNote,
      );
      onChange();
      return;
    }

    task.stages[stage] = existing.copyWith(state: StageState.active);
    onChange();

    final started = DateTime.now();
    await body();

    task.stages[stage] = task.stages[stage]!.copyWith(
      state: StageState.done,
      duration: DateTime.now().difference(started),
    );
    onChange();
  }
}
