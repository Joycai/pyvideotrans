import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:subtitle_studio/services/settings.dart';

const _bailian = 'dashscope_qwen_asr';

void main() {
  late AppSettings settings;

  /// 每次写设置记一笔，用来查「这一步有没有写」。
  late int writes;

  Future<void> load([Map<String, Object> configs = const {}]) async {
    SharedPreferences.setMockInitialValues({
      'asrProviderId': 'openai',
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
    Widget Function(Widget child)? wrap,
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
              builder: (context, _) {
                final section = ProviderSection(
                  kind: kind,
                  settings: settings,
                  stacked: stacked,
                  keyVisible: false,
                  onToggleKeyVisible: () {},
                  onChanged: ({bool typed = false}) {},
                );
                return wrap?.call(section) ?? section;
              },
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
    if (nameField.evaluate().isEmpty) {
      await tester.tap(find.text('添加模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义模型'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(nameField, text);
    await tester.pump();
  }

  Future<void> add(WidgetTester tester, String text) async {
    await type(tester, text);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
  }

  List<ModelSpec> stored(String id) => settings.configFor(id).models;


  Future<void> menu(WidgetTester tester, String name, String action) async {
    await tester.ensureVisible(inRow(name, find.byTooltip('更多操作')));
    await tester.tap(inRow(name, find.byTooltip('更多操作')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('添加表单按需打开；取消不写入设置', (tester) async {
    await load();
    await pump(tester, ProviderKind.mt);
    expect(nameField, findsNothing);
    await type(tester, 'draft-model');
    expect(writes, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(nameField, findsNothing);
    expect(writes, 0);
  });

  testWidgets('自定义添加保留内置候选和默认，输入校验阻止重复', (tester) async {
    await load();
    await pump(tester, ProviderKind.mt);
    final defaults = ProviderCatalog.translationInfo('deepseek')!.presets;
    await add(tester, ' custom-model ');
    expect(stored('deepseek').last.name, 'custom-model');
    expect(stored('deepseek').first.name, defaults.first.name);
    await type(tester, 'custom-model');
    expect(tester.widget<ControlButton>(find.widgetWithText(ControlButton, '添加')).onPressed, isNull);
    await tester.enterText(nameField, 'bad model');
    await tester.pump();
    expect(tester.widget<ControlButton>(find.widgetWithText(ControlButton, '添加')).onPressed, isNull);
  });

  testWidgets('内置搜索添加保留完整 Message 声明，已添加不能重复选', (tester) async {
    await load();
    settings.asrProviderId = _bailian;
    final presets = ProviderCatalog.asrInfo(_bailian)!.presets;
    settings.setModels(_bailian, [presets.first]);
    await pump(tester, ProviderKind.asr);
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    expect(find.text('已添加'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '3.1-asr-flash-message');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen Audio 3.1 · 流式文件转写'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加所选模型'));
    await tester.pumpAndSettle();
    expect(stored(_bailian).last, presets.last);
    expect((stored(_bailian).last as AsrModelSpec).transport, AsrTransport.dashscopeMessage);
  });

  testWidgets('移除默认模型先说明接替者；取消不修改，确认后切换默认', (tester) async {
    await load({'deepseek': {'models': [for (final n in ['a', 'b']) ChatModelSpec(name: n).toJson()]}});
    await pump(tester, ProviderKind.mt);
    await menu(tester, 'a', '移除模型');
    expect(find.text('默认模型将改为 b。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['a', 'b']);
    await menu(tester, 'a', '移除模型');
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['b']);
    await menu(tester, 'b', '移除模型');
    expect(find.text('移除最后一项后，将恢复使用内置模型列表。'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(stored('deepseek'), isEmpty);
  });

  testWidgets('窄窗口长 ID 和自定义接入配置无溢出', (tester) async {
    await load();
    settings.asrProviderId = _bailian;
    settings.setModels(_bailian, ProviderCatalog.asrInfo(_bailian)!.presets);
    await pump(tester, ProviderKind.asr, width: 480, stacked: true);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('添加模型'));
    await type(tester, 'custom-qwen');
    expect(tester.takeException(), isNull);
    expect(find.text('接入方式'), findsOneWidget);
  });
  group('参数面板', () {
    testWidgets('同一时间只展开一行；配置按钮开合', (tester) async {
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

      await tester.tap(inRow('a', find.text('配置')));
      await tester.pumpAndSettle();
      expect(inRow('a', find.text(footnote)), findsOneWidget);

      await tester.tap(inRow('b', find.text('配置')));
      await tester.pumpAndSettle();
      expect(inRow('a', find.text(footnote)), findsNothing);
      expect(inRow('b', find.text(footnote)), findsOneWidget);

      await tester.tap(inRow('b', find.text('收起')));
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
      await tester.tap(inRow('b', find.text('配置')));
      await tester.pumpAndSettle();
      await menu(tester, 'b', '设为默认');
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
      await tester.tap(inRow(preset.name, find.text('配置')));
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
      await tester.tap(inRow('deepseek-chat', find.text('配置')));
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
      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pump();
      expect(temperature(), 2.0);
      expect(field().controller!.text, '2.0');

      final before = writes;
      await tester.enterText(number, '.');
      tester.binding.focusManager.primaryFocus?.unfocus();
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
      await tester.tap(inRow('deepseek-reasoner', find.text('配置')));
      await tester.pumpAndSettle();
      final number = inRow('deepseek-reasoner', find.byType(TextField));
      // 先改成别的值：取消「不发送」之后框里得是默认值，不是这个旧值。
      await tester.enterText(number, '0.7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

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
      await tester.tap(inRow('whisper-1', find.text('配置')));
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
      await tester.tap(inRow(preset.name, find.text('配置')));
      await tester.pumpAndSettle();

      expect(inRow(preset.name, find.text('该模型没有可调参数')), findsOneWidget);
      expect(inRow(preset.name, find.byType(AppSwitch)), findsNothing);
      expect(inRow(preset.name, find.byType(TextField)), findsNothing);
    });
  });

}
