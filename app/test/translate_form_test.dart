import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/shared/footer_message.dart';
import 'package:subtitle_studio/features/translate/translate_form.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 可控的解析：每个路径一个 Completer，测试决定什么时候「解析完」。
class GatedFfmpeg extends Ffmpeg {
  final gates = <String, Completer<MediaFileInfo>>{};

  @override
  Future<MediaFileInfo> probeFile(String path) =>
      (gates[path] ??= Completer<MediaFileInfo>()).future;

  void finish(String path, {int cues = 100, bool exists = true}) {
    (gates[path] ??= Completer<MediaFileInfo>()).complete(
      MediaFileInfo(
        path: path,
        sizeBytes: 24576,
        duration: cues == 0 ? null : const Duration(minutes: 48, seconds: 12),
        cueCount: cues,
        exists: exists,
      ),
    );
  }
}

Future<AppSettings> _settings({bool withKey = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  if (withKey) {
    settings.setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
  }
  return settings;
}

Future<(TranslateFormController, GatedFfmpeg)> _form({
  bool withKey = true,
}) async {
  final media = GatedFfmpeg();
  final form = TranslateFormController(
    settings: await _settings(withKey: withKey),
    media: media,
  );
  return (form, media);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('文件列表', () {
    test('先以「解析中」入列，解析完再就绪；解析中不阻断提交', () async {
      final (form, media) = await _form();
      final done = form.add(['/s/a.srt', '/s/b.vtt']);

      expect(
        form.files.map((f) => f.state),
        everyElement(StagedSubtitleState.parsing),
      );
      expect(form.parsingCount, 2);
      expect(form.totalCues, 0);
      expect(form.canStart, isFalse);
      expect(form.footer.error, isFalse);
      expect(form.footer.text, '文件仍在解析，解析完即可开始');

      media.finish('/s/a.srt', cues: 1284);
      await Future<void>.delayed(Duration.zero);
      expect(form.canStart, isTrue);
      expect(form.footer.text, contains('1 个文件仍在解析，可先开始'));

      media.finish('/s/b.vtt', cues: 312);
      await done;
      expect(
        form.files.map((f) => f.state),
        everyElement(StagedSubtitleState.ready),
      );
      expect(form.totalCues, 1596);
      expect(form.footer.text, '将创建 2 个翻译任务，按列表顺序排队');
      expect(form.summary, '2 个文件 · 共 1,596 条 · 自动检测 → 英语 · 将创建 2 个翻译任务');
    });

    test('只收字幕，同一个文件不会重复加进来', () async {
      final (form, media) = await _form();
      final done = form.add([
        '/s/a.srt',
        '/s/a.srt',
        '/v/x.mp4',
        '/d/notes.txt',
      ]);
      media.finish('/s/a.srt');
      await done;
      expect(form.files.map((f) => f.path), ['/s/a.srt']);
    });

    test('解析不出内容的文件留在列表里但不入队、不计入总数', () async {
      final (form, media) = await _form();
      final done = form.add(['/s/ok.srt', '/s/broken.srt']);
      media.finish('/s/ok.srt', cues: 1284);
      media.finish('/s/broken.srt', cues: 0);
      await done;

      expect(form.brokenCount, 1);
      expect(form.totalCues, 1284);
      expect(form.enqueueable.map((f) => f.path), ['/s/ok.srt']);
      expect(form.footer.text, '将创建 1 个翻译任务，加入队列后在任务页查看进度；1 个文件无法解析，将跳过');
      expect(form.submit()!.paths, ['/s/ok.srt']);
    });

    test('全都解析不出时拦住', () async {
      final (form, media) = await _form();
      final done = form.add(['/s/broken.srt']);
      media.finish('/s/broken.srt', cues: 0);
      await done;
      expect(form.canStart, isFalse);
      expect(form.footer.error, isTrue);
      expect(form.footer.text, contains('都解析不出字幕内容'));
    });

    test('解析期间被移除的文件不会再冒出来', () async {
      final (form, media) = await _form();
      final done = form.add(['/s/a.srt']);
      form.remove(form.files.single);
      media.finish('/s/a.srt');
      await done;
      expect(form.files, isEmpty);
      expect(form.footer.text, '先添加字幕文件');
    });
  });

  group('拖放', () {
    test('音视频不算错：记为已忽略，字幕照常入列', () async {
      final (form, media) = await _form();
      form.handleDrop(['/s/a.srt', '/v/x.mp4', '/v/x.mp4', '/v/y.mov']);
      media.finish('/s/a.srt');
      await Future<void>.delayed(Duration.zero);

      expect(form.dropError, isNull);
      expect(form.ignoredMedia, ['/v/x.mp4', '/v/y.mov']);
      expect(form.ignoredNote, '已忽略 2 个音视频文件，音视频请用「新建转写」');
      expect(form.files.map((f) => f.path), ['/s/a.srt']);
      expect(form.canStart, isTrue);
    });

    test('「改用新建转写」交出音视频并清掉说明', () async {
      final (form, _) = await _form();
      form.handleDrop(['/v/x.mp4']);
      expect(form.takeIgnoredMedia(), ['/v/x.mp4']);
      expect(form.ignoredMedia, isEmpty);
      expect(form.ignoredNote, isNull);
    });

    test('不认识的格式给一句说明，压过其他文案，清掉后恢复', () async {
      final (form, media) = await _form();
      form.handleDrop(['/s/a.srt', '/d/notes.txt', '/d/deck.pdf']);
      media.finish('/s/a.srt');
      await Future<void>.delayed(Duration.zero);

      expect(form.dropError, '不认识的格式：txt、pdf');
      expect(form.footer.error, isTrue);
      expect(form.footer.text, form.dropError);

      form.clearDropError();
      expect(form.footer.error, isFalse);
      expect(form.footer.text, startsWith('将创建 1 个翻译任务'));
    });

    test('清空把文件、忽略记录与说明一起清掉', () async {
      final (form, _) = await _form();
      form.handleDrop(['/s/a.srt', '/v/x.mp4', '/d/notes.txt']);
      form.clear();
      expect(form.files, isEmpty);
      expect(form.ignoredMedia, isEmpty);
      expect(form.dropError, isNull);
    });
  });

  group('语言对', () {
    test('原文为自动检测时不能对换', () async {
      final (form, _) = await _form();
      expect(form.options.sourceLanguage.isAuto, isTrue);
      expect(form.canSwapLanguages, isFalse);
      final before = form.direction;
      form.swapLanguages();
      expect(form.direction, before);
    });

    test('指定原文后可以对换', () async {
      final (form, _) = await _form();
      form.update((o) => o.copyWith(sourceLanguage: Languages.resolve('zh')));
      expect(form.canSwapLanguages, isTrue);
      form.swapLanguages();
      expect(form.options.sourceLanguage.code, 'en');
      expect(form.options.targetLanguage.code, 'zh');
    });
  });

  group('条数与调用次数', () {
    test('按每批条数向上取整，调批次大小时跟着变', () async {
      final (form, media) = await _form();
      expect(form.batchCount, 0);
      expect(form.applyNote, '参数统一应用到每个文件；单个失败不影响其余');

      final done = form.add(['/s/a.srt']);
      media.finish('/s/a.srt', cues: 1596);
      await done;
      expect(form.batchCount, 80);
      expect(
        form.applyNote,
        '参数统一应用到每个文件；共 1,596 条，每批 20 条，约 80 次调用；单个失败不影响其余',
      );

      form.update((o) => o.copyWith(translationBatchSize: 50));
      expect(form.batchCount, 32);
    });
  });

  group('产物与摘要', () {
    test('仅译文只带目标语言；双语带两种，自动检测写 src', () async {
      final (form, _) = await _form();
      expect(form.outputNameExample, '原文件名.en.srt');
      form.update((o) => o.copyWith(bilingual: BilingualLayout.targetAbove));
      expect(form.outputNameExample, '原文件名.src-en.srt');
      form.update((o) => o.copyWith(sourceLanguage: Languages.resolve('zh')));
      expect(form.outputNameExample, '原文件名.zh-en.srt');
    });

    test('纯文本让双语回落到仅译文，摘要与文件名都跟着回落', () async {
      final (form, _) = await _form();
      form.update(
        (o) => o.copyWith(
          bilingual: BilingualLayout.targetAbove,
          format: SubtitleFormat.txt,
        ),
      );
      expect(form.outputNameExample, '原文件名.en.txt');
      expect(form.advancedSummary, '仅译文 · 15 / 40 字 · TXT · 与源文件同目录');
    });
  });

  group('就绪与上次参数', () {
    test('服务没配密钥时拦住，并说去哪儿填', () async {
      final (form, media) = await _form(withKey: false);
      final done = form.add(['/s/a.srt']);
      media.finish('/s/a.srt');
      await done;
      expect(form.readiness.isBlocked, isTrue);
      expect(form.canStart, isFalse);
      expect(form.footer.error, isTrue);
      expect(form.footer.text, contains('密钥'));
      expect(form.submit(), isNull);
      expect(form.settings.lastTranslateOptions, isNull);
    });

    test('提交时记下参数，下次可整份填回；与转写的存档互不影响', () async {
      final settings = await _settings();
      final media = GatedFfmpeg();
      final form = TranslateFormController(settings: settings, media: media);
      expect(form.hasLastUsed, isFalse);
      expect(form.applyLastUsed(), isFalse);

      final done = form.add(['/s/a.srt']);
      media.finish('/s/a.srt');
      await done;
      form.update(
        (o) => o.copyWith(
          translationBatchSize: 40,
          translationGuidance: 'X=Y',
          bilingual: BilingualLayout.targetBelow,
        ),
      );
      expect(form.submit(), isNotNull);
      expect(settings.lastTranscribeOptions, isNull);

      final again = TranslateFormController(settings: settings, media: media);
      expect(again.options.translationBatchSize, 20);
      expect(again.hasLastUsed, isTrue);
      expect(again.applyLastUsed(), isTrue);
      expect(again.options.translationBatchSize, 40);
      expect(again.options.translationGuidance, 'X=Y');
      expect(again.options.bilingual, BilingualLayout.targetBelow);

      again.reset();
      expect(again.options.translationBatchSize, 20);
      expect(again.options.translationGuidance, '');
    });
  });
}
