import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/services/settings.dart';

const _ollama = GlossaryEntry(term: 'Ollama');
const _bailian = GlossaryEntry(term: '百炼', translation: 'Bailian');

List<(String, String)> _pairs(List<GlossaryEntry> entries) => [
  for (final entry in entries) (entry.term, entry.translation),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('粘贴的多行文本 → 条目', () {
    test('四种分隔：等号、全角等号、箭头、制表符', () {
      expect(_pairs(GlossaryText.parse('百炼=Bailian')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('百炼＝Bailian')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('百炼→Bailian')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('百炼\tBailian')), [('百炼', 'Bailian')]);
    });

    test('键盘上打得出来的箭头也认，=> 不会剩下一个 >', () {
      expect(_pairs(GlossaryText.parse('百炼 -> Bailian')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('百炼 => Bailian')), [('百炼', 'Bailian')]);
    });

    test('只有原文：译文为空', () {
      expect(_pairs(GlossaryText.parse('Ollama')), [('Ollama', '')]);
      // 分隔符后面什么都没写也一样。
      expect(_pairs(GlossaryText.parse('Ollama =  ')), [('Ollama', '')]);
    });

    test('分隔符两边的空白不算内容，中间的空白留一个', () {
      expect(
        _pairs(GlossaryText.parse('  LM   Studio  =  LM  Studio 本地版  ')),
        [('LM Studio', 'LM Studio 本地版')],
      );
    });

    test('只按第一个分隔符拆：译文里可以有等号和箭头', () {
      expect(_pairs(GlossaryText.parse('质能方程=E=mc²')), [('质能方程', 'E=mc²')]);
      expect(_pairs(GlossaryText.parse('a→b→c')), [('a', 'b→c')]);
    });

    test('有制表符就按制表符拆：表格格子里的等号是内容', () {
      expect(_pairs(GlossaryText.parse('E=mc²\t质能方程')), [('E=mc²', '质能方程')]);
      // 多出来的列并进译文，不丢。
      expect(_pairs(GlossaryText.parse('a\tb\tc')), [('a', 'b c')]);
    });

    test('行首尾的制表符不算分隔：带缩进复制来的行不会整条丢掉', () {
      expect(_pairs(GlossaryText.parse('\t百炼=Bailian')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('百炼=Bailian\t')), [('百炼', 'Bailian')]);
      expect(_pairs(GlossaryText.parse('\t百炼\tBailian\t')), [
        ('百炼', 'Bailian'),
      ]);
    });

    test('空行、没有原文的行丢掉；重复的原文只留第一条', () {
      const text = '百炼=Bailian\r\n\r\n   \n=没有原文\nOllama\r百炼=Model Studio\n';
      expect(_pairs(GlossaryText.parse(text)), [
        ('百炼', 'Bailian'),
        ('Ollama', ''),
      ]);
      expect(GlossaryText.parse(''), isEmpty);
    });

    test('原文分大小写：Apple 与 apple 是两条', () {
      expect(GlossaryText.parse('Apple=苹果公司\napple=苹果'), hasLength(2));
    });
  });

  group('识别提示', () {
    test('没有词表：自由文本原样返回，一个字符都不动', () {
      expect(GlossaryText.asrPrompt(const [], '  保持口语 \n'), '  保持口语 \n');
      expect(GlossaryText.asrPrompt(const [], ''), '');
      // 条目全是空的也算没有词表。
      expect(
        GlossaryText.asrPrompt(const [GlossaryEntry(term: '  ')], ' x '),
        ' x ',
      );
    });

    test('韩文用逗号：顿号只有中文、日文在用', () {
      expect(
        GlossaryText.asrPrompt(const [
          GlossaryEntry(term: '삼성'),
          GlossaryEntry(term: '서울'),
        ], ''),
        '삼성, 서울',
      );
    });

    test('中文、日文为主用顿号，否则用逗号加空格', () {
      expect(
        GlossaryText.asrPrompt(const [
          _bailian,
          GlossaryEntry(term: '通义千问'),
        ], ''),
        '百炼、通义千问',
      );
      expect(
        GlossaryText.asrPrompt(const [
          _ollama,
          GlossaryEntry(term: 'LM Studio'),
        ], ''),
        'Ollama, LM Studio',
      );
      expect(
        GlossaryText.asrPrompt(const [
          GlossaryEntry(term: 'さくら'),
          GlossaryEntry(term: '東京'),
        ], ''),
        'さくら、東京',
      );
      // 中文节目里夹一个英文产品名，仍然算中日韩为主。
      expect(
        GlossaryText.asrPrompt(const [
          _bailian,
          GlossaryEntry(term: '通义千问'),
          GlossaryEntry(term: 'Qwen'),
        ], ''),
        '百炼、通义千问、Qwen',
      );
    });

    test('只发原文，不发译文；重复的原文只出现一次', () {
      expect(
        GlossaryText.asrPrompt(const [
          _bailian,
          GlossaryEntry(term: '百炼', translation: 'Model Studio'),
          GlossaryEntry(term: '通义'),
        ], ''),
        '百炼、通义',
      );
    });

    test('词在前，自由文本另起一行接在后面', () {
      expect(
        GlossaryText.asrPrompt(const [_ollama], '  这是一段技术访谈。\n'),
        'Ollama\n这是一段技术访谈。',
      );
    });
  });

  group('翻译术语段', () {
    test('没有条目返回空串', () {
      expect(GlossaryText.translationSection(const []), '');
      expect(
        GlossaryText.translationSection(const [GlossaryEntry(term: '')]),
        '',
      );
    });

    test('有译文写「原文 → 译文」，没译文写「保留原文写法」', () {
      final lines = GlossaryText.translationSection(const [
        _bailian,
        _ollama,
      ]).split('\n');
      expect(lines.first, '# 术语表');
      expect(lines.where((l) => l.startsWith('- ')), [
        '- 百炼 → Bailian',
        '- Ollama（保留原文写法）',
      ]);
      // 前后不带空行：段与段之间空几行由系统提示的模板决定。
      expect(lines.last, '- Ollama（保留原文写法）');
    });

    test('条目里的换行压成空格：一条只占一行', () {
      final section = GlossaryText.translationSection(const [
        GlossaryEntry(term: '张\n三', translation: 'Zhang\r\nSan'),
      ]);
      expect(section.split('\n').last, '- 张 三 → Zhang San');
    });
  });

  group('词表的存档', () {
    test('来回一致；没有译文的条目不写 translation 键', () {
      const glossary = Glossary(
        id: 'g1',
        name: '访谈',
        enabledByDefault: false,
        entries: [_bailian, _ollama],
      );
      final json =
          jsonDecode(jsonEncode(glossary.toJson())) as Map<String, Object?>;
      expect(json['entries'], [
        {'term': '百炼', 'translation': 'Bailian'},
        {'term': 'Ollama'},
      ]);

      final back = Glossary.fromJson(json)!;
      expect(back.id, 'g1');
      expect(back.name, '访谈');
      expect(back.enabledByDefault, isFalse);
      expect(back.entries, glossary.entries);
    });

    test('读坏存档不抛：没有 id 的整份不要，坏的条目丢掉，其余用默认', () {
      expect(Glossary.fromJson(null), isNull);
      expect(Glossary.fromJson('x'), isNull);
      expect(Glossary.fromJson({'name': '没有 id'}), isNull);
      expect(Glossary.fromJson({'id': ''}), isNull);

      final partial = Glossary.fromJson({
        'id': 'g1',
        'name': 1,
        'enabledByDefault': 'yes',
        'entries': [
          {'term': ' 百炼 ', 'translation': 3},
          {'translation': '没有原文'},
          'x',
          {'term': '百炼', 'translation': '重复'},
          {'term': 'Ollama'},
        ],
      })!;
      expect(partial.name, '');
      expect(Glossary.fromJson({'id': 'g3', 'name': ' 访谈 '})!.name, '访谈');
      expect(partial.enabledByDefault, isTrue);
      expect(_pairs(partial.entries), [('百炼', ''), ('Ollama', '')]);

      expect(Glossary.fromJson({'id': 'g2', 'entries': 'x'})!.entries, isEmpty);
    });
  });

  group('设置里的词表', () {
    Future<AppSettings> load([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      return AppSettings.load();
    }

    const interview = Glossary(id: 'a', name: '访谈', entries: [_bailian]);
    const tech = Glossary(
      id: 'b',
      name: '技术',
      enabledByDefault: false,
      entries: [
        GlossaryEntry(term: '百炼', translation: 'Model Studio'),
        _ollama,
      ],
    );

    test('一开始没有词表', () async {
      final settings = await load();
      expect(settings.glossaries, isEmpty);
      expect(settings.defaultGlossaryIds, isEmpty);
      expect(settings.glossaryEntries(['a']), isEmpty);
    });

    test('新建加在末尾，同 id 就地替换，删除；每次都通知并写盘', () async {
      final settings = await load();
      var notified = 0;
      settings.addListener(() => notified++);

      settings
        ..setGlossary(interview)
        ..setGlossary(tech);
      expect([for (final g in settings.glossaries) g.id], ['a', 'b']);
      expect(notified, 2);

      settings.setGlossary(interview.copyWith(name: '人物访谈'));
      expect(
        [for (final g in settings.glossaries) g.name],
        ['人物访谈', '技术'],
      );

      // 重新读一遍：上面的改动都落盘了。
      final reloaded = await AppSettings.load();
      expect([for (final g in reloaded.glossaries) g.name], ['人物访谈', '技术']);
      expect(reloaded.glossaries.last.entries, tech.entries);

      settings.removeGlossary('a');
      expect([for (final g in settings.glossaries) g.id], ['b']);
      expect(notified, 4);
      // 删不存在的：什么都不做，也不通知。
      settings.removeGlossary('没有');
      expect(notified, 4);
      expect([for (final g in (await AppSettings.load()).glossaries) g.id], [
        'b',
      ]);
    });

    test('存之前收拾干净：名字去空白，空条目与重复条目丢掉', () async {
      final settings = await load();
      settings.setGlossary(
        const Glossary(
          id: 'a',
          name: '  访谈 ',
          entries: [
            GlossaryEntry(term: ' 百炼 ', translation: ' Bailian '),
            GlossaryEntry(term: ''),
            GlossaryEntry(term: '百炼', translation: '重复'),
          ],
        ),
      );
      final saved = settings.glossaries.single;
      expect(saved.name, '访谈');
      expect(saved.entries, [_bailian]);
    });

    test('外面拿到的列表改不了', () async {
      final settings = await load();
      settings.setGlossary(interview);
      expect(() => settings.glossaries.add(tech), throwsUnsupportedError);
      expect(() => settings.glossaries.clear(), throwsUnsupportedError);
    });

    test('默认启用的 id 按列表顺序给出', () async {
      final settings = await load();
      settings
        ..setGlossary(interview)
        ..setGlossary(tech)
        ..setGlossary(const Glossary(id: 'c', name: '空的'));
      expect(settings.defaultGlossaryIds, ['a', 'c']);
    });

    test('展开：跟列表顺序不跟勾选顺序，重复的原文留前一份，删掉的 id 跳过', () async {
      final settings = await load();
      settings
        ..setGlossary(interview)
        ..setGlossary(tech);

      expect(_pairs(settings.glossaryEntries(['b', '已删', 'a'])), [
        ('百炼', 'Bailian'),
        ('Ollama', ''),
      ]);
      expect(_pairs(settings.glossaryEntries(['b'])), [
        ('百炼', 'Model Studio'),
        ('Ollama', ''),
      ]);
      expect(settings.glossaryEntries(const []), isEmpty);
    });

    test('新建：名字取第一个没被占用的「词表 N」，默认启用，id 各不相同', () async {
      final settings = await load();
      var notified = 0;
      settings.addListener(() => notified++);

      final first = settings.addGlossary();
      expect(first.name, '词表 1');
      expect(first.enabledByDefault, isTrue);
      expect(first.entries, isEmpty);
      expect(notified, 1);

      // 「词表 2」被改名占了：跳过它。
      settings.setGlossary(first.copyWith(name: '词表 2'));
      final second = settings.addGlossary();
      expect(second.name, '词表 3');
      expect(second.id, isNot(first.id));
      expect(
        [for (final g in settings.glossaries) g.id],
        [first.id, second.id],
      );

      // 存下来了。
      final reloaded = await AppSettings.load();
      expect([for (final g in reloaded.glossaries) g.name], ['词表 2', '词表 3']);
    });

    test('恢复默认不动词表：单个分区与全部恢复都一样', () async {
      final settings = await load();
      settings
        ..setGlossary(interview)
        ..themeMode = 'dark';

      for (final group in SettingsGroup.values) {
        settings.reset(group);
      }
      settings.resetAll();

      expect(settings.themeMode, 'system');
      expect(settings.glossaries.single.entries, [_bailian]);
      expect((await AppSettings.load()).glossaries.single.name, '访谈');
    });

    test('存档坏了不影响启动：整串坏了当没有，坏的那份跳过，id 撞了留前一份', () async {
      expect((await load({'glossaries': '不是 JSON'})).glossaries, isEmpty);
      expect((await load({'glossaries': '{"a":1}'})).glossaries, isEmpty);

      final settings = await load({
        'glossaries': jsonEncode([
          interview.toJson(),
          'x',
          {'name': '没有 id'},
          tech.toJson(),
          {'id': 'a', 'name': '撞 id 的'},
        ]),
      });
      expect([for (final g in settings.glossaries) g.name], ['访谈', '技术']);
      // 冷启动读出来的那份同样改不了。
      expect(() => settings.glossaries.clear(), throwsUnsupportedError);
    });
  });
}
