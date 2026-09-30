import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/buttons.dart';
import 'package:subtitle_studio/core/widgets/fields.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/features/settings/model_list_editor.dart';
import 'package:subtitle_studio/features/settings/provider_section.dart';
import 'package:subtitle_studio/features/settings/settings_section.dart';
import 'package:subtitle_studio/services/settings.dart';

const _bailian = 'dashscope_qwen_asr';

void main() {
  late AppSettings settings;

  /// 每次写设置记一笔，用来查「这一步有没有写」。
  late int writes;

  Future<void> load([Map<String, Object> configs = const {}]) async {
    SharedPreferences.setMockInitialValues({
      if (configs.isNotEmpty) 'providerConfigs': jsonEncode(configs),
    });
    settings = await AppSettings.load();
    writes = 0;
    settings.addListener(() => writes++);
  }

  /// 把一个服务分区摆出来。宽度取设置页内容列的上限。
  Future<void> pump(
    WidgetTester tester,
    ProviderKind kind, {
    double width = 880,
    bool stacked = false,
  }) async {
    tester.view
      ..physicalSize = Size(width + 48, 1400)
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
              builder: (context, _) => ProviderSection(
                kind: kind,
                settings: settings,
                stacked: stacked,
                keyVisible: false,
                onToggleKeyVisible: () {},
                onChanged: ({bool typed = false}) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  final nameField = find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('模型名'),
  );
  Finder row(String name) => find.byKey(ValueKey(name));
  Finder inRow(String name, Finder what) =>
      find.descendant(of: row(name), matching: what);
  Finder inEditor(Finder what) =>
      find.descendant(of: find.byType(ModelListEditor), matching: what);

  /// 列表里现在有哪些行，按显示顺序。
  List<String> rows(WidgetTester tester) => [
    for (final w in tester.widgetList(
      // 编辑器里带字符串 key 的只有模型行（key 就是模型名）。
      inEditor(find.byWidgetPredicate((w) => w.key is ValueKey<String>)),
    ))
      (w.key! as ValueKey<String>).value,
  ];

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(nameField, text);
    await tester.pump();
  }

  Future<void> add(WidgetTester tester, String text) async {
    await type(tester, text);
    await tester.tap(find.text('添加'));
    await tester.pump();
  }

  List<ModelSpec> stored(String id) => settings.configFor(id).models;

  group('空列表', () {
    testWidgets('有常用列表的服务：说明新建任务用常用列表，服务仍算已配置', (tester) async {
      await load({
        'groq': {'apiKey': 'sk-x'},
      });
      settings.asrProviderId = 'groq';
      await pump(tester, ProviderKind.asr);

      expect(find.text('未添加模型，新建任务时使用常用列表'), findsOneWidget);
      expect(find.text('已配置'), findsOneWidget);
      expect(rows(tester), isEmpty);
      // 常用里列着全部预置，一个都还没加。
      expect(inEditor(find.text('whisper-large-v3')), findsOneWidget);
      expect(inEditor(find.text('whisper-large-v3-turbo')), findsOneWidget);
      // 占位举的例子是这家服务自己的模型。
      expect(
        tester.widget<TextField>(nameField).decoration?.hintText,
        '模型名，例 whisper-large-v3',
      );
    });

    testWidgets('没有常用列表的服务：必须添加一个，横幅说添加后恢复可用', (tester) async {
      await load({
        'mt_custom': {'baseUrl': 'https://x/v1', 'apiKey': 'sk-x'},
      });
      settings.translationProviderId = 'mt_custom';
      await pump(tester, ProviderKind.mt);

      expect(find.text('至少添加一个模型'), findsOneWidget);
      expect(find.text('未配置'), findsOneWidget);
      expect(find.text('还没有添加模型。添加后「开始翻译」会自动恢复可用，已排队的任务不会丢失。'), findsOneWidget);
      expect(find.text('常用'), findsNothing);
      expect(
        tester.widget<TextField>(nameField).decoration?.hintText,
        '模型名，例 deepseek-chat',
      );

      await add(tester, 'my-model');
      expect(find.text('至少添加一个模型'), findsNothing);
      expect(find.text('已配置'), findsOneWidget);
      expect(stored('mt_custom'), const [ChatModelSpec(name: 'my-model')]);
    });
  });

  group('添加', () {
    testWidgets('空着不报错，只是不能添加', (tester) async {
      await load();
      await pump(tester, ProviderKind.mt);
      expect(
        tester
            .widget<ControlButton>(find.widgetWithText(ControlButton, '添加'))
            .onPressed,
        isNull,
      );
      await type(tester, '   ');
      expect(inEditor(find.byType(InlineNote)), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(writes, 0);
    });

    testWidgets('校验不过：当场说原因，加不进列表', (tester) async {
      await load({
        'deepseek': {
          'models': [const ChatModelSpec(name: 'deepseek-chat').toJson()],
        },
      });
      await pump(tester, ProviderKind.mt);

      for (final (input, reason) in [
        ('gpt 4o', '模型名不能含空格或逗号'),
        ('a,b', '模型名不能含空格或逗号'),
        ('a，b', '模型名不能含空格或逗号'),
        ('gpt​4o', '模型名里有不可见字符'),
        ('a' * 129, '模型名不能超过 128 个字符'),
        (' deepseek-chat ', '列表里已经有 deepseek-chat'),
      ]) {
        await type(tester, input);
        expect(find.text(reason), findsOneWidget, reason: input);
        await tester.tap(find.text('添加'));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }
      expect(writes, 0);
      expect(rows(tester), ['deepseek-chat']);
    });

    testWidgets('打字途中不写设置，确认了才写', (tester) async {
      await load();
      await pump(tester, ProviderKind.mt);
      for (final partial in ['d', 'deep', 'deepseek-v', 'deepseek-v3']) {
        await type(tester, partial);
      }
      // 建任务表单按「模型还等于设置里的默认」判断要不要跟着设置走：
      // 逐键写设置会在打字途中把用户选的模型带走。
      expect(writes, 0);

      await tester.tap(find.text('添加'));
      await tester.pump();
      expect(writes, 1);
      expect(stored('deepseek'), const [ChatModelSpec(name: 'deepseek-v3')]);
    });

    testWidgets('回车添加并清空，焦点留在框里接着加；首尾空白去掉', (tester) async {
      await load();
      await pump(tester, ProviderKind.mt);
      await type(tester, '  model-a ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(rows(tester), ['model-a']);
      final field = tester.widget<TextField>(nameField);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);

      await type(tester, 'model-b');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(rows(tester), ['model-a', 'model-b']);
      // 先加的是默认。
      expect(inRow('model-a', find.text('默认')), findsOneWidget);
      expect(inRow('model-b', find.text('默认')), findsNothing);
    });

    testWidgets('Esc 清空输入与错误', (tester) async {
      await load();
      await pump(tester, ProviderKind.mt);
      await type(tester, 'a b');
      expect(find.text('模型名不能含空格或逗号'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.widget<TextField>(nameField).controller!.text, isEmpty);
      expect(find.text('模型名不能含空格或逗号'), findsNothing);
      expect(writes, 0);
    });

    testWidgets('旧版本存的那串模型名照样列出来，第一次改动后存成声明', (tester) async {
      await load({
        'deepseek': {'model': 'my-chat，deepseek-chat', 'apiKey': 'sk-x'},
      });
      await pump(tester, ProviderKind.mt);
      expect(rows(tester), ['my-chat', 'deepseek-chat']);
      expect(stored('deepseek'), isEmpty);

      await add(tester, 'third');
      expect(stored('deepseek'), const [
        ChatModelSpec(name: 'my-chat'),
        ChatModelSpec(name: 'deepseek-chat'),
        ChatModelSpec(name: 'third'),
      ]);
      final config = settings.configFor('deepseek');
      expect(config.legacyModelText, isNull);
      expect(config.apiKey, 'sk-x');
    });
  });

  group('常用', () {
    testWidgets('点一下按预置声明加到末尾，加过的不再列出；全加完整行消失', (tester) async {
      await load();
      settings.asrProviderId = 'siliconflow';
      await pump(tester, ProviderKind.asr);
      final preset = ProviderCatalog.asrInfo('siliconflow')!.presets.single;

      expect(find.text('常用'), findsOneWidget);
      await tester.tap(inEditor(find.text(preset.name)));
      await tester.pump();

      // 预置的语种限制跟着进了列表。
      expect(stored('siliconflow'), [preset]);
      expect(inRow(preset.name, find.text('语种受限')), findsOneWidget);
      expect(find.text('常用'), findsNothing);
    });

    testWidgets('手填一个与预置同名的：得到的就是预置那份声明', (tester) async {
      await load();
      settings.asrProviderId = 'siliconflow';
      await pump(tester, ProviderKind.asr);
      await add(tester, 'FunAudioLLM/SenseVoiceSmall');
      expect(
        stored('siliconflow').single,
        same(ProviderCatalog.asrInfo('siliconflow')!.presets.single),
      );
      expect(find.text('常用'), findsNothing);
    });
  });

  group('设为默认与删除', () {
    Future<void> three(WidgetTester tester) async {
      await load({
        'deepseek': {
          'models': [
            for (final name in ['a', 'b', 'c'])
              ChatModelSpec(name: name).toJson(),
          ],
        },
      });
      await pump(tester, ProviderKind.mt);
    }

    testWidgets('设为默认：挪到第一位，其余顺延；第一行没有这个按钮', (tester) async {
      await three(tester);
      expect(inRow('a', find.byTooltip('设为默认')), findsNothing);

      await tester.tap(inRow('c', find.byTooltip('设为默认')));
      await tester.pump();
      expect(rows(tester), ['c', 'a', 'b']);
      expect(inRow('c', find.text('默认')), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(
        settings
            .defaultChatModel(ProviderCatalog.translationInfo('deepseek')!)
            .name,
        'c',
      );
    });

    testWidgets('删除不询问；删掉默认行后第二行成为默认', (tester) async {
      await three(tester);
      await tester.tap(inRow('a', find.byTooltip('删除')));
      await tester.pump();
      expect(rows(tester), ['b', 'c']);
      expect(inRow('b', find.text('默认')), findsOneWidget);
    });

    testWidgets('删光：回到空列表，新建任务重新用常用列表', (tester) async {
      await load({
        'deepseek': {
          'models': [const ChatModelSpec(name: 'mine').toJson()],
        },
      });
      await pump(tester, ProviderKind.mt);
      await tester.tap(inRow('mine', find.byTooltip('删除')));
      await tester.pump();

      expect(find.text('未添加模型，新建任务时使用常用列表'), findsOneWidget);
      final deepseek = ProviderCatalog.translationInfo('deepseek')!;
      expect(settings.chatModelsFor(deepseek), same(deepseek.presets));
    });
  });

  group('接入方式与模型族（百炼）', () {
    setUp(() async {
      await load({
        _bailian: {'apiKey': 'sk-x'},
      });
      settings.asrProviderId = _bailian;
    });

    testWidgets('模型行带声明标签与能力；说明里点名要标明接入方式', (tester) async {
      final presets = ProviderCatalog.asrInfo(_bailian)!.presets;
      settings.setModels(_bailian, [presets[0], presets[3], presets[1]]);
      await pump(tester, ProviderKind.asr);

      expect(find.textContaining('阿里百炼的模型要标明接入方式与模型族'), findsOneWidget);
      // 同步的 Qwen3-ASR：接受提示，不能分离。
      expect(inRow(presets[0].name, find.text('同步逐段')), findsOneWidget);
      expect(inRow(presets[0].name, find.text('Qwen3-ASR')), findsOneWidget);
      expect(inRow(presets[0].name, find.text('提示词')), findsOneWidget);
      expect(inRow(presets[0].name, find.text('说话人分离')), findsNothing);
      // 录音文件转写的 Qwen-Audio 3.0：能分离，不接受提示。
      expect(inRow(presets[3].name, find.text('异步整文件')), findsOneWidget);
      expect(
        inRow(presets[3].name, find.text('Qwen-Audio 3.0')),
        findsOneWidget,
      );
      expect(inRow(presets[3].name, find.text('说话人分离')), findsOneWidget);
      expect(inRow(presets[3].name, find.text('提示词')), findsNothing);
      // 同步的 Qwen-Audio 3.0：两样都没有。
      expect(inRow(presets[1].name, find.text('提示词')), findsNothing);
      expect(inRow(presets[1].name, find.text('说话人分离')), findsNothing);
    });

    testWidgets('按名字预填两组分段并说明是猜的', (tester) async {
      await pump(tester, ProviderKind.asr);
      PillSegments<AsrTransport> transport() =>
          tester.widget(find.byType(PillSegments<AsrTransport>));
      PillSegments<DashScopeDialect> dialect() =>
          tester.widget(find.byType(PillSegments<DashScopeDialect>));

      expect(transport().value, AsrTransport.dashscopeSync);
      expect(dialect().value, DashScopeDialect.qwen3Asr);
      expect(find.textContaining('已按名字预填'), findsNothing);

      await type(tester, 'fun-asr-2026-filetrans');
      expect(transport().value, AsrTransport.dashscopeFileTrans);
      expect(dialect().value, DashScopeDialect.funAsr);
      expect(find.text('已按名字预填「异步整文件 · Fun-ASR」，不对可以改'), findsOneWidget);

      await tester.tap(find.text('添加'));
      await tester.pump();
      expect(stored(_bailian), const [
        AsrModelSpec(
          name: 'fun-asr-2026-filetrans',
          transport: AsrTransport.dashscopeFileTrans,
          dialect: DashScopeDialect.funAsr,
        ),
      ]);
      // 加完回到初始的分段，下一个名字重新预填。
      expect(transport().value, AsrTransport.dashscopeSync);
      expect(dialect().value, DashScopeDialect.qwen3Asr);
    });

    testWidgets('手动点过分段之后不再跟着名字变，照用户选的存', (tester) async {
      await pump(tester, ProviderKind.asr);
      await type(tester, 'my');
      // 分段在添加行里；模型行的标签用的是同样的字，但这时列表是空的。
      await tester.tap(find.text('异步整文件'));
      await tester.tap(find.text('Fun-ASR'));
      await tester.pump();
      expect(find.textContaining('已按名字预填'), findsNothing);

      // 名字本身按规律会被猜成「同步逐段 · Qwen3-ASR」。
      await type(tester, 'my-model');
      expect(
        tester
            .widget<PillSegments<AsrTransport>>(
              find.byType(PillSegments<AsrTransport>),
            )
            .value,
        AsrTransport.dashscopeFileTrans,
      );
      await tester.tap(find.text('添加'));
      await tester.pump();
      expect(stored(_bailian), const [
        AsrModelSpec(
          name: 'my-model',
          transport: AsrTransport.dashscopeFileTrans,
          dialect: DashScopeDialect.funAsr,
        ),
      ]);
      // 自填的名字不合命名规律，照样按声明得出能力。
      expect(inRow('my-model', find.text('说话人分离')), findsOneWidget);
    });

    testWidgets('默认模型不接受上下文提示：提示框下说一声，框不禁用', (tester) async {
      const note = '当前默认模型不接受上下文提示，词表与识别提示不会发送';
      final presets = ProviderCatalog.asrInfo(_bailian)!.presets;
      await pump(tester, ProviderKind.asr);
      // 没配过：默认是预置第一个（同步 Qwen3-ASR），接受提示。
      expect(find.text(note), findsNothing);

      settings.setModels(_bailian, [presets[3], presets[0]]);
      await tester.pump();
      expect(find.text(note), findsOneWidget);
      expect(find.byType(MultilineField), findsOneWidget);

      await tester.tap(inRow(presets[0].name, find.byTooltip('设为默认')));
      await tester.pump();
      expect(find.text(note), findsNothing);
    });
  });

  testWidgets('只有一种接入方式的服务：没有分段，没有声明标签', (tester) async {
    await load({
      'openai': {
        'models': [
          const AsrModelSpec(
            name: 'whisper-1',
            transport: AsrTransport.openaiTranscription,
          ).toJson(),
        ],
      },
    });
    await pump(tester, ProviderKind.asr);

    expect(find.byType(PillSegments<AsrTransport>), findsNothing);
    expect(find.byType(PillSegments<DashScopeDialect>), findsNothing);
    expect(find.text(AsrTransport.openaiTranscription.label), findsNothing);
    expect(find.textContaining('接入方式'), findsNothing);
    // 能力照样显示。
    expect(inRow('whisper-1', find.text('提示词')), findsOneWidget);

    await type(tester, 'gpt-4o-transcribe');
    expect(find.textContaining('已按名字预填'), findsNothing);
  });

  group('参数面板', () {
    testWidgets('同一时间只展开一行；行首箭头与「参数」都能开合', (tester) async {
      await load({
        'deepseek': {
          'models': [
            for (final name in ['a', 'b']) ChatModelSpec(name: name).toJson(),
          ],
        },
      });
      await pump(tester, ProviderKind.mt);
      const footnote = '参数随任务入队时定下，改动只影响之后新建的任务。';
      expect(find.text(footnote), findsNothing);

      await tester.tap(inRow('a', find.byTooltip('展开参数')));
      await tester.pumpAndSettle();
      expect(inRow('a', find.text(footnote)), findsOneWidget);

      await tester.tap(inRow('b', find.byTooltip('参数')));
      await tester.pumpAndSettle();
      expect(inRow('a', find.text(footnote)), findsNothing);
      expect(inRow('b', find.text(footnote)), findsOneWidget);

      await tester.tap(inRow('b', find.byTooltip('收起参数')));
      await tester.pumpAndSettle();
      expect(find.text(footnote), findsNothing);
    });

    testWidgets('展开的面板跟着模型走，不跟着位置', (tester) async {
      await load({
        'deepseek': {
          'models': [
            for (final name in ['a', 'b']) ChatModelSpec(name: name).toJson(),
          ],
        },
      });
      await pump(tester, ProviderKind.mt);
      await tester.tap(inRow('b', find.byTooltip('参数')));
      await tester.pumpAndSettle();
      await tester.tap(inRow('b', find.byTooltip('设为默认')));
      await tester.pumpAndSettle();

      expect(rows(tester), ['b', 'a']);
      expect(inRow('b', find.text('temperature')), findsOneWidget);
      expect(inRow('a', find.text('temperature')), findsNothing);
    });

    testWidgets('开关：逆文本规范化写回这个模型的声明', (tester) async {
      await load();
      settings.asrProviderId = _bailian;
      final preset = ProviderCatalog.asrInfo(_bailian)!.presets.first;
      settings.setModels(_bailian, [preset]);
      await pump(tester, ProviderKind.asr);
      await tester.tap(inRow(preset.name, find.byTooltip('参数')));
      await tester.pumpAndSettle();

      expect(find.text('逆文本规范化'), findsOneWidget);
      expect(
        tester.widget<AppSwitch>(inEditor(find.byType(AppSwitch))).value,
        isTrue,
      );

      await tester.tap(inEditor(find.byType(AppSwitch)));
      await tester.pump();
      final spec = stored(_bailian).single;
      expect(spec.options.flag(ModelParams.enableItn), isFalse);
      expect(spec.toJson()['options'], {'enable_itn': false});

      // 整行都能点；改回默认值后声明与预置那份相等，存档里不留这一项。
      await tester.tap(find.text('逆文本规范化'));
      await tester.pump();
      expect(stored(_bailian).single, preset);
      expect(stored(_bailian).single.toJson().containsKey('options'), isFalse);
    });

    testWidgets('数字：失焦才写回，越界夹住；打的不是数就回到原值', (tester) async {
      await load({
        'deepseek': {
          'models': [const ChatModelSpec(name: 'deepseek-chat').toJson()],
        },
      });
      await pump(tester, ProviderKind.mt);
      await tester.tap(inRow('deepseek-chat', find.byTooltip('参数')));
      await tester.pumpAndSettle();
      final number = inRow('deepseek-chat', find.byType(TextField));
      TextField field() => tester.widget<TextField>(number);
      double? temperature() => (stored('deepseek').single as ChatModelSpec)
          .options
          .number(ModelParams.chatTemperature);

      expect(field().controller!.text, '0.3');

      await tester.enterText(number, '0.7');
      await tester.pump();
      expect(writes, 0);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(temperature(), 0.7);

      // 只收数字与一个小数点、一位小数。
      await tester.enterText(number, '1.25x');
      expect(field().controller!.text, '1.2');

      await tester.enterText(number, '9');
      // 点到别处：失焦提交。
      await tester.tap(nameField);
      await tester.pump();
      expect(temperature(), 2.0);
      expect(field().controller!.text, '2.0');

      final before = writes;
      await tester.enterText(number, '.');
      await tester.tap(nameField);
      await tester.pump();
      expect(field().controller!.text, '2.0');
      expect(writes, before);
    });

    testWidgets('不发送：勾上后数字框置灰，取消勾选回到目录默认值', (tester) async {
      await load({
        'deepseek': {
          'models': [const ChatModelSpec(name: 'deepseek-reasoner').toJson()],
        },
      });
      await pump(tester, ProviderKind.mt);
      await tester.tap(inRow('deepseek-reasoner', find.byTooltip('参数')));
      await tester.pumpAndSettle();
      final number = inRow('deepseek-reasoner', find.byType(TextField));

      await tester.tap(find.text('不发送'));
      await tester.pump();
      final spec = stored('deepseek').single as ChatModelSpec;
      expect(spec.options.has('temperature'), isTrue);
      expect(spec.options.number(ModelParams.chatTemperature), isNull);
      expect(number, findsNothing);
      expect(inRow('deepseek-reasoner', find.text('—')), findsOneWidget);

      await tester.tap(find.text('不发送'));
      await tester.pump();
      expect(
        stored('deepseek').single,
        const ChatModelSpec(name: 'deepseek-reasoner'),
      );
      expect(tester.widget<TextField>(number).controller!.text, '0.3');
    });

    testWidgets('默认就不发送的参数：取消勾选从下限起', (tester) async {
      await load({
        'openai': {
          'models': [
            const AsrModelSpec(
              name: 'whisper-1',
              transport: AsrTransport.openaiTranscription,
            ).toJson(),
          ],
        },
      });
      await pump(tester, ProviderKind.asr);
      await tester.tap(inRow('whisper-1', find.byTooltip('参数')));
      await tester.pumpAndSettle();
      expect(inRow('whisper-1', find.text('—')), findsOneWidget);

      await tester.tap(find.text('不发送'));
      await tester.pump();
      expect(
        (stored('openai').single as AsrModelSpec).options.number(
          ModelParams.asrTemperature,
        ),
        0.0,
      );
    });

    testWidgets('没有可调参数的模型：只有一句说明', (tester) async {
      await load();
      settings.asrProviderId = _bailian;
      final preset = ProviderCatalog.asrInfo(_bailian)!.presets[3];
      settings.setModels(_bailian, [preset]);
      await pump(tester, ProviderKind.asr);
      await tester.tap(inRow(preset.name, find.byTooltip('参数')));
      await tester.pumpAndSettle();

      expect(inRow(preset.name, find.text('该模型没有可调参数')), findsOneWidget);
      expect(inRow(preset.name, find.byType(AppSwitch)), findsNothing);
      expect(inRow(preset.name, find.byType(TextField)), findsNothing);
    });
  });

  testWidgets('窄窗（960）下不溢出：标签折行，分段折到下一行', (tester) async {
    await load({
      _bailian: {'apiKey': 'sk-x'},
    });
    settings
      ..asrProviderId = _bailian
      ..setModels(_bailian, ProviderCatalog.asrInfo(_bailian)!.presets);
    // 960 窗口：标签堆到控件上方，内容列约 800；再窄一档确认折行兜得住。
    for (final width in [800.0, 640.0]) {
      await pump(tester, ProviderKind.asr, width: width, stacked: true);
      expect(tester.takeException(), isNull, reason: '$width');
      expect(rows(tester), hasLength(5));
      // 名字长到要折行的那一行，标签没有被挤出去。
      expect(
        inRow('qwen-audio-3.0-asr-flash-filetrans', find.text('说话人分离')),
        findsOneWidget,
      );
    }
  });

  testWidgets('换服务：添加行里打到一半的名字不带到另一家', (tester) async {
    await load();
    await pump(tester, ProviderKind.mt);
    await type(tester, 'half-typed');
    settings.translationProviderId = 'openai_chat';
    await tester.pump();
    expect(tester.widget<TextField>(nameField).controller!.text, isEmpty);
  });
}
