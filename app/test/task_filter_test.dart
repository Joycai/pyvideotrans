import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_filter.dart';

import 'helpers.dart';

SubtitleTask _task(TaskStatus status) => SubtitleTask(
  id: status.name,
  sourcePath: '/a/${status.name}.mp4',
  kind: TaskKind.transcribe,
  options: testOptions(),
  status: status,
);

void main() {
  Set<TaskStatus> matched(TaskFilter f) => {
    for (final s in TaskStatus.values)
      if (f.matches(_task(s))) s,
  };

  test('排队算进行中，取消算失败', () {
    expect(matched(TaskFilter.running), {TaskStatus.running, TaskStatus.queued});
    expect(matched(TaskFilter.failed), {TaskStatus.failed, TaskStatus.cancelled});
    expect(matched(TaskFilter.done), {TaskStatus.done});
  });

  test('全部不挑；已暂停只落在全部里', () {
    expect(matched(TaskFilter.all), TaskStatus.values.toSet());
    for (final f in TaskFilter.values.where((f) => f != TaskFilter.all)) {
      expect(f.matches(_task(TaskStatus.paused)), isFalse, reason: f.name);
    }
  });

  test('chip 上的文案', () {
    expect([for (final f in TaskFilter.values) f.label], [
      '全部',
      '进行中',
      '失败',
      '已完成',
    ]);
  });
}
