import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/translation_protocol.dart';

const _info = ChatProviderInfo(
  id: 'test',
  name: '测试',
  vendor: '测试服务',
  defaultBaseUrl: 'https://example.invalid/v1',
);

const _endpoint = Endpoint(
  baseUrl: 'https://example.invalid/v1',
  model: 'm',
  apiKey: 'k',
);

const _m = TranslationProtocol.marker;

/// 目标语言为「英文」、没有补充要求时的系统提示全文。
///
/// 故意抄一份字面量而不是调 [TranslationProtocol.systemPrompt] 来比：
/// 拿被测函数自己当期望值，规则正文被改掉一行也照样绿。有意改提示词时
/// 这里会挂，那正是想要的信号 —— 改完把这份一起更新。
const _englishSystemPrompt = r'''
你是字幕翻译专家。把 <INPUT> 里的每一行翻译成英文。

# 绝对规则：逐行一一对应

- 输出的行数必须与输入**完全相同**。输入 N 行就输出 N 行。
- 每行以 `§` + 行号 + `§` 开头，行号照抄输入，不要重排。
- 禁止合并：即使两行原文属于同一个句子，也必须分别翻译成两行。
- 禁止删除：语气词、拟声词、重复的短句、单个字的应答，全都要保留对应行。
- 禁止增行：不要加解释、不要加标题、不要输出原文、不要用代码块包裹。

# 跨行断句的处理

口语会把一句话切在几行里。只翻译当前行**实际出现**的词，
不要为了符合英文 的语序把成分挪到相邻行。
如果某行在句中断开，用省略号收尾；下一行承接时用省略号开头。

# 语感

- 面向听觉而非阅读：用日常口语词，避免书面语和翻译腔。
- 字幕停留时间有限，去掉可省的主语、客套和冗余修饰，取最短的自然说法。
- 保留原文的专有名词、数字与单位。原文是人名/产品名且无通行译法时保留原文。

# 示例

输入：
§1§ 我们先确认一下
§2§ Ollama 有没有在跑。
§3§ 嗯。

输出：
§1§ Let's first check...
§2§ ...whether Ollama is running.
§3§ Mm-hm.
''';

const _whisper = AsrModelSpec(
  name: 'whisper-1',
  transport: AsrTransport.openaiTranscription,
);

const _chat = ChatModelSpec(name: 'm');

/// 这家服务默认模型的连接参数：设置解析出来、什么任务都没建时会用的那份。
Endpoint _endpointOf(AppSettings settings, ProviderInfo info) =>
    settings.endpointFor(info, settings.defaultModel(info));

/// 建任务页模型下拉里的候选名字。
List<String> _namesOf(AppSettings settings, ProviderInfo info) => [
  for (final model in settings.modelChoices(info)) model.name,
];

List<String> _presetNames(ProviderInfo info) => [
  for (final preset in info.presets) preset.name,
];

Future<AppSettings> _settings() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettings.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('翻译线路协议', () {
    test('编码带行号，正文换行压成空格', () {
      final encoded = TranslationProtocol.encode(['第一行\n续行', '第二行']);
      expect(encoded, '${_m}1$_m 第一行 续行\n${_m}2$_m 第二行');
    });

    test('按行号还原，顺序与输入一致', () {
      final out = TranslationProtocol.decode(
        '${_m}2$_m B\n${_m}1$_m A\n${_m}3$_m C',
        3,
      );
      expect(out, ['A', 'B', 'C']);
    });

    test('剥掉代码块包裹', () {
      final out = TranslationProtocol.decode(
        '```\n${_m}1$_m A\n${_m}2$_m B\n```',
        2,
      );
      expect(out, ['A', 'B']);
    });

    test('条数不符时判定为不可信', () {
      expect(TranslationProtocol.decode('${_m}1$_m A', 2), isNull);
    });

    test('行号越界时判定为不可信', () {
      expect(TranslationProtocol.decode('${_m}1$_m A\n${_m}9$_m B', 2), isNull);
    });

    test('行号重复时判定为不可信', () {
      expect(TranslationProtocol.decode('${_m}1$_m A\n${_m}1$_m B', 2), isNull);
    });

    test('模型没打标记但行数正好时按顺序对应', () {
      expect(TranslationProtocol.decode('A\n\nB\n', 2), ['A', 'B']);
    });

    test('没打标记且行数不符时判定为不可信', () {
      expect(TranslationProtocol.decode('A\nB\nC', 2), isNull);
    });
  });

  group('翻译 provider', () {
    TranslationProvider build(MockClient client) =>
        OpenAiCompatibleTranslationProvider(
          info: _info,
          endpoint: _endpoint,
          client: client,
        );

    String reply(String content) => jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    });

    /// 发一批并把请求体解出来。
    Future<Map<String, Object?>> sentBody({
      String? guidance,
      List<GlossaryEntry> glossary = const [],
    }) async {
      late http.Request sent;
      final provider = OpenAiCompatibleTranslationProvider(
        info: _info,
        endpoint: _endpoint,
        extraGuidance: guidance,
        glossary: glossary,
        client: MockClient((r) async {
          sent = r;
          return http.Response(reply('${_m}1$_m Hello\n${_m}2$_m World'), 200);
        }),
      );
      await provider.translateBatch(
        lines: ['你好', '世界'],
        sourceLanguage: '中文',
        targetLanguage: '英文',
        token: CancellationToken(),
      );
      // 头也是请求的一部分：多出一个也算变了。
      expect(sent.headers.map((k, v) => MapEntry(k.toLowerCase(), v)), {
        'content-type': 'application/json; charset=utf-8',
        'authorization': 'Bearer k',
      });
      return jsonDecode(utf8.decode(sent.bodyBytes)) as Map<String, Object?>;
    }

    // 下面两条钉的是「发出去的请求长什么样」。重构模型配置、加词表时，
    // 不改设置的用户发出的请求必须一个字节都不变。
    test('请求体：模型、温度 0.3、一条 system 一条 user', () async {
      final body = await sentBody();

      expect(body.keys, unorderedEquals(['model', 'temperature', 'messages']));
      expect(body['model'], 'm');
      expect(body['temperature'], 0.3);
      expect(body['messages'], [
        {
          'role': 'system',
          'content': TranslationProtocol.systemPrompt(
            targetLanguageName: '英文',
          ),
        },
        {
          'role': 'user',
          'content': '<INPUT>\n${_m}1$_m 你好\n${_m}2$_m 世界\n</INPUT>',
        },
      ]);
    });

    test('温度选了不发送：请求体里没有这个键，其余不变', () async {
      // 不走上面的 sentBody：那个不传温度，钉的是构造默认值 0.3。
      Future<Map<String, Object?>> bodyWith(double? temperature) async {
        late http.Request sent;
        await OpenAiCompatibleTranslationProvider(
          info: _info,
          endpoint: _endpoint,
          temperature: temperature,
          client: MockClient((r) async {
            sent = r;
            return http.Response(reply('${_m}1$_m Hello'), 200);
          }),
        ).translateBatch(
          lines: ['你好'],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: CancellationToken(),
        );
        return jsonDecode(utf8.decode(sent.bodyBytes)) as Map<String, Object?>;
      }

      final omitted = await bodyWith(null);
      expect(omitted.keys, unorderedEquals(['model', 'messages']));
      final sent = await bodyWith(1.2);
      expect(sent['temperature'], 1.2);
      expect(omitted['messages'], sent['messages']);
    });

    test('补充要求只在填了的时候进系统提示，位置在「示例」之前', () async {
      String systemOf(Map<String, Object?> body) =>
          ((body['messages']! as List).first as Map)['content'] as String;
      List<String> headings(String prompt) => [
        for (final line in prompt.split('\n'))
          if (line.startsWith('# ')) line,
      ];

      final plain = systemOf(await sentBody());
      expect(plain, _englishSystemPrompt);
      expect(plain, startsWith('你是字幕翻译专家。把 <INPUT> 里的每一行翻译成英文。'));
      expect(headings(plain), [
        '# 绝对规则：逐行一一对应',
        '# 跨行断句的处理',
        '# 语感',
        '# 示例',
      ]);
      // 只有空白等于没填。
      expect(systemOf(await sentBody(guidance: ' \n ')), plain);

      final guided = systemOf(await sentBody(guidance: '  语气随意些。\n'));
      expect(
        guided,
        plain.replaceFirst('\n# 示例', '\n# 补充要求\n\n语气随意些。\n\n# 示例'),
      );
    });

    test('词表只在有条目时进系统提示，位置在「补充要求」之前', () async {
      String systemOf(Map<String, Object?> body) =>
          ((body['messages']! as List).first as Map)['content'] as String;
      const glossary = [
        GlossaryEntry(term: '百炼', translation: 'Bailian'),
        GlossaryEntry(term: 'Ollama'),
      ];
      // 术语段的全文抄在这里，不调 GlossaryText 来拼：措辞被改也要挂。
      const section = '''
# 术语表

下面的词在原文里出现时，按给定的译法翻译；标了「保留原文写法」的照抄原文，不要翻译也不要音译。

- 百炼 → Bailian
- Ollama（保留原文写法）
''';

      // 没有词表：和加词表之前逐字相同。
      expect(systemOf(await sentBody()), _englishSystemPrompt);
      // 条目全是空的等于没有词表。
      expect(
        systemOf(await sentBody(glossary: const [GlossaryEntry(term: ' ')])),
        _englishSystemPrompt,
      );

      expect(
        systemOf(await sentBody(glossary: glossary)),
        _englishSystemPrompt.replaceFirst('\n# 示例', '\n$section\n# 示例'),
      );
      expect(
        systemOf(await sentBody(glossary: glossary, guidance: '语气随意些。')),
        _englishSystemPrompt.replaceFirst(
          '\n# 示例',
          '\n$section\n# 补充要求\n\n语气随意些。\n\n# 示例',
        ),
      );

      // 词表不改请求的其余部分。
      final body = await sentBody(glossary: glossary);
      expect(body.keys, unorderedEquals(['model', 'temperature', 'messages']));
      expect(body['messages'], hasLength(2));
    });

    test('返回等长译文', () async {
      final provider = build(
        MockClient((r) async {
          expect(r.url.path, '/v1/chat/completions');
          expect(r.headers['Authorization'], 'Bearer k');
          return http.Response(
            reply('${_m}1$_m Hello\n${_m}2$_m World'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final out = await provider.translateBatch(
        lines: ['你好', '世界'],
        sourceLanguage: '中文',
        targetLanguage: '英文',
        token: CancellationToken(),
      );
      expect(out, ['Hello', 'World']);
    });

    test('条数对不上时报错而不是写入错位译文', () async {
      final provider = build(
        MockClient((_) async => http.Response(reply('${_m}1$_m Hello'), 200)),
      );

      expect(
        () => provider.translateBatch(
          lines: ['你好', '世界'],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: CancellationToken(),
        ),
        throwsA(
          isA<ActionableException>().having(
            (e) => e.message,
            'message',
            contains('条数对不上'),
          ),
        ),
      );
    });

    test('401 给出核对密钥的建议', () async {
      final provider = build(MockClient((_) async => http.Response('no', 401)));
      expect(
        () => provider.translateBatch(
          lines: ['a'],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: CancellationToken(),
        ),
        throwsA(
          isA<ActionableException>()
              .having((e) => e.message, 'message', contains('拒绝'))
              .having((e) => e.hint, 'hint', contains('API 密钥')),
        ),
      );
    });

    test('已取消的任务不发请求', () async {
      var called = false;
      final provider = build(
        MockClient((_) async {
          called = true;
          return http.Response(reply(''), 200);
        }),
      );
      final token = CancellationToken()..cancel();

      expect(
        () => provider.translateBatch(
          lines: ['a'],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: token,
        ),
        throwsA(isA<TaskCancelled>()),
      );
      expect(called, isFalse);
    });

    test('空批次直接返回空', () async {
      final provider = build(
        MockClient((_) async => throw StateError('不该发请求')),
      );
      expect(
        await provider.translateBatch(
          lines: const [],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: CancellationToken(),
        ),
        isEmpty,
      );
    });
  });

  group('登记表', () {
    test('未实施的服务给出可行动的提示，而不是默默失败', () async {
      final settings = await _settings();
      expect(
        () => Registry.buildAsr('local_backend', settings, model: _whisper),
        throwsA(
          isA<ActionableException>()
              .having((e) => e.message, 'message', contains('尚未实施'))
              .having((e) => e.hint, 'hint', contains('OpenAI')),
        ),
      );
    });

    test('未知 id 也报可行动的错', () async {
      final settings = await _settings();
      expect(
        () => Registry.buildTranslation('不存在', settings, model: _chat),
        throwsA(isA<ActionableException>()),
      );
    });

    // 「设置 → 连接参数」与「连接参数 → 请求」两头各有测试，这一组钉中间
    // 那道接缝：模型、提示词、词表都是任务入队时定死的，建实例时只从设置
    // 拿地址与密钥。拿错了来源，排着队的任务就会被后来的设置改动影响。
    group('任务级参数', () {
      late AppSettings settings;

      setUp(() async {
        SharedPreferences.setMockInitialValues({
          'providerConfigs': jsonEncode({
            'openai': {
              'baseUrl': 'https://proxy.example/v1',
              'model': 'my-whisper, whisper-1',
              'apiKey': 'sk-asr',
            },
            'deepseek': {
              'model': 'deepseek-reasoner，deepseek-chat',
              'apiKey': 'sk-mt',
            },
          }),
          'asrPrompt': '设置里的提示',
          'translationGuidance': '设置里的要求',
        });
        settings = await AppSettings.load();
      });

      OpenAiCompatibleAsrProvider asr({
        AsrModelSpec model = _whisper,
        String prompt = '',
        List<GlossaryEntry> glossary = const [],
      }) =>
          Registry.buildAsr(
                'openai',
                settings,
                model: model,
                prompt: prompt,
                glossary: glossary,
              )
              as OpenAiCompatibleAsrProvider;

      OpenAiCompatibleTranslationProvider mt({
        ChatModelSpec model = _chat,
        String guidance = '',
        List<GlossaryEntry> glossary = const [],
      }) =>
          Registry.buildTranslation(
                'deepseek',
                settings,
                model: model,
                guidance: guidance,
                glossary: glossary,
              )
              as OpenAiCompatibleTranslationProvider;

      test('识别：声明里的模型与任务的提示词原样进实例，地址与密钥来自设置', () {
        final p = asr(
          model: const AsrModelSpec(
            name: 'gpt-4o-transcribe',
            transport: AsrTransport.openaiTranscription,
          ),
          prompt: '任务的提示',
        );
        expect(p.endpoint.model, 'gpt-4o-transcribe');
        expect(p.prompt, '任务的提示');
        expect(p.endpoint.baseUrl, 'https://proxy.example/v1');
        expect(p.endpoint.apiKey, 'sk-asr');
        // 任务里没有提示词就是不要提示词，不回头读设置里的那份。
        expect(asr().prompt, '');
      });

      test('识别：词表的原文拼在提示词前面', () {
        const glossary = [
          GlossaryEntry(term: 'Ollama'),
          GlossaryEntry(term: 'LM Studio', translation: '不发给识别'),
        ];
        expect(
          asr(prompt: '技术访谈', glossary: glossary).prompt,
          'Ollama, LM Studio\n技术访谈',
        );
        expect(asr(glossary: glossary).prompt, 'Ollama, LM Studio');
      });

      test('识别：温度没动过不发，调过就跟着声明走', () {
        expect(asr().temperature, isNull);
        expect(
          asr(
            model: _whisper.withOptions(
              ModelOptions.none.set(ModelParams.asrTemperature.key, 0.2),
            ),
          ).temperature,
          0.2,
        );
      });

      test('识别：声明的接入方式这家服务没有，报可行动的错', () {
        expect(
          () => asr(
            model: const AsrModelSpec(
              name: 'qwen3-asr-flash',
              transport: AsrTransport.dashscopeSync,
              dialect: DashScopeDialect.qwen3Asr,
            ),
          ),
          throwsA(
            isA<ActionableException>()
                .having((e) => e.message, 'message', contains('同步逐段'))
                .having((e) => e.hint, 'hint', contains('设置')),
          ),
        );
      });

      test('翻译：声明里的模型、任务的要求与词表原样进实例', () {
        const glossary = [GlossaryEntry(term: '百炼', translation: 'Bailian')];
        final p = mt(
          model: const ChatModelSpec(name: 'deepseek-chat'),
          guidance: '任务的要求',
          glossary: glossary,
        );
        expect(p.endpoint.model, 'deepseek-chat');
        expect(p.extraGuidance, '任务的要求');
        expect(p.glossary, glossary);
        expect(p.endpoint.baseUrl, 'https://api.deepseek.com/v1');
        expect(p.endpoint.apiKey, 'sk-mt');
        expect(mt().extraGuidance, '');
        expect(mt().glossary, isEmpty);
      });

      test('翻译：温度没动过是 0.3，选了不发送就是 null', () {
        expect(mt().temperature, 0.3);
        final key = ModelParams.chatTemperature.key;
        expect(
          mt(
            model: _chat.withOptions(ModelOptions.none.set(key, null)),
          ).temperature,
          isNull,
        );
        expect(
          mt(
            model: _chat.withOptions(ModelOptions.none.set(key, 1.2)),
          ).temperature,
          1.2,
        );
      });

      test('按服务 id 取默认模型：服务认不出来时是空名占位，不抛', () {
        expect(settings.defaultAsrModelOf('openai').name, 'my-whisper');
        expect(
          settings.defaultChatModelOf('deepseek').name,
          'deepseek-reasoner',
        );
        expect(settings.defaultAsrModelOf('不存在').isUnset, isTrue);
        expect(settings.defaultChatModelOf('不存在').isUnset, isTrue);
      });

      test('建好的实例不跟着之后的设置改动变', () {
        final recognizer = asr(
          model: settings.defaultAsrModelOf('openai'),
          prompt: '任务的提示',
        );
        final translator = mt(
          model: settings.defaultChatModelOf('deepseek'),
          guidance: '任务的要求',
        );

        settings
          ..asrPrompt = '后来改的提示'
          ..translationGuidance = '后来改的要求'
          ..setConfig('openai', const ProviderConfig(legacyModelText: 'later'))
          ..setConfig(
            'deepseek',
            const ProviderConfig(legacyModelText: 'later'),
          );

        expect(recognizer.prompt, '任务的提示');
        expect(recognizer.endpoint.model, 'my-whisper');
        expect(recognizer.endpoint.apiKey, 'sk-asr');
        expect(translator.extraGuidance, '任务的要求');
        expect(translator.endpoint.model, 'deepseek-reasoner');
      });
    });

    test('本地服务与在线服务走同一个实现类', () async {
      final settings = await _settings();
      expect(
        Registry.buildTranslation('ollama', settings, model: _chat),
        isA<OpenAiCompatibleTranslationProvider>(),
      );
      expect(
        Registry.buildTranslation('deepseek', settings, model: _chat),
        isA<OpenAiCompatibleTranslationProvider>(),
      );
    });
  });

  group('设置', () {
    test('用户填的值优先于默认值', () async {
      final settings = await _settings();
      final info = ProviderCatalog.translationInfo('deepseek')!;

      expect(_endpointOf(settings, info).model, 'deepseek-chat');

      settings.setConfig(
        'deepseek',
        const ProviderConfig(
          legacyModelText: 'deepseek-reasoner',
          apiKey: 'sk-x',
        ),
      );
      final endpoint = _endpointOf(settings, info);
      expect(endpoint.model, 'deepseek-reasoner');
      // 没填的字段仍然回落到默认值。
      expect(endpoint.baseUrl, 'https://api.deepseek.com/v1');
    });

    test('模型框用逗号写多个：第一个是默认，其余进候选', () async {
      final settings = await _settings();
      final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;

      // 没填时候选来自登记表。
      expect(_namesOf(settings, info), _presetNames(info));

      settings.setConfig(
        'dashscope_qwen_asr',
        const ProviderConfig(
          legacyModelText:
              ' qwen-audio-3.0-asr-flash ,fun-asr-flash，'
              'qwen-audio-3.0-asr-flash,, ',
          apiKey: 'sk-x',
        ),
      );
      expect(_namesOf(settings, info), [
        'qwen-audio-3.0-asr-flash',
        'fun-asr-flash',
      ]);
      expect(_endpointOf(settings, info).model, 'qwen-audio-3.0-asr-flash');

      // 只有逗号和空白等于没填。
      expect(
        const ProviderConfig(legacyModelText: ' , ，').legacyModelNames,
        isEmpty,
      );
      expect(const ProviderConfig().legacyModelNames, isEmpty);
    });

    // 真实用户的存档是 prefs 里的一段 JSON 字符串，不经过 setConfig。
    // 这几条直接预置那段字符串：改存储形状时，旧存档读出来的结果不能变。
    test('读旧存档：逗号串的第一个是默认模型，地址与密钥照用', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'dashscope_qwen_asr': {
            'model':
                ' qwen-audio-3.0-asr-flash-filetrans ,fun-asr-flash，'
                'qwen-audio-3.0-asr-flash-filetrans,, my-model ',
            'apiKey': 'sk-asr',
          },
          'deepseek': {
            'baseUrl': 'https://proxy.example/v1',
            'model': 'deepseek-reasoner，deepseek-chat',
          },
          // 只填了密钥：模型与地址回落到登记表。
          'openai': {'apiKey': 'sk-openai'},
        }),
      });
      final settings = await AppSettings.load();

      final dashscope = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      expect(_namesOf(settings, dashscope), [
        'qwen-audio-3.0-asr-flash-filetrans',
        'fun-asr-flash',
        'my-model',
      ]);
      final asr = _endpointOf(settings, dashscope);
      expect(asr.model, 'qwen-audio-3.0-asr-flash-filetrans');
      expect(asr.baseUrl, 'https://dashscope.aliyuncs.com/api/v1');
      expect(asr.apiKey, 'sk-asr');
      expect(settings.isConfigured(dashscope), isTrue);

      final deepseek = ProviderCatalog.translationInfo('deepseek')!;
      expect(_namesOf(settings, deepseek), [
        'deepseek-reasoner',
        'deepseek-chat',
      ]);
      final mt = _endpointOf(settings, deepseek);
      expect(mt.model, 'deepseek-reasoner');
      expect(mt.baseUrl, 'https://proxy.example/v1');
      expect(mt.apiKey, '');
      expect(settings.isConfigured(deepseek), isFalse);

      final openai = ProviderCatalog.asrInfo('openai')!;
      expect(_namesOf(settings, openai), _presetNames(openai));
      expect(_endpointOf(settings, openai).model, 'whisper-1');
      expect(settings.isConfigured(openai), isTrue);
    });

    test('读旧存档：模型只有逗号与空白等于没填', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'groq': {'model': ' , ，', 'apiKey': 'k'},
        }),
      });
      final settings = await AppSettings.load();
      final groq = ProviderCatalog.asrInfo('groq')!;

      expect(_namesOf(settings, groq), _presetNames(groq));
      expect(_endpointOf(settings, groq).model, 'whisper-large-v3');
    });

    test('旧存档的模型名读的时候补成声明，不写盘', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'dashscope_qwen_asr': {
            'model':
                'qwen-audio-3.0-asr-flash-filetrans, fun-asr-flash, '
                'my-model',
            'apiKey': 'sk-asr',
          },
          'deepseek': {'model': 'my-chat，deepseek-chat'},
        }),
      });
      final settings = await AppSettings.load();
      final dashscope = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      final deepseek = ProviderCatalog.translationInfo('deepseek')!;

      // 接入方式与报文族照重构前按名字判断的规则补：同一份存档，
      // 请求还是打到原来那个接口、用原来那种报文。
      expect(
        [
          for (final m in settings.asrModelsFor(dashscope))
            (m.name, m.transport, m.dialect),
        ],
        [
          (
            'qwen-audio-3.0-asr-flash-filetrans',
            AsrTransport.dashscopeFileTrans,
            DashScopeDialect.qwenAudio3,
          ),
          (
            'fun-asr-flash',
            AsrTransport.dashscopeSync,
            DashScopeDialect.funAsr,
          ),
          ('my-model', AsrTransport.dashscopeSync, DashScopeDialect.qwen3Asr),
        ],
      );
      expect(
        settings.defaultAsrModel(dashscope),
        same(dashscope.presets[3]),
      );
      expect(settings.chatModelsFor(deepseek), [
        const ChatModelSpec(name: 'my-chat'),
        const ChatModelSpec(name: 'deepseek-chat'),
      ]);
      expect(settings.defaultModel(deepseek).name, 'my-chat');

      // 读不改存档：那串文本原样留着，也没有多出 models。
      expect(
        settings.configFor('dashscope_qwen_asr').toJson().keys,
        unorderedEquals(['model', 'apiKey']),
      );
    });

    test('什么都没配：候选就是登记表的预置，没有预置时默认是空名占位', () async {
      final settings = await _settings();
      final openai = ProviderCatalog.asrInfo('openai')!;
      final custom = ProviderCatalog.asrInfo('asr_custom')!;
      final lmstudio = ProviderCatalog.translationInfo('lmstudio')!;

      expect(settings.asrModelsFor(openai), same(openai.presets));
      expect(settings.defaultAsrModel(openai), same(openai.presets.first));
      expect(settings.asrModelsFor(custom), isEmpty);
      expect(settings.defaultAsrModel(custom).isUnset, isTrue);
      expect(settings.defaultChatModel(lmstudio).isUnset, isTrue);
      expect(_endpointOf(settings, custom).model, '');
      expect(settings.isConfigured(lmstudio), isFalse);
    });

    test('用户自己配的模型：没配过是空的，预置不算；旧的那串名字算', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'deepseek': {'model': 'my-chat，deepseek-chat'},
          'groq': {'apiKey': 'sk-x'},
          'openai': {
            'models': [_whisper.toJson()],
          },
        }),
      });
      final settings = await AppSettings.load();
      final groq = ProviderCatalog.asrInfo('groq')!;

      // 设置页的模型列表编辑的是这一份：把预置当成用户的列出来，
      // 删光之后它们又会自己长回来。
      expect(settings.ownModels(groq), isEmpty);
      expect(settings.asrModelsFor(groq), same(groq.presets));
      expect(settings.ownModels(ProviderCatalog.asrInfo('openai')!), [
        _whisper,
      ]);
      expect(
        settings.ownModels(ProviderCatalog.translationInfo('deepseek')!),
        const [
          ChatModelSpec(name: 'my-chat'),
          ChatModelSpec(name: 'deepseek-chat'),
        ],
      );

      // 删光：回到「没配过」，候选重新来自预置。
      settings.setModels('openai', const []);
      final openai = ProviderCatalog.asrInfo('openai')!;
      expect(settings.ownModels(openai), isEmpty);
      expect(settings.asrModelsFor(openai), same(openai.presets));
    });

    test('加模型：列表空着时先把常用模型落进来，默认模型不变', () async {
      final settings = await _settings();
      final groq = ProviderCatalog.asrInfo('groq')!;
      const custom = AsrModelSpec(
        name: 'my-whisper',
        transport: AsrTransport.openaiTranscription,
      );

      // 只存新加的那个的话，默认模型会被换成它，其余常用的也从新建任务
      // 的下拉里消失。
      settings.addModel(groq, custom);
      expect(settings.ownModels(groq), [...groq.presets, custom]);
      expect(settings.defaultAsrModel(groq), groq.presets.first);

      // 加的就是常用里的某一个：落进来的列表里已经有它，不重复。
      final other = await _settings();
      other.addModel(groq, groq.presets[1]);
      expect(other.ownModels(groq), groq.presets);

      // 没有常用模型的服务：列表里就是加的这一个。
      final customInfo = ProviderCatalog.asrInfo('asr_custom')!;
      settings.addModel(customInfo, custom);
      expect(settings.ownModels(customInfo), [custom]);
    });

    test('加模型：已有列表时加在末尾，同名的就地换掉', () async {
      final settings = await _settings();
      final dashscope = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      const a = AsrModelSpec(
        name: 'a',
        transport: AsrTransport.dashscopeSync,
        dialect: DashScopeDialect.qwen3Asr,
      );
      const b = AsrModelSpec(
        name: 'b',
        transport: AsrTransport.dashscopeSync,
        dialect: DashScopeDialect.funAsr,
      );
      const aAsync = AsrModelSpec(
        name: 'a',
        transport: AsrTransport.dashscopeFileTrans,
        dialect: DashScopeDialect.qwenAudio3,
      );
      settings.setModels(dashscope.id, const [a]);

      settings.addModel(dashscope, b);
      expect(settings.ownModels(dashscope), const [a, b]);
      settings.addModel(dashscope, aAsync);
      expect(settings.ownModels(dashscope), const [aAsync, b]);
    });

    test('设为默认、删除、改参数：按名字认行，读的是此刻的列表', () async {
      final settings = await _settings();
      final deepseek = ProviderCatalog.translationInfo('deepseek')!;
      const a = ChatModelSpec(name: 'a');
      const b = ChatModelSpec(name: 'b');
      const c = ChatModelSpec(name: 'c');
      settings.setModels(deepseek.id, const [a, b, c]);

      settings.setModelOption(deepseek, 'a', 'temperature', 0.9);
      settings.setDefaultModel(deepseek, 'c');
      expect([for (final m in settings.ownModels(deepseek)) m.name], [
        'c',
        'a',
        'b',
      ]);
      // 前一步改的参数还在：每一步都是在上一步的结果上算的。
      expect(
        settings.ownModels(deepseek)[1].options.number(
          ModelParams.chatTemperature,
        ),
        0.9,
      );

      settings.removeModel(deepseek, 'c');
      expect(settings.defaultChatModel(deepseek).name, 'a');
      // 改回默认值等于没动过。
      settings.setModelOption(deepseek, 'a', 'temperature', 0.3);
      expect(settings.ownModels(deepseek), const [a, b]);

      // 列表里没有的名字：什么都不变。
      var notified = 0;
      settings.addListener(() => notified++);
      settings.setDefaultModel(deepseek, '不存在');
      expect(notified, 0);
      settings
        ..removeModel(deepseek, '不存在')
        ..setModelOption(deepseek, '不存在', 'temperature', 1.0);
      expect(settings.ownModels(deepseek), const [a, b]);

      // 删光：回到「没配过」。
      settings
        ..removeModel(deepseek, 'a')
        ..removeModel(deepseek, 'b');
      expect(settings.ownModels(deepseek), isEmpty);
      expect(settings.chatModelsFor(deepseek), same(deepseek.presets));
    });

    test('改别的字段不丢旧存档里的模型名', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'openai': {'model': 'my-whisper', 'apiKey': 'old'},
        }),
      });
      final settings = await AppSettings.load();
      settings.setConfig(
        'openai',
        settings.configFor('openai').copyWith(apiKey: 'new'),
      );

      final reloaded = await AppSettings.load();
      final openai = ProviderCatalog.asrInfo('openai')!;
      expect(_endpointOf(reloaded, openai).model, 'my-whisper');
      expect(_endpointOf(reloaded, openai).apiKey, 'new');
    });

    test('存模型列表：第一个是默认，参数一起落盘，旧的那串模型名不再用', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'dashscope_qwen_asr': {
            'baseUrl': 'https://proxy.example/api/v1',
            'model': 'old-model',
            'apiKey': 'sk-asr',
          },
        }),
      });
      final settings = await AppSettings.load();
      final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      const custom = AsrModelSpec(
        name: 'my-model',
        transport: AsrTransport.dashscopeFileTrans,
        dialect: DashScopeDialect.funAsr,
      );
      final tuned = info.presets.first.withOptions(
        ModelOptions.none.set(ModelParams.enableItn.key, false),
      );

      var notified = 0;
      settings.addListener(() => notified++);
      settings.setModels(info.id, [custom, tuned]);
      expect(notified, 1);

      for (final s in [settings, await AppSettings.load()]) {
        expect(s.asrModelsFor(info), [custom, tuned]);
        expect(s.defaultAsrModel(info), custom);
        // 自填的名字不合任何命名规律，接入方式照声明来。
        expect(
          s.defaultAsrModel(info).transport,
          AsrTransport.dashscopeFileTrans,
        );
        final endpoint = _endpointOf(s, info);
        expect(endpoint.model, 'my-model');
        expect(endpoint.baseUrl, 'https://proxy.example/api/v1');
        expect(endpoint.apiKey, 'sk-asr');
        expect(_namesOf(s, info), ['my-model', 'qwen3-asr-flash']);
        final config = s.configFor(info.id);
        expect(config.legacyModelText, isNull);
        expect(config.toJson().keys, isNot(contains('model')));
      }
    });

    test('读模型列表：读不出来的那条丢掉，种类不对的不算数', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'openai': {
            'models': [
              'x',
              {'kind': '不认识', 'name': 'a'},
              const ChatModelSpec(name: '翻译模型放错了地方').toJson(),
              _whisper.toJson(),
            ],
          },
          // 列表里一条能用的都没有：当成没配过，回落到预置。
          'groq': {
            'models': [
              {'kind': 'asr'},
            ],
          },
          'deepseek': {'models': '不是列表', 'model': 'fallback-chat'},
          // 存档被手改出重名：只留前一个。界面按名字认行，两个同名的
          // 会让设置页起不来。
          'openai_chat': {
            'models': [
              const ChatModelSpec(name: 'gpt-4o').toJson(),
              const ChatModelSpec(
                name: 'gpt-4o',
                options: ModelOptions({'temperature': 1.0}),
              ).toJson(),
              const ChatModelSpec(name: 'gpt-4o-mini').toJson(),
            ],
          },
        }),
      });
      final settings = await AppSettings.load();
      expect(
        settings.chatModelsFor(
          ProviderCatalog.translationInfo('openai_chat')!,
        ),
        const [
          ChatModelSpec(name: 'gpt-4o'),
          ChatModelSpec(name: 'gpt-4o-mini'),
        ],
      );

      expect(settings.asrModelsFor(ProviderCatalog.asrInfo('openai')!), [
        _whisper,
      ]);
      final groq = ProviderCatalog.asrInfo('groq')!;
      expect(settings.asrModelsFor(groq), same(groq.presets));
      expect(
        settings
            .defaultChatModel(ProviderCatalog.translationInfo('deepseek')!)
            .name,
        'fallback-chat',
      );
    });

    test('存档损坏时回到默认值，不让应用起不来', () async {
      for (final broken in [
        '{不是 JSON',
        '[]',
        // 有一条不是对象：整份作废，不猜哪几条还能用。
        jsonEncode({
          'openai': 'whisper-1',
          'groq': {'apiKey': 'k'},
        }),
      ]) {
        SharedPreferences.setMockInitialValues({'providerConfigs': broken});
        final settings = await AppSettings.load();

        expect(settings.configFor('groq').apiKey, isNull, reason: broken);
        expect(
          _endpointOf(settings, ProviderCatalog.asrInfo('openai')!).model,
          'whisper-1',
          reason: broken,
        );
      }
    });

    test('恢复识别分区的默认：清掉识别侧的配置与提示词，翻译侧不动', () async {
      SharedPreferences.setMockInitialValues({
        'providerConfigs': jsonEncode({
          'openai': {'model': 'gpt-4o-transcribe', 'apiKey': 'sk-asr'},
          'deepseek': {'model': 'deepseek-reasoner', 'apiKey': 'sk-mt'},
        }),
        'asrProviderId': 'groq',
        'asrPrompt': '专有名词',
        'translationProviderId': 'ollama',
        'translationGuidance': '口语化',
      });
      final settings = await AppSettings.load();

      settings.reset(
        SettingsGroup.asr,
        providerIds: ProviderCatalog.asr.map((p) => p.id),
      );

      expect(settings.asrProviderId, 'openai');
      expect(settings.asrPrompt, '');
      expect(settings.configFor('openai').apiKey, isNull);
      expect(
        _endpointOf(settings, ProviderCatalog.asrInfo('openai')!).model,
        'whisper-1',
      );

      expect(settings.translationProviderId, 'ollama');
      expect(settings.translationGuidance, '口语化');
      expect(settings.configFor('deepseek').apiKey, 'sk-mt');

      // 落盘的那份也只剩翻译侧，重启后不会又读回来。
      final reloaded = await AppSettings.load();
      expect(reloaded.configFor('openai').apiKey, isNull);
      expect(
        _endpointOf(
          reloaded,
          ProviderCatalog.translationInfo('deepseek')!,
        ).model,
        'deepseek-reasoner',
      );
    });

    test('缺密钥时算未配置，本地服务不需要密钥', () async {
      final settings = await _settings();
      expect(
        settings.isConfigured(ProviderCatalog.translationInfo('deepseek')!),
        isFalse,
      );
      expect(
        settings.isConfigured(ProviderCatalog.translationInfo('ollama')!),
        isTrue,
      );
    });

    test('每批条数被夹在合理区间', () async {
      final settings = await _settings();
      settings.translationBatchSize = 9999;
      expect(settings.translationBatchSize, 100);
      settings.translationBatchSize = 0;
      expect(settings.translationBatchSize, 1);
    });
  });

  group('Endpoint', () {
    test('容忍 baseUrl 结尾的斜杠', () {
      const a = Endpoint(baseUrl: 'https://x/v1/', model: 'm');
      const b = Endpoint(baseUrl: 'https://x/v1', model: 'm');
      expect(a.resolve('/chat/completions'), b.resolve('/chat/completions'));
    });

    test('没有密钥时不发 Authorization 头', () {
      expect(const Endpoint(baseUrl: 'x', model: 'm').authHeaders, isEmpty);
    });
  });
}
