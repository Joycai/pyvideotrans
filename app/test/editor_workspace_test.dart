import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_workspace.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

SubtitleTask _task(String id) =>
    SubtitleTask(
        id: id,
        sourcePath: '/v/$id.mp4',
        kind: TaskKind.transcribeAndTranslate,
        status: TaskStatus.done,
        options: testOptions(),
      )
      ..document = const SubtitleDocument(
        cues: [Cue(index: 1, startMs: 0, endMs: 1000, source: '一')],
      );

void main() {
  late Directory dir;
  late TaskQueue queue;
  late EditorWorkspace workspace;
  late int shown;
  late List<String> said;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subtitle_studio_ws');
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: dir.path),
      settings: settings,
    );
    shown = 0;
    said = [];
    workspace = EditorWorkspace(
      settings: settings,
      store: EditorStore('${dir.path}${Platform.pathSeparator}editor'),
      queue: queue,
      // 没有 context：换会话前的「先写入字幕文件？」直接放行。
      dialogContext: () => null,
      say: said.add,
      onShow: () => shown++,
    );
  });

  tearDown(() async {
    await workspace.recentsSettled;
    workspace.dispose();
    await dir.delete(recursive: true);
  });

  test('打开任务：切到编辑器分区，再开同一个任务不换会话', () async {
    final task = _task('a');
    await workspace.openTask(task);
    final first = workspace.current;
    expect(first, isNotNull);
    expect(workspace.editing, isTrue);
    expect(shown, 1);

    workspace.openOther();
    await workspace.openTask(task);
    expect(workspace.current, same(first));
    expect(workspace.showOpen, isFalse, reason: '同一个任务只收起入口页');
    expect(shown, 2);
  });

  test('换成另一个会话时关掉旧的 controller', () async {
    await workspace.openTask(_task('a'));
    final first = workspace.current!;
    await workspace.openTask(_task('b'));
    expect(workspace.current, isNot(same(first)));
    expect(() => first.addListener(() {}), throwsFlutterError);
  });

  test('入口页盖在编辑页上：打开其他 / 返回编辑器', () async {
    await workspace.openTask(_task('a'));
    workspace.openOther();
    expect(workspace.showOpen, isTrue);
    expect(workspace.editing, isFalse);
    expect(workspace.current, isNotNull, reason: '真正打开新会话前旧的还在');

    workspace.backToEditor();
    expect(workspace.editing, isTrue);
  });

  test('最近打开里的任务已经删了：提示一句，不动当前会话', () async {
    await workspace.openRecent(
      RecentSession(
        title: 'gone.mp4',
        openedAt: DateTime(2026),
        cueCount: 1,
        taskId: 'gone',
      ),
    );
    expect(said, ['这个任务已经删除了']);
    expect(workspace.current, isNull);
  });

  test('打开会话记进最近打开，新的在前', () async {
    await workspace.openTask(_task('a'));
    await workspace.openTask(_task('b'));
    await workspace.recentsSettled;
    // 连着换两次会话：两次写盘排队，不会互相踩掉临时文件。
    expect(workspace.recents.map((r) => r.taskId), ['b', 'a']);
  });

  test('TaskRunner 默认建的 Transcoder 与自身共用同一个 Media', () {
    final runner = TaskRunner(settings: queue.settings, workDir: dir.path);
    expect(runner.transcoder.media, same(runner.media));
  });
}
