import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/translation_protocol.dart';

const _info = ProviderInfo(
  id: 'test',
  name: '测试',
  vendor: '测试服务',
  defaultBaseUrl: 'https://example.invalid/v1',
  defaultModel: 'm',
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
          isA<ProviderException>().having(
            (e) => e.message,
            'message',
            contains('条数对不上'),
          ),
        ),
      );
    });

    test('401 给出核对密钥的建议', () async {
      final provider = build(
        MockClient((_) async => http.Response('no', 401)),
      );
      expect(
        () => provider.translateBatch(
          lines: ['a'],
          sourceLanguage: '中文',
          targetLanguage: '英文',
          token: CancellationToken(),
        ),
        throwsA(
          isA<ProviderException>()
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
          isA<ProviderException>()
              .having((e) => e.message, 'message', contains('尚未实施'))
              .having((e) => e.hint, 'hint', contains('OpenAI')),
        ),
      );
    });

    test('未知 id 也报可行动的错', () async {
      final settings = await _settings();
      expect(
        () => Registry.buildTranslation('不存在', settings),
        throwsA(isA<ProviderException>()),
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
      final info = Registry.translationInfo('deepseek')!;

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

    test('缺密钥时算未配置，本地服务不需要密钥', () async {
      final settings = await _settings();
      expect(settings.isConfigured(Registry.translationInfo('deepseek')!), isFalse);
      expect(settings.isConfigured(Registry.translationInfo('ollama')!), isTrue);
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
