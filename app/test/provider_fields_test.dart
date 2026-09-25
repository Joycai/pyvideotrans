import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/features/shared/provider_fields.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_form.dart';
import 'package:subtitle_studio/features/transcribe/transcribe_recognize_section.dart';
import 'package:subtitle_studio/services/registry.dart';
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
    final info = Registry.asrInfo('dashscope_qwen_asr')!;
    settings.setConfig(
      info.id,
      const ProviderConfig(model: 'qwen-audio-3.0-asr-flash, fun-asr-flash'),
    );
    await pump(
      tester,
      modelField(
        info: info,
        model: null,
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'qwen-audio-3.0-asr-flash');
    expect(entries(tester), ['qwen-audio-3.0-asr-flash', 'fun-asr-flash']);
    // 服务下拉旁的标签也得是这个模型，而不是登记表默认值。
    expect(
      serviceLabel(info, null, settings),
      '阿里百炼 · Qwen3-ASR · qwen-audio-3.0-asr-flash',
    );
  });

  testWidgets('设置里只填一个模型时，下拉也只列这一个，不再显示登记表默认值', (tester) async {
    final info = Registry.asrInfo('openai')!;
    settings.setConfig(info.id, const ProviderConfig(model: 'my-whisper'));
    await pump(
      tester,
      modelField(
        info: info,
        model: null,
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'my-whisper');
    expect(entries(tester), ['my-whisper']);
  });

  testWidgets('没填时用登记表的常用列表；任务里覆盖的模型即使不在候选里也列出来', (tester) async {
    final info = Registry.asrInfo('openai')!;
    await pump(
      tester,
      modelField(
        info: info,
        model: 'gpt-4o-transcribe',
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'gpt-4o-transcribe');
    expect(entries(tester), info.models);

    await pump(
      tester,
      modelField(
        info: info,
        model: 'legacy-model',
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(dropdown(tester).value, 'legacy-model');
    expect(entries(tester).first, 'legacy-model');
  });

  testWidgets('自定义接口：设置里填了就按填的列，没填才给输入框', (tester) async {
    final info = Registry.asrInfo('asr_custom')!;
    await pump(
      tester,
      modelField(
        info: info,
        model: null,
        settings: settings,
        onChanged: (_) {},
      ),
    );
    expect(find.byType(AppDropdown<String>), findsNothing);
    expect(find.byType(SingleLineField), findsOneWidget);

    settings.setConfig(info.id, const ProviderConfig(model: 'whisper-x'));
    await pump(
      tester,
      modelField(
        info: info,
        model: null,
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
