import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/recognition_checkpoint.dart';
import 'package:subtitle_studio/domain/task.dart';

import 'helpers.dart';

/// 走一遍真正落盘时的路径：toJson → 字符串 → 解析 → fromJson。
SubtitleTask _roundTrip(SubtitleTask task) => SubtitleTask.fromJson(
  (jsonDecode(jsonEncode(task.toJson())) as Map).cast<String, Object?>(),
  fallbackOptions: testOptions(),
);

void main() {
  test('任务来回一致：文档、阶段、日志、错误、识别检查点都不丢', () {
    final task = SubtitleTask(
      id: 'j1',
      sourcePath: '/v/demo.mp4',
      kind: TaskKind.transcribeAndTranslate,
      options: testOptions(source: 'ja', cjkLineLength: 22),
      status: TaskStatus.failed,
      stage: TaskStage.translate,
      progress: 0.4,
      mediaDuration: const Duration(minutes: 3),
      createdAt: DateTime.utc(2026, 9, 13, 8),
      error: const TaskError(title: '云端超时', detail: 'timeout', hint: '重试'),
      document: const SubtitleDocument(
        sourceLanguage: '日文',
        targetLanguage: '英文',
        cues: [
          Cue(
            index: 1,
            startMs: 0,
            endMs: 1500,
            source: 'こんにちは',
            translation: 'Hello',
            confidence: 0.5,
            reviewed: true,
            speaker: 1,
          ),
          Cue(index: 2, startMs: 1500, endMs: 3000, source: '', confidence: 0),
        ],
      ),
    );
    task.stages[TaskStage.prepare] = const StageRecord(
      state: StageState.done,
      duration: Duration(seconds: 2),
      note: '音频 3:00',
    );
    task.note('识别完成', LogLevel.warn);
    final cp = RecognitionCheckpoint()
      ..total = 5
      ..asyncTaskId = 'task-1'
      ..autoRetry = true;
    cp.segment(0, 1500)
      ..text = 'こんにちは'
      ..pieces = const [
        SegmentPiece(startMs: 0, endMs: 1500, text: 'こんにちは', speaker: 1),
      ];
    cp.fail(cp.segment(1500, 3000), 'boom');
    task.recognition = cp;

    final back = _roundTrip(task);

    expect(back.toJson(), task.toJson());
    expect(back.createdAt, task.createdAt);
    expect(back.document.cues[1].source, '');
    expect(back.document.cues[0].speaker, 1);
    expect(back.stages[TaskStage.prepare]!.note, '音频 3:00');
    expect(back.log.single.level, LogLevel.warn);
    expect(back.error!.title, '云端超时');
    expect(back.recognition!.segment(0, 1500).pieces!.single.speaker, 1);
    expect(back.recognition!.segment(1500, 3000).failures, 1);
    expect(back.options.cjkLineLength, 22);
  });

  test('缺 id 或源文件路径的存档无法使用', () {
    expect(
      () => SubtitleTask.fromJson({
        'sourcePath': '/a.mp4',
      }, fallbackOptions: testOptions()),
      throwsFormatException,
    );
  });

  test('未知的状态、阶段与坏日志条目按默认处理，不抛异常', () {
    final task = SubtitleTask.fromJson({
      'id': 'j2',
      'sourcePath': '/a.mp4',
      'status': 'exploded',
      'stage': 'teleport',
      'stages': {'prepare': 'nope'},
      'log': [
        42,
        {'time': 'x'},
      ],
    }, fallbackOptions: testOptions());
    expect(task.status, TaskStatus.paused);
    expect(task.stage, TaskStage.queued);
    expect(task.stages[TaskStage.prepare]!.state, StageState.pending);
    expect(task.log, isEmpty);
  });

  // 阶段记录里一个字段坏了，不该连累整份任务读不回来。
  test('阶段记录里未知的状态名与类型不对的字段按默认处理', () {
    final task = SubtitleTask.fromJson({
      'id': 'j3',
      'sourcePath': '/a.mp4',
      'stages': {
        'queued': {'state': 'done', 'durationMs': 1200, 'note': '好'},
        'prepare': {'state': 'melted', 'durationMs': 'slow', 'note': 7},
        'recognize': {'durationMs': 1.5},
      },
    }, fallbackOptions: testOptions());
    final queued = task.stages[TaskStage.queued]!;
    expect(queued.state, StageState.done);
    expect(queued.duration, const Duration(milliseconds: 1200));
    expect(queued.note, '好');
    final prepare = task.stages[TaskStage.prepare]!;
    expect(prepare.state, StageState.pending);
    expect(prepare.duration, isNull);
    expect(prepare.note, isNull);
    expect(task.stages[TaskStage.recognize]!.state, StageState.pending);
  });
}
