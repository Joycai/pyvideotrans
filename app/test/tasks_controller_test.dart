import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_filter.dart';
import 'package:subtitle_studio/features/tasks/task_detail_panel.dart';
import 'package:subtitle_studio/features/tasks/tasks_controller.dart';
import 'package:subtitle_studio/features/tasks/tasks_page.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

/// 不真跑：任务状态由测试直接摆好，好让各个分组里都有东西。
class _IdleRunner extends TaskRunner {
  _IdleRunner({required super.settings}) : super(workDir: '/unused');

  final _never = Completer<void>();

  @override
  Future<void> run(
    SubtitleTask task, {
    required CancellationToken token,
    required void Function() onChange,
  }) => _never.future;
}

void main() {
  late TaskQueue queue;
  late TasksController tasks;
  late int notified;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    queue = TaskQueue(runner: _IdleRunner(settings: settings), settings: settings);
    tasks = TasksController(queue: queue);
    notified = 0;
    tasks.addListener(() => notified++);
  });

  tearDown(() => tasks.dispose());

  SubtitleTask add(String name, TaskStatus status) =>
      queue.enqueue(sourcePath: '/a/$name.mp4', options: testOptions())
        ..status = status;

  group('筛选', () {
    test('可见列表与计数都按 TaskFilter 分组', () {
      final queued = add('q', TaskStatus.queued);
      final failed = add('f', TaskStatus.failed);
      final cancelled = add('c', TaskStatus.cancelled);
      final done = add('d', TaskStatus.done);
      add('p', TaskStatus.paused);

      expect(tasks.counts, {
        TaskFilter.all: 5,
        TaskFilter.running: 1,
        TaskFilter.failed: 2,
        TaskFilter.done: 1,
      });

      tasks.setFilter(TaskFilter.failed);
      expect(tasks.visible, [cancelled, failed]); // 队列新的在前
      tasks.setFilter(TaskFilter.running);
      expect(tasks.visible, [queued]);
      tasks.setFilter(TaskFilter.done);
      expect(tasks.visible, [done]);
    });

    test('选同一个筛选不通知', () {
      tasks.setFilter(TaskFilter.all);
      expect(notified, 0);
      tasks.setFilter(TaskFilter.done);
      expect(notified, 1);
      expect(tasks.filter, TaskFilter.done);
    });
  });

  group('选中', () {
    test('再点一次同一行收起', () {
      tasks.toggleSelect('x');
      expect(tasks.selectedId, 'x');
      tasks.toggleSelect('y');
      expect(tasks.selectedId, 'y');
      tasks.toggleSelect('y');
      expect(tasks.selectedId, isNull);
      expect(notified, 3);
    });

    test('建完任务选中这一批的第一个文件，不是队列最前面那条', () {
      tasks.selectEnqueued(const []);
      expect(tasks.selectedId, isNull, reason: '空批什么也不做');
      expect(notified, 0);

      add('old', TaskStatus.done);
      final batch = queue.enqueueAll(
        ['/a/1.mp4', '/a/2.mp4', '/a/3.mp4'],
        options: testOptions(),
      );
      expect(queue.tasks.first, batch.last, reason: '队列新的在前');
      tasks.selectEnqueued(batch);
      expect(tasks.selectedId, batch.first.id);
      expect(notified, 1);
    });

    test('删掉的是选中的才清掉', () {
      tasks.toggleSelect('a');
      tasks.forget('b');
      expect(tasks.selectedId, 'a');
      tasks.forget('a');
      expect(tasks.selectedId, isNull);
      expect(notified, 2);
    });
  });

  // main.dart 按分区 switch 换页面、不保活。这里照样把任务页拆掉再装回来。
  testWidgets('离开任务页再回来，筛选与选中还在', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final t = add('keep', TaskStatus.failed);
    add('other', TaskStatus.done);
    var onTasks = true;
    late StateSetter go;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              go = setState;
              if (!onTasks) return const Text('别的页面');
              return ListenableBuilder(
                listenable: Listenable.merge([queue, tasks]),
                builder: (_, _) => TasksPage(
                  queue: queue,
                  controller: tasks,
                  onOpenEditor: (_) {},
                  showNewTranscribe: (_, _) async => null,
                  showNewTranslate: (_, _, _) async => null,
                ),
              );
            },
          ),
        ),
      ),
    );

    tasks.setFilter(TaskFilter.failed);
    await tester.pump();
    expect(find.text('other.mp4'), findsNothing);
    await tester.tap(find.text('keep.mp4'));
    await tester.pumpAndSettle();
    expect(tasks.selectedId, t.id);
    expect(find.byType(TaskDetailPanel), findsOneWidget);

    go(() => onTasks = false);
    await tester.pumpAndSettle();
    expect(find.byType(TasksPage), findsNothing);

    go(() => onTasks = true);
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPanel), findsOneWidget);
    expect(find.text('other.mp4'), findsNothing);
    expect(tasks.filter, TaskFilter.failed);
  });

  test('顶栏副标题与筛选 chip 同一口径：排队算进行中，取消算失败', () {
    add('r', TaskStatus.queued);
    add('f', TaskStatus.failed);
    add('c', TaskStatus.cancelled);
    add('d', TaskStatus.done);
    add('p', TaskStatus.paused);
    final chrome = tasksChrome(
      queue,
      onNewTranslate: () {},
      onNewTranscribe: () {},
    );
    expect(chrome.subtitle, '5 个任务 · 1 个进行中 · 2 个失败');
  });

  group('拖入分流', () {
    test('只有字幕走翻译，只有音视频走转写', () {
      expect(TasksController.routeDrop(['/a.srt', '/b.vtt']), DropRoute.translate);
      expect(TasksController.routeDrop(['/a.mp4', '/b.wav']), DropRoute.transcribe);
    });

    test('混在一起时多的一边赢，一样多算字幕', () {
      expect(
        TasksController.routeDrop(['/a.srt', '/b.mp4', '/c.mkv']),
        DropRoute.transcribe,
      );
      expect(
        TasksController.routeDrop(['/a.srt', '/b.ass', '/c.mp4']),
        DropRoute.translate,
      );
      expect(TasksController.routeDrop(['/a.srt', '/b.mp4']), DropRoute.translate);
    });

    test('一个认得的都没有就不开对话框', () {
      expect(TasksController.routeDrop(const []), DropRoute.none);
      expect(TasksController.routeDrop(['/a.txt', '/b.pdf']), DropRoute.none);
    });

    test('认不得的文件不参与计数', () {
      expect(
        TasksController.routeDrop(['/a.mp4', '/x.txt', '/y.txt']),
        DropRoute.transcribe,
      );
    });
  });
}
