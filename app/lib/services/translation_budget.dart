import 'dart:convert';

import '../domain/providers/model_spec.dart';
import 'provider_api.dart';

/// 本地估算用于提前降批，服务端的超窗错误仍是最终依据。
abstract final class TranslationBudget {
  static void check(ChatModelSpec model, String instructions, String input) {
    final window = model.contextTokenLimit;
    if (window == null) return;
    // 未发送上限时，已知模型按其最大输出量留空间，不能当作零输出。
    final output = model.outputTokenLimit ?? model.capabilities?.maxOutputTokens ?? 0;
    final available = window - output;
    // UTF-8 字节数对常见 BPE 分词器是保守估算，另为消息边界预留空间。
    final fixed = utf8.encode(instructions).length + 256;
    if (available <= fixed) {
      throw const ActionableException('提示词与输出预算超过上下文容量',
        hint: '缩短翻译要求或词表，降低每批输出预算，或核对模型的上下文上限。');
    }
    if (fixed + utf8.encode(input).length > available) {
      throw const ActionableException('本批字幕预计超过上下文容量',
        hint: '将减半批量重试；若单条仍过长，请缩短该条字幕或词表。',
        batchTooLarge: true);
    }
  }

  /// 只接受可辨识的上下文容量错误，不能把所有参数错误变成付费重试。
  static bool isContextError(Object? body) {
    if (body is! Map) return false;
    final error = body['error'];
    if (error is! Map) return false;
    const codes = {'context_length_exceeded', 'context_window_exceeded',
      'input_too_long', 'prompt_too_long'};
    if (codes.contains(error['code']) || codes.contains(error['type'])) return true;
    final message = error['message'];
    if (message is! String) return false;
    final lower = message.toLowerCase();
    return lower.contains('maximum context length') ||
        RegExp(r'(exceed|longer than|too long).{0,100}context (window|length)').hasMatch(lower) ||
        RegExp(r'context (window|length).{0,100}(exceed|too long)').hasMatch(lower);
  }

  static Never contextExceeded() => throw const ActionableException(
    '服务端报告上下文超出上限',
    hint: '将减半批量重试；若单条仍失败，请缩短字幕、翻译要求或词表，并核对输出预算。',
    batchTooLarge: true);
}
