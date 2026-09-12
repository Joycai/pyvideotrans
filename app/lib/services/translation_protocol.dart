/// 字幕翻译的线路协议。
///
/// 大模型翻译字幕最容易出的问题是**条数对不上** —— 合并短句、丢掉语气词、
/// 把一句话的成分挪到下一条。原 Python 实现用一大段提示词来压制这些行为，
/// 这里保留同样的约束，并加上可机检的行号标记，这样条数不符时能立刻发现并重试，
/// 而不是把错位的译文写进字幕。
abstract final class TranslationProtocol {
  /// 每行的标记前缀。用不常见的符号组合，避免与正文内容冲突。
  static const marker = '§';

  static String systemPrompt({
    required String targetLanguageName,
    String? extraGuidance,
  }) =>
      '''
你是字幕翻译专家。把 <INPUT> 里的每一行翻译成$targetLanguageName。

# 绝对规则：逐行一一对应

- 输出的行数必须与输入**完全相同**。输入 N 行就输出 N 行。
- 每行以 `$marker` + 行号 + `$marker` 开头，行号照抄输入，不要重排。
- 禁止合并：即使两行原文属于同一个句子，也必须分别翻译成两行。
- 禁止删除：语气词、拟声词、重复的短句、单个字的应答，全都要保留对应行。
- 禁止增行：不要加解释、不要加标题、不要输出原文、不要用代码块包裹。

# 跨行断句的处理

口语会把一句话切在几行里。只翻译当前行**实际出现**的词，
不要为了符合$targetLanguageName 的语序把成分挪到相邻行。
如果某行在句中断开，用省略号收尾；下一行承接时用省略号开头。

# 语感

- 面向听觉而非阅读：用日常口语词，避免书面语和翻译腔。
- 字幕停留时间有限，去掉可省的主语、客套和冗余修饰，取最短的自然说法。
- 保留原文的专有名词、数字与单位。原文是人名/产品名且无通行译法时保留原文。
${extraGuidance == null || extraGuidance.trim().isEmpty ? '' : '\n# 补充要求\n\n${extraGuidance.trim()}\n'}
# 示例

输入：
${marker}1$marker 我们先确认一下
${marker}2$marker Ollama 有没有在跑。
${marker}3$marker 嗯。

输出：
${marker}1$marker Let's first check...
${marker}2$marker ...whether Ollama is running.
${marker}3$marker Mm-hm.
''';

  /// 把一批原文包装成带行号的输入。
  static String encode(List<String> lines) {
    final buffer = StringBuffer();
    for (final (i, line) in lines.indexed) {
      // 正文里的换行会破坏「一行一条」的约定，压成空格。
      final flat = line.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      buffer.writeln('$marker${i + 1}$marker $flat');
    }
    return buffer.toString().trimRight();
  }

  static final _markedLine = RegExp('^\\s*$marker\\s*(\\d+)\\s*$marker\\s*(.*)\$');

  /// 解析模型返回，还原成与输入等长的列表。
  ///
  /// 返回 null 表示这批结果不可信（行号缺失、条数对不上、出现越界行号），
  /// 调用方应当重试或降批。宁可重试也不要把错位的译文写进字幕。
  static List<String>? decode(String raw, int expected) {
    final stripped = _stripCodeFence(raw);
    final byIndex = <int, String>{};
    var sawMarker = false;

    for (final line in stripped.split('\n')) {
      final m = _markedLine.firstMatch(line);
      if (m == null) continue;
      sawMarker = true;
      final n = int.parse(m.group(1)!);
      if (n < 1 || n > expected) return null;
      // 同一行号出现两次说明模型在自我重复，不可信。
      if (byIndex.containsKey(n)) return null;
      byIndex[n] = m.group(2)!.trim();
    }

    if (sawMarker) {
      if (byIndex.length != expected) return null;
      return [for (var i = 1; i <= expected; i++) byIndex[i]!];
    }

    // 模型没打标记时退一步：如果非空行数正好等于输入条数，按顺序对应。
    final plain = stripped
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return plain.length == expected ? plain : null;
  }

  /// 模型经常把结果裹进 ``` 代码块。
  static String _stripCodeFence(String raw) {
    final text = raw.trim();
    if (!text.startsWith('```')) return text;
    final lines = text.split('\n');
    final end = lines.lastIndexWhere((l) => l.trimRight() == '```');
    return (end > 0 ? lines.sublist(1, end) : lines.sublist(1)).join('\n');
  }
}
