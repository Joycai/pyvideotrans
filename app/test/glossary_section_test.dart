import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/features/settings/glossary_entry_table.dart';
import 'package:subtitle_studio/features/settings/glossary_section.dart';
import 'package:subtitle_studio/services/settings.dart';

const _terms = Glossary(
  id: 'terms',
  name: '术语',
  entries: [
    GlossaryEntry(term: '百炼', translation: 'Bailian'),
    GlossaryEntry(term: 'Ollama'),
  ],
);
const _people = Glossary(
  id: 'people',
  name: '人名',
  enabledByDefault: false,
  entries: [GlossaryEntry(term: '陈嘉行', translation: 'Chen Jiaxing')],
);

List<(String, String)> _pairs(List<GlossaryEntry> entries) => [
  for (final e in entries) (e.term, e.translation),
];

void main() {
  late AppSettings settings;

  /// 每次写设置记一笔。
  late int writes;

  /// 分区回报的改动：true 是键入，false 是点选。
  late List<bool> touched;

  Future<void> load([List<Glossary> glossaries = const []]) async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    glossaries.forEach(settings.setGlossary);
    writes = 0;
    touched = [];
    settings.addListener(() => writes++);
  }

  Future<void> pump(
    WidgetTester tester, {
    double width = 880,
    bool stacked = false,
  }) async {
    tester.view
      ..physicalSize = Size(width + 48, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => GlossarySection(
                settings: settings,
                stacked: stacked,
                onChanged: ({bool typed = false}) => touched.add(typed),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 条目表里的输入框，按行排：每行原文、译文两格，最后两格是新增行。
  final cells = find.descendant(
    of: find.byType(GlossaryEntryTable),
    matching: find.byType(TextField),
  );
  Finder term(int row) => cells.at(row * 2);
  Finder translation(int row) => cells.at(row * 2 + 1);
  TextField field(WidgetTester tester, Finder cell) =>
      tester.widget<TextField>(cell);

  /// 改名输入框。按占位找：框里的字一改，按文字找就找不到了。
  final rename = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == '词表名',
  );

  Glossary stored(String id) =>
      settings.glossaries.firstWhere((g) => g.id == id);

  /// 让剪贴板里是 [text]。
  void clipboard(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': text},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  /// 在焦点所在的格子里按粘贴快捷键（测试环境按 Ctrl+V）。
  Future<void> paste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  group('词表列表', () {
    testWidgets('还没有词表：说明怎么用；新建一份默认启用并直接改名', (tester) async {
      await load();
      await pump(tester);
      expect(find.text('还没有词表'), findsOneWidget);
      expect(find.byType(GlossaryEntryTable), findsNothing);

      await tester.tap(find.text('新建词表'));
      await tester.pump();

      final created = settings.glossaries.single;
      expect(created.name, '词表 1');
      expect(created.enabledByDefault, isTrue);
      expect(created.id, isNotEmpty);
      expect(settings.defaultGlossaryIds, [created.id]);
      expect(find.text('还没有词表'), findsNothing);
      // 名字已经是输入框，整段选中，直接打字就能换掉。
      expect(rename, findsOneWidget);
      expect(field(tester, rename).controller!.text, '词表 1');
      expect(field(tester, rename).focusNode!.hasFocus, isTrue);
      expect(
        field(tester, rename).controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );

      await tester.enterText(rename, '访谈');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(settings.glossaries.single.name, '访谈');
      // 改名不换 id：「上次参数」里记的勾选靠它对上。
      expect(settings.glossaries.single.id, created.id);
    });

    testWidgets('默认名跳过已经占用的「词表 N」', (tester) async {
      await load(const [
        Glossary(id: 'a', name: '词表 2'),
        Glossary(id: 'b', name: '词表 3'),
      ]);
      await pump(tester);
      await tester.tap(find.byTooltip('新建词表'));
      await tester.pump();
      expect(settings.glossaries.last.name, '词表 4');
    });

    testWidgets('列出每份的条数与默认启用的圆点；点一份换到它的条目', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      expect(find.text('2 份词表'), findsOneWidget);
      // 默认看第一份。
      expect(field(tester, term(0)).controller!.text, '百炼');
      expect(find.textContaining('共 2 条。'), findsOneWidget);

      await tester.tap(find.text('人名'));
      await tester.pump();
      expect(field(tester, term(0)).controller!.text, '陈嘉行');
      expect(find.textContaining('共 1 条。'), findsOneWidget);
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isFalse);
    });

    testWidgets('默认启用开关写回设置', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      expect(settings.defaultGlossaryIds, ['terms']);

      // 整行可点。
      await tester.tap(find.text('新建任务时默认启用').last);
      await tester.pump();
      expect(settings.defaultGlossaryIds, isEmpty);
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      expect(settings.defaultGlossaryIds, ['terms']);
      expect(touched, [false, false]);
      // 条目没有被动到。
      expect(stored('terms').entries, _terms.entries);
    });

    testWidgets('窄窗：列表变成一行筹码，选中的是当前词表', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester, width: 800, stacked: true);
      expect(find.text('2 份词表'), findsNothing);
      final chips = tester
          .widgetList<FilterChipButton>(find.byType(FilterChipButton))
          .toList();
      expect(
        [for (final c in chips) (c.label, c.count, c.selected)],
        [('术语', 2, true), ('人名', 1, false)],
      );

      await tester.tap(find.widgetWithText(FilterChipButton, '人名'));
      await tester.pump();
      expect(field(tester, term(0)).controller!.text, '陈嘉行');

      await tester.tap(find.text('新建'));
      await tester.pump();
      expect(settings.glossaries, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('重命名', () {
    Future<void> startRename(WidgetTester tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      await tester.tap(find.byTooltip('重命名'));
      await tester.pump();
      expect(field(tester, rename).controller!.text, '术语');
    }

    testWidgets('回车提交，首尾空白去掉', (tester) async {
      await startRename(tester);
      await tester.enterText(rename, '  产品术语 ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(stored('terms').name, '产品术语');
      expect(stored('terms').entries, _terms.entries);
      expect(find.byTooltip('重命名'), findsOneWidget);
    });

    testWidgets('失焦提交', (tester) async {
      await startRename(tester);
      await tester.enterText(rename, '产品术语');
      await tester.tap(term(0));
      await tester.pump();
      expect(stored('terms').name, '产品术语');
    });

    testWidgets('Esc 放弃', (tester) async {
      await startRename(tester);
      await tester.enterText(rename, '不要这个名字');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(stored('terms').name, '术语');
      expect(find.text('术语'), findsWidgets);
      expect(writes, 0);
    });

    testWidgets('空名、与别的词表重名：说明原因，回车不提交，失焦等于放弃', (tester) async {
      await startRename(tester);
      for (final (input, reason) in [
        ('   ', '名字不能为空'),
        (' 人名 ', '已经有一份叫「人名」的词表'),
      ]) {
        await tester.enterText(rename, input);
        await tester.pump();
        expect(find.text(reason), findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(stored('terms').name, '术语');
      }
      await tester.tap(term(0));
      await tester.pump();
      expect(stored('terms').name, '术语');
      expect(find.byTooltip('重命名'), findsOneWidget);
      expect(writes, 0);
    });

    testWidgets('改名失焦提交与紧跟着的点击落在同一帧：两次改动都在', (tester) async {
      await startRename(tester);
      await tester.enterText(rename, '产品术语');
      await tester.pump();

      // 桌面上按下的那一刻改名框就失焦并提交；抬起触发的是上一帧的回调，
      // 它要是拿旧的那份词表去改，刚提交的名字就被盖回去了。
      await tester.tap(find.byType(AppSwitch), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(stored('terms').name, '产品术语');
      expect(stored('terms').enabledByDefault, isFalse);
      expect(stored('terms').entries, _terms.entries);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('切去别的应用时丢了焦点：不提交也不放弃，回来接着改', (tester) async {
      await startRename(tester);
      await tester.enterText(rename, '半截');
      await tester.pump();

      // 桌面上应用失去激活时焦点管理器会把焦点拿走，回到前台再还上。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      field(tester, rename).focusNode!.unfocus();
      await tester.pump();
      expect(rename, findsOneWidget);
      expect(field(tester, rename).controller!.text, '半截');
      expect(writes, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      field(tester, rename).focusNode!.requestFocus();
      await tester.pump();
      await tester.enterText(rename, '半截补全');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(stored('terms').name, '半截补全');
    });

    testWidgets('名字没变：不写设置', (tester) async {
      await startRename(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(writes, 0);
    });
  });

  group('删除词表', () {
    testWidgets('要确认；取消什么都不动', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      await tester.tap(find.byTooltip('删除这份词表'));
      await tester.pumpAndSettle();
      expect(find.text('删除「术语」？'), findsOneWidget);
      expect(find.text('里面的 2 条会一起删掉；已入队的任务不受影响。'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(settings.glossaries, hasLength(2));
      expect(writes, 0);
    });

    testWidgets('确认后删掉，选中落到剩下的第一份；删光回到空态', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      await tester.tap(find.text('人名'));
      await tester.pump();
      await tester.tap(find.byTooltip('删除这份词表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect([for (final g in settings.glossaries) g.id], ['terms']);
      expect(field(tester, term(0)).controller!.text, '百炼');

      await tester.tap(find.byTooltip('删除这份词表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(settings.glossaries, isEmpty);
      expect(find.text('还没有词表'), findsOneWidget);
    });
  });

  group('条目表', () {
    testWidgets('空词表：一句说明加常驻的新增行', (tester) async {
      await load(const [Glossary(id: 'g', name: '空的')]);
      await pump(tester);
      expect(find.text('还没有条目。在下面一行输入，或把多行文本直接粘贴进来。'), findsOneWidget);
      expect(cells, findsNWidgets(2));
      expect(find.textContaining('条。'), findsNothing);
    });

    testWidgets('新增行：回车加进表并清空，焦点回到原文格接着录', (tester) async {
      await load(const [Glossary(id: 'g', name: '空的')]);
      await pump(tester);

      // 原文空着：回车什么都不加。
      await tester.enterText(translation(0), 'ignored');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(stored('g').entries, isEmpty);

      await tester.enterText(term(0), ' 百炼 ');
      await tester.enterText(translation(0), 'Bailian');
      // 还在新增行里：没进表，也没写设置。
      expect(writes, 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(_pairs(stored('g').entries), [('百炼', 'Bailian')]);
      expect(cells, findsNWidgets(4));
      expect(field(tester, term(1)).controller!.text, isEmpty);
      expect(field(tester, translation(1)).controller!.text, isEmpty);
      expect(field(tester, term(1)).focusNode!.hasFocus, isTrue);
      expect(touched, [true]);

      // 加号与回车一样。
      await tester.enterText(term(1), 'Ollama');
      await tester.tap(find.byTooltip('添加这一条（Enter）'));
      await tester.pump();
      expect(_pairs(stored('g').entries), [('百炼', 'Bailian'), ('Ollama', '')]);
    });

    testWidgets('逐格编辑：每次改动都存；打字途中不被存回来的值冲掉', (tester) async {
      await load(const [_terms]);
      await pump(tester);

      // 末尾的空格存盘时会去掉；框里得留着，否则「New York」打不出来。
      for (final partial in ['New', 'New ', 'New Y', 'New York']) {
        await tester.enterText(term(1), partial);
        await tester.pump();
        expect(field(tester, term(1)).controller!.text, partial);
      }
      expect(_pairs(stored('terms').entries), [
        ('百炼', 'Bailian'),
        ('New York', ''),
      ]);

      await tester.enterText(translation(1), '纽约');
      await tester.pump();
      expect(stored('terms').entries.last.translation, '纽约');
      // 名字与默认启用没有被条目的改动带着变。
      expect(stored('terms').name, '术语');
      expect(touched.every((typed) => typed), isTrue);
    });

    testWidgets('回车跳到下一行同一列，最后一行跳到新增行', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      await tester.tap(translation(0));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(field(tester, translation(1)).focusNode!.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(field(tester, translation(2)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('原文为空：标红说明，这一条不存', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      await tester.enterText(term(0), '  ');
      await tester.pump();

      expect(find.text('原文为空，这一条不会保存'), findsOneWidget);
      expect(_pairs(stored('terms').entries), [('Ollama', '')]);
      // 行还在表里，译文没丢，补上原文就回来了。
      expect(field(tester, translation(0)).controller!.text, 'Bailian');
      expect(find.textContaining('共 1 条。'), findsOneWidget);

      await tester.enterText(term(0), '阿里百炼');
      await tester.pump();
      expect(find.text('原文为空，这一条不会保存'), findsNothing);
      expect(_pairs(stored('terms').entries), [
        ('阿里百炼', 'Bailian'),
        ('Ollama', ''),
      ]);
    });

    testWidgets('原文重复：后一条标红并指出第一条在哪，只存第一条', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      // 多余的空白不算不同。
      await tester.enterText(term(1), ' 百炼 ');
      await tester.pump();

      expect(find.text('「百炼」已在第 1 行，重复的原文只保留第一条'), findsOneWidget);
      expect(_pairs(stored('terms').entries), [('百炼', 'Bailian')]);

      // 把第一条改掉：原来重复的那条变成有效的。
      await tester.enterText(term(0), '通义');
      await tester.pump();
      expect(find.textContaining('重复的原文'), findsNothing);
      expect(_pairs(stored('terms').entries), [('通义', 'Bailian'), ('百炼', '')]);
    });

    testWidgets('删除一条', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      await tester.tap(find.byTooltip('删除这一条').first);
      await tester.pump();
      expect(_pairs(stored('terms').entries), [('Ollama', '')]);
      expect(cells, findsNWidgets(4));
      expect(field(tester, term(0)).controller!.text, 'Ollama');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('换一份词表：写到一半没存的行不带过去', (tester) async {
      await load(const [_terms, _people]);
      await pump(tester);
      await tester.enterText(term(0), '');
      await tester.enterText(term(2), '还没回车');
      await tester.pump();

      await tester.tap(find.text('人名'));
      await tester.pump();
      expect(find.text('原文为空，这一条不会保存'), findsNothing);
      expect(cells, findsNWidgets(4));
      expect(field(tester, term(1)).controller!.text, isEmpty);
      expect(stored('people').entries, _people.entries);
    });

    testWidgets('词表在别处被改了：按外面的内容重建，接着改的是新内容', (tester) async {
      await load(const [_terms]);
      await pump(tester);

      // 表挂上之后还没动过，条目就在别处换掉了。
      settings.setGlossary(
        _terms.copyWith(entries: const [GlossaryEntry(term: '外来的')]),
      );
      await tester.pump();
      expect(cells, findsNWidgets(4));
      expect(field(tester, term(0)).controller!.text, '外来的');

      await tester.enterText(translation(0), 'external');
      await tester.pump();
      expect(_pairs(stored('terms').entries), [('外来的', 'external')]);
    });

    testWidgets('Tab 在格子之间走，不停在行尾的删除按钮上', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      await tester.tap(term(1));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field(tester, translation(1)).focusNode!.hasFocus, isTrue);
      // 最后一行的译文格再按 Tab：到新增行的原文格。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field(tester, term(2)).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field(tester, translation(2)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('右键菜单里的粘贴：多行文本同样按行追加', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      clipboard(tester, '通义=Tongyi\nLM Studio\n');
      await tester.tap(term(0));
      await tester.pump();
      await tester.tap(
        term(0),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(field(tester, term(0)).controller!.text, '百炼');
      expect(_pairs(stored('terms').entries), [
        ('百炼', 'Bailian'),
        ('Ollama', ''),
        ('通义', 'Tongyi'),
        ('LM Studio', ''),
      ]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('多行粘贴：逐行解析后追加在末尾，不写进当前格', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      clipboard(
        tester,
        '通义=Tongyi\n'
        '\n'
        'LM Studio\n'
        '百炼=已经有了\n'
        '向量数据库\tvector database\r\n'
        '缓存穿透 → cache penetration\n',
      );
      await tester.tap(term(0));
      await tester.pump();
      await paste(tester);

      expect(field(tester, term(0)).controller!.text, '百炼');
      expect(_pairs(stored('terms').entries), [
        ('百炼', 'Bailian'),
        ('Ollama', ''),
        ('通义', 'Tongyi'),
        ('LM Studio', ''),
        ('向量数据库', 'vector database'),
        ('缓存穿透', 'cache penetration'),
      ]);
      // 已经有的原文跳过，不会多出一排标红的重复行。
      expect(find.textContaining('重复的原文'), findsNothing);
      expect(cells, findsNWidgets(14));
    });

    testWidgets('单行粘贴：照常粘进当前格', (tester) async {
      await load(const [_terms]);
      await pump(tester);
      // 从表格里复制一格，末尾常带一个换行：不算多行。
      clipboard(tester, '-cloud\n');
      await tester.tap(term(1));
      await tester.pump();
      field(tester, term(1)).controller!.selection =
          const TextSelection.collapsed(offset: 6);
      await paste(tester);

      expect(cells, findsNWidgets(6));
      expect(stored('terms').entries.last.term, 'Ollama-cloud');
    });

    testWidgets('几百条：只建看得见的那些行，表里自己滚', (tester) async {
      await load([
        Glossary(
          id: 'big',
          name: '很长',
          entries: [for (var i = 0; i < 300; i++) GlossaryEntry(term: '词 $i')],
        ),
      ]);
      await pump(tester);
      expect(find.textContaining('共 300 条。'), findsOneWidget);
      // 远少于 300 行 × 2 格。
      expect(tester.widgetList(cells).length, lessThan(80));
      // 新增行不跟着滚，始终在表尾。
      expect(find.byTooltip('添加这一条（Enter）'), findsOneWidget);

      await tester.enterText(cells.last, '');
      await tester.enterText(
        cells.at(tester.widgetList(cells).length - 2),
        '新词',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(stored('big').entries.last.term, '新词');
      expect(stored('big').entries, hasLength(301));
      // 加完滚到表尾，看得见刚加的那条。
      expect(find.widgetWithText(TextField, '新词'), findsOneWidget);
    });
  });
}
