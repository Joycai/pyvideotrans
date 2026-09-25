import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/subtitle_pairing.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_leave_dialog.dart';
import 'package:subtitle_studio/features/editor/editor_open_form.dart';
import 'package:subtitle_studio/features/editor/editor_page.dart';
import 'package:subtitle_studio/features/editor/editor_page_actions.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/editor_widgets.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';
import 'helpers.dart';

Future<EditorController> _controller({bool withTranslation = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  return EditorController(
    session: localSession(withTranslation: withTranslation),
    settings: settings,
  );
}

Future<void> _pump(WidgetTester tester, EditorController controller) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: 1332,
          height: 800,
          child: EditorPage(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('本地会话的编辑页', () {
    testWidgets('说话人列：同一人连续只显示一次，未配对行写明没有原文', (tester) async {
      final c = await _controller();
      await _pump(tester, c);
      expect(find.text('— 没有对应的原文'), findsOneWidget);
      // 周老师的四段连续发言，各只在第一条显示一次名字。
      expect(find.text('周老师'), findsNWidgets(4));
      expect(find.text('说话人'), findsWidgets);
      expect(find.text('结束'), findsWidgets); // 检视面板里的时间码标签
      // 没有配套视频：只预览字幕样式，并给出手动关联的入口。
      expect(find.text('未关联视频 · 只预览字幕样式'), findsOneWidget);
      expect(find.text('关联视频…'), findsOneWidget);
    });

    testWidgets('说话人筛选：多选，chip 文案跟着变', (tester) async {
      final c = await _controller();
      await _pump(tester, c);
      await tester.tap(find.text('说话人 · 全部'));
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byType(GlassMenu), matching: find.text('Mia')),
      );
      await tester.pump();
      final mia = c.speakers.firstWhere((s) => s.name == 'Mia').id;
      expect(c.speakerFilter, {mia});
      expect(find.text('说话人 · Mia'), findsOneWidget);
    });

    testWidgets('数字键把当前条改给名单里的第 N 位', (tester) async {
      final c = await _controller();
      await _pump(tester, c);
      await tester.pump();
      c.select(0);
      final third = c.speakers[2];
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      expect(c.document.cues.first.speaker, third.id);
    });

    testWidgets('只挂原文：译文表头给出挂载入口，检视面板是空态', (tester) async {
      final c = await _controller(withTranslation: false);
      await _pump(tester, c);
      expect(find.text('+ 挂载译文…'), findsNothing); // 没传回调就不显示
      expect(find.text('这份字幕还没有译文'), findsOneWidget);
      expect(find.text('未翻译'), findsNothing);
    });

    testWidgets('窄于 1100：说话人列只留徽标，视图切换收进下拉', (tester) async {
      final c = await _controller();
      tester.view
        ..physicalSize = const Size(1080, 760)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                children: [
                  EditorPageActions(
                    controller: c,
                    onTranslateMissing: () {},
                    onExport: () {},
                    onSave: () {},
                  ),
                  Expanded(child: EditorPage(controller: c)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('周老师'), findsNothing);
      expect(find.text('双语'), findsNothing);
      expect(find.text('说话人 · 全部'), findsNothing);
      expect(find.byTooltip('说话人 · 全部'), findsOneWidget);
      // 数量为 0 的筛选 chip 藏起来，有数量的照常显示。
      expect(c.countOf(CueFilter.review), 0);
      expect(find.text('待校对'), findsNothing);
      expect(find.text('未配对'), findsWidgets);
      await tester.tap(find.text('视图 · 双语'));
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byType(GlassMenu), matching: find.text('译文')),
      );
      await tester.pump();
      expect(c.view, CueView.translation);
      expect(find.text('视图 · 译文'), findsOneWidget);
    });

    testWidgets('未配对行被选中时，原文框换成并入按钮', (tester) async {
      final c = await _controller();
      c.select(c.document.cues.indexWhere((x) => x.source.isEmpty));
      await _pump(tester, c);
      expect(find.text('这一条译文找不到对应的原文'), findsOneWidget);
      await tester.tap(find.text('并入上一条'));
      await tester.pump();
      expect(c.document.unpairedCount, 0);
    });
  });

  group('离开编辑器前的询问', () {
    Future<bool?> ask(
      WidgetTester tester,
      EditorController c,
      String button,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await confirmLeaveEditor(context, c),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('先写入字幕文件？'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('没有修改时不问', (tester) async {
      final c = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  expect(await confirmLeaveEditor(context, c), isTrue),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('先写入字幕文件？'), findsNothing);
    });

    testWidgets('「稍后再写」可以继续，「取消」不行', (tester) async {
      final c = await _controller()
        ..select(0)
        ..toggleReviewed();
      expect(await ask(tester, c, '稍后再写'), isTrue);
      expect(await ask(tester, c, '取消'), isFalse);
      // 两个选项都不动字幕文件：修改还在，等下次写入。
      expect(c.unsavedEdits, 1);
    });
  });

  group('入口页表单', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('open_form'));
    tearDown(() => dir.delete(recursive: true));

    EditorOpenForm form() => EditorOpenForm(
      defaults: () => testOptions(source: 'zh', target: 'en'),
    );

    test('一次拖两个文件，按文件名里的语言段分配', () async {
      final zh = File('${dir.path}/ep.zh.srt')..writeAsStringSync(localZhSrt);
      final en = File('${dir.path}/ep.en.srt')..writeAsStringSync(localEnSrt);
      final f = form();
      await f.handleDrop([en.path, zh.path, '${dir.path}/movie.mp4']);
      expect(f.source?.path, zh.path);
      expect(f.translation?.path, en.path);
      expect(f.footer.text, contains('写回这 2 个文件'));
      expect(f.speakerLabels, ['Mia', '周老师', '说话人3']);
    });

    test('读不了的文件记下错误，位置不变', () async {
      final bad = File('${dir.path}/bad.srt')
        ..writeAsStringSync('nothing here');
      final f = form();
      await f.load(OpenSlot.source, bad.path);
      expect(f.source, isNull);
      expect(f.error(OpenSlot.source), contains('解析不出字幕内容'));
      expect(f.canOpen, isFalse);
      expect(f.footer.text, '先添加原文字幕');
    });

    test('时间轴对不上时不能打开，切到按序号后可以', () {
      final shifted = localEnSrt.replaceAllMapped(
        RegExp(r'00:00:(\d\d)'),
        (m) => '00:10:${m[1]}',
      );
      final f = form()
        ..setFile(OpenSlot.source, localZhFile())
        ..setFile(
          OpenSlot.translation,
          LocalSubtitleFile.parse('/x/far.en.srt', shifted),
        );
      expect(f.pairing!.plausible, isFalse);
      expect(f.canOpen, isFalse);
      expect(f.footer.error, isTrue);
      f.setMode(PairingMode.byIndex);
      expect(f.canOpen, isTrue);
    });

    test('配对预览与打开后的文档一致；关掉标签时文本里保留标签', () {
      final f = form()
        ..setFile(OpenSlot.source, localZhFile())
        ..setFile(OpenSlot.translation, localEnFile());
      expect(f.pairing!.translationOnly, 1);
      expect(f.pairingNote, isNotNull);
      final session = f.build();
      expect(session.document.cues.length, f.cueCount);
      expect(session.document.speakers.values, containsAll(['Mia', '周老师']));

      f.setReadSpeakerLabels(false);
      expect(f.pairing!.cues.first.source, startsWith('Mia：'));
      expect(f.build().document.hasSpeakers, isFalse);
    });

    test('对换原文与译文，语言跟着换', () {
      final f = form()
        ..setFile(OpenSlot.source, localZhFile())
        ..setFile(OpenSlot.translation, localEnFile());
      expect(f.language(OpenSlot.source).code, 'zh');
      expect(f.languageGuessed(OpenSlot.source), isTrue);
      f.swap();
      expect(f.source!.fileName, 'interview_ep12.en.srt');
      expect(f.language(OpenSlot.source).code, 'en');
    });
  });
}
