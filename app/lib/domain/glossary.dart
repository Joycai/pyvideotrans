import 'language.dart';

/// 词表里的一条：一个专有名词，和它的译法。
final class GlossaryEntry {
  const GlossaryEntry({required this.term, this.translation = ''});

  /// 原文里的写法。识别时当作提示词，翻译时当作要认出来的词。
  final String term;

  /// 译法。空串表示「照抄原文」：人名、产品名多半是这种。
  final String translation;

  static final _blank = RegExp(r'\s+');

  /// 首尾空白去掉，中间的空白（含换行、制表符）压成一个空格。
  ///
  /// 词条要进提示词里的一行列表，夹着换行就会被模型读成两条。
  GlossaryEntry normalized() => GlossaryEntry(
    term: term.replaceAll(_blank, ' ').trim(),
    translation: translation.replaceAll(_blank, ' ').trim(),
  );

  Map<String, Object?> toJson() => {
    'term': term,
    if (translation.isNotEmpty) 'translation': translation,
  };

  /// 读不出原文的返回 null，由调用方丢掉这一条。
  static GlossaryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final term = json['term'];
    final translation = json['translation'];
    if (term is! String) return null;
    return GlossaryEntry(
      term: term,
      translation: translation is String ? translation : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlossaryEntry &&
      other.term == term &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(term, translation);

  @override
  String toString() => translation.isEmpty
      ? 'GlossaryEntry($term)'
      : 'GlossaryEntry($term → $translation)';
}

/// 一份词表：一组专有名词，识别与翻译共用。
///
/// 可以有多份（按节目、按客户分），建任务时勾选其中几份。任务用到的是
/// 入队那一刻展开的条目，之后再改词表不影响排着队的任务。
final class Glossary {
  const Glossary({
    required this.id,
    required this.name,
    this.enabledByDefault = true,
    this.entries = const [],
  });

  /// 不变的标识。改名不换 id：「上次参数」里记的勾选靠它对上。
  final String id;
  final String name;

  /// 新建任务时默认勾上。
  final bool enabledByDefault;
  final List<GlossaryEntry> entries;

  Glossary copyWith({
    String? name,
    bool? enabledByDefault,
    List<GlossaryEntry>? entries,
  }) => Glossary(
    id: id,
    name: name ?? this.name,
    enabledByDefault: enabledByDefault ?? this.enabledByDefault,
    entries: entries ?? this.entries,
  );

  /// 名字去首尾空白，条目收拾干净（见 [GlossaryText.clean]）。存盘前过一遍。
  Glossary normalized() => Glossary(
    id: id,
    name: name.trim(),
    enabledByDefault: enabledByDefault,
    entries: GlossaryText.clean(entries),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabledByDefault': enabledByDefault,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  /// 没有 id 的读不回来（返回 null）；其余字段坏了就用默认值，坏的条目丢掉，
  /// 不因为一条写坏了把整份词表扔了。
  static Glossary? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final name = json['name'];
    final enabled = json['enabledByDefault'];
    final entries = json['entries'];
    return Glossary(
      id: id,
      name: name is String ? name.trim() : '',
      enabledByDefault: enabled is bool ? enabled : true,
      entries: GlossaryText.clean([
        if (entries is List)
          for (final entry in entries) ?GlossaryEntry.fromJson(entry),
      ]),
    );
  }
}

/// 词表与文本之间的三种转换：粘贴的多行文本 → 条目，条目 → 识别提示，
/// 条目 → 翻译系统提示里的术语段。
abstract final class GlossaryText {
  /// 收拾一组条目：压空白，丢掉没有原文的，原文重复的只留第一条。
  ///
  /// 同一个词给两种译法，模型只会随便挑一个；留第一条，结果才可预期。
  static List<GlossaryEntry> clean(Iterable<GlossaryEntry> entries) {
    final seen = <String>{};
    return [
      for (final entry in entries.map((e) => e.normalized()))
        if (entry.term.isNotEmpty && seen.add(entry.term)) entry,
    ];
  }

  /// 原文与译文之间认的分隔：`=`（全角也认）、`→`，以及键盘上打得出来的
  /// `->` `=>`。`=>` 排在 `=` 前面，否则会被拆成 `=` 加一个多余的 `>`。
  static final _separator = RegExp(r'→|=>|->|=|＝');

  /// 多行文本 → 条目。每行「原文=译文」「原文→译文」、用制表符隔开的
  /// 两格，或只有原文；空行与重复的原文丢弃。
  ///
  /// 有制表符就按制表符分 —— 那是从表格里复制来的，格子里的 `=` 是内容。
  static List<GlossaryEntry> parse(String text) => clean([
    for (final line in text.split(RegExp(r'\r\n|\n|\r'))) _parseLine(line),
  ]);

  static GlossaryEntry _parseLine(String line) {
    final tab = line.indexOf('\t');
    if (tab >= 0) {
      return GlossaryEntry(
        term: line.substring(0, tab),
        translation: line.substring(tab + 1),
      );
    }
    final match = _separator.firstMatch(line);
    if (match == null) return GlossaryEntry(term: line);
    return GlossaryEntry(
      term: line.substring(0, match.start),
      translation: line.substring(match.end),
    );
  }

  /// 识别用的上下文提示：词表里的原文在前，自由文本在后。
  ///
  /// 词表为空时原样返回 [freeText] —— 没建词表的用户，发出去的提示一个字都
  /// 不变。词之间中日韩为主用「、」，否则用「, 」：提示词要像一段目标语言
  /// 的文字，模型才会照着里面的写法出字。
  static String asrPrompt(List<GlossaryEntry> entries, String freeText) {
    final terms = [for (final entry in clean(entries)) entry.term];
    if (terms.isEmpty) return freeText;
    final cjk = Languages.guessFromText(terms.join(' '))?.cjk ?? false;
    final list = terms.join(cjk ? '、' : ', ');
    final free = freeText.trim();
    return free.isEmpty ? list : '$list\n$free';
  }

  /// 翻译系统提示里的「# 术语表」段；词表为空返回空串。
  ///
  /// 有译文的写「原文 → 译文」，没有的写「原文（保留原文写法）」。
  static String translationSection(List<GlossaryEntry> entries) {
    final cleaned = clean(entries);
    if (cleaned.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('# 术语表')
      ..writeln()
      ..writeln(
        '下面的词在原文里出现时，按给定的译法翻译；'
        '标了「保留原文写法」的照抄原文，不要翻译也不要音译。',
      )
      ..writeln();
    for (final entry in cleaned) {
      buffer.writeln(
        entry.translation.isEmpty
            ? '- ${entry.term}（保留原文写法）'
            : '- ${entry.term} → ${entry.translation}',
      );
    }
    return buffer.toString().trimRight();
  }
}
