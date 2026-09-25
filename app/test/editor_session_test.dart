import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/subtitle_pairing.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

const _zh = '''1
00:00:00,000 --> 00:00:02,000
Mia：大家好

2
00:00:02,000 --> 00:00:04,000
周老师：谢谢邀请

3
00:00:04,000 --> 00:00:06,000
Mia：好，我们继续
''';

const _en = '''1
00:00:00,000 --> 00:00:02,000
Hello everyone

2
00:00:02,100 --> 00:00:03,000
Thanks

3
00:00:03,000 --> 00:00:04,000
for having me

4
00:00:07,000 --> 00:00:08,000
Right.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String sep;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('editor_session_test');
    sep = Platform.pathSeparator;
  });

  tearDown(() => dir.delete(recursive: true));

  Future<String> file(String name, String content) async {
    final path = '${dir.path}$sep$name';
    await File(path).writeAsString(content);
    return path;
  }

  group('读本地字幕', () {
    test('解析、识别说话人标签、从文件名认语言', () async {
      final f = await LocalSubtitleFile.load(await file('ep12.zh.srt', _zh));
      expect(f.cues, hasLength(3));
      expect(f.speakerLabels!.labels, ['Mia', '周老师']);
      expect(f.language?.code, 'zh');
      expect(f.fileName, 'ep12.zh.srt');
    });

    test('文件名认不出时按文字猜', () {
      final f = LocalSubtitleFile.parse('/x/notes.srt', _en);
      expect(f.language?.code, 'en');
      expect(LocalSubtitleFile.parse('/x/a.srt', _zh).language?.code, 'zh');
    });

    test('解析不出字幕时抛 FormatException', () {
      expect(
        () => LocalSubtitleFile.parse('/x/empty.srt', 'not a subtitle'),
        throwsFormatException,
      );
    });
  });

  group('打开本地会话', () {
    Future<(LocalSubtitleFile, LocalSubtitleFile)> pair() async => (
      await LocalSubtitleFile.load(await file('ep12.zh.srt', _zh)),
      await LocalSubtitleFile.load(await file('ep12.en.srt', _en)),
    );

    test('原文与译文配对，说话人来自原文标签，语言来自文件名', () async {
      final (zh, en) = await pair();
      final s = FileSession.open(
        source: zh,
        translation: en,
        defaults: testOptions(source: 'auto', target: 'ja'),
      );
      expect(s.sourceLanguage.code, 'zh');
      expect(s.targetLanguage.code, 'en');
      expect(s.pairing!.mode, PairingMode.byTime);
      expect(s.pairing!.mergedTranslations, 1);
      expect(s.pairing!.translationOnly, 1);
      final cues = s.document.cues;
      expect(cues.map((c) => c.source), ['大家好', '谢谢邀请', '好，我们继续', '']);
      expect(cues[1].translation, 'Thanks for having me');
      expect(cues[3].state, CueState.unpaired);
      expect(s.document.speakerName(cues[0].speaker!), 'Mia');
      expect(s.title, 'ep12');
    });

    test('关掉标签识别时标签留在文本里', () async {
      final (zh, _) = await pair();
      final s = FileSession.open(
        source: zh,
        defaults: testOptions(),
        readSpeakerLabels: false,
      );
      expect(s.document.cues.first.source, 'Mia：大家好');
      expect(s.document.hasSpeakers, isFalse);
    });

    test('只挂原文时目标语言回落到设置里的默认值', () async {
      final (zh, _) = await pair();
      final s = FileSession.open(
        source: zh,
        defaults: testOptions(target: 'ja', mt: 'deepseek'),
      );
      expect(s.targetLanguage.code, 'ja');
      expect(s.options.translationProviderId, 'deepseek');
      expect(s.pairing, isNull);
    });
  });

  group('保存', () {
    test('写回两个文件：原文带回说话人标签，译文不加标签，未配对行只进译文', () async {
      final zhPath = await file('ep12.zh.srt', _zh);
      final enPath = await file('ep12.en.srt', _en);
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zhPath),
        translation: await LocalSubtitleFile.load(enPath),
        defaults: testOptions(),
      );
      s.document = s.document.renameSpeaker(1, '周老师（嘉宾）');

      expect(await s.save(), [zhPath, enPath]);
      final zh = await File(zhPath).readAsString();
      expect(zh, contains('周老师（嘉宾）：谢谢邀请'));
      expect(zh, contains('Mia：大家好'));
      expect(zh.split('-->'), hasLength(4));
      final en = await File(enPath).readAsString();
      expect(en, contains('Thanks for having me'));
      expect(en, contains('Right.'));
      expect(en, isNot(contains('Mia')));
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('只挂原文、翻译过之后，译文写到旁边的新文件，不覆盖已有文件', () async {
      final zhPath = await file('ep12.zh.srt', _zh);
      await file('ep12.en.srt', 'someone else');
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zhPath),
        defaults: testOptions(target: 'en'),
      );
      s.document = s.document.replaceAt(
        0,
        s.document.cues.first.copyWith(translation: 'Hello'),
      );
      final written = await s.save();
      expect(written.last, '${dir.path}${sep}ep12-2.en.srt');
      expect(s.translationPath, written.last);
      expect(
        await File('${dir.path}${sep}ep12.en.srt').readAsString(),
        'someone else',
      );
    });

    test('卸载译文后保存不动译文文件，也不再挂着它', () async {
      final zhPath = await file('ep12.zh.srt', _zh);
      final enPath = await file('ep12.en.srt', _en);
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(zhPath),
        translation: await LocalSubtitleFile.load(enPath),
        defaults: testOptions(),
      );
      s.document = s.document.withoutTranslations();
      expect(s.mountedTranslationPath, isNull);
      expect(await s.save(), [zhPath]);
      expect(s.translationPath, isNull);
      expect(await File(enPath).readAsString(), _en);
    });

    test('VTT 按 VTT 写回', () async {
      final path = await file(
        'talk.vtt',
        'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n',
      );
      final s = FileSession.open(
        source: await LocalSubtitleFile.load(path),
        defaults: testOptions(),
      );
      await s.save();
      final text = await File(path).readAsString();
      expect(text, startsWith('WEBVTT'));
      expect(text, contains('00:00:00.000 --> 00:00:01.000'));
    });
  });

  group('控制器：本地会话', () {
    Future<EditorController> controller({EditorStore? store}) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      final zhPath = await file('ep12.zh.srt', _zh);
      final enPath = await file('ep12.en.srt', _en);
      final session = FileSession.open(
        source: await LocalSubtitleFile.load(zhPath),
        translation: await LocalSubtitleFile.load(enPath),
        defaults: settings.defaultTaskOptions(),
      );
      return EditorController(
        session: session,
        settings: settings,
        store: store,
      );
    }

    test('未保存计数：改动累加，撤销回到保存时的版本归零，保存后归零', () async {
      final c = await controller()
        ..select(0);
      expect(c.unsavedEdits, 0);
      c
        ..editSource('大家好呀')
        ..toggleReviewed();
      expect(c.unsavedEdits, 2);
      c
        ..undo()
        ..undo();
      expect(c.unsavedEdits, 0);

      c.editSource('改了');
      await c.save();
      expect(c.unsavedEdits, 0);
      // 保存之后再撤销，文档与存盘的不一样了，要算作未保存。
      c.undo();
      expect(c.unsavedEdits, 1);
    });

    test('任务会话没有未保存的概念', () async {
      final c = await controller();
      expect(c.session, isA<FileSession>());
      final zh = Languages.byCode('zh')!;
      expect(c.session.sourceLanguage, zh);
    });

    test('卸载译文可以撤销', () async {
      final c = await controller();
      c.unmountTranslation();
      expect(c.document.cues, hasLength(3));
      expect(c.document.cues.every((x) => !x.hasTranslation), isTrue);
      c.undo();
      expect(c.document.unpairedCount, 1);
    });

    test('保存时写附加状态，下次打开能恢复已校对标记', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final c = await controller(store: store)
        ..select(0)
        ..toggleReviewed();
      await c.save();
      final s = c.session as FileSession;
      final restored = await store.loadFileState(
        s.sourcePath,
        s.translationPath,
      );
      expect(restored!.cues.first.reviewed, isTrue);
      expect(restored.speakers, s.document.speakers);
    });
  });

  group('EditorStore', () {
    test('文件在别处被改过后附加状态作废', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      final path = await file('a.srt', _zh);
      await store.saveFileState(
        sourcePath: path,
        document: SubtitleDocument.empty,
      );
      expect(await store.loadFileState(path, null), isNotNull);
      expect(await store.loadFileState(path, '/other.srt'), isNull);

      await File(path).writeAsString('$_zh\n');
      expect(await store.loadFileState(path, null), isNull);
    });

    test('最近打开：同一会话挪到最前，超出上限丢掉最旧的', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      RecentSession local(int i) => RecentSession(
        title: 'f$i',
        openedAt: DateTime(2026, 9, 13, 10, i),
        cueCount: i,
        sourcePath: '/s/$i.srt',
      );
      for (var i = 0; i < EditorStore.recentLimit + 2; i++) {
        await store.touchRecent(local(i));
      }
      await store.touchRecent(
        RecentSession(
          title: '任务',
          openedAt: DateTime(2026, 9, 13, 11),
          cueCount: 486,
          speakerCount: 3,
          taskId: 't1',
        ),
      );
      await store.touchRecent(local(5));

      final recents = await store.loadRecents();
      expect(recents, hasLength(EditorStore.recentLimit));
      expect(recents.first.title, 'f5');
      expect(recents[1].isTask, isTrue);
      expect(recents[1].speakerCount, 3);
      expect(recents.where((r) => r.title == 'f5'), hasLength(1));
      expect(recents.map((r) => r.title), isNot(contains('f0')));
    });

    test('存档坏了读成空列表', () async {
      final store = EditorStore('${dir.path}${sep}editor');
      await Directory(store.dir).create(recursive: true);
      await File('${store.dir}${sep}recent.json').writeAsString('{oops');
      expect(await store.loadRecents(), isEmpty);
    });
  });
}
