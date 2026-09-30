import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_control.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
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
      expect(o.minCueMs, 500);
      expect(o.maxCueMs, 10000);
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

    test('字幕时长上下限被限制在合理区间，并带进任务参数', () async {
      final s = await freshSettings()
        ..minCueMs = -5
        ..maxCueMs = 999999;
      expect(s.minCueMs, 0);
      expect(s.maxCueMs, 60000);
      s.maxCueMs = 15000;
      expect(s.defaultTaskOptions().maxCueMs, 15000);
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

    test('copyWith 传 null 可以明确清掉输出目录；模型不给就不变', () {
      final o = testOptions(
        asrModel: 'whisper-1',
        translationModel: 'gpt-test',
        outputDir: '/tmp/out',
      );
      final cleared = o.copyWith(outputDir: null);
      expect(cleared.outputDir, isNull);
      // 模型是整份声明，没有「清掉」这回事：要换就给一份新的。
      expect(cleared.asrModel, o.asrModel);
      expect(cleared.translationModel, o.translationModel);
      expect(
        o.copyWith(translationModel: ChatModelSpec.unset).translationModel,
        ChatModelSpec.unset,
      );
    });

    test('换识别服务：模型换成新服务的默认，新模型分不了说话人就关掉开关', () {
      final dashscope = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      final capable = dashscope.presets.firstWhere(
        (p) => p.capabilities.diarization,
      );
      final o = testOptions(asr: 'openai').copyWith(diarize: true);

      final kept = o.withAsrProvider(dashscope.id, defaultModel: capable);
      expect(kept.asrProviderId, dashscope.id);
      expect(kept.asrModel, same(capable));
      expect(kept.diarize, isTrue);

      // 同一家服务，默认模型是同步逐段的：看的是模型的能力，不是服务。
      final off = o.withAsrProvider(
        dashscope.id,
        defaultModel: dashscope.presets.first,
      );
      expect(off.asrModel, same(dashscope.presets.first));
      expect(off.diarize, isFalse);
    });

    test('换翻译服务：模型换成新服务的默认', () {
      final o = testOptions(mt: 'deepseek', translationModel: 'deepseek-chat');
      final next = o.withTranslationProvider(
        'ollama',
        defaultModel: const ChatModelSpec(name: 'llama3.1'),
      );
      expect(next.translationProviderId, 'ollama');
      expect(next.translationModel.name, 'llama3.1');
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

    // 占位词（以前的 `src`）会被 Jellyfin 当成字幕标题，不如不写。
    test('自动检测的源语言不写语言段', () async {
      final out = await write(testOptions(source: 'auto'));
      // 这里的源文件恰好就是 `in.srt`：不写语言段就与它同名，带序号避让。
      expect(out.first.split('/').last, 'in.2.srt');
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
      expect(caught, isA<ActionableException>());
      expect((caught! as ActionableException).message, contains('ASS'));
      expect((caught as ActionableException).hint, contains('第二期'));
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
      TaskOptions read(String bilingual) => TaskOptions.fromJson({
        'bilingual': bilingual,
      }, fallback: testOptions(bilingual: BilingualLayout.targetBelow));
      expect(read('targetAbove').bilingual, BilingualLayout.targetAbove);
      expect(read(' targetAbove ').bilingual, BilingualLayout.targetAbove);
      expect(read('乱写').bilingual, BilingualLayout.targetOnly);
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
        asrModel: const AsrModelSpec(
          name: 'my-model',
          transport: AsrTransport.dashscopeFileTrans,
          dialect: DashScopeDialect.funAsr,
        ),
        translationModel: const ChatModelSpec(name: 'my-chat').withOptions(
          ModelOptions.none.set(ModelParams.chatTemperature.key, null),
        ),
        glossaryIds: ['g1', 'g2'],
        glossary: const [
          GlossaryEntry(term: '百炼', translation: 'Bailian'),
          GlossaryEntry(term: 'Ollama'),
        ],
        asrPrompt: '专有名词',
        diarize: true,
        translate: false,
        translationBatchSize: 7,
        bilingual: BilingualLayout.targetAbove,
        cjkLineLength: 20,
        minCueMs: 800,
        maxCueMs: 12000,
        format: SubtitleFormat.vtt,
        outputLocation: OutputLocation.custom,
        outputDir: '/out',
      );
      final back = TaskOptions.fromJson(
        o.toJson(),
        fallback: s.defaultTaskOptions(),
      );
      expect(back.toJson(), o.toJson());
      // 模型是整份声明：接入方式、报文族、「不发送」的参数都原样回来。
      expect(back.asrModel, o.asrModel);
      expect(back.translationModel, o.translationModel);
      expect(back.translationModel.options.has('temperature'), isTrue);
      expect(back.glossaryIds, ['g1', 'g2']);
      expect(back.glossary, o.glossary);
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
        'maxCueMs': 999999,
        'format': 'ass',
        'outputLocation': 'custom',
      }, fallback: fallback);
      expect(o.translationBatchSize, fallback.translationBatchSize);
      expect(o.cjkLineLength, 60);
      expect(o.maxCueMs, 60000);
      expect(o.format, SubtitleFormat.ass);
      expect(o.outputLocation, OutputLocation.besideSource);
      expect(o.outputDir, isNull);
      // 没写模型的旧存档：读回来就是这一刻设置里的默认模型，此后不再变。
      expect(o.asrModel, fallback.asrModel);
      expect(o.translationModel, fallback.translationModel);
      expect(o.asrModel.name, 'whisper-1');
    });

    group('读旧格式的模型（只有名字，或 null）', () {
      late AppSettings s;
      late TaskOptions fallback;

      setUp(() async {
        s = await freshSettings();
        // 用户在设置里给默认模型调过参数：同名的旧存档读回来要带着它。
        s
          ..setModels('openai', [
            const AsrModelSpec(
              name: 'my-whisper',
              transport: AsrTransport.openaiTranscription,
            ).withOptions(
              ModelOptions.none.set(ModelParams.asrTemperature.key, 0.2),
            ),
          ])
          ..setModels('deepseek', [
            const ChatModelSpec(name: 'my-chat').withOptions(
              ModelOptions.none.set(ModelParams.chatTemperature.key, 1.0),
            ),
          ]);
        fallback = s.defaultTaskOptions();
      });

      TaskOptions read(Map<String, Object?> json) =>
          TaskOptions.fromJson(json, fallback: fallback);

      test('同一家服务、同名：用设置里那份，参数还在', () {
        final o = read({
          'asrProviderId': 'openai',
          'asrModel': ' my-whisper ',
          'translationProviderId': 'deepseek',
          'translationModel': 'my-chat',
        });
        expect(o.asrModel, fallback.asrModel);
        expect(o.asrModel.options.number(ModelParams.asrTemperature), 0.2);
        expect(o.translationModel, fallback.translationModel);
      });

      test('同一家服务、别的名字：预置里有的用预置，没有的按名字推断', () {
        final o = read({
          'asrProviderId': 'openai',
          'asrModel': 'gpt-4o-transcribe',
          'translationProviderId': 'deepseek',
          'translationModel': 'deepseek-reasoner',
        });
        expect(
          o.asrModel,
          same(ProviderCatalog.asrInfo('openai')!.presets[1]),
        );
        expect(
          o.translationModel,
          same(ProviderCatalog.translationInfo('deepseek')!.presets[1]),
        );

        final custom = read({'asrModel': 'x', 'translationModel': 'y'});
        expect(
          custom.asrModel,
          const AsrModelSpec(
            name: 'x',
            transport: AsrTransport.openaiTranscription,
          ),
        );
        expect(custom.translationModel, const ChatModelSpec(name: 'y'));
      });

      test('另一家服务：接法按那家服务的规则补，不串到默认服务上', () {
        final o = read({
          'asrProviderId': 'dashscope_qwen_asr',
          'asrModel': 'my-model-filetrans',
          'translationProviderId': 'ollama',
          // 碰巧与默认服务的模型同名，也不能拿默认服务那份来用。
          'translationModel': 'my-chat',
        });
        expect(o.asrModel.transport, AsrTransport.dashscopeFileTrans);
        expect(o.asrModel.dialect, DashScopeDialect.qwenAudio3);
        expect(o.translationModel, const ChatModelSpec(name: 'my-chat'));
      });

      test('null：同一家服务用现在的默认，另一家用它的第一个预置', () {
        final same = read({'asrModel': null, 'translationModel': null});
        expect(same.asrModel, fallback.asrModel);
        expect(same.translationModel, fallback.translationModel);

        final other = read({
          'asrProviderId': 'dashscope_qwen_asr',
          'translationProviderId': 'ollama',
        });
        expect(other.asrModel.name, 'qwen3-asr-flash');
        expect(other.asrModel.transport, AsrTransport.dashscopeSync);
        expect(other.translationModel.name, 'qwen2.5:14b');

        // 服务也认不出来：空名占位，就绪检查会说「未知的服务」。
        final unknown = read({
          'asrProviderId': '不存在',
          'translationProviderId': '不存在',
        });
        expect(unknown.asrModel.isUnset, isTrue);
        expect(unknown.translationModel.isUnset, isTrue);
      });

      test('种类不对或读不出来的对象按没写处理，不抛', () {
        final o = read({
          'asrModel': const ChatModelSpec(name: '放错了').toJson(),
          'translationModel': {'kind': '不认识'},
        });
        expect(o.asrModel, fallback.asrModel);
        expect(o.translationModel, fallback.translationModel);
        expect(read({'asrModel': 3}).asrModel, fallback.asrModel);
      });

      test('旧存档没有词表：读回来是空的，不拿现在默认启用的词表来补', () {
        s.setGlossary(
          const Glossary(
            id: 'g1',
            name: '访谈',
            entries: [GlossaryEntry(term: '百炼')],
          ),
        );
        final withGlossary = s.defaultTaskOptions();
        expect(withGlossary.glossary, isNotEmpty);

        final o = TaskOptions.fromJson({}, fallback: withGlossary);
        expect(o.glossaryIds, isEmpty);
        expect(o.glossary, isEmpty);

        // 坏类型、坏条目：丢掉坏的，留下好的。
        final messy = TaskOptions.fromJson({
          'glossaryIds': ['g1', 3, null],
          'glossary': [
            {'term': ' 百炼 ', 'translation': 'Bailian'},
            'x',
            {'term': ''},
          ],
        }, fallback: withGlossary);
        expect(messy.glossaryIds, ['g1']);
        expect(messy.glossary, [
          const GlossaryEntry(term: '百炼', translation: 'Bailian'),
        ]);
        expect(
          TaskOptions.fromJson({
            'glossaryIds': 'g1',
            'glossary': {'term': 'x'},
          }, fallback: withGlossary).glossary,
          isEmpty,
        );
      });
    });

    test('默认参数：模型是设置里的默认声明，默认启用的词表已经展开', () async {
      final s = await freshSettings();
      s
        ..asrProviderId = 'dashscope_qwen_asr'
        ..translationProviderId = 'ollama'
        ..setGlossary(
          const Glossary(
            id: 'a',
            name: '访谈',
            entries: [GlossaryEntry(term: '百炼', translation: 'Bailian')],
          ),
        )
        ..setGlossary(
          const Glossary(
            id: 'b',
            name: '没启用',
            enabledByDefault: false,
            entries: [GlossaryEntry(term: 'Ollama')],
          ),
        );
      final o = s.defaultTaskOptions();
      expect(
        o.asrModel,
        same(ProviderCatalog.asrInfo('dashscope_qwen_asr')!.presets.first),
      );
      expect(o.translationModel.name, 'qwen2.5:14b');
      expect(o.glossaryIds, ['a']);
      expect(o.glossary, [
        const GlossaryEntry(term: '百炼', translation: 'Bailian'),
      ]);

      // 偏好里的服务 id 已经不在登记表里：不抛，模型是空名占位。
      s.asrProviderId = '不存在';
      expect(s.defaultTaskOptions().asrModel.isUnset, isTrue);
    });

    test('「上次参数」只记勾选了哪几份词表，不把条目存进偏好', () async {
      final s = await freshSettings();
      s.setGlossary(
        const Glossary(
          id: 'a',
          name: '访谈',
          entries: [GlossaryEntry(term: '百炼', translation: 'Bailian')],
        ),
      );
      final submitted = s.defaultTaskOptions();
      expect(submitted.glossary, isNotEmpty);
      s.lastTranscribeOptions = submitted;

      final last = s.lastTranscribeOptions!;
      expect(last.glossaryIds, ['a']);
      expect(last.glossary, isEmpty);
      expect(last.asrModel, submitted.asrModel);
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
