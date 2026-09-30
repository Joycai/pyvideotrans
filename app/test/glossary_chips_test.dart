import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/features/shared/glossary_chips.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_form.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_recognize_section.dart';
import 'package:subtitle_studio/features/translate/translate_form.dart';
import 'package:subtitle_studio/features/translate/translate_language_section.dart';
import 'package:subtitle_studio/services/settings.dart';

const _interview = Glossary(
  id: 'a',
  name: '访谈',
  entries: [
    GlossaryEntry(term: '百炼', translation: 'Bailian'),
    GlossaryEntry(term: 'Ollama'),
  ],
);
const _tech = Glossary(id: 'b', name: '技术', enabledByDefault: false);

const _ignoredNote =
    '当前模型不接受上下文提示，识别时不会发送词表与识别提示；'
    '接着翻译时仍会用词表。';

/// 建任务页里勾选词表的那一行。
void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 720, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<(String, int?, bool)> chips(WidgetTester tester) => [
    for (final chip in tester.widgetList<FilterChipButton>(
      find.byType(FilterChipButton),
    ))
      (chip.label, chip.count, chip.selected),
  ];

  group('筹码行', () {
    testWidgets('列出全部词表与条数，空的也列；点一下回报那一份的 id', (tester) async {
      final toggled = <String>[];
      await pump(
        tester,
        GlossaryChips(
          glossaries: const [_interview, _tech],
          selectedIds: const {'a'},
          onToggle: toggled.add,
        ),
      );
      expect(find.text('词表'), findsOneWidget);
      expect(chips(tester), [('访谈', 2, true), ('技术', 0, false)]);

      await tester.tap(find.text('技术'));
      await tester.tap(find.text('访谈'));
      expect(toggled, ['b', 'a']);
    });

    testWidgets('还没有词表：一句话加去设置的链接；没给去处时是纯文字', (tester) async {
      var opened = 0;
      await pump(
        tester,
        GlossaryChips(
          glossaries: const [],
          selectedIds: const {},
          onToggle: (_) {},
          onOpenSettings: () => opened++,
          note: _ignoredNote,
        ),
      );
      expect(find.byType(FilterChipButton), findsNothing);
      expect(find.text('还没有词表 · '), findsOneWidget);
      // 没有词表时说明也在：它同时在说识别提示不会发送。
      expect(find.text(_ignoredNote), findsOneWidget);
      await tester.tap(find.text('去设置里建一个'));
      expect(opened, 1);

      await pump(
        tester,
        GlossaryChips(
          glossaries: const [],
          selectedIds: const {},
          onToggle: (_) {},
        ),
      );
      expect(find.text('还没有词表，可在设置里新建'), findsOneWidget);
      expect(find.byType(LinkText), findsNothing);
    });

    testWidgets('说明写在筹码下面，筹码照常能点', (tester) async {
      final toggled = <String>[];
      await pump(
        tester,
        GlossaryChips(
          glossaries: const [_interview],
          selectedIds: const {'a'},
          onToggle: toggled.add,
          note: _ignoredNote,
        ),
      );
      expect(find.text(_ignoredNote), findsOneWidget);
      await tester.tap(find.text('访谈'));
      expect(toggled, ['a']);
    });
  });

  group('转写 · 识别段', () {
    Future<TranscribeFormController> pumpSection(
      WidgetTester tester, {
      VoidCallback? onOpenGlossary,
    }) async {
      final form = TranscribeFormController(settings: settings);
      addTearDown(form.dispose);
      await pump(
        tester,
        ListenableBuilder(
          listenable: form,
          builder: (_, _) => TranscribeRecognizeSection(
            form: form,
            onOpenGlossary: onOpenGlossary,
          ),
        ),
      );
      return form;
    }

    testWidgets('默认启用的勾着；点一下改的是任务参数里的勾选', (tester) async {
      settings
        ..setGlossary(_interview)
        ..setGlossary(_tech);
      final form = await pumpSection(tester);
      expect(chips(tester), [('访谈', 2, true), ('技术', 0, false)]);

      await tester.tap(find.text('技术'));
      await tester.pump();
      expect(form.options.glossaryIds, ['a', 'b']);
      expect(chips(tester), [('访谈', 2, true), ('技术', 0, true)]);
      // 勾选不动设置。
      expect(settings.defaultGlossaryIds, ['a']);
    });

    testWidgets('表单开着的时候在设置里建了词表：这一行跟着出现', (tester) async {
      var opened = 0;
      await pumpSection(tester, onOpenGlossary: () => opened++);
      await tester.tap(find.text('去设置里建一个'));
      expect(opened, 1);

      settings.setGlossary(_interview);
      await tester.pump();
      expect(chips(tester), [('访谈', 2, true)]);
    });

    testWidgets('选中的模型不接受上下文提示：说明识别时不会发，筹码不禁用', (tester) async {
      final bailian = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      settings
        ..asrProviderId = bailian.id
        ..setGlossary(_interview);
      final form = await pumpSection(tester);
      // 默认是同步的 Qwen3-ASR：接受提示。
      expect(find.text(_ignoredNote), findsNothing);

      form.update((o) => o.copyWith(asrModel: bailian.presets[3]));
      await tester.pump();
      expect(find.text(_ignoredNote), findsOneWidget);
      await tester.tap(find.text('访谈'));
      await tester.pump();
      expect(form.options.glossaryIds, isEmpty);
    });
  });

  group('翻译 · 翻译段', () {
    testWidgets('词表行在「每批条数」与「翻译要求」之间，没有识别那句说明', (tester) async {
      settings
        ..setGlossary(_interview)
        ..setGlossary(_tech);
      final form = TranslateFormController(settings: settings);
      addTearDown(form.dispose);
      await pump(
        tester,
        ListenableBuilder(
          listenable: form,
          builder: (_, _) => TranslateLanguageSection(form: form),
        ),
      );

      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(top('每批条数'), lessThan(top('词表')));
      expect(top('词表'), lessThan(top('翻译要求（可选）')));
      expect(find.text(_ignoredNote), findsNothing);

      await tester.tap(find.text('访谈'));
      await tester.pump();
      expect(form.options.glossaryIds, isEmpty);
      await tester.tap(find.text('技术'));
      await tester.pump();
      expect(form.options.glossaryIds, ['b']);
    });

    testWidgets('文案收窄：翻译要求只管风格，专有名词指向词表', (tester) async {
      final form = TranslateFormController(settings: settings);
      addTearDown(form.dispose);
      await pump(
        tester,
        ListenableBuilder(
          listenable: form,
          builder: (_, _) => TranslateLanguageSection(form: form),
        ),
      );
      expect(find.text('翻译要求（可选）'), findsOneWidget);
      expect(find.text('风格与说明；专有名词请用词表。仅用于本次任务。'), findsOneWidget);
      expect(find.textContaining('原文=译文'), findsNothing);
    });
  });
}
