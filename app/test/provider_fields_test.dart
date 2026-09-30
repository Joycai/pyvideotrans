import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/features/shared/provider_fields.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_form.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_recognize_section.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

const _bailian = 'dashscope_qwen_asr';

/// 「新建转写」「新建翻译」的模型字段：显示的必须就是会发出去的那个模型。
void main() {
  group('说话人分离开关', _diarizeToggleTests);

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
          body: Center(child: SizedBox(width: 360, child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  /// 把模型字段摆出来，像表单那样记住选中的模型并传回去。
  Future<List<T>> pumpField<T extends ModelSpec>(
    WidgetTester tester, {
    required ProviderInfo info,
    required T model,
    VoidCallback? onOpenSettings,
  }) async {
    final emitted = <T>[];
    var current = model;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ModelField<T>(
          info: info,
          model: current,
          settings: settings,
          onOpenSettings: onOpenSettings,
          onChanged: (m) {
            emitted.add(m);
            setState(() => current = m);
          },
        ),
      ),
    );
    return emitted;
  }

  AppDropdown<String> dropdown(WidgetTester tester) =>
      tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>));

  /// 下拉里的模型（不含末尾隔开的「其他模型…」）。
  List<DropdownEntry<String>> models(WidgetTester tester) => [
    for (final g in dropdown(tester).groups)
      if (!g.divided) ...g.entries,
  ];

  List<String> names(WidgetTester tester) => [
    for (final e in models(tester)) e.value,
  ];

  /// 末尾那一项「其他模型…」；没有时为 null。
  DropdownEntry<String>? other(WidgetTester tester) =>
      dropdown(tester).groups
          .where((g) => g.divided)
          .firstOrNull
          ?.entries
          .single;

  Future<void> pickOther(WidgetTester tester) async {
    dropdown(tester).onChanged(other(tester)!.value);
    await tester.pump();
  }

  TextField typing(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  group('候选', () {
    testWidgets('设置里逗号分隔的模型成为候选，第一个是默认选中', (tester) async {
      final info = ProviderCatalog.asrInfo(_bailian)!;
      settings.setConfig(
        info.id,
        const ProviderConfig(
          legacyModelText: 'qwen-audio-3.0-asr-flash, fun-asr-flash',
        ),
      );
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      expect(dropdown(tester).value, 'qwen-audio-3.0-asr-flash');
      expect(names(tester), ['qwen-audio-3.0-asr-flash', 'fun-asr-flash']);
      // 服务下拉旁的标签也得是这个模型，而不是登记表默认值。
      expect(
        serviceLabel(info, settings.defaultAsrModel(info)),
        '阿里百炼 · Qwen3-ASR · qwen-audio-3.0-asr-flash',
      );
    });

    testWidgets('设置里只有一个模型时，下拉也只列这一个，不再显示登记表默认值', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      settings.setConfig(
        info.id,
        const ProviderConfig(legacyModelText: 'my-whisper'),
      );
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      expect(dropdown(tester).value, 'my-whisper');
      expect(names(tester), ['my-whisper']);
    });

    testWidgets('没配过时用登记表的常用列表；不在候选里的模型排在最前', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      await pumpField(
        tester,
        info: info,
        model: info.guess('gpt-4o-transcribe'),
      );
      expect(dropdown(tester).value, 'gpt-4o-transcribe');
      expect(names(tester), [for (final p in info.presets) p.name]);

      // 「上次参数」带来的、设置里已经删掉的模型：照样列出来，别让下拉崩掉。
      await pumpField(tester, info: info, model: info.guess('legacy-model'));
      expect(dropdown(tester).value, 'legacy-model');
      expect(names(tester), [
        'legacy-model',
        for (final p in info.presets) p.name,
      ]);
    });

    testWidgets('在下拉里选中的是整份声明，不只是名字', (tester) async {
      final info = ProviderCatalog.asrInfo(_bailian)!;
      final picked = await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      dropdown(tester).onChanged('qwen-audio-3.0-asr-flash-filetrans');
      // 接入方式与报文族跟着一起来：任务冻结的就是这一份。
      expect(picked.single, same(info.presets[3]));
      expect(picked.single.transport, AsrTransport.dashscopeFileTrans);
    });

    testWidgets('设置里调过参数的模型：选中的是带着参数的那一份', (tester) async {
      final info = ProviderCatalog.translationInfo('deepseek')!;
      settings.setModels(info.id, const [
        ChatModelSpec(name: 'deepseek-chat'),
        ChatModelSpec(
          name: 'deepseek-reasoner',
          options: ModelOptions({'temperature': null}),
        ),
      ]);
      final picked = await pumpField(
        tester,
        info: info,
        model: settings.defaultChatModel(info),
      );
      dropdown(tester).onChanged('deepseek-reasoner');
      expect(picked.single.options.number(ModelParams.chatTemperature), isNull);
    });

    testWidgets('还没选模型的声明：下拉里列成「未选择」，服务标签只有服务名', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      await pumpField(tester, info: info, model: info.unsetModel);
      expect(dropdown(tester).value, '');
      expect(models(tester).first.label, '未选择');
      expect(models(tester).first.description, isNull);
      expect(serviceLabel(info, info.unsetModel), 'OpenAI');
      expect(serviceLabel(null, info.unsetModel), '—');
    });

    testWidgets('未实施的服务：灰掉并说明', (tester) async {
      final info = ProviderCatalog.asrInfo('local_backend')!;
      await pumpField(tester, info: info, model: info.presets.first);
      expect(dropdown(tester).enabled, isFalse);
      expect(find.text('该服务暂不支持切换模型'), findsOneWidget);
    });
  });

  group('每一项的说明', () {
    testWidgets('多接入方式的服务：带接入方式标签与能力摘要', (tester) async {
      final info = ProviderCatalog.asrInfo(_bailian)!;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      expect(
        [for (final e in models(tester)) (e.value, e.badge, e.description)],
        [
          ('qwen3-asr-flash', '同步逐段', '上下文提示 · 切片时间码'),
          ('qwen-audio-3.0-asr-flash', '同步逐段', '切片时间码'),
          ('fun-asr-flash-2026-06-15', '同步逐段', '切片时间码'),
          ('qwen-audio-3.0-asr-flash-filetrans', '异步整文件', '说话人分离 · 句级时间戳'),
          ('qwen3-asr-flash-filetrans', '异步整文件', '句级时间戳'),
        ],
      );
    });

    testWidgets('只有一种接入方式的服务：没有标签，只有能力摘要', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      for (final entry in models(tester)) {
        expect(entry.badge, isNull);
        expect(entry.description, '上下文提示 · 分段时间戳');
      }
    });

    testWidgets('翻译模型：没有标签也没有摘要', (tester) async {
      final info = ProviderCatalog.translationInfo('deepseek')!;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultChatModel(info),
      );
      for (final entry in models(tester)) {
        expect(entry.badge, isNull);
        expect(entry.description, isNull);
      }
    });
  });

  group('其他模型…', () {
    testWidgets('只有一种接入方式的服务：菜单末尾隔开一项', (tester) async {
      // 包括只登记了一个预置的翻译服务：那一个只是例子，想用别的不必先
      // 绕去设置。
      for (final info in <ProviderInfo>[
        ProviderCatalog.asrInfo('openai')!,
        ProviderCatalog.translationInfo('deepseek')!,
        ProviderCatalog.translationInfo('ollama')!,
      ]) {
        await pumpField(tester, info: info, model: settings.defaultModel(info));
        expect(names(tester), [for (final p in info.presets) p.name]);
        expect(other(tester)?.label, '其他模型…', reason: info.id);
        expect(other(tester)?.description, '手动填写模型名，只用于这次任务');
        expect(dropdown(tester).footer, isNull);
      }
    });

    testWidgets('选中后变成输入框；填了按名字补成只用于这次任务的声明', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      final emitted = await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      await pickOther(tester);

      expect(find.byType(AppDropdown<String>), findsNothing);
      expect(typing(tester).controller!.text, isEmpty);
      expect(typing(tester).focusNode!.hasFocus, isTrue);
      expect(find.text('只用于这次任务，不会加进设置里的列表。清空后回到列表。'), findsOneWidget);
      // 还没填：交出去的是「未选择」，就绪检查会拦住，不会拿旧模型去跑。
      expect(emitted.single.isUnset, isTrue);

      await tester.enterText(find.byType(TextField), ' my-whisper ');
      await tester.pump();
      expect(
        emitted.last,
        const AsrModelSpec(
          name: 'my-whisper',
          transport: AsrTransport.openaiTranscription,
        ),
      );
      // 没有写进设置。
      expect(settings.ownModels(info), isEmpty);
    });

    testWidgets('填的名字设置里有：用设置里带着参数的那一份', (tester) async {
      final info = ProviderCatalog.translationInfo('deepseek')!;
      const tuned = ChatModelSpec(
        name: 'deepseek-reasoner',
        options: ModelOptions({'temperature': null}),
      );
      settings.setModels(info.id, const [
        ChatModelSpec(name: 'deepseek-chat'),
        tuned,
      ]);
      final emitted = await pumpField(
        tester,
        info: info,
        model: settings.defaultChatModel(info),
      );
      await pickOther(tester);
      await tester.enterText(find.byType(TextField), 'deepseek-reasoner');
      await tester.pump();
      expect(emitted.last, tuned);
    });

    testWidgets('名字不合法：说明原因，交出「未选择」', (tester) async {
      final info = ProviderCatalog.translationInfo('deepseek')!;
      final emitted = await pumpField(
        tester,
        info: info,
        model: settings.defaultChatModel(info),
      );
      await pickOther(tester);
      await tester.enterText(find.byType(TextField), 'gpt 4o');
      await tester.pump();
      expect(find.text('模型名不能含空格或逗号'), findsOneWidget);
      expect(emitted.last.isUnset, isTrue);

      await tester.enterText(find.byType(TextField), 'gpt-4o');
      await tester.pump();
      expect(find.text('模型名不能含空格或逗号'), findsNothing);
      expect(emitted.last, const ChatModelSpec(name: 'gpt-4o'));
    });

    testWidgets('点 × 回到列表，选回默认模型', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      final emitted = await pumpField(
        tester,
        info: info,
        model: info.presets[1],
      );
      await pickOther(tester);
      await tester.enterText(find.byType(TextField), 'my-whisper');
      await tester.pump();

      await tester.tap(find.byTooltip('回到列表'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(emitted.last, settings.defaultAsrModel(info));
      expect(dropdown(tester).value, info.presets.first.name);
    });

    testWidgets('清空后失焦：回到列表；填着东西失焦：留在输入框', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      final emitted = await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      await pickOther(tester);
      await tester.enterText(find.byType(TextField), 'my-whisper');
      await tester.pump();
      typing(tester).focusNode!.unfocus();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      typing(tester).focusNode!.unfocus();
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(emitted.last, settings.defaultAsrModel(info));
    });

    testWidgets('切去别的应用时丢了焦点：留在输入框，回来接着填', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      await pickOther(tester);

      // 框还空着就去别的应用复制模型名：不能回来发现输入框没了。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      typing(tester).focusNode!.unfocus();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('手填途中参数被别处换掉（重置、上次参数）：回到列表', (tester) async {
      final info = ProviderCatalog.asrInfo('openai')!;
      var model = settings.defaultAsrModel(info);
      late StateSetter rebuild;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ModelField<AsrModelSpec>(
              info: info,
              model: model,
              settings: settings,
              onChanged: (m) => setState(() => model = m),
            );
          },
        ),
      );
      await pickOther(tester);
      await tester.enterText(find.byType(TextField), 'my-whisper');
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      rebuild(() => model = info.presets[2]);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(dropdown(tester).value, info.presets[2].name);
    });
  });

  group('多接入方式的服务（百炼）', () {
    testWidgets('没有「其他模型…」：光有名字不知道怎么接，菜单末尾指路去设置', (tester) async {
      final info = ProviderCatalog.asrInfo(_bailian)!;
      var opened = 0;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
        onOpenSettings: () => opened++,
      );
      expect(other(tester), isNull);

      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      expect(find.text('要用列表外的模型，'), findsOneWidget);
      await tester.tap(find.text('在设置里添加'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      // 菜单跟着收起来了。
      expect(find.text('在设置里添加'), findsNothing);
    });

    testWidgets('宿主没给去处：那句话是纯文字', (tester) async {
      final info = ProviderCatalog.asrInfo(_bailian)!;
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      expect(find.text('要用列表外的模型，在设置里添加'), findsOneWidget);
      expect(find.byType(LinkText), findsNothing);
    });
  });

  group('没有候选的服务（自定义接口）', () {
    testWidgets('一直是输入框：填了按名字补成声明，清空或写坏了交出「未选择」', (tester) async {
      final custom = ProviderCatalog.asrInfo('asr_custom')!;
      final typed = await pumpField(
        tester,
        info: custom,
        model: settings.defaultAsrModel(custom),
      );
      expect(find.byType(AppDropdown<String>), findsNothing);
      // 没有列表可回。
      expect(find.byTooltip('回到列表'), findsNothing);
      expect(typing(tester).decoration?.hintText, '填写模型名');

      await tester.enterText(find.byType(TextField), ' my-whisper ');
      await tester.pump();
      expect(
        typed.last,
        const AsrModelSpec(
          name: 'my-whisper',
          transport: AsrTransport.openaiTranscription,
        ),
      );
      await tester.enterText(find.byType(TextField), 'my whisper');
      await tester.pump();
      expect(typed.last.isUnset, isTrue);
      expect(find.text('模型名不能含空格或逗号'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(typed.last.isUnset, isTrue);
      expect(find.text('模型名不能含空格或逗号'), findsNothing);
      // 失焦也还是输入框。
      typing(tester).focusNode!.unfocus();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('框里先放着任务里的模型；设置里配了模型之后换成下拉', (tester) async {
      final info = ProviderCatalog.asrInfo('asr_custom')!;
      await pumpField(tester, info: info, model: info.guess('from-last-time'));
      expect(typing(tester).controller!.text, 'from-last-time');

      settings.setConfig(
        info.id,
        const ProviderConfig(legacyModelText: 'whisper-x'),
      );
      await pumpField(
        tester,
        info: info,
        model: settings.defaultAsrModel(info),
      );
      expect(find.byType(TextField), findsNothing);
      expect(dropdown(tester).value, 'whisper-x');
      expect(names(tester), ['whisper-x']);
    });
  });
}

/// 「识别」段里的说话人分离开关。
void _diarizeToggleTests() {
  late AppSettings settings;
  final bailian = ProviderCatalog.asrInfo(_bailian)!;
  final capable = bailian.presets[3];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load()
      ..asrProviderId = _bailian
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk'))
      ..setConfig(_bailian, const ProviderConfig(apiKey: 'sk'));
  });

  Future<TranscribeFormController> pump(
    WidgetTester tester, {
    AsrModelSpec? model,
    bool diarize = false,
  }) async {
    final form = TranscribeFormController(
      settings: settings,
      initial: settings.defaultTaskOptions().copyWith(
        asrModel: model,
        diarize: diarize,
      ),
    );
    addTearDown(form.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 720,
              child: ListenableBuilder(
                listenable: form,
                builder: (_, _) => TranscribeRecognizeSection(form: form),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return form;
  }

  /// 识别段里的模型下拉（第三个下拉：语言、服务之后）。
  AppDropdown<String> modelDropdown(WidgetTester tester) => tester
      .widgetList<AppDropdown<String>>(find.byType(AppDropdown<String>))
      .elementAt(2);

  testWidgets('选中的模型能分离才显示开关，不给灰掉的', (tester) async {
    // 默认模型是同步的 Qwen3-ASR：同一家服务，但这个模型不能分离。
    await pump(tester);
    expect(find.text('说话人分离'), findsNothing);

    await pump(tester, model: capable);
    expect(find.text('说话人分离'), findsOneWidget);
    expect(find.text('区分多位说话人，给每条字幕标上说话人编号'), findsOneWidget);
  });

  testWidgets('开着时的说明：时间码来源取自模型的能力，不写模型名', (tester) async {
    final form = await pump(tester, model: capable);
    await tester.tap(find.text('说话人分离'));
    await tester.pump();
    expect(form.options.diarize, isTrue);
    expect(
      find.text(
        '按说话人切开字幕并标上「说话人1：」；多人会议、访谈适用。'
        '时间码取自句级时间戳。',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('filetrans 模型'), findsNothing);
  });

  testWidgets('模型换成不能分离的那一刻：开关关掉并收起', (tester) async {
    final form = await pump(tester, model: capable, diarize: true);
    expect(form.options.diarize, isTrue);

    modelDropdown(tester).onChanged('qwen3-asr-flash');
    await tester.pump();
    expect(form.options.asrModel.name, 'qwen3-asr-flash');
    expect(form.options.diarize, isFalse);
    expect(find.text('说话人分离'), findsNothing);

    // 换回来不会自己打开：用户得再点一次。
    modelDropdown(tester).onChanged(capable.name);
    await tester.pump();
    expect(find.text('说话人分离'), findsOneWidget);
    expect(form.options.diarize, isFalse);
  });

  testWidgets('换到不支持的服务时参数随之关掉', (tester) async {
    final form = await pump(tester, model: capable, diarize: true);
    // 走服务下拉的 onChanged，跟用户真换服务一样。
    final service = tester
        .widgetList<AppDropdown<String>>(find.byType(AppDropdown<String>))
        .firstWhere((d) => d.value == _bailian);
    service.onChanged('openai');
    await tester.pump();
    expect(form.options.asrProviderId, 'openai');
    expect(form.options.diarize, isFalse);
    expect(find.text('说话人分离'), findsNothing);
  });

  testWidgets('手填框里写坏的名字：重置之后不留在框里', (tester) async {
    settings.asrProviderId = 'asr_custom';
    final form = await pump(tester);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '填写模型名',
    );
    await tester.enterText(field, 'my whisper');
    await tester.pump();
    expect(find.text('模型名不能含空格或逗号'), findsOneWidget);
    tester.widget<TextField>(field).focusNode!.unfocus();
    await tester.pump();

    // 自定义接口的默认模型本来就是「未选择」，与写坏时交出去的那份
    // 相等：光比模型看不出参数已经整份换过了。
    form.reset();
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('模型名不能含空格或逗号'), findsNothing);
  });

  testWidgets('初始参数里开着分离而模型不支持：建表单时就关掉', (tester) async {
    // 「上次参数」、旧存档都可能带来这样一份：界面上没有开关，不能让它
    // 悄悄开着进任务。
    final form = await pump(tester, diarize: true);
    expect(form.options.diarize, isFalse);
    expect(find.text('说话人分离'), findsNothing);
  });
}
