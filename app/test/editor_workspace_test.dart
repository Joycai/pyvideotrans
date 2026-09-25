import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_prompts.dart';
import 'package:subtitle_studio/features/editor/editor_workspace.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';
import 'helpers.dart';

SubtitleTask _task(String id, {String? sourcePath}) =>
    SubtitleTask(
        id: id,
        sourcePath: sourcePath ?? '/v/$id.mp4',
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
  late ScriptedPrompts prompts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subtitle_studio_ws');
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    queue = TaskQueue(
      runner: TaskRunner(settings: settings, workDir: dir.path),
      settings: settings,
    );
    shown = 0;
    // 默认有未写入修改时答「取消」：测到换会话的放行必须是没修改才不问。
    prompts = ScriptedPrompts(leave: LeaveChoice.cancel);
    workspace = EditorWorkspace(
      settings: settings,
      store: EditorStore('${dir.path}${Platform.pathSeparator}editor'),
      queue: queue,
      prompts: prompts,
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
    expect(prompts.said, ['这个任务已经删除了']);
    expect(workspace.current, isNull);
  });

  test('打开会话记进最近打开，新的在前', () async {
    await workspace.openTask(_task('a'));
    await workspace.openTask(_task('b'));
    await workspace.recentsSettled;
    // 连着换两次会话：两次写盘排队，不会互相踩掉临时文件。
    expect(workspace.recents.map((r) => r.taskId), ['b', 'a']);
  });

  test('换会话前有未写入的修改：按 prompts 的回答决定换不换', () async {
    await workspace.openTask(_task('a'));
    final first = workspace.current!..editSource('改过');
    expect(prompts.asked, isEmpty, reason: '第一次打开没有旧会话要问');

    await workspace.openTask(_task('b'));
    expect(prompts.asked, ['leave']);
    expect(workspace.current, same(first), reason: '「取消」留在原会话');

    prompts.leave = LeaveChoice.later;
    await workspace.openTask(_task('b'));
    expect(workspace.current, isNot(same(first)));
  });

  test('退出前的询问带「写入并退出」；没有会话时直接放行', () async {
    expect(await workspace.confirmLeave(intent: LeaveIntent.exit), isTrue);
    expect(prompts.asked, isEmpty);

    await workspace.openTask(_task('a'));
    workspace.current!.editSource('改过');
    expect(await workspace.confirmLeave(intent: LeaveIntent.exit), isFalse);
    expect(prompts.lastLeave!.intent, LeaveIntent.exit);
  });

  test('保存：没东西可写时不动，有修改时走写入流程', () async {
    await workspace.save();
    final task = _task('a', sourcePath: '${dir.path}/a.mp4');
    await workspace.openTask(task);
    await workspace.save();
    expect(task.outputs, isEmpty, reason: '没有修改，也不是没写过产物');

    workspace.current!.editSource('改过');
    await workspace.save();
    expect(task.outputs, isNotEmpty);
    expect(workspace.current!.unsavedEdits, 0);
    expect(prompts.asked, isEmpty);
  });

  test('打开会话时找一次预览用的音视频，换会话时随旧 controller 释放', () async {
    await workspace.openTask(_task('a'));
    final media = workspace.current!.media;
    await media.locate();
    // 任务的源文件不存在、旁边也没有：只预览字幕样式。
    expect(media.path, isNull);
    expect(media.onError, isNotNull, reason: '播放器打不开时要能提示');

    await workspace.openTask(_task('b'));
    expect(() => media.addListener(() {}), throwsFlutterError);
  });
}
