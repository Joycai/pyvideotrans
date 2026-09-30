import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/features/shared/provider_fields.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_form.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_recognize_section.dart';
import 'package:subtitle_studio/services/settings.dart';

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

  AppDropdown<String> dropdown(WidgetTester tester) =>
      tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>));

  List<String> entries(WidgetTester tester) => [
    for (final g in dropdown(tester).groups)
      for (final e in g.entries) e.value,
  ];

  testWidgets('设置里逗号分隔的模型成为候选，第一个是默认选中', (tester) async {
    final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
    settings.setConfig(
      info.id,
      const ProviderConfig(
        legacyModelText: 'qwen-audio-3.0-asr-flash, fun-asr-flash',
      ),
    );
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultAsrModel(info),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'qwen-audio-3.0-asr-flash');
    expect(entries(tester), ['qwen-audio-3.0-asr-flash', 'fun-asr-flash']);
    // 服务下拉旁的标签也得是这个模型，而不是登记表默认值。
    expect(
      serviceLabel(info, settings.defaultAsrModel(info)),
      '阿里百炼 · Qwen3-ASR · qwen-audio-3.0-asr-flash',
    );
  });

  testWidgets('设置里只填一个模型时，下拉也只列这一个，不再显示登记表默认值', (tester) async {
    final info = ProviderCatalog.asrInfo('openai')!;
    settings.setConfig(
      info.id,
      const ProviderConfig(legacyModelText: 'my-whisper'),
    );
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultAsrModel(info),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'my-whisper');
    expect(entries(tester), ['my-whisper']);
  });

  testWidgets('没填时用登记表的常用列表；任务里覆盖的模型即使不在候选里也列出来', (tester) async {
    final info = ProviderCatalog.asrInfo('openai')!;
    await pump(
      tester,
      modelField(
        info: info,
        model: info.guess('gpt-4o-transcribe'),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'gpt-4o-transcribe');
    expect(entries(tester), [for (final p in info.presets) p.name]);

    await pump(
      tester,
      modelField(
        info: info,
        model: info.guess('legacy-model'),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'legacy-model');
    expect(entries(tester).first, 'legacy-model');
  });

  testWidgets('只登记了一个默认模型的翻译服务：没填时给输入框，可以手填', (tester) async {
    // Ollama、OpenRouter 的模型是用户自己挑的，登记表里那一个只是例子。
    for (final id in ['siliconflow_chat', 'openrouter', 'ollama']) {
      final info = ProviderCatalog.translationInfo(id)!;
      await pump(
        tester,
        modelField(
          info: info,
          model: settings.defaultChatModel(info),
          settings: settings,
          onChanged: (_) {},
        ),
      );
      expect(find.byType(AppDropdown<String>), findsNothing, reason: id);
      final field = tester.widget<SingleLineField>(
        find.byType(SingleLineField),
      );
      // 框里先放着默认模型：不改就用它。
      expect(field.value, info.presets.single.name, reason: id);
    }
  });

  testWidgets('在下拉里选中的是整份声明，不只是名字', (tester) async {
    final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
    final picked = <AsrModelSpec>[];
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultAsrModel(info),
        settings: settings,
        onChanged: picked.add,
      ),
    );
    dropdown(tester).onChanged('qwen-audio-3.0-asr-flash-filetrans');
    // 接入方式与报文族跟着一起来：任务冻结的就是这一份。
    expect(picked.single, same(info.presets[3]));
    expect(picked.single.transport, AsrTransport.dashscopeFileTrans);
  });

  testWidgets('手填：填了按名字补成声明，清空回到默认模型', (tester) async {
    final custom = ProviderCatalog.asrInfo('asr_custom')!;
    final typed = <AsrModelSpec>[];
    await pump(
      tester,
      modelField(
        info: custom,
        model: settings.defaultAsrModel(custom),
        settings: settings,
        onChanged: typed.add,
      ),
    );
    final field = tester.widget<SingleLineField>(find.byType(SingleLineField));
    field.onChanged(' my-whisper ');
    field.onChanged('  ');
    expect(typed, [
      const AsrModelSpec(
        name: 'my-whisper',
        transport: AsrTransport.openaiTranscription,
      ),
      settings.defaultAsrModel(custom),
    ]);
    expect(typed.last.isUnset, isTrue);

    // 翻译侧同理：清空回到登记表里那个例子。
    final ollama = ProviderCatalog.translationInfo('ollama')!;
    final chat = <ChatModelSpec>[];
    await pump(
      tester,
      modelField(
        info: ollama,
        model: settings.defaultChatModel(ollama),
        settings: settings,
        onChanged: chat.add,
      ),
    );
    tester.widget<SingleLineField>(find.byType(SingleLineField))
      ..onChanged('llama3.1')
      ..onChanged('');
    expect(chat, [
      const ChatModelSpec(name: 'llama3.1'),
      ollama.presets.single,
    ]);
  });

  testWidgets('只登记了一个预置的翻译服务：用户配过模型之后就给下拉', (tester) async {
    final info = ProviderCatalog.translationInfo('ollama')!;
    settings.setConfig(
      info.id,
      const ProviderConfig(legacyModelText: 'llama3.1'),
    );
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultChatModel(info),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(find.byType(SingleLineField), findsNothing);
    expect(entries(tester), ['llama3.1']);
  });

  testWidgets('还没选模型的声明：下拉里列成「未选择」，服务标签只有服务名', (tester) async {
    final info = ProviderCatalog.asrInfo('openai')!;
    await pump(
      tester,
      modelField(
        info: info,
        model: info.unsetModel,
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, '');
    expect(
      dropdown(tester).groups.single.entries.first.label,
      '未选择',
    );
    expect(serviceLabel(info, info.unsetModel), 'OpenAI');
    expect(serviceLabel(null, info.unsetModel), '—');
  });

  testWidgets('自定义接口：设置里填了就按填的列，没填才给输入框', (tester) async {
    final info = ProviderCatalog.asrInfo('asr_custom')!;
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultAsrModel(info),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(find.byType(AppDropdown<String>), findsNothing);
    expect(find.byType(SingleLineField), findsOneWidget);

    settings.setConfig(
      info.id,
      const ProviderConfig(legacyModelText: 'whisper-x'),
    );
    await pump(
      tester,
      modelField(
        info: info,
        model: settings.defaultAsrModel(info),
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(find.byType(SingleLineField), findsNothing);
    expect(dropdown(tester).value, 'whisper-x');
    expect(entries(tester), ['whisper-x']);
  });
}

/// 「识别」段里的说话人分离开关。
void _diarizeToggleTests() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load()
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk'))
      ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'sk'));
  });

  Future<TranscribeFormController> pump(
    WidgetTester tester, {
    required String asr,
    bool diarize = false,
  }) async {
    final form = TranscribeFormController(
      settings: settings,
      initial: settings.defaultTaskOptions().copyWith(
        asrProviderId: asr,
        diarize: diarize,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: ListenableBuilder(
              listenable: form,
              builder: (_, _) => TranscribeRecognizeSection(form: form),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return form;
  }

  testWidgets('只有支持的服务才显示开关', (tester) async {
    await pump(tester, asr: 'openai');
    expect(find.text('说话人分离'), findsNothing);

    await pump(tester, asr: 'dashscope_qwen_asr');
    expect(find.text('说话人分离'), findsOneWidget);
  });

  // 「上次参数」里开着分离，而设置里能分离的模型已经删了：开关得留着，
  // 不然参数里一直是开的，界面上没地方关。
  testWidgets('开关开着时总是显示，关掉之后才收起', (tester) async {
    settings.setModels('dashscope_qwen_asr', [
      const AsrModelSpec(
        name: 'qwen3-asr-flash',
        transport: AsrTransport.dashscopeSync,
        dialect: DashScopeDialect.qwen3Asr,
      ),
    ]);
    final form = await pump(tester, asr: 'dashscope_qwen_asr', diarize: true);
    expect(find.text('说话人分离'), findsOneWidget);

    await tester.tap(find.text('说话人分离'));
    await tester.pump();
    expect(form.options.diarize, isFalse);
    expect(find.text('说话人分离'), findsNothing);
  });

  testWidgets('点开关切换参数；换到不支持的服务时参数随之关掉', (tester) async {
    final form = await pump(tester, asr: 'dashscope_qwen_asr');
    await tester.tap(find.text('说话人分离'));
    await tester.pump();
    expect(form.options.diarize, isTrue);

    // 走服务下拉的 onChanged，跟用户真换服务一样。
    final service = tester
        .widgetList<AppDropdown<String>>(find.byType(AppDropdown<String>))
        .firstWhere((d) => d.value == 'dashscope_qwen_asr');
    service.onChanged('openai');
    await tester.pump();
    expect(form.options.asrProviderId, 'openai');
    expect(form.options.diarize, isFalse);
    expect(find.text('说话人分离'), findsNothing);
  });
}
