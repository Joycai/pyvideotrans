/// 官方预置的能力随声明保存；同名模型经其他网关时不自动继承。
final class ChatCapabilities {
  const ChatCapabilities({
    this.efforts = const [],
    this.defaultEffort,
    this.contextWindow,
    this.maxOutputTokens,
    this.defaultOutputTokens,
  });

  final List<String> efforts;
  final String? defaultEffort;
  final int? contextWindow;
  final int? maxOutputTokens;
  final int? defaultOutputTokens;

  static const openai = ChatCapabilities(
    efforts: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
    defaultEffort: 'low', contextWindow: 1050000,
    maxOutputTokens: 128000, defaultOutputTokens: 32768,
  );
  static const openaiRequired = ChatCapabilities(
    efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
    defaultEffort: 'low', contextWindow: 1050000,
    maxOutputTokens: 128000, defaultOutputTokens: 32768,
  );
  static const deepseek = ChatCapabilities(
    efforts: ['off', 'low', 'high', 'max'],
    defaultEffort: 'low', contextWindow: 1048576,
    maxOutputTokens: 393216, defaultOutputTokens: 32768,
  );

  static const qwen38 = ChatCapabilities(
    efforts: ['off', 'low', 'medium', 'xhigh'], defaultEffort: 'off',
    contextWindow: 1000000, maxOutputTokens: 131072, defaultOutputTokens: 32768,
  );
  static const qwen37 = ChatCapabilities(
    efforts: ['off', 'on'], defaultEffort: 'off',
    contextWindow: 1000000, maxOutputTokens: 131072, defaultOutputTokens: 32768,
  );
  static const doubao20 = ChatCapabilities(
    efforts: ['off', 'low', 'medium', 'high'], defaultEffort: 'off',
    contextWindow: 256000, maxOutputTokens: 128000, defaultOutputTokens: 32768,
  );

  // 2.1 的 0915 版与套餐 Pro / Lite 扩大窗口，Turbo 仍为 256k。
  // 输出上限按官方 256k 的保守值设置，不把套餐别名等同于旧日期版。
  static const doubao21 = ChatCapabilities(
    efforts: ['off', 'low', 'medium', 'high'], defaultEffort: 'off',
    contextWindow: 1024000, maxOutputTokens: 256000, defaultOutputTokens: 32768,
  );
  static const doubao21Turbo = ChatCapabilities(
    efforts: ['off', 'low', 'medium', 'high'], defaultEffort: 'off',
    contextWindow: 256000, maxOutputTokens: 256000, defaultOutputTokens: 32768,
  );

  Map<String, Object?> toJson() => {
    'efforts': efforts,
    'defaultEffort': defaultEffort,
    'contextWindow': contextWindow,
    'maxOutputTokens': maxOutputTokens,
    'defaultOutputTokens': defaultOutputTokens,
  };

  static ChatCapabilities? fromJson(Object? raw) {
    if (raw is! Map || raw['efforts'] is! List) return null;
    final efforts = raw['efforts'] as List;
    const allowed = {'none', 'off', 'on', 'low', 'medium', 'high', 'xhigh', 'max'};
    if (efforts.any((e) => !allowed.contains(e)) ||
        efforts.toSet().length != efforts.length) {
      return null;
    }
    final defaultEffort = raw['defaultEffort'];
    if (efforts.isEmpty ? defaultEffort != null : !efforts.contains(defaultEffort)) {
      return null;
    }
    for (final key in ['contextWindow', 'maxOutputTokens', 'defaultOutputTokens']) {
      final value = raw[key];
      if (value != null && (value is! int || value <= 0 || value > 10000000)) return null;
    }
    if (raw['contextWindow'] != null && (raw['contextWindow'] as int) < 1024) return null;
    final output = raw['maxOutputTokens'] as int?;
    final budget = raw['defaultOutputTokens'] as int?;
    final window = raw['contextWindow'] as int?;
    if (budget != null && ((output != null && budget > output) ||
        (window != null && budget >= window))) {
      return null;
    }
    return ChatCapabilities(efforts: List<String>.unmodifiable(efforts),
      defaultEffort: defaultEffort as String?, contextWindow: window,
      maxOutputTokens: output, defaultOutputTokens: budget);
  }

  @override
  bool operator ==(Object other) => other is ChatCapabilities &&
      other.efforts.length == efforts.length &&
      Iterable.generate(efforts.length).every((i) => other.efforts[i] == efforts[i]) &&
      other.defaultEffort == defaultEffort && other.contextWindow == contextWindow &&
      other.maxOutputTokens == maxOutputTokens && other.defaultOutputTokens == defaultOutputTokens;

  @override
  int get hashCode => Object.hash(Object.hashAll(efforts), defaultEffort,
    contextWindow, maxOutputTokens, defaultOutputTokens);
}
