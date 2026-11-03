import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subtitle_studio/domain/providers/chat_capabilities.dart';
import 'package:subtitle_studio/domain/providers/chat_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/translation_budget.dart';
import 'package:subtitle_studio/services/translation_wire.dart';

ChatModelSpec _preset(String name) => ProviderCatalog.translationInfo('openai_chat')!
    .presets.firstWhere((m) => m.name == name);
Map<String, Object?> _request(ChatModelSpec model) => TranslationWire.request(
  model: model, modelName: model.name, instructions: '翻译', input: 'hello',
  temperature: model.temperature);

void main() {
  test('GPT 按型号允许 none，声明和请求往返保留关闭意图', () {
    for (final model in ProviderCatalog.translationInfo('openai_chat')!.presets) {
      final required = {'gpt-6-astra', 'gpt-6.1-sol'}.contains(model.name);
      if (required) {
        expect(() => model.withOption('reasoningEffort', 'none'), throwsArgumentError);
      } else {
        final off = model.withOption('reasoningEffort', 'none');
        expect(ChatModelSpec.fromJson(jsonDecode(jsonEncode(off.toJson()))), off);
        expect(_request(off)['reasoning'], {'effort': 'none'});
        expect(_request(off)['temperature'], 0.3);
        final chat = off.withDeclaration(ChatTransport.completions, off.dialect);
        expect(_request(chat)['reasoning_effort'], 'none');
        expect(chat.capabilities, off.capabilities);
      }
      for (final effort in model.capabilities!.efforts.where((e) => e != 'none')) {
        final thinking = _request(model.withOption('reasoningEffort', effort));
        expect(thinking['reasoning'], {'effort': effort});
        expect(thinking.containsKey('temperature'), false);
      }
    }
  });

  test('能力数值按官方精确值保存，输出字段按协议与画像分派', () {
    final gpt = _preset('gpt-6.1-terra');
    expect(gpt.contextTokenLimit, 1050000);
    expect(gpt.capabilities!.maxOutputTokens, 128000);
    expect(_request(gpt)['max_output_tokens'], 32768);
    final chat = gpt.withDeclaration(ChatTransport.completions, gpt.dialect);
    expect(_request(chat)['max_completion_tokens'], 32768);
    expect(_request(chat).containsKey('max_tokens'), false);
    final deep = ProviderCatalog.translationInfo('deepseek')!.presets.first;
    expect(deep.contextTokenLimit, 1048576);
    expect(deep.capabilities!.maxOutputTokens, 393216);
    expect(_request(deep)['max_tokens'], 32768);
    expect(_request(deep.withDeclaration(ChatTransport.responses, deep.dialect))['max_output_tokens'], 32768);
    expect(_request(gpt.withOption('outputTokens', null)).containsKey('max_output_tokens'), false);
    expect(gpt.withOption('outputTokens', 999999).outputTokenLimit, 128000);
    expect(gpt.withOption('contextWindow', 9999999).contextTokenLimit, 1050000);
  });

  test('旧声明不自动增加预算，同名自定义网关不继承官方能力', () {
    final legacy = ChatModelSpec.fromJson({'name': 'gpt-6.1-terra',
      'dialect': 'openaiReasoning', 'transport': 'responses'})!;
    expect(legacy.capabilities, isNull);
    expect(legacy.contextTokenLimit, isNull);
    expect(legacy.outputTokenLimit, isNull);
    const generic = ChatModelSpec(name: 'gpt-6.1-terra');
    expect(_request(generic).containsKey('max_tokens'), false);
    final custom = generic.withOption('contextWindow', 8192).withOption('outputTokens', 1024);
    expect(ChatModelSpec.fromJson(custom.toJson()), custom);
    expect(_request(custom)['max_tokens'], 1024);
  });

  test('预检保留输出空间，计入中文、固定提示与包装开销，边界允许恰好装下', () {
    final model = const ChatModelSpec(name: 'test')
        .withOption('contextWindow', 4096).withOption('outputTokens', 1024);
    // 固定提示 3 字节 + 256 协议余量 + 2813 字节输入 + 1024 输出 = 4096。
    expect(() => TranslationBudget.check(model, '中', 'a' * 2813), returnsNormally);
    expect(() => TranslationBudget.check(model, '中', 'a' * 2814),
      throwsA(isA<ActionableException>().having((e) => e.batchTooLarge, '降批', true)));
    expect(() => TranslationBudget.check(model, '中' * 1024, 'a'),
      throwsA(isA<ActionableException>().having((e) => e.batchTooLarge, '固定提示不降批', false)));
    final noSpace = model.withOption('outputTokens', 4096);
    expect(() => TranslationBudget.check(noSpace, '', 'a'), throwsA(isA<ActionableException>()));
    const unknown = ChatModelSpec(name: 'test');
    expect(() => TranslationBudget.check(unknown, '', 'a' * 99999), returnsNormally);
  });

  test('损坏的能力、跨厂商 effort 不得静默通过', () {
    final gpt = _preset('gpt-6.1-terra');
    for (final caps in [
      {...gpt.capabilities!.toJson(), 'efforts': ['ultra']},
      {...gpt.capabilities!.toJson(), 'defaultEffort': 'unknown'},
      {...gpt.capabilities!.toJson(), 'contextWindow': -1},
      {...gpt.capabilities!.toJson(), 'defaultOutputTokens': 999999},
      ChatCapabilities.deepseek.toJson(),
    ]) {
      expect(ChatModelSpec.fromJson({...gpt.toJson(), 'capabilities': caps}), isNull);
    }
  });

  test('只有明确超窗错误才降批，普通 400、401、429 不重试', () async {
    for (final (status, error, retry) in [
      (400, {'code': 'context_length_exceeded'}, true),
      (400, {'message': "This model's maximum context length is 8192 tokens"}, true),
      (422, {'message': 'Input exceeds the context window'}, true),
      (200, {'code': 'context_length_exceeded'}, true),
      (400, {'message': 'Invalid reasoning effort'}, false),
      (400, {'message': 'context window parameter is unsupported'}, false),
      (401, {'code': 'context_length_exceeded'}, false),
      (429, {'message': 'rate limit'}, false),
    ]) {
      final provider = OpenAiCompatibleTranslationProvider(
        info: ProviderCatalog.translationInfo('openai_chat')!,
        endpoint: const Endpoint(baseUrl: 'https://test/v1', model: 'test'),
        client: MockClient((_) async => http.Response(jsonEncode({'error': error}), status)));
      await expectLater(provider.translateBatch(lines: ['a', 'b'], sourceLanguage: 'en',
        targetLanguage: 'zh', token: CancellationToken()),
        throwsA(isA<ActionableException>().having((e) => e.batchTooLarge, '$status $error', retry)));
    }
  });

  test('预检拦截超长批次时不发 HTTP 请求', () async {
    var requests = 0;
    final model = const ChatModelSpec(name: 'test')
        .withOption('contextWindow', 4096).withOption('outputTokens', 512);
    final provider = OpenAiCompatibleTranslationProvider(
      info: ProviderCatalog.translationInfo('openai_chat')!, model: model,
      endpoint: const Endpoint(baseUrl: 'https://test/v1', model: 'test'),
      client: MockClient((_) async { requests++; return http.Response('{}', 200); }));
    await expectLater(provider.translateBatch(lines: ['a' * 6000], sourceLanguage: 'en',
      targetLanguage: 'zh', token: CancellationToken()), throwsA(isA<ActionableException>()));
    expect(requests, 0);
  });
}
