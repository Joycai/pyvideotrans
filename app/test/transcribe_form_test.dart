import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/shared/footer_message.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_form.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 可控的探测：每个路径一个 Completer，测试决定什么时候「探完」。
class GatedFfmpeg extends Ffmpeg {
  final gates = <String, Completer<MediaFileInfo>>{};

  @override
  Future<MediaFileInfo> probeFile(String path) =>
      (gates[path] ??= Completer<MediaFileInfo>()).future;

  void finish(String path, {bool exists = true, Duration? duration}) {
    (gates[path] ??= Completer<MediaFileInfo>()).complete(
      MediaFileInfo(
        path: path,
        sizeBytes: 1024,
        duration: duration ?? const Duration(minutes: 1),
        exists: exists,
      ),
    );
  }
}

Future<AppSettings> _settings({bool withKey = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  if (withKey) {
    settings
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk-test'))
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
  }
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('文件列表', () {
    test('先以「探测中」入列，探完再就绪；探测中不阻断提交', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/a.mp4']);

      expect(form.files.single.state, StagedFileState.probing);
      expect(form.probingCount, 1);
      expect(form.canStart, isTrue);
      expect(form.footer.text, contains('1 个文件仍在探测'));

      media.finish('/v/a.mp4', duration: const Duration(minutes: 3));
      await done;
      expect(form.files.single.state, StagedFileState.ready);
      expect(form.totalDuration, const Duration(minutes: 3));
      expect(form.footer.text, '将创建 1 个转写并翻译任务，加入队列后在任务页查看进度');
    });

    test('读不出来的文件不入队、不计入总数，全都读不出时拦住', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/ok.mp4', '/v/bad.mkv']);
      media.finish('/v/ok.mp4');
      media.finish('/v/bad.mkv', exists: false);
      await done;

      expect(form.unreadableCount, 1);
      expect(form.enqueueable.map((f) => f.path), ['/v/ok.mp4']);
      expect(form.submit()!.paths, ['/v/ok.mp4']);

      form.remove(form.files.first);
      expect(form.canStart, isFalse);
      expect(form.footer.error, isTrue);
      expect(form.footer.text, contains('读不出来'));
    });

    test('探测期间被移除的文件不会再冒出来', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/a.mp4']);
      form.remove(form.files.single);
      media.finish('/v/a.mp4');
      await done;
      expect(form.files, isEmpty);
    });

    test('拒收说明压过其他所有文案，清掉后恢复', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      form.handleDrop(['/v/a.mp4', '/v/sub.srt']);
      expect(form.dropError, '已忽略 1 个字幕文件，字幕请用「新建翻译」');
      expect(form.footer.error, isTrue);
      expect(form.files.map((f) => f.path), ['/v/a.mp4']);

      form.clearDropError();
      expect(form.footer.error, isFalse);
    });
  });

  group('上次参数', () {
    test('提交时记下参数，下次可整份填回', () async {
      final settings = await _settings();
      final media = GatedFfmpeg();
      final form = TranscribeFormController(settings: settings, media: media);
      expect(form.hasLastUsed, isFalse);
      expect(form.applyLastUsed(), isFalse);

      final done = form.add(['/v/a.mp4']);
      media.finish('/v/a.mp4');
      await done;
      form.update(
        (o) => o.copyWith(translate: false, cjkLineLength: 22, asrPrompt: 'X'),
      );
      expect(form.submit(), isNotNull);

      final again = TranscribeFormController(settings: settings, media: media);
      expect(again.options.translate, isTrue);
      expect(again.hasLastUsed, isTrue);
      expect(again.applyLastUsed(), isTrue);
      expect(again.options.translate, isFalse);
      expect(again.options.cjkLineLength, 22);
      expect(again.options.asrPrompt, 'X');

      again.reset();
      expect(again.options.translate, isTrue);
      expect(again.options.cjkLineLength, 15);
    });

    test('不能开始时提交不记参数', () async {
      final settings = await _settings(withKey: false);
      final form = TranscribeFormController(
        settings: settings,
        media: GatedFfmpeg(),
      );
      expect(form.submit(), isNull);
      expect(settings.lastTranscribeOptions, isNull);
    });
  });

  group('产物名示例', () {
    // 与流水线写出的同名：原文带语言段，开了翻译再列上译文那份。
    test('带语言段；开翻译后列出两份', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      form.update(
        (o) => o.copyWith(
          sourceLanguage: Languages.resolve('zh'),
          translate: false,
        ),
      );
      expect(
        form.outputNameExample,
        'interview_ep12.mp4 → interview_ep12.zh.srt',
      );

      final done = form.add(['/v/talk.mov']);
      media.finish('/v/talk.mov');
      await done;
      form.update(
        (o) => o.copyWith(
          translate: true,
          targetLanguage: Languages.resolve('en'),
        ),
      );
      expect(form.outputNameExample, 'talk.mov → talk.zh.srt、talk.en.srt');
    });
  });

  group('输出位置', () {
    test('选「指定目录」时取消选择框：留在原来的位置', () async {
      String? picked;
      final form = TranscribeFormController(
        settings: await _settings(),
        media: GatedFfmpeg(),
        pickDirectory: () async => picked,
      );
      form.chooseOutputLocation(OutputLocation.custom);
      await pumpEventQueue();
      expect(form.options.outputLocation, OutputLocation.besideSource);
      expect(form.options.outputDir, isNull);

      picked = '/out';
      form.chooseOutputLocation(OutputLocation.custom);
      await pumpEventQueue();
      expect(form.options.outputLocation, OutputLocation.custom);
      expect(form.options.outputDir, '/out');

      // 已有目录时来回切不再弹框。
      picked = null;
      form
        ..chooseOutputLocation(OutputLocation.besideSource)
        ..chooseOutputLocation(OutputLocation.custom);
      expect(form.options.outputLocation, OutputLocation.custom);
      expect(form.options.outputDir, '/out');
    });
  });

  group('换服务', () {
    test('模型换成新服务的默认；新模型分不了说话人时关掉开关', () async {
      final settings = await _settings();
      final form = TranscribeFormController(
        settings: settings,
        media: GatedFfmpeg(),
      );
      final dashscope = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      final filetrans = dashscope.presets.firstWhere(
        (p) => p.capabilities.diarization,
      );

      form.selectAsrProvider(dashscope.id);
      expect(form.options.asrModel, same(dashscope.presets.first));
      form
        ..update((o) => o.copyWith(asrModel: filetrans, diarize: true))
        ..selectAsrProvider('openai');
      expect(form.options.asrProviderId, 'openai');
      // 不会把上一家的模型带到下一家去。
      expect(form.options.asrModel.name, 'whisper-1');
      expect(form.options.diarize, isFalse);

      // 新服务的默认取的是设置里配的那个，不是登记表的第一个预置。
      settings.setModels(dashscope.id, [filetrans, dashscope.presets.first]);
      form
        ..update((o) => o.copyWith(diarize: true))
        ..selectAsrProvider(dashscope.id);
      expect(form.options.asrModel, filetrans);

      form
        ..update(
          (o) => o.copyWith(translationModel: const ChatModelSpec(name: 'm2')),
        )
        ..selectTranslationProvider('ollama');
      expect(form.options.translationProviderId, 'ollama');
      expect(form.options.translationModel.name, 'qwen2.5:14b');

      // 登记表里没有的 id：不抛，模型是空名占位，就绪检查会拦。
      form.selectAsrProvider('不存在');
      expect(form.options.asrModel.isUnset, isTrue);
      expect(form.asrReadiness.isBlocked, isTrue);
    });
  });

  // 表单挂在根节点上长期存活，参数里的模型是一份声明的拷贝。用户去设置里
  // 改了模型再回来，没动过的那几项要跟着变，否则任务用的还是旧的。
  group('跟着设置走', () {
    late AppSettings settings;
    late TranscribeFormController form;
    late int notified;

    setUp(() async {
      settings = await _settings();
      form = TranscribeFormController(settings: settings, media: GatedFfmpeg());
      notified = 0;
      form.addListener(() => notified++);
    });

    const custom = AsrModelSpec(
      name: 'my-whisper',
      transport: AsrTransport.openaiTranscription,
    );

    test('没动过模型：设置里换了默认模型，表单跟着换', () {
      expect(form.options.asrModel.name, 'whisper-1');
      settings.setModels('openai', [custom]);
      expect(form.options.asrModel, custom);
      expect(notified, 1);

      settings.setModels('deepseek', [const ChatModelSpec(name: 'my-chat')]);
      expect(form.options.translationModel.name, 'my-chat');
      // 接连改也跟得上：每次都和「上一次的默认」比。
      settings.setModels('deepseek', [const ChatModelSpec(name: 'again')]);
      expect(form.options.translationModel.name, 'again');
    });

    test('一开始没有模型可选：在设置里填好之后回来就能开始', () {
      form.selectAsrProvider('asr_custom');
      expect(form.options.asrModel.isUnset, isTrue);
      settings.setConfig(
        'asr_custom',
        const ProviderConfig(
          baseUrl: 'https://asr.example/v1',
          apiKey: 'k',
          legacyModelText: 'whisper-x',
        ),
      );
      expect(form.options.asrModel.name, 'whisper-x');
      expect(form.asrReadiness.isBlocked, isFalse);
    });

    test('自己选了别的模型：默认模型变了不跟，同名声明的参数照样刷新', () {
      final openai = ProviderCatalog.asrInfo('openai')!;
      form.update((o) => o.copyWith(asrModel: openai.presets[1]));

      settings.setModels('openai', [custom, ...openai.presets]);
      expect(form.options.asrModel, same(openai.presets[1]));

      final tuned = openai.presets[1].withOptions(
        ModelOptions.none.set(ModelParams.asrTemperature.key, 0.2),
      );
      settings.setModels('openai', [custom, tuned]);
      expect(form.options.asrModel, tuned);
    });

    test('选的模型设置里已经没有了：留着不动（手填的、上次参数带来的）', () {
      form.update((o) => o.copyWith(asrModel: custom));
      settings.setModels('openai', [
        ProviderCatalog.asrInfo('openai')!.presets.first,
      ]);
      expect(form.options.asrModel, custom);
    });

    test('与模型无关的设置改动不触发刷新', () {
      settings.themeMode = 'dark';
      settings.asrPrompt = '后来改的提示';
      expect(notified, 0);
      // 提示词这类不是「跟着走」的项：表单里的是打开那一刻的拷贝。
      expect(form.options.asrPrompt, '');
    });

    test('默认启用的词表：没动过勾选就跟着设置变，动过的不碰', () {
      expect(form.options.glossaryIds, isEmpty);
      settings.setGlossary(const Glossary(id: 'a', name: '访谈'));
      expect(form.options.glossaryIds, ['a']);

      form.update((o) => o.copyWith(glossaryIds: const []));
      settings.setGlossary(const Glossary(id: 'b', name: '技术'));
      expect(form.options.glossaryIds, isEmpty);
    });

    // 看参数有没有变，不看通知次数：销毁之后表单本来就不再通知，监听
    // 还挂着也数不出来。
    test('表单销毁后不再听设置', () {
      form.dispose();
      settings.setModels('openai', [custom]);
      expect(form.options.asrModel.name, 'whisper-1');
      expect(notified, 0);
    });

    // 下拉里只看得到名字。上次提交之后在设置里改过这个模型的参数，填回来
    // 的必须是改过的那份，否则任务悄悄用了旧参数。
    test('「上次参数」里的模型按名字换成设置里现在的声明', () {
      final tuned = custom.withOptions(
        ModelOptions.none.set(ModelParams.asrTemperature.key, 0.2),
      );
      settings
        ..setModels('openai', [
          const AsrModelSpec(
            name: 'whisper-1',
            transport: AsrTransport.openaiTranscription,
          ),
          tuned,
        ])
        ..lastTranscribeOptions = form.options.copyWith(
          asrModel: custom,
          translationModel: const ChatModelSpec(name: '设置里已经删掉的'),
        );

      expect(form.applyLastUsed(), isTrue);
      expect(form.options.asrModel, tuned);
      // 设置里找不到同名的：照上次的原样填回。
      expect(form.options.translationModel.name, '设置里已经删掉的');
    });
  });

  group('词表勾选', () {
    const interview = Glossary(
      id: 'a',
      name: '访谈',
      entries: [GlossaryEntry(term: '百炼', translation: 'Bailian')],
    );
    const tech = Glossary(
      id: 'b',
      name: '技术',
      enabledByDefault: false,
      entries: [GlossaryEntry(term: 'Ollama')],
    );

    late AppSettings settings;
    late TranscribeFormController form;

    setUp(() async {
      settings = await _settings()
        ..setGlossary(interview)
        ..setGlossary(tech);
      form = TranscribeFormController(settings: settings);
      addTearDown(form.dispose);
    });

    test('提交时按勾选把条目展开进任务参数；「上次参数」只记勾选', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(settings: settings, media: media);
      final done = form.add(['/v/a.mp4']);
      media.finish('/v/a.mp4');
      await done;

      // 表单打开之后词表又加了一条：提交时取的是此刻的内容。
      form.toggleGlossary('b');
      settings.setGlossary(
        tech.copyWith(
          entries: const [
            GlossaryEntry(term: 'Ollama'),
            GlossaryEntry(term: 'LM Studio'),
          ],
        ),
      );

      final request = form.submit()!;
      expect(request.options.glossary, const [
        GlossaryEntry(term: '百炼', translation: 'Bailian'),
        GlossaryEntry(term: 'Ollama'),
        GlossaryEntry(term: 'LM Studio'),
      ]);
      expect(request.options.asrModel, form.options.asrModel);

      final last = settings.lastTranscribeOptions!;
      expect(last.glossaryIds, ['a', 'b']);
      expect(last.glossary, isEmpty);
    });

    test('点一下勾上、再点去掉；顺序跟着设置里的词表走，不跟着点击先后', () {
      expect(form.options.glossaryIds, ['a']);

      form
        ..toggleGlossary('a')
        ..toggleGlossary('b');
      expect(form.options.glossaryIds, ['b']);
      form.toggleGlossary('a');
      // 后勾的 a 排在前面：它在设置里排在前面。
      expect(form.options.glossaryIds, ['a', 'b']);

      // 不存在的 id 勾不上。
      form.toggleGlossary('没有这份');
      expect(form.options.glossaryIds, ['a', 'b']);
    });

    test('去掉再勾回来仍算没动过：继续跟着设置里的默认走', () {
      form
        ..toggleGlossary('a')
        ..toggleGlossary('a');
      settings.setGlossary(tech.copyWith(enabledByDefault: true));
      expect(form.options.glossaryIds, ['a', 'b']);
    });

    test('勾选动过之后不跟默认走；词表被删掉时把它从勾选里去掉', () {
      form.toggleGlossary('b');
      expect(form.options.glossaryIds, ['a', 'b']);

      settings.setGlossary(interview.copyWith(enabledByDefault: false));
      expect(form.options.glossaryIds, ['a', 'b']);

      settings.removeGlossary('a');
      expect(form.options.glossaryIds, ['b']);
    });

    test('「上次参数」恢复勾选，已经删掉的那几份丢掉', () {
      settings.lastTranscribeOptions = form.options.copyWith(
        glossaryIds: ['b', '已删', 'a'],
      );
      settings.removeGlossary('a');

      expect(form.applyLastUsed(), isTrue);
      expect(form.options.glossaryIds, ['b']);
    });

    test('重置为默认：回到默认启用的那几份', () {
      form
        ..toggleGlossary('a')
        ..toggleGlossary('b');
      expect(form.options.glossaryIds, ['b']);
      form.reset();
      expect(form.options.glossaryIds, ['a']);
    });
  });

  group('说话人分离与模型能力', () {
    final bailian = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
    final capable = bailian.presets[3];
    final incapable = bailian.presets[0];

    late AppSettings settings;
    late TranscribeFormController form;

    setUp(() async {
      settings = await _settings()
        ..asrProviderId = bailian.id
        ..setModels(bailian.id, [capable, incapable]);
      form = TranscribeFormController(settings: settings);
      addTearDown(form.dispose);
      form.update((o) => o.copyWith(diarize: true));
    });

    test('模型能分离：开关开得起来', () {
      expect(form.options.asrModel, capable);
      expect(form.options.diarize, isTrue);
    });

    test('换成不能分离的模型：开关随之关掉，换回来也不会自己打开', () {
      form.update((o) => o.copyWith(asrModel: incapable));
      expect(form.options.diarize, isFalse);
      form.update((o) => o.copyWith(asrModel: capable));
      expect(form.options.diarize, isFalse);
    });

    test('模型不能分离时开不了', () {
      form
        ..update((o) => o.copyWith(asrModel: incapable))
        ..update((o) => o.copyWith(diarize: true));
      expect(form.options.diarize, isFalse);
    });

    test('设置里把默认模型换成不能分离的：表单跟过去，开关关掉', () {
      settings.setModels(bailian.id, [incapable, capable]);
      expect(form.options.asrModel, incapable);
      expect(form.options.diarize, isFalse);
    });

    test('「上次参数」里开着分离，而那个模型现在声明成不能分离的：填回时关掉', () {
      settings.lastTranscribeOptions = form.options;
      // 同一个名字，在设置里改成了同步接入：不再能分离。
      settings.setModels(bailian.id, [
        AsrModelSpec(
          name: capable.name,
          transport: AsrTransport.dashscopeSync,
          dialect: DashScopeDialect.qwenAudio3,
        ),
      ]);
      form.applyLastUsed();
      expect(form.options.asrModel.transport, AsrTransport.dashscopeSync);
      expect(form.options.diarize, isFalse);
    });

    test('初始参数里开着分离而模型不支持：建表单时就关掉', () {
      final form = TranscribeFormController(
        settings: settings,
        initial: settings.defaultTaskOptions().copyWith(
          asrModel: incapable,
          diarize: true,
        ),
      );
      addTearDown(form.dispose);
      expect(form.options.diarize, isFalse);
    });
  });
}
