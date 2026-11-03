import '../domain/providers/chat_transport.dart';
import '../domain/providers/model_spec.dart';
import 'provider_api.dart';
import 'translation_budget.dart';

/// 两种接口共用字幕协议，只在这里转换报文与检查完成状态。
abstract final class TranslationWire {
  static Map<String, Object?> request({
    required ChatModelSpec model,
    required String modelName,
    required String instructions,
    required String input,
    required double? temperature,
  }) {
    if (!model.dialect.transports.contains(model.transport)) {
      throw const ActionableException('所选参数画像不支持此接口协议',
        hint: '百炼 Qwen 请使用 Chat Completions，并核对服务地址。');
    }
    final responses = model.transport == ChatTransport.responses;
    final effort = model.reasoningEffort;
    final outputLimit = model.outputTokenLimit;
    return {
      'model': modelName,
      'temperature': ?temperature,
      if (responses) ...{
        'max_output_tokens': ?outputLimit,
        'instructions': instructions,
        'input': input,
        // 每批字幕互相独立，不依赖服务器保存的会话。
        if (model.dialect != ChatDialect.deepseek) 'store': false,
        if (effort != null) 'reasoning': {
          'effort': effort == 'off' ? 'none' : effort,
        },
      } else ...{
        ((model.dialect == ChatDialect.openaiReasoning ||
            model.dialect == ChatDialect.qwen || model.dialect == ChatDialect.doubao)
            ? 'max_completion_tokens' : 'max_tokens'): ?outputLimit,
        'messages': [
          {'role': 'system', 'content': instructions},
          {'role': 'user', 'content': input},
        ],
        if (model.dialect == ChatDialect.deepseek || model.dialect == ChatDialect.doubao) 'thinking': {
          'type': effort == 'off' ? 'disabled' : 'enabled',
        },
        if (model.dialect == ChatDialect.qwen) 'enable_thinking': effort != 'off',
        if (effort != null && effort != 'off' && effort != 'on') 'reasoning_effort': effort,
      },
    };
  }

  static String? content(Map<String, Object?> body, ChatTransport transport) {
    if (TranslationBudget.isContextError(body)) TranslationBudget.contextExceeded();
    if (body['error'] != null) {
      throw const ActionableException('翻译服务返回错误',
        hint: '检查模型与服务配置后重试；已完成的译文保留。');
    }
    return transport == ChatTransport.responses
        ? _responses(body) : _completions(body);
  }

  static Never _refused() => throw const ActionableException(
    '模型拒绝了翻译请求', hint: '检查原文与翻译要求，或换一个模型后重试。');

  static Never _unfinished({bool tooLarge = false}) => throw ActionableException(
    '模型未完成本批翻译',
    hint: tooLarge ? '输出被截断，将减半批量重试。' : '检查服务状态与模型配置后重试。',
    batchTooLarge: tooLarge,
  );

  static String? _responses(Map<String, Object?> body) {
    if (body['status'] != 'completed') {
      final details = body['incomplete_details'];
      if (details is Map && details['reason'] == 'content_filter') _refused();
      _unfinished(tooLarge: body['status'] == 'incomplete' &&
          details is Map && details['reason'] == 'max_output_tokens');
    }
    final output = body['output'];
    if (output is! List) return null;
    final text = <String>[];
    for (final item in output.whereType<Map>()) {
      // 推理条目可能含可读文本，但不能作为字幕正文。
      if (item['type'] != 'message' || item['role'] != 'assistant') continue;
      if (item['status'] != null && item['status'] != 'completed') _unfinished();
      final parts = item['content'];
      if (parts is! List) continue;
      for (final part in parts.whereType<Map>()) {
        if (part['type'] == 'refusal') _refused();
        if (part['type'] == 'output_text' && part['text'] is String) {
          text.add(part['text'] as String);
        }
      }
    }
    return text.isEmpty ? null : text.join('\n');
  }

  static String? _completions(Map<String, Object?> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return null;
    final first = choices.first as Map;
    final finish = first['finish_reason'];
    if (finish == 'content_filter') _refused();
    if (finish != null && finish != 'stop') _unfinished(tooLarge: finish == 'length');
    final message = first['message'];
    if (message is! Map) return null;
    if (message['refusal'] != null && message['refusal'] != '') _refused();
    final content = message['content'];
    if (content is String) return content;
    if (content is! List) return null;
    final text = <String>[];
    for (final part in content.whereType<Map>()) {
      if (part['type'] == 'refusal') _refused();
      if ((part['type'] == null || part['type'] == 'text' ||
          part['type'] == 'output_text') && part['text'] is String) {
        text.add(part['text'] as String);
      }
    }
    return text.join();
  }
}
