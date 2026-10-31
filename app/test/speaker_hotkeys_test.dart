import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/speaker_hotkeys.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/editor_shortcuts.dart';
import 'package:subtitle_studio/features/editor/speaker_hotkey_bar.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';
import 'helpers.dart';

Future<EditorController> controller({
  EditorSession? session,
  EditorStore? store,
}) async {
  SharedPreferences.setMockInitialValues({});
  return EditorController(
    session: session ?? localSession(),
    settings: await AppSettings.load(),
    store: store,
  );
}

void main() {
  test('旧存档与不合法按键安全兼容，任务映射 JSON 往返', () {
    expect(readSpeakerHotkeys(null), isEmpty);
    expect(
      readSpeakerHotkeys({'j': 1, 'A': 2, 'ab': 0, 'a': 2, 'b': null, 'c': -1}),
      {'a': 2, 'b': null, 'c': -1},
    );
    final task = SubtitleTask(
      id: 'hotkeys',
      sourcePath: '/tmp/a.mp4',
      kind: TaskKind.transcribe,
      options: testOptions(),
      speakerHotkeys: {'a': 2, 'b': null, 'c': -1},
    );
    expect(
      SubtitleTask.fromJson(
        task.toJson(),
        fallbackOptions: testOptions(),
      ).speakerHotkeys,
      task.speakerHotkeys,
    );
    final old = task.toJson()..remove('speakerHotkeys');
    expect(
      SubtitleTask.fromJson(old, fallbackOptions: testOptions()).speakerHotkeys,
      isEmpty,
    );
  });

  test('配置不增加字幕修改；不连续选区一次分配，可撤销重做与清除', () async {
    final c = await controller();
    addTearDown(c.dispose);
    c.setSpeakerHotkeys({'a': 1, 'b': null});
    expect(c.unsavedEdits, 0);
    expect(c.canUndo, isFalse);
    c.selectWith(0);
    c.selectWith(6, toggle: true);
    final before = c.document;
    expect(c.assignHotkey('a'), 2);
    expect(c.document.cues[0].speaker, 1);
    expect(c.document.cues[6].speaker, 1);
    expect(c.document.cues[1], same(before.cues[1]));
    c.undo();
    expect(c.document, same(before));
    c.redo();
    expect(c.document.cues[6].speaker, 1);
    expect(c.assignHotkey('b'), 2);
    expect(c.document.cues[0].speaker, isNull);
  });

  test('映射跟随重命名，合并后失效，不因编号重用而改绑', () async {
    final c = await controller();
    addTearDown(c.dispose);
    final id = c.addSpeaker('临时人物');
    c.setSpeakerHotkeys({'a': id});
    c.renameSpeaker(id, '新名称');
    expect(hotkeyTargetLabel(c, c.speakerHotkeys['a']), '新名称');
    c.mergeSpeaker(id, 0);
    expect(c.speakerHotkeys['a'], -1);
    c.addSpeaker('另一个人');
    expect(c.canAssignHotkey('a'), isFalse);
    expect(c.assignHotkey('a'), 0);
  });

  test('运行中的任务不可分配或修改配置', () async {
    final task = SubtitleTask(
      id: 'busy',
      sourcePath: '/tmp/a.mp4',
      kind: TaskKind.transcribe,
      options: testOptions(),
      document: localSession().document,
      speakerHotkeys: {'a': 1},
    );
    final c = await controller(session: TaskSession(task));
    addTearDown(c.dispose);
    final before = c.document;
    expect(c.assignHotkey('a'), 0);
    c.setSpeakerHotkeys({'b': 0});
    expect(c.speakerHotkeys, {'a': 1});
    expect(c.document, same(before));
  });

  test('本地会话仅配置也能写盘恢复，字幕内容不改动', () async {
    final dir = await Directory.systemTemp.createTemp('hotkeys');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/input.srt');
    await file.writeAsString(localZhSrt);
    final session = localSession()..sourcePath = file.path;
    session.translationPath = null;
    await session.captureStamps();
    final store = EditorStore('${dir.path}/state');
    final c = await controller(session: session, store: store);
    addTearDown(c.dispose);
    c.setSpeakerHotkeys({'a': 1, 'b': null});
    await c.flushDraft();
    final state = await store.loadFileDraft(file.path, null);
    expect(state!.speakerHotkeys, {'a': 1, 'b': null});
    expect(state.pendingEdits, 0);
    expect(state.draft, isNull);
    expect(await file.readAsString(), localZhSrt);
  });

  test('筛选后只分配可见选区，空结果不修改隐藏字幕', () async {
    final c = await controller();
    addTearDown(c.dispose);
    c.setSpeakerHotkeys({'a': 1});
    c.selectWith(2);
    c.selectWith(0, extend: true);
    c.setSpeakerFilter({0});
    final before = c.document;
    expect(c.assignHotkey('a'), 2);
    expect(c.document.cues[2], same(before.cues[2]));
    c.setSearch('不存在的字幕内容');
    final filtered = c.document;
    expect(c.assignHotkey('a'), 0);
    expect(c.document, same(filtered));
  });

  testWidgets('窄窗口深色长名称与大量映射不溢出', (tester) async {
    tester.view.physicalSize = const Size(600, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await controller();
    final focus = FocusNode();
    addTearDown(c.dispose);
    addTearDown(focus.dispose);
    c.renameSpeaker(0, '这是一位名字特别长的说话人，用于验证省略与完整提示');
    c.setSpeakerHotkeys({
      for (final key in speakerHotkeyLetters.split('')) key: 0,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: SpeakerHotkeyBar(controller: c, tableFocus: focus),
        ),
      ),
    );
    await tester.tap(find.text('配置…'));
    await tester.pumpAndSettle();
    expect(find.text('应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('字母键只在字幕表触发，输入框与配置弹窗不触发', (tester) async {
    final c = await controller();
    final focus = FocusNode();
    addTearDown(c.dispose);
    addTearDown(focus.dispose);
    c.setSpeakerHotkeys({'a': 1});
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              children: [
                SpeakerHotkeyBar(controller: c, tableFocus: focus),
                const TextField(),
                Expanded(
                  child: CueTableShortcuts(
                    controller: c,
                    focusNode: focus,
                    child: const Text('字幕表'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(c.document.cues[0].speaker, 1);
    c.undo();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(c.document.cues[0].speaker, 0);
    await tester.tap(find.text('配置…'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(c.document.cues[0].speaker, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认空槽可搜索配置；取消不写入，应用保存', (tester) async {
    final c = await controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SpeakerHotkeyDialog(controller: c),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择说话人').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '周老师');
    await tester.pumpAndSettle();
    await tester.tap(find.text('周老师 · 编号 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.speakerHotkeys, isEmpty);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择说话人').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除说话人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(c.speakerHotkeys, {'a': null});
    expect(c.unsavedEdits, 0);
    expect(tester.takeException(), isNull);
  });
}
