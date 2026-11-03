import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/chat_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/translation_wire.dart';

const _model = ChatModelSpec(name: 'gpt-6.1-sol',
  transport: ChatTransport.responses, dialect: ChatDialect.openaiReasoning);

Map<String, Object?> _message(String text) => {
  'type': 'message', 'role': 'assistant', 'status': 'completed',
  'content': [{'type': 'output_text', 'text': text}],
};

Map<String, Object?> _reply() => {'status': 'completed', 'output': [
  {'type': 'reasoning', 'content': [{'type': 'reasoning_text', 'text': '不是字幕'}]},
  _message('§1§ Hello'), _message('§2§ World'),
]};

Future<List<String>> _translate(Map<String, Object?> reply,
    {void Function(http.Request)? inspect, ChatModelSpec model = _model}) {
  final provider = OpenAiCompatibleTranslationProvider(
    info: ProviderCatalog.translationInfo('openai_chat')!, model: model,
    endpoint: Endpoint(baseUrl: 'https://example.com/v1', model: model.name, apiKey: 'test-key'),
    extraGuidance: '简洁', glossary: const [GlossaryEntry(term: '世界', translation: 'World')],
    client: MockClient((request) async {
      inspect?.call(request);
      return http.Response(jsonEncode(reply), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return provider.translateBatch(lines: ['你好', '世界'], sourceLanguage: '中文',
    targetLanguage: '英文', token: CancellationToken());
}

void main() {
  test('Responses 发送独立批次与完整提示，仅提取正文', () async {
    expect(await _translate(_reply(), inspect: (request) {
      expect(request.url.path, '/v1/responses');
      expect(request.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map;
      expect(body['model'], 'gpt-6.1-sol');
      expect(body['reasoning'], {'effort': 'low'});
      expect(body['store'], false);
      expect(body.containsKey('temperature'), false);
      expect(body.containsKey('messages'), false);
      expect(body['instructions'], allOf(contains('翻译成英文'), contains('世界 → World'), contains('简洁')));
      expect(body['input'], '<INPUT>\n§1§ 你好\n§2§ 世界\n</INPUT>');
    }), ['Hello', 'World']);
  });

  test('Responses 截断即使行数正确也不接收，允许减半', () async {
    final reply = _reply()..['status'] = 'incomplete'
      ..['incomplete_details'] = {'reason': 'max_output_tokens'};
    await expectLater(_translate(reply), throwsA(isA<ActionableException>()
      .having((e) => e.batchTooLarge, '减半', true)));
  });

  test('Responses 失败、运行中、缺终态及拒答不作为译文或降批重试', () async {
    for (final reply in [
      {..._reply(), 'status': 'failed', 'error': {'message': 'bad'}},
      {..._reply(), 'status': 'in_progress'},
      {..._reply()}..remove('status'),
      {'status': 'completed', 'output': [{..._message('§1§ Hello\n§2§ World'),
        'content': [{'type': 'refusal', 'refusal': 'no'}]}]},
    ]) {
      await expectLater(_translate(reply), throwsA(isA<ActionableException>()
        .having((e) => e.batchTooLarge, '不减半', false)));
    }
  });

  test('Responses 缺行和重复行沿用字幕降批协议', () async {
    for (final text in ['§1§ Hello', '§1§ Hello\n§1§ World']) {
      await expectLater(_translate({'status': 'completed', 'output': [_message(text)]}),
        throwsA(isA<ActionableException>().having((e) => e.batchTooLarge, '减半', true)));
    }
  });

  test('DeepSeek 两种协议按声明转换思考字段，不向通用网关泄漏', () {
    Map<String, Object?> request(ChatModelSpec model) => TranslationWire.request(
      model: model, modelName: model.name, instructions: '翻译', input: 'hi',
      temperature: model.temperature);
    final deepseek = ProviderCatalog.translationInfo('deepseek')!.presets.first;
    final thinking = request(deepseek);
    expect(thinking['thinking'], {'type': 'enabled'});
    expect(thinking['reasoning_effort'], 'low');
    expect(thinking.containsKey('temperature'), false);
    final off = deepseek.withOption('reasoningEffort', 'off');
    expect(request(off)['thinking'], {'type': 'disabled'});
    expect(request(off)['temperature'], 0.3);
    expect(request(off).containsKey('reasoning_effort'), false);
    final responses = request(off.withDeclaration(ChatTransport.responses, ChatDialect.deepseek));
    expect(responses['reasoning'], {'effort': 'none'});
    expect(responses.containsKey('thinking'), false);
    expect(responses.containsKey('store'), false);
    final generic = request(const ChatModelSpec(name: 'deepseek-flash'));
    expect(generic.containsKey('thinking'), false);
    expect(generic.containsKey('reasoning_effort'), false);
  });

  test('Chat Completions 的截断和拒答不会接受等长部分正文', () {
    for (final reason in ['length', 'content_filter', 'tool_calls']) {
      expect(() => TranslationWire.content({'choices': [{
        'finish_reason': reason, 'message': {'content': '§1§ Hello\n§2§ World'},
      }]}, ChatTransport.completions), throwsA(isA<ActionableException>()));
    }
  });

  test('旧声明保留原协议，新声明设置持久化且工厂采用同一份声明', () async {
    final old = ChatModelSpec.fromJson({'name': 'gpt-6.1-sol'})!;
    expect(old.transport, ChatTransport.completions);
    expect(old.dialect, ChatDialect.generic);
    expect(ProviderCatalog.legacyChatSpec('openai_chat', old.name), old);
    expect(ChatModelSpec.fromJson({..._model.toJson(), 'transport': 'unknown'}), isNull);
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final configured = _model.withOption('reasoningEffort', 'high');
    settings.setModels('openai_chat', [configured]);
    final loaded = await AppSettings.load();
    expect(loaded.defaultChatModelOf('openai_chat'), configured);
    final provider = Registry.buildTranslation('openai_chat', loaded, model: configured)
        as OpenAiCompatibleTranslationProvider;
    expect(provider.model, configured);
    expect(provider.temperature, isNull);
    settings.dispose();
    loaded.dispose();
  });

  test('硅基流动翻译禁用但保留目录，识别不受本次影响', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(ProviderCatalog.translationInfo('siliconflow_chat')!.available, false);
    expect(() => Registry.buildTranslation('siliconflow_chat', settings, model: _model),
      throwsA(isA<ActionableException>()));
    settings.dispose();
  });
}
