import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/task_store.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  late TaskStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('task_store_test_');
    store = TaskStore('${tmp.path}/tasks');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  SubtitleTask task(String id, DateTime createdAt, {TaskStatus? status}) =>
      SubtitleTask(
        id: id,
        sourcePath: '/v/$id.mp4',
        kind: TaskKind.transcribe,
        options: testOptions(),
        createdAt: createdAt,
        status: status ?? TaskStatus.done,
        document: const SubtitleDocument(
          cues: [Cue(index: 1, startMs: 0, endMs: 1000, source: '你好')],
        ),
      );

  group('TaskStore', () {
    test('存了读得回来，新的在前', () async {
      await store.save(task('old', DateTime(2026, 1, 1)));
      await store.save(task('new', DateTime(2026, 2, 1)));
      final loaded = await store.loadAll(fallbackOptions: testOptions());
      expect(loaded.map((t) => t.id), ['new', 'old']);
      expect(loaded.first.document.cues.single.source, '你好');
    });

    test('删掉后不再读回，删不存在的不报错', () async {
      await store.save(task('a', DateTime(2026)));
      await store.delete('a');
      await store.delete('never');
      expect(await store.loadAll(fallbackOptions: testOptions()), isEmpty);
    });

    test('坏存档跳过，不影响其他任务', () async {
      await store.save(task('good', DateTime(2026)));
      File('${store.dir}/bad.json').writeAsStringSync('{not json');
      File('${store.dir}/empty.json').writeAsStringSync('{}');
      final loaded = await store.loadAll(fallbackOptions: testOptions());
      expect(loaded.map((t) => t.id), ['good']);
    });

    test('目录不存在时是空列表', () async {
      expect(await store.loadAll(fallbackOptions: testOptions()), isEmpty);
    });
  });

  group('队列持久化', () {
    late AppSettings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });

    TaskQueue queue() => TaskQueue(
      runner: TaskRunner(settings: settings, workDir: tmp.path),
      settings: settings,
      store: store,
    );

    test('启动时恢复任务；上次没跑完的标为已暂停，可以继续', () async {
      final running = task('r', DateTime(2026, 3), status: TaskStatus.running)
        ..stage = TaskStage.recognize;
      running.stages[TaskStage.queued] = const StageRecord(
        state: StageState.done,
      );
      running.stages[TaskStage.prepare] = const StageRecord(
        state: StageState.done,
      );
      running.stages[TaskStage.recognize] = const StageRecord(
        state: StageState.active,
      );
      await store.save(running);
      await store.save(task('d', DateTime(2026, 2)));

      final q = queue();
      await q.restore();

      expect(q.tasks.map((t) => t.id), ['r', 'd']);
      final r = q.byId('r')!;
      expect(r.status, TaskStatus.paused);
      expect(r.stages[TaskStage.recognize]!.state, StageState.pending);
      expect(r.stages[TaskStage.prepare]!.state, StageState.done);
      expect(r.resumeStage, TaskStage.recognize);
      expect(q.byId('d')!.status, TaskStatus.done);

      // 暂停状态也写回了磁盘。
      await q.flush();
      final again = await store.loadAll(fallbackOptions: testOptions());
      expect(again.first.status, TaskStatus.paused);
    });

    // 旧版本的存档里模型只有名字或没写。不写回的话每次启动都按当时的
    // 设置重新补一遍，两次启动之间改过默认模型，没续跑的旧任务就换了模型。
    test('旧格式的存档：按此刻的设置补成声明并写回，之后不再跟着设置变', () async {
      settings.setModels('mt_custom', [const ChatModelSpec(name: 'first')]);
      final old = task('old', DateTime(2026), status: TaskStatus.failed);
      final json = old.toJson();
      json['options'] = {
        ...json['options']! as Map<String, Object?>,
        'translationProviderId': 'mt_custom',
        'translationModel': null,
        'asrModel': 'whisper-1',
      };
      Map<String, Object?> read(String id) =>
          jsonDecode(File('${store.dir}/$id.json').readAsStringSync())
              as Map<String, Object?>;
      await store.save(task('new', DateTime(2025)));
      File('${store.dir}/old.json').writeAsStringSync(jsonEncode(json));
      // 新格式的存档里放一个重写就会丢的键，用来看它有没有被重写。
      File(
        '${store.dir}/new.json',
      ).writeAsStringSync(jsonEncode({...read('new'), 'marker': 1}));

      final q = queue();
      await q.restore();
      // 已失败的任务不改状态，但模型补成了设置里给那家服务配的。
      expect(q.byId('old')!.status, TaskStatus.failed);
      expect(q.byId('old')!.options.translationModel.name, 'first');
      await q.flush();

      expect(
        TaskOptions.isLegacyJson(
          read('old')['options']! as Map<String, Object?>,
        ),
        isFalse,
      );
      // 新格式的存档不重写。
      expect(read('new')['marker'], 1);

      settings.setModels('mt_custom', [const ChatModelSpec(name: 'second')]);
      final again = queue();
      await again.restore();
      expect(again.byId('old')!.options.translationModel.name, 'first');
    });

    test('入队写盘，删除任务删存档', () async {
      final q = queue();
      final t = q.enqueue(sourcePath: '${tmp.path}/missing.srt');
      // 源文件不存在，任务很快失败；等它跑完。
      for (var i = 0; i < 200 && q.running != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await q.flush();
      var loaded = await store.loadAll(fallbackOptions: testOptions());
      expect(loaded.single.id, t.id);
      expect(loaded.single.status, TaskStatus.failed);

      q.remove(t.id);
      await q.flush();
      loaded = await store.loadAll(fallbackOptions: testOptions());
      expect(loaded, isEmpty);
    });

    test('编辑器改了文档，persist 后写盘', () async {
      final q = queue();
      await store.save(task('e', DateTime(2026)));
      await q.restore();
      final t = q.byId('e')!;
      t.document = t.document.replaceAt(
        0,
        t.document.cues.single.copyWith(source: '改过了'),
      );
      q.persist(t);
      await q.flush();
      final loaded = await store.loadAll(fallbackOptions: testOptions());
      expect(loaded.single.document.cues.single.source, '改过了');
    });
  });
}
