import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    Future<Map<String, Object?>> sentBody({String? guidance}) async {
      late http.Request sent;
      final provider = OpenAiCompatibleTranslationProvider(
        info: _info,
        endpoint: _endpoint,
        extraGuidance: guidance,
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
      expect(sent.headers['content-type'], 'application/json; charset=utf-8');
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

    test('补充要求只在填了的时候进系统提示，位置在「示例」之前', () async {
      String systemOf(Map<String, Object?> body) =>
          ((body['messages']! as List).first as Map)['content'] as String;
      List<String> headings(String prompt) => [
        for (final line in prompt.split('\n'))
          if (line.startsWith('# ')) line,
      ];

      final plain = systemOf(await sentBody());
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
        () => Registry.buildAsr('local_backend', settings),
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
        () => Registry.buildTranslation('不存在', settings),
        throwsA(isA<ActionableException>()),
      );
    });

    test('本地服务与在线服务走同一个实现类', () async {
      final settings = await _settings();
      expect(
        Registry.buildTranslation('ollama', settings),
        isA<OpenAiCompatibleTranslationProvider>(),
      );
      expect(
        Registry.buildTranslation('deepseek', settings),
        isA<OpenAiCompatibleTranslationProvider>(),
      );
    });
  });

  group('设置', () {
    test('用户填的值优先于默认值', () async {
      final settings = await _settings();
      final info = ProviderCatalog.translationInfo('deepseek')!;

      expect(settings.endpointFor(info).model, 'deepseek-chat');

      settings.setConfig(
        'deepseek',
        const ProviderConfig(model: 'deepseek-reasoner', apiKey: 'sk-x'),
      );
      final endpoint = settings.endpointFor(info);
      expect(endpoint.model, 'deepseek-reasoner');
      // 没填的字段仍然回落到默认值。
      expect(endpoint.baseUrl, 'https://api.deepseek.com/v1');
    });

    test('模型框用逗号写多个：第一个是默认，其余进候选', () async {
      final settings = await _settings();
      final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;

      // 没填时候选来自登记表。
      expect(settings.modelsFor(info), info.models);

      settings.setConfig(
        'dashscope_qwen_asr',
        const ProviderConfig(
          model: ' qwen-audio-3.0-asr-flash ,fun-asr-flash，qwen-audio-3.0-asr-flash,, ',
          apiKey: 'sk-x',
        ),
      );
      expect(settings.modelsFor(info), [
        'qwen-audio-3.0-asr-flash',
        'fun-asr-flash',
      ]);
      expect(settings.endpointFor(info).model, 'qwen-audio-3.0-asr-flash');

      // 只有逗号和空白等于没填。
      expect(ProviderConfig.splitModels(' , ，'), isEmpty);
      expect(ProviderConfig.splitModels(null), isEmpty);
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
      expect(settings.modelsFor(dashscope), [
        'qwen-audio-3.0-asr-flash-filetrans',
        'fun-asr-flash',
        'my-model',
      ]);
      final asr = settings.endpointFor(dashscope);
      expect(asr.model, 'qwen-audio-3.0-asr-flash-filetrans');
      expect(asr.baseUrl, 'https://dashscope.aliyuncs.com/api/v1');
      expect(asr.apiKey, 'sk-asr');
      expect(settings.isConfigured(dashscope), isTrue);

      final deepseek = ProviderCatalog.translationInfo('deepseek')!;
      expect(settings.modelsFor(deepseek), [
        'deepseek-reasoner',
        'deepseek-chat',
      ]);
      final mt = settings.endpointFor(deepseek);
      expect(mt.model, 'deepseek-reasoner');
      expect(mt.baseUrl, 'https://proxy.example/v1');
      expect(mt.apiKey, '');
      expect(settings.isConfigured(deepseek), isFalse);

      final openai = ProviderCatalog.asrInfo('openai')!;
      expect(settings.modelsFor(openai), openai.models);
      expect(settings.endpointFor(openai).model, 'whisper-1');
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

      expect(settings.modelsFor(groq), groq.models);
      expect(settings.endpointFor(groq).model, 'whisper-large-v3');
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
          settings.endpointFor(ProviderCatalog.asrInfo('openai')!).model,
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
      expect(settings.endpointFor(ProviderCatalog.asrInfo('openai')!).model, 'whisper-1');

      expect(settings.translationProviderId, 'ollama');
      expect(settings.translationGuidance, '口语化');
      expect(settings.configFor('deepseek').apiKey, 'sk-mt');

      // 落盘的那份也只剩翻译侧，重启后不会又读回来。
      final reloaded = await AppSettings.load();
      expect(reloaded.configFor('openai').apiKey, isNull);
      expect(
        reloaded.endpointFor(ProviderCatalog.translationInfo('deepseek')!).model,
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
