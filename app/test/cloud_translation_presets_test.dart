import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/providers/chat_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/translation_wire.dart';

import 'helpers.dart';

const _routes = {
  'volcengine_api': 'https://ark.cn-beijing.volces.com/api/v3',
  'volcengine_coding_plan': 'https://ark.cn-beijing.volces.com/api/coding/v3',
  'volcengine_agent_plan': 'https://ark.cn-beijing.volces.com/api/plan/v3',
  'bailian_api': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  'bailian_plan': 'https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1',
};

Map<String, Object?> _request(ChatModelSpec model) => TranslationWire.request(
  model: model, modelName: model.name, instructions: '翻译', input: '§1§ 你好',
  temperature: model.temperature);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('五条线路各自保存凭证、地址与模型，重载后不串配置', () async {
    final settings = await AppSettings.load();
    for (final entry in _routes.entries) {
      final info = ProviderCatalog.translationInfo(entry.key)!;
      final model = info.presets.last.withOption('outputTokens', 8192);
      expect(settings.endpointFor(info, model).baseUrl, entry.value);
      settings.setConfig(info.id, ProviderConfig(apiKey: 'test-${info.id}',
        baseUrl: '${entry.value}/proxy', models: [model]));
    }
    final loaded = await AppSettings.load();
    for (final entry in _routes.entries) {
      final info = ProviderCatalog.translationInfo(entry.key)!;
      final model = loaded.defaultChatModel(info);
      final endpoint = loaded.endpointFor(info, model);
      expect(endpoint.apiKey, 'test-${info.id}');
      expect(endpoint.baseUrl, '${entry.value}/proxy');
      expect(model, info.presets.last.withOption('outputTokens', 8192));
    }
  });

  for (final entry in _routes.entries) {
    test('${entry.key} 发往专属地址并沿用字幕行号协议', () async {
      final settings = await AppSettings.load();
      final info = ProviderCatalog.translationInfo(entry.key)!;
      settings.setConfig(info.id, const ProviderConfig(apiKey: 'test-key'));
      final model = settings.defaultChatModel(info);
      final provider = OpenAiCompatibleTranslationProvider(
        info: info, model: model, endpoint: settings.endpointFor(info, model),
        temperature: model.temperature,
        client: MockClient((request) async {
          expect(request.url.toString(), '${entry.value}/chat/completions');
          expect(request.headers['Authorization'], 'Bearer test-key');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], model.name);
          expect(body['max_completion_tokens'], 32768);
          expect(body.containsKey('max_tokens'), false);
          expect(body['temperature'], 0.3);
          if (entry.key.startsWith('bailian')) {
            expect(body['enable_thinking'], false);
            expect(body.containsKey('thinking'), false);
          } else {
            expect(body['thinking'], {'type': 'disabled'});
            expect(body.containsKey('enable_thinking'), false);
          }
          expect(body.containsKey('reasoning_effort'), false);
          final messages = body['messages'] as List;
          expect((messages[1] as Map)['content'], contains('§1§ 你好'));
          return http.Response(jsonEncode({'choices': [{
            'finish_reason': 'stop', 'message': {
              'content': '§1§ Hello', 'reasoning_content': '不要进入译文',
            },
          }]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      expect(await provider.translateBatch(lines: ['你好'], sourceLanguage: '中文',
        targetLanguage: '英文', token: CancellationToken()), ['Hello']);
    });

    test('${entry.key} 模型与档位随任务存档，不继承后续目录修改', () {
      final info = ProviderCatalog.translationInfo(entry.key)!;
      for (final preset in info.presets) {
        for (final effort in preset.capabilities!.efforts) {
          final model = preset.withOption('reasoningEffort', effort)
              .withOption('contextWindow', 64000).withOption('outputTokens', 8000);
          final task = SubtitleTask(id: 'snapshot', sourcePath: '/v/a.srt',
            kind: TaskKind.translate,
            options: testOptions(mt: info.id).copyWith(translationModel: model));
          final loaded = SubtitleTask.fromJson(
            (jsonDecode(jsonEncode(task.toJson())) as Map).cast<String, Object?>(),
            fallbackOptions: testOptions());
          expect(loaded.options.translationProviderId, info.id);
          expect(loaded.options.translationModel, model);
        }
      }
    });
  }

  test('Qwen 3.8 使用原生档位，3.7 只发送思考开关', () {
    final info = ProviderCatalog.translationInfo('bailian_api')!;
    for (final model in info.presets) {
      for (final effort in model.capabilities!.efforts) {
        final body = _request(model.withOption('reasoningEffort', effort));
        expect(body['enable_thinking'], effort != 'off');
        expect(body.containsKey('temperature'), effort == 'off');
        if (effort == 'off' || effort == 'on') {
          expect(body.containsKey('reasoning_effort'), false);
        } else {
          expect(body['reasoning_effort'], effort);
        }
        expect(body.containsKey('thinking_budget'), false);
      }
      expect(() => model.withOption('reasoningEffort', 'max'), throwsArgumentError);
    }
  });

  test('豆包两种协议正确发送关闭与各档思考，不携带冲突参数', () {
    final preset = ProviderCatalog.defaultChatSpec('volcengine_agent_plan');
    for (final transport in ChatTransport.values) {
      for (final effort in preset.capabilities!.efforts) {
        final model = preset.withDeclaration(transport, preset.dialect)
            .withOption('reasoningEffort', effort);
        final body = _request(model);
        expect(body.containsKey('temperature'), effort == 'off');
        if (transport == ChatTransport.responses) {
          expect(body['reasoning'], {'effort': effort == 'off' ? 'none' : effort});
          expect(body['max_output_tokens'], 32768);
          expect(body['store'], false);
          expect(body.containsKey('thinking'), false);
        } else {
          expect(body['thinking'], {'type': effort == 'off' ? 'disabled' : 'enabled'});
          expect(body['reasoning_effort'], effort == 'off' ? null : effort);
          expect(body['max_completion_tokens'], 32768);
        }
      }
    }
  });

  test('Doubao 2.1 按版本保留窗口、输出预算及原生思考档位', () {
    const models = {
      'volcengine_api': {
        'doubao-seed-2-1-pro-260915': 1024000,
        'doubao-seed-2-1-lite-260915': 1024000,
        'doubao-seed-2-1-turbo-260628': 256000,
      },
      'volcengine_coding_plan': {
        'doubao-seed-2.1-pro': 1024000, 'doubao-seed-2.1-lite': 1024000,
      },
      'volcengine_agent_plan': {
        'doubao-seed-2.1-pro': 1024000, 'doubao-seed-2.1-lite': 1024000,
      },
    };
    for (final provider in models.entries) {
      final info = ProviderCatalog.translationInfo(provider.key)!;
      for (final entry in provider.value.entries) {
        final model = info.presets.firstWhere((m) => m.name == entry.key);
        expect(model.contextTokenLimit, entry.value);
        expect(model.capabilities!.maxOutputTokens, 256000);
        expect(model.outputTokenLimit, 32768);
        expect(model.capabilities!.efforts, ['off', 'low', 'medium', 'high']);
        expect(() => model.withOption('reasoningEffort', 'max'), throwsArgumentError);
        for (final transport in ChatTransport.values) {
          final configured = model.withDeclaration(transport, model.dialect)
              .withOption('reasoningEffort', 'high').withOption('outputTokens', 64000);
          final body = _request(configured);
          expect(body['model'], entry.key);
          expect(body.containsKey('temperature'), false);
          if (transport == ChatTransport.responses) {
            expect(body['reasoning'], {'effort': 'high'});
            expect(body['max_output_tokens'], 64000);
          } else {
            expect(body['thinking'], {'type': 'enabled'});
            expect(body['reasoning_effort'], 'high');
            expect(body['max_completion_tokens'], 64000);
          }
          expect(ChatModelSpec.fromJson(configured.toJson()), configured);
        }
      }
    }
  });

  test('百炼 Chat 画像不误用 Responses，未知模型不继承 Qwen 参数', () {
    final info = ProviderCatalog.translationInfo('bailian_api')!;
    expect(info.guess('qwen-custom'), const ChatModelSpec(name: 'qwen-custom'));
    final model = info.presets.first;
    expect(model.withDeclaration(ChatTransport.responses, ChatDialect.qwen).transport,
      ChatTransport.completions);
    expect(ChatModelSpec.fromJson({...model.toJson(), 'transport': 'responses'}), isNull);
    expect(() => _request(const ChatModelSpec(name: 'custom',
      transport: ChatTransport.responses, dialect: ChatDialect.qwen)),
      throwsA(isA<ActionableException>()));
  });
}
