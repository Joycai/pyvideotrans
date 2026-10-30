import '../domain/glossary.dart';
import 'provider_api.dart';

/// 热词与上下文分开发送，避免词表耗尽上下文的 400 字符预算。
abstract final class QwenAsrEnhancement {
  static Map<String, int> vocabulary(List<GlossaryEntry> entries) {
    final terms = GlossaryText.clean(entries);
    if (terms.length > 2000) {
      throw const ActionableException('识别热词超过 2000 个',
        hint: '减少本次任务选择的词表。');
    }
    final result = <String, int>{};
    for (final entry in terms) {
      final term = entry.term;
      final ascii = term.runes.every((r) => r < 128);
      if (ascii ? term.split(' ').length > 7 : term.runes.length > 15) {
        throw ActionableException('识别热词过长：$term',
          hint: '含非 ASCII 字符的词条最多 15 字符，纯英文等 ASCII 词条最多 7 个词；长描述请放入识别提示。');
      }
      result[term] = 4;
    }
    return Map.unmodifiable(result);
  }

  static List<Map<String, Object?>> context(String prompt) => [
    if (prompt.trim().isNotEmpty)
      {
        'role': 'user',
        'content': [
          {'type': 'input_text',
           'text': String.fromCharCodes(prompt.trim().runes.take(400))},
        ],
      },
  ];
}
