import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/file_stamp.dart';
import 'package:subtitle_studio/domain/paths.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_banners.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_leave_dialog.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/editor_title.dart';
import 'package:subtitle_studio/features/tasks/task_resume_dialog.dart';
import 'package:subtitle_studio/pipeline/subtitle_output_writer.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/file_io.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

const _zh = '''1
00:00:00,000 --> 00:00:02,000
大家好

2
00:00:02,000 --> 00:00:04,000
谢谢邀请

3
00:00:04,000 --> 00:00:06,000
我们继续
''';

SubtitleDocument _doc() => const SubtitleDocument(
  cues: [
    Cue(index: 1, startMs: 0, endMs: 2000, source: '第一句', translation: 'First'),
    Cue(
      index: 2,
      startMs: 2000,
      endMs: 4000,
      source: '第二句话',
      translation: 'Second',
    ),
    Cue(
      index: 3,
      startMs: 4000,
      endMs: 6000,
      source: '第三句',
      translation: 'Third',
    ),
  ],
);

/// 可以拨动的钟：合并连续编辑按时间窗算。
class _Clock {
  DateTime now = DateTime(2026, 9, 18, 10);

  void advance(Duration d) => now = now.add(d);

  DateTime call() => now;
}

/// 手动放行的假翻译：在等译文的那段时间里改文档，看回来的译文怎么落地。
class _GatedTranslator implements TranslationProvider {
  final gate = Completer<void>();
  final calls = <List<String>>[];

  @override
  ProviderInfo get info =>
      const ProviderInfo(id: 'fake_mt', name: '假翻译', vendor: '测试');

  @override
  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  }) async {
    calls.add(lines);
    await gate.future;
    return [for (final l in lines) '译:$l'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String sep;
  late AppSettings settings;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('editor_save_test');
    sep = Platform.pathSeparator;
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  tearDown(() => dir.delete(recursive: true));

  SubtitleTask task({TaskStatus status = TaskStatus.done}) => SubtitleTask(
    id: 't1',
    sourcePath: '${dir.path}${sep}demo.mp4',
    kind: TaskKind.transcribeAndTranslate,
    options: testOptions(),
    status: status,
    document: _doc(),
  );

  EditorController controllerFor(
    EditorSession session, {
    _Clock? clock,
    EditorStore? store,
    SubtitleDocument? saved,
  }) => EditorController(
    session: session,
    settings: settings,
    store: store,
    saved: saved,
    clock: clock?.call,
  );

  group('连续编辑合并', () {
    test('同一条同一字段 1 秒内的连续改动算一处、撤销一次退回', () {
      final clock = _Clock();
      final c = controllerFor(TaskSession(task()), clock: clock)..select(0);
      for (final text in ['第', '第一', '第一句改']) {
        c.editSource(text);
        clock.advance(const Duration(milliseconds: 300));
      }
      expect(c.unsavedEdits, 1);
      c.undo();
      expect(c.document.cues.first.source, '第一句');
      expect(c.canUndo, isFalse);
    });

    test('停顿超过 1 秒、换字段、换一条都另算一处', () {
      final clock = _Clock();
      final c = controllerFor(TaskSession(task()), clock: clock)..select(0);
      c.editSource('甲');
      clock.advance(const Duration(milliseconds: 1500));
      c.editSource('甲乙');
      expect(c.unsavedEdits, 2);
      c.editTranslation('A');
      expect(c.unsavedEdits, 3);
      c
        ..select(1)
        ..editSource('乙');
      expect(c.unsavedEdits, 4);
    });

    test('中间插进别的操作后不再合并', () {
      final clock = _Clock();
      final c = controllerFor(TaskSession(task()), clock: clock)..select(0);
      c
        ..editSource('甲')
        ..toggleReviewed()
        ..editSource('甲乙');
      expect(c.unsavedEdits, 3);
    });
  });

  group('任务会话：写产物', () {
    test('改动记为未写入，保存写出与完成阶段同名的产物并清零', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      expect(c.sync, SyncState.synced);

      c.editSource('改过的第一句');
      expect(c.sync, SyncState.dirty);
      expect(t.unsyncedEdits, 1);
      expect(t.editorEdits, 1);

      final written = await c.save();
      expect(written, ['${dir.path}/demo.zh.srt', '${dir.path}/demo.en.srt']);
      expect(await File(written.first).readAsString(), contains('改过的第一句'));
      expect(c.unsavedEdits, 0);
      expect(t.unsyncedEdits, 0);
      // 累计数不随写入清零：续跑前要靠它提醒。
      expect(t.editorEdits, 1);
      expect(t.outputs.keys, written);
      expect(t.outputsWrittenAt, isNotNull);
      expect(c.sync, SyncState.written);
      c.dispose();
    });

    test('重开任务时接着显示上次没写入的修改数', () {
      final t = task()..unsyncedEdits = 3;
      final c = controllerFor(TaskSession(t));
      expect(c.unsavedEdits, 3);
      expect(c.sync, SyncState.dirty);
      // 不知道上次写的是哪一版，不能「撤销到上次写入」。
      expect(c.canRevertToWritten, isFalse);
    });

    test('产物在外部被改过：保存抛 WriteConflict，覆盖后恢复同步', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      final written = await c.save();
      await File(written.first).writeAsString('别的程序写的内容，长度不一样');

      c.editSource('二');
      await expectLater(c.save(), throwsA(isA<WriteConflict>()));
      expect(c.sync, SyncState.conflict);
      expect(c.conflicts.single.path, written.first);
      expect(c.canWrite, isTrue);

      await c.save(overwrite: true);
      expect(await File(written.first).readAsString(), contains('二'));
      expect(c.conflicts, isEmpty);
      c.dispose();
    });

    test('产物被删掉不算冲突，直接写回', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      final written = await c.save();
      await File(written.first).delete();
      c.editSource('二');
      await c.save();
      expect(await File(written.first).exists(), isTrue);
      c.dispose();
    });

    test('没跑完的任务：还没有产物，保存生成文件', () async {
      final t = task(status: TaskStatus.failed);
      final c = controllerFor(TaskSession(t));
      expect(c.sync, SyncState.noOutput);
      expect(c.canWrite, isTrue);
      await c.save();
      expect(t.outputs, isNotEmpty);
      expect(c.sync, SyncState.written);
      c.dispose();
    });

    test('任务的另存为不许落在产物目录（冲突时默认打开的就是它）', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      await expectLater(c.saveAs(dir.path), throwsA(isA<TargetRejected>()));
      expect(await File('${dir.path}/demo.zh.srt').exists(), isFalse);
      expect(c.sync, SyncState.dirty);
    });

    test('导出不许写到字幕文件自己身上', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      await expectLater(
        c.export({SrtField.source}),
        throwsA(isA<TargetRejected>()),
      );
      final other = await Directory('${dir.path}${sep}out').create();
      final written = await c.export({SrtField.source}, dir: other.path);
      expect(written.single, startsWith(other.path));
      expect(c.sync, SyncState.dirty);
    });

    test('写完 2 秒内再改：马上回到有修改未写入，⌘S 可用', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      await c.save();
      expect(c.sync, SyncState.written);
      c.toggleReviewed();
      expect(c.sync, SyncState.dirty);
      expect(c.canWrite, isTrue);
      c.dispose();
    });

    test('写入失败后继续编辑，红色保留到下一次写成', () async {
      final t = SubtitleTask(
        id: 't3',
        sourcePath: '${dir.path}${sep}blocker${sep}demo.mp4',
        kind: TaskKind.transcribeAndTranslate,
        options: testOptions(),
        status: TaskStatus.done,
        document: _doc(),
      );
      final blocker = File('${dir.path}${sep}blocker');
      await blocker.writeAsString('x');
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      await expectLater(c.save(), throwsA(anything));
      c.toggleReviewed();
      expect(c.sync, SyncState.failed);
      await blocker.delete();
      await c.save();
      expect(c.failure, isNull);
      expect(c.unsavedEdits, 0);
      c.dispose();
    });

    test('另存为只写一份副本，产物与同步状态不变', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      final other = await Directory('${dir.path}${sep}copy').create();
      final written = await c.saveAs(other.path);
      expect(written.every((p) => p.startsWith(other.path)), isTrue);
      expect(c.unsavedEdits, 1);
      expect(t.outputs, isEmpty);
      c.dispose();
    });

    test('另存为：译文写不进去时，原文也不留下', () async {
      final t = task();
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      final other = await Directory('${dir.path}${sep}copy').create();
      // 译文的临时文件位置被一个目录占着，写译文必然失败。
      await Directory('${other.path}${sep}demo.en.srt.tmp').create();

      await expectLater(c.saveAs(other.path), throwsA(anything));
      final left = other.listSync().map((e) => baseName(e.path)).toList();
      expect(left, ['demo.en.srt.tmp']);
      expect(c.unsavedEdits, 1);
      c.dispose();
    });

    test('写入失败：记下原因，修改数不变', () async {
      final t = SubtitleTask(
        id: 't2',
        // 输出目录是一个已存在的普通文件，建目录必然失败。
        sourcePath: '${dir.path}${sep}blocker${sep}demo.mp4',
        kind: TaskKind.transcribeAndTranslate,
        options: testOptions(),
        status: TaskStatus.done,
        document: _doc(),
      );
      await File('${dir.path}${sep}blocker').writeAsString('x');
      final c = controllerFor(TaskSession(t))..select(0);
      c.editSource('一');
      await expectLater(c.save(), throwsA(anything));
      expect(c.sync, SyncState.failed);
      expect(c.failure, isNotNull);
      expect(c.unsavedEdits, 1);
      c.dispose();
    });
  });

  group('本次修改', () {
    test('只有内容变了的条目算改过；拆分只让被拆的那条算改过', () {
      final c = controllerFor(TaskSession(task()))..select(0);
      expect(c.countOf(CueFilter.edited), 0);
      c.split();
      // 拆出的两条是新的；后面两条只是重新编号，不算改过。
      expect(c.countOf(CueFilter.edited), 2);
      c.setFilter(CueFilter.edited);
      expect(c.visibleCues.map((x) => x.index), [1, 2]);
    });

    test('写入后以写入的版本为准重新算', () async {
      final c = controllerFor(TaskSession(task()))..select(0);
      c.toggleReviewed();
      expect(c.countOf(CueFilter.edited), 1);
      await c.save();
      expect(c.countOf(CueFilter.edited), 0);
      c.dispose();
    });
  });

  group('撤销到上次写入', () {
    test('换回上次写入的版本，本身可以撤销', () async {
      final c = controllerFor(TaskSession(task()))..select(0);
      c
        ..editSource('一')
        ..toggleReviewed();
      expect(c.canRevertToWritten, isTrue);
      c.revertToWritten();
      expect(c.unsavedEdits, 0);
      expect(c.document.cues.first.source, '第一句');
      c.undo();
      expect(c.document.cues.first.source, '一');
      expect(c.unsavedEdits, greaterThan(0));
    });
  });

  group('本地会话：编辑进度与恢复', () {
    Future<FileSession> open(String path, {FileState? state}) async {
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(path),
        defaults: testOptions(),
        restored: state?.current,
      )..pendingEdits = state?.pendingEdits ?? 0;
      await s.captureStamps();
      return s;
    }

    test('改动攒成草稿存下，重开时接着显示并能撤销到文件的版本', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);

      final c = controllerFor(await open(path), store: store)..select(0);
      c
        ..editSource('大家好呀')
        ..toggleReviewed();
      await c.flushDraft();
      // 字幕文件本身没动。
      expect(await File(path).readAsString(), _zh);

      final state = await store.loadFileDraft(path, null);
      expect(state, isNotNull);
      expect(state!.pendingEdits, 2);
      expect(state.draft!.cues.first.source, '大家好呀');
      expect(state.saved.cues.first.source, '大家好');

      final reopened = controllerFor(
        await open(path, state: state),
        store: store,
        saved: state.saved,
      );
      expect(reopened.unsavedEdits, 2);
      expect(reopened.canRevertToWritten, isTrue);
      reopened.revertToWritten();
      expect(reopened.document.cues.first.source, '大家好');
      expect(reopened.unsavedEdits, 0);
    });

    test('写回文件后草稿清掉，下次打开不再提示恢复', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final c = controllerFor(await open(path), store: store)..select(0);
      c.editSource('大家好呀');
      await c.flushDraft();
      await c.save();
      final state = await store.loadFileDraft(path, null);
      expect(state!.draft, isNull);
      expect(state.saved.cues.first.source, '大家好呀');
      c.dispose();
    });

    test('文件在外部被改过：草稿照样留着并标出来，保存前报冲突', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final c = controllerFor(await open(path), store: store)..select(0);
      c.editSource('大家好呀');
      await c.flushDraft();
      await File(path)
          .writeAsString('$_zh\n4\n00:00:06,000 --> 00:00:07,000\n新\n');

      // 离开时答应过「不写入也不会丢」。
      final state = await store.loadFileDraft(path, null);
      expect(state!.changedOutside, isTrue);
      expect(state.draft!.cues.first.source, '大家好呀');
      // 只有附加状态、没有草稿的，照旧作废。
      expect(await store.loadFileState(path, null), isNull);
      await expectLater(c.save(), throwsA(isA<WriteConflict>()));
    });

    test('丢弃草稿：存档清掉，之后也不会再写回来', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final c = controllerFor(await open(path), store: store)..select(0);
      c.editSource('大家好呀');
      await c.flushDraft();
      c.toggleReviewed();
      await c.forgetDraft();
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await store.loadFileDraft(path, null), isNull);
    });

    test('只检查这次会写的文件：卸载了的译文被改过不报冲突', () async {
      final zh = '${dir.path}${sep}ep.zh.srt';
      final en = '${dir.path}${sep}ep.en.srt';
      await File(zh).writeAsString(_zh);
      await File(en).writeAsString(_zh.replaceAll('大家好', 'Hello'));
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zh),
        translation: await LocalSubtitleFile.load(en),
        defaults: testOptions(),
      );
      await s.captureStamps();
      final c = controllerFor(s)..unmountTranslation();
      await File(en).writeAsString('被别的程序改过');
      expect(await s.externalChanges(), isEmpty);
      await c.save();
      expect(await File(en).readAsString(), '被别的程序改过');
      c.dispose();
    });

    test('另存为：写到新目录并挂上新文件，更新最近打开', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final s = await open(path);
      var remounted = 0;
      final c = controllerFor(s, store: store)
        ..onRemount = (() => remounted++)
        ..select(0);
      c.editSource('大家好呀');

      final target = await Directory('${dir.path}${sep}out').create();
      await c.saveAs(target.path);
      expect(s.sourcePath, '${target.path}${sep}ep.zh.srt');
      expect(await File(path).readAsString(), _zh);
      expect(c.unsavedEdits, 0);
      expect(remounted, 1);
      c.dispose();
    });

    test('另存为不许写回原目录、不许盖掉同名文件，也不算写入失败', () async {
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final s = await open(path);
      final c = controllerFor(s)..select(0);
      c.editSource('大家好呀');

      await expectLater(c.saveAs(dir.path), throwsA(isA<TargetRejected>()));
      final other = await Directory('${dir.path}${sep}other').create();
      await File('${other.path}${sep}ep.zh.srt').writeAsString('别人的');
      await expectLater(c.saveAs(other.path), throwsA(isA<TargetRejected>()));
      expect(await File('${other.path}${sep}ep.zh.srt').readAsString(), '别人的');
      expect(s.sourcePath, path);
      expect(c.sync, SyncState.dirty);
    });

    test('另存为：译文写不进去时一份都不留，仍挂在原来的文件上', () async {
      final zh = '${dir.path}${sep}ep.zh.srt';
      final en = '${dir.path}${sep}ep.en.srt';
      await File(zh).writeAsString(_zh);
      await File(en).writeAsString(_zh.replaceAll('大家好', 'Hello'));
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zh),
        translation: await LocalSubtitleFile.load(en),
        defaults: testOptions(),
      );
      await s.captureStamps();
      final c = controllerFor(s)..select(0);
      c.editSource('大家好呀');
      final other = await Directory('${dir.path}${sep}other').create();
      await Directory('${other.path}${sep}ep.en.srt.tmp').create();

      await expectLater(c.saveAs(other.path), throwsA(anything));
      final left = other.listSync().map((e) => baseName(e.path)).toList();
      expect(left, ['ep.en.srt.tmp']);
      expect((s.sourcePath, s.translationPath), (zh, en));
      expect(await File(zh).readAsString(), _zh);
      c.dispose();
    });

    test('另存为写失败：仍挂在原来的文件上', () async {
      final path = '${dir.path}${sep}ep.zh.srt';
      await File(path).writeAsString(_zh);
      final s = await open(path);
      final c = controllerFor(s)..select(0);
      c.editSource('大家好呀');
      // 目标「目录」其实是个文件，写不进去。
      final blocker = '${dir.path}${sep}blocker';
      await File(blocker).writeAsString('x');

      await expectLater(c.saveAs(blocker), throwsA(anything));
      expect(s.sourcePath, path);
      expect(s.trackedStamps.keys, [path]);
      expect(c.sync, SyncState.failed);
      c.dispose();
    });
  });

  group('任务运行中', () {
    // 任务队列：流水线每改一次文档就通知一次。
    final queue = ValueNotifier(0);

    SubtitleDocument translated(SubtitleDocument doc, String suffix) =>
        doc.copyWith(
          cues: [
            for (final c in doc.cues)
              c.copyWith(translation: '${c.translation}$suffix'),
          ],
        );

    EditorController follow(SubtitleTask t) => EditorController(
      session: TaskSession(t),
      settings: settings,
      follow: queue,
    )..select(0);

    test('排队、运行中只读：改不了、撤销不了、不写文件', () async {
      for (final status in [TaskStatus.queued, TaskStatus.running]) {
        final t = task(status: status);
        final before = t.document;
        final c = follow(t);
        expect(c.locked, isTrue);
        c
          ..editSource('一')
          ..toggleReviewed()
          ..split()
          ..undo()
          ..revertToWritten();
        expect(identical(t.document, before), isTrue);
        expect(t.unsyncedEdits, 0);
        expect(t.editorEdits, 0);
        expect(c.canWrite, isFalse);
        expect(await c.save(), isEmpty);
        await expectLater(
          c.saveAs('${dir.path}${sep}copy'),
          throwsA(isA<TargetRejected>()),
        );
        expect(await c.translateMissing(), 0);
        expect(editorLockNote(c), isNotNull);
        c.dispose();
      }
    });

    test('流水线换了文档：跟着刷新，撤销栈清掉，不算本次修改', () {
      final t = task(status: TaskStatus.paused);
      final c = follow(t);
      c.editSource('暂停时改的');
      expect(c.canUndo, isTrue);

      // 续跑：排队 → 运行，流水线写进一批译文。
      t.status = TaskStatus.running;
      queue.value++;
      expect(c.locked, isTrue);
      var notified = 0;
      c.addListener(() => notified++);
      t.document = translated(t.document, '·新');
      queue.value++;
      expect(notified, 1);
      expect(c.canUndo, isFalse);
      expect(c.isEdited(c.document.cues.first), isFalse);
      expect(c.document.cues.first.source, '暂停时改的');

      // 跑完：完成阶段写出产物、清零未写入数。
      t
        ..status = TaskStatus.done
        ..unsyncedEdits = 0;
      queue.value++;
      expect(c.locked, isFalse);
      expect(c.sync, SyncState.synced);
      // 撤销不会把流水线的结果换回运行前的样子。
      c.undo();
      expect(c.document.cues.first.translation, 'First·新');
      c.editSource('跑完再改');
      expect(c.sync, SyncState.dirty);
      c.dispose();
    });

    test('文档被换得更短：选中条收回范围内', () {
      final t = task(status: TaskStatus.running);
      final c = follow(t)..select(2);
      t.document = t.document.copyWith(cues: [t.document.cues.first]);
      queue.value++;
      expect(c.selected, 0);
      expect(c.current, isNotNull);
      c.dispose();
    });

    testWidgets('运行中切走不问「先写入字幕文件？」', (tester) async {
      final t = task(status: TaskStatus.paused);
      final c = follow(t)..editSource('一');
      t.status = TaskStatus.running;
      late bool left;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => left = await confirmLeaveEditor(context, c),
              child: const Text('走'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('走'));
      await tester.pumpAndSettle();
      expect(find.text('先写入字幕文件？'), findsNothing);
      expect(left, isTrue);
      c.dispose();
    });

    test('阶段变了也刷新只读说明', () {
      final t = task(status: TaskStatus.queued)..stage = TaskStage.queued;
      final c = follow(t);
      var notified = 0;
      c.addListener(() => notified++);
      expect(editorLockNote(c), contains('排队'));
      t
        ..status = TaskStatus.running
        ..stage = TaskStage.recognize;
      queue.value++;
      expect(notified, 1);
      expect(editorLockNote(c), contains('识别'));
      c.dispose();
    });

    test('跑完解锁才认产物已同步；取消解锁时修改标记还在', () {
      for (final (end, synced) in [
        (TaskStatus.done, true),
        (TaskStatus.cancelled, false),
      ]) {
        final t = task(status: TaskStatus.paused);
        final c = follow(t)..editSource('暂停时改的');
        final cue = c.document.cues.first;
        expect(c.isEdited(cue), isTrue);
        // 从翻译阶段续跑：文档不换，跑完或被取消。
        t.status = TaskStatus.running;
        queue.value++;
        t.status = end;
        if (end == TaskStatus.done) t.unsyncedEdits = 0;
        queue.value++;
        expect(c.locked, isFalse);
        expect(c.isEdited(cue), !synced);
        expect(c.unsavedEdits == 0, synced);
        c.dispose();
      }
    });

    test('翻译未译：等译文时文档被换掉或又改了，译文只填原文没变的空位', () async {
      final t = task()
        ..document = _doc().copyWith(
          cues: [
            for (final c in _doc().cues) c.copyWith(translation: ''),
          ],
        );
      final translator = _GatedTranslator();
      final c = EditorController(
        session: TaskSession(t),
        settings: settings,
        follow: queue,
        translator: () => translator,
      )..select(1);
      final running = c.translateMissing();
      await Future<void>.delayed(Duration.zero);
      expect(translator.calls.single, ['第一句', '第二句话', '第三句']);

      // 等译文期间：用户改了第 2 条原文，流水线（续跑后又失败）换掉了第 3 条。
      c.editSource('改过的第二句');
      final cues = [...t.document.cues];
      cues[2] = cues[2].copyWith(source: '重新断句的第三句');
      t.document = t.document.copyWith(cues: cues);
      queue.value++;

      translator.gate.complete();
      expect(await running, 1);
      final after = t.document.cues;
      expect(after[0].translation, '译:第一句');
      expect(after[1].source, '改过的第二句');
      expect(after[1].hasTranslation, isFalse);
      expect(after[2].source, '重新断句的第三句');
      expect(after[2].hasTranslation, isFalse);
      c.dispose();
    });

    test('翻译未译：等译文时任务开跑了，译文不写回', () async {
      final t = task(status: TaskStatus.paused)
        ..document = _doc().copyWith(
          cues: [for (final c in _doc().cues) c.copyWith(translation: '')],
        );
      final translator = _GatedTranslator();
      final c = EditorController(
        session: TaskSession(t),
        settings: settings,
        follow: queue,
        translator: () => translator,
      );
      final running = c.translateMissing();
      await Future<void>.delayed(Duration.zero);
      t.status = TaskStatus.running;
      queue.value++;
      final pipeline = t.document;
      translator.gate.complete();
      expect(await running, 0);
      expect(identical(t.document, pipeline), isTrue);
      // 一条没写回，不算编辑。
      expect(t.unsyncedEdits, 0);
      expect(t.editorEdits, 0);
      c.dispose();
    });

    test('重新翻译此条：等译文时文档被换掉，结果不要了', () async {
      final t = task(status: TaskStatus.paused);
      final translator = _GatedTranslator();
      final c = EditorController(
        session: TaskSession(t),
        settings: settings,
        follow: queue,
        translator: () => translator,
      );
      final running = c.retranslate(0);
      await Future<void>.delayed(Duration.zero);
      t.document = t.document.copyWith(
        cues: [
          t.document.cues.first.copyWith(source: '别的'),
          ...t.document.cues.skip(1),
        ],
      );
      queue.value++;
      translator.gate.complete();
      await running;
      expect(t.document.cues.first.translation, 'First');
      c.dispose();
    });
  });

  group('成组写入', () {
    test('改名阶段失败：删掉这次新建的，原有文件保持完整', () async {
      final a = '${dir.path}${sep}a.srt';
      final b = '${dir.path}${sep}b.srt';
      final c = '${dir.path}${sep}c.srt';
      await File(c).writeAsString('旧的');
      // b 是一个非空目录，文件改名盖不过去。
      await File('$b${sep}x').create(recursive: true);

      await expectLater(
        writeFilesAtomically({a: 'A', c: 'C', b: 'B'}),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(a).exists(), isFalse);
      expect(await File(c).readAsString(), 'C');
      expect(await File('$b.tmp').exists(), isFalse);
    });

    test('改名阶段失败：已换成新内容的产物重新记时间戳，下次保存不误报冲突', () async {
      final t = task();
      final zh = '${dir.path}${sep}demo.zh.srt';
      final en = '${dir.path}${sep}demo.en.srt';
      await SubtitleOutputWriter.write(t);
      // 译文产物被一个非空目录占了，改名盖不过去；原文先改名成功。
      await File(en).delete();
      await File('$en${sep}x').create(recursive: true);
      t.document = t.document.copyWith(
        cues: [
          t.document.cues.first.copyWith(source: '新的'),
          ...t.document.cues.skip(1),
        ],
      );
      // 让修改时间看得出差别。
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await expectLater(SubtitleOutputWriter.write(t), throwsA(anything));
      expect(await File(zh).readAsString(), contains('新的'));
      final changes = await TaskSession(t).externalChanges();
      expect(changes.map((c) => c.path), isNot(contains(zh)));
    });

    test('本地会话改名阶段失败：原文重新记时间戳', () async {
      final zh = '${dir.path}${sep}ep.zh.srt';
      final en = '${dir.path}${sep}ep.en.srt';
      await File(zh).writeAsString(_zh);
      await File(en).writeAsString(_zh.replaceAll('大家好', 'Hello'));
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zh),
        translation: await LocalSubtitleFile.load(en),
        defaults: testOptions(),
      );
      await s.captureStamps();
      await File(en).delete();
      await File('$en${sep}x').create(recursive: true);
      s.document = s.document.replaceAt(
        0,
        s.document.cues.first.copyWith(source: '新的'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await expectLater(s.save(), throwsA(anything));
      expect(await File(zh).readAsString(), contains('新的'));
      final changes = await s.externalChanges();
      expect(changes.map((c) => c.path), isNot(contains(zh)));
    });
  });

  group('续跑提醒', () {
    test('改过的任务从断句及之前的阶段续跑才提醒', () {
      final t = task(status: TaskStatus.failed)..editorEdits = 2;
      t.stages[TaskStage.segment] = const StageRecord(state: StageState.failed);
      expect(t.resumeOverwritesEdits, isTrue);

      t.stages[TaskStage.segment] = const StageRecord(state: StageState.done);
      t.stages[TaskStage.translate] = const StageRecord(
        state: StageState.failed,
      );
      for (final s in [
        TaskStage.queued,
        TaskStage.prepare,
        TaskStage.recognize,
      ]) {
        t.stages[s] = const StageRecord(state: StageState.done);
      }
      expect(t.resumeStage, TaskStage.translate);
      expect(t.resumeOverwritesEdits, isFalse);

      t.editorEdits = 0;
      t.stages[TaskStage.segment] = const StageRecord(state: StageState.failed);
      expect(t.resumeOverwritesEdits, isFalse);
    });
  });

  group('任务存档', () {
    test('产物时间戳与修改计数随任务 JSON 往返', () {
      final t = task()
        ..outputs = {
          '/a/demo.zh.srt': const FileStamp(size: 10, modifiedMs: 1234),
        }
        ..outputsWrittenAt = DateTime(2026, 9, 18, 14, 2)
        ..unsyncedEdits = 3
        ..editorEdits = 5;
      final back = SubtitleTask.fromJson(
        t.toJson(),
        fallbackOptions: testOptions(),
      );
      expect(back.outputs, t.outputs);
      expect(back.outputsWrittenAt, t.outputsWrittenAt);
      expect(back.unsyncedEdits, 3);
      expect(back.editorEdits, 5);
    });

    test('旧存档没有这些字段时按零处理', () {
      final json = task().toJson()
        ..remove('outputs')
        ..remove('unsyncedEdits');
      final back = SubtitleTask.fromJson(json, fallbackOptions: testOptions());
      expect(back.outputs, isEmpty);
      expect(back.unsyncedEdits, 0);
      // 已完成的旧任务视为有产物，只是不做外部修改比对。
      expect(TaskSession(back).hasOutputs, isTrue);
    });
  });

  group('界面', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(1200, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(body: Center(child: child)),
        ),
      );
    }

    testWidgets('任务会话的 chip 说明两层存储，弹层里能直接写入', (tester) async {
      final c = controllerFor(TaskSession(task()))
        ..select(0)
        ..toggleReviewed();
      var saved = 0;
      await pump(
        tester,
        EditorTitleTrailing(controller: c, onSave: () => saved++),
      );
      await tester.tap(find.text('1 处修改未写入文件'));
      await tester.pumpAndSettle();
      expect(find.text('编辑进度'), findsOneWidget);
      expect(find.text('字幕文件'), findsOneWidget);
      expect(find.text('demo.zh.srt'), findsOneWidget);
      expect(find.text('撤销到上次写入'), findsOneWidget);
      await tester.tap(find.text('写入文件 ⌘S'));
      await tester.pumpAndSettle();
      expect(saved, 1);
    });

    testWidgets('续跑会覆盖修改时先问，「去编辑器」不续跑', (tester) async {
      final t = task(status: TaskStatus.failed)..editorEdits = 3;
      t.stages[TaskStage.segment] = const StageRecord(state: StageState.failed);
      ResumeChoice? choice;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await confirmResume(context, t),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('继续会覆盖编辑器里的修改'), findsOneWidget);
      await tester.tap(find.text('去编辑器'));
      await tester.pumpAndSettle();
      expect(choice, ResumeChoice.openEditor);
    });
  });
}
