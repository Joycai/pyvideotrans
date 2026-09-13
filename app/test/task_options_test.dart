import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

Future<AppSettings> freshSettings() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettings.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _jsonTests();

  late Directory work;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('subtitle_studio_options');
  });
  tearDown(() => work.deleteSync(recursive: true));

  group('默认参数', () {
    test('从设置生成，语言按代码解析', () async {
      final s = await freshSettings()
        ..sourceLanguage = 'zh'
        ..targetLanguage = '英文';
      final o = s.defaultTaskOptions();
      expect(o.sourceLanguage.code, 'zh');
      expect(o.targetLanguage.code, 'en');
      expect(o.cjkLineLength, 15);
      expect(o.latinLineLength, 40);
      expect(o.format, SubtitleFormat.srt);
    });

    test('没设过输出目录就是「与源文件同目录」', () async {
      final s = await freshSettings();
      expect(
        s.defaultTaskOptions().outputLocation,
        OutputLocation.besideSource,
      );
      s.outputDir = work.path;
      expect(s.defaultTaskOptions().outputLocation, OutputLocation.custom);
    });

    test('单行字数被限制在合理区间', () async {
      final s = await freshSettings()
        ..cjkLineLength = 999;
      expect(s.cjkLineLength, lessThanOrEqualTo(60));
    });

    test('按源语言与目标语言各取各的折行上限', () {
      final o = testOptions(source: 'zh', target: 'en');
      expect(o.sourceLineLength, 15);
      expect(o.targetLineLength, 40);
    });

    test('copyWith 传 null 可以明确清掉可选模型与输出目录', () {
      final o = testOptions(
        asrModel: 'whisper-1',
        translationModel: 'gpt-test',
        outputDir: '/tmp/out',
      );
      final cleared = o.copyWith(
        asrModel: null,
        translationModel: null,
        outputDir: null,
      );
      expect(cleared.asrModel, isNull);
      expect(cleared.translationModel, isNull);
      expect(cleared.outputDir, isNull);
    });
  });

  group('入队', () {
    late TaskQueue queue;

    setUp(() async {
      final settings = await freshSettings();
      queue = TaskQueue(
        runner: TaskRunner(settings: settings, workDir: work.path),
        settings: settings,
      );
    });

    test('字幕文件只能翻译，哪怕参数说要转写', () {
      final task = queue.enqueue(
        sourcePath: '/v/a.srt',
        options: testOptions(translate: false),
      );
      expect(task.kind, TaskKind.translate);
    });

    test('音视频按「是否继续翻译」决定任务类型', () {
      expect(
        queue.enqueue(sourcePath: '/v/a.mp4', options: testOptions()).kind,
        TaskKind.transcribeAndTranslate,
      );
      expect(
        queue
            .enqueue(
              sourcePath: '/v/b.mp4',
              options: testOptions(translate: false),
            )
            .kind,
        TaskKind.transcribe,
      );
    });

    test('一批文件共用同一份参数', () {
      final tasks = queue.enqueueAll([
        '/v/a.mp4',
        '/v/b.mov',
      ], options: testOptions(source: 'ja'));
      expect(tasks, hasLength(2));
      expect(tasks.every((t) => t.sourceLanguage.code == 'ja'), isTrue);
    });

    // 任务串行跑，排队期间改设置不该影响已经排上的任务。
    test('参数在入队时定死，之后改设置不影响它', () async {
      final settings = await freshSettings()
        ..translationBatchSize = 8;
      final q = TaskQueue(
        runner: TaskRunner(settings: settings, workDir: work.path),
        settings: settings,
      );
      final task = q.enqueue(sourcePath: '/v/a.mp4');
      settings.translationBatchSize = 50;
      expect(task.options.translationBatchSize, 8);
    });
  });

  group('产物', () {
    Future<SubtitleTask> taskWith(TaskOptions options) async {
      final srt = File('${work.path}/in.srt')
        ..writeAsStringSync(
          Srt.serialize([
            const Cue(
              index: 1,
              startMs: 0,
              endMs: 2000,
              source: '这是一句足够长的中文原文，用来验证导出时会按上限折行。',
              translation: 'A line',
            ),
          ]),
        );
      final task = SubtitleTask(
        id: 'o1',
        sourcePath: srt.path,
        kind: TaskKind.transcribeAndTranslate,
        options: options,
      );
      task.document = SubtitleDocument(cues: Srt.parse(srt.readAsStringSync()));
      task.document = task.document.copyWith(
        cues: [
          task.document.cues.first.copyWith(translation: 'A translated line'),
        ],
      );
      return task;
    }

    Future<List<String>> write(TaskOptions options) async {
      final settings = await freshSettings();
      final runner = TaskRunner(settings: settings, workDir: work.path);
      return runner.writeOutputs(await taskWith(options));
    }

    test('文件名带语言代码而不是中文名', () async {
      final out = await write(testOptions(source: 'zh', target: 'en'));
      expect(out.map((p) => p.split('/').last), ['in.zh.srt', 'in.en.srt']);
    });

    test('自动检测的源语言写成 src', () async {
      final out = await write(testOptions(source: 'auto'));
      expect(out.first, endsWith('in.src.srt'));
    });

    test('导出时按单行上限折行，文档本身不动', () async {
      final task = await taskWith(testOptions(cjkLineLength: 10));
      final settings = await freshSettings();
      final runner = TaskRunner(settings: settings, workDir: work.path);
      final out = await runner.writeOutputs(task);

      final content = File(out.first).readAsStringSync();
      expect(content, contains('\n'));
      expect(Srt.parse(content).first.source, contains('\n'));
      // 文档里存的仍然是不带硬换行的干净文本。
      expect(task.document.cues.first.source, isNot(contains('\n')));
    });

    test('VTT 带文件头，时间码用小数点', () async {
      final out = await write(testOptions(format: SubtitleFormat.vtt));
      final content = File(out.first).readAsStringSync();
      expect(out.first, endsWith('.vtt'));
      expect(content, startsWith('WEBVTT'));
      expect(content, contains('00:00:00.000 --> '));
    });

    test('纯文本只有文字，没有时间码', () async {
      final out = await write(testOptions(format: SubtitleFormat.txt));
      final content = File(out.first).readAsStringSync();
      expect(content, isNot(contains('-->')));
      expect(content.trim(), isNotEmpty);
    });

    test('ASS 尚未实施，报错说清楚原因', () async {
      Object? caught;
      try {
        await write(testOptions(format: SubtitleFormat.ass));
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ProviderException>());
      expect((caught! as ProviderException).message, contains('ASS'));
      expect((caught as ProviderException).hint, contains('第二期'));
    });

    test('指定目录不存在时自动建出来', () async {
      final dir = '${work.path}/nested/out';
      final out = await write(
        testOptions(outputLocation: OutputLocation.custom, outputDir: dir),
      );
      expect(out.first, startsWith(dir));
      expect(Directory(dir).existsSync(), isTrue);
    });
  });

  group('双语排版', () {
    test('三档各自对应一路文本', () {
      expect(BilingualLayout.targetOnly.field, SrtField.translation);
      expect(BilingualLayout.targetAbove.field, SrtField.bilingualTargetAbove);
      expect(BilingualLayout.targetBelow.field, SrtField.bilingualTargetBelow);
      expect(BilingualLayout.targetOnly.isBilingual, isFalse);
      expect(BilingualLayout.targetAbove.isBilingual, isTrue);
    });

    test('纯文本把双语抹平成仅译文', () {
      final opts = testOptions(bilingual: BilingualLayout.targetBelow);
      expect(opts.resolvedBilingual, BilingualLayout.targetBelow);
      expect(
        opts.copyWith(format: SubtitleFormat.txt).resolvedBilingual,
        BilingualLayout.targetOnly,
      );
    });

    // 存盘用的是枚举名，认不出来的值（旧版本写的、手改坏的）回落到默认。
    test('读不认识的值回落到仅译文', () {
      expect(
        BilingualLayout.byName('targetAbove'),
        BilingualLayout.targetAbove,
      );
      expect(BilingualLayout.byName('乱写'), BilingualLayout.targetOnly);
    });

    test('设置里存得住，并带进默认参数', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.bilingual, BilingualLayout.targetOnly);

      settings.bilingual = BilingualLayout.targetAbove;
      expect(
        (await AppSettings.load()).defaultTaskOptions().bilingual,
        BilingualLayout.targetAbove,
      );
    });
  });
}

// ——— 持久化 ————————————————————————————————————————————————
void _jsonTests() {
  group('JSON', () {
    test('来回一致', () async {
      final s = await freshSettings();
      final o = s.defaultTaskOptions().copyWith(
        asrModel: 'whisper-1',
        asrPrompt: '专有名词',
        diarize: true,
        translate: false,
        translationBatchSize: 7,
        bilingual: BilingualLayout.targetAbove,
        cjkLineLength: 20,
        format: SubtitleFormat.vtt,
        outputLocation: OutputLocation.custom,
        outputDir: '/out',
      );
      final back = TaskOptions.fromJson(
        o.toJson(),
        fallback: s.defaultTaskOptions(),
      );
      expect(back.toJson(), o.toJson());
      expect(back.sourceLanguage.code, o.sourceLanguage.code);
      expect(back.format, SubtitleFormat.vtt);
      expect(back.outputDir, '/out');
      expect(back.diarize, isTrue);
      // 旧存档没有这个字段：回落到默认的关。
      expect(
        TaskOptions.fromJson({}, fallback: s.defaultTaskOptions()).diarize,
        isFalse,
      );
    });

    test('缺字段与坏类型回落到默认，指定目录却没目录则回到同目录', () async {
      final s = await freshSettings();
      final fallback = s.defaultTaskOptions();
      final o = TaskOptions.fromJson({
        'translationBatchSize': 'many',
        'cjkLineLength': 999,
        'format': 'ass',
        'outputLocation': 'custom',
      }, fallback: fallback);
      expect(o.translationBatchSize, fallback.translationBatchSize);
      expect(o.cjkLineLength, 60);
      expect(o.format, SubtitleFormat.ass);
      expect(o.outputLocation, OutputLocation.besideSource);
      expect(o.outputDir, isNull);
    });

    test('设置里的「上次参数」坏了就当没有', () async {
      final s = await freshSettings();
      expect(s.lastTranscribeOptions, isNull);
      s.lastTranscribeOptions = s.defaultTaskOptions().copyWith(
        translate: false,
      );
      expect(s.lastTranscribeOptions!.translate, isFalse);
      s.lastTranscribeOptions = null;
      expect(s.lastTranscribeOptions, isNull);
    });
  });
}
