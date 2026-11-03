@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/features/settings/model_list_editor.dart';

void main() {
  setUpAll(() async {
    final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (!font.existsSync()) return;
    final bytes = font.readAsBytesSync().buffer.asByteData();
    for (final family in ['Noto Sans SC', 'JetBrains Mono']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  for (final (id, dark, width) in [
    ('openai_chat', false, 880.0),
    ('deepseek', true, 600.0),
    ('openai_none', true, 600.0),
    ('bailian_api', false, 880.0),
    ('volcengine_agent_plan', true, 600.0),
  ]) {
    testWidgets('翻译模型高级配置 · $id', (tester) async {
      tester.view..physicalSize = Size(width, 1000)..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final info = ProviderCatalog.translationInfo(id == 'openai_none' ? 'openai_chat' : id)!;
      final model = id == 'openai_none'
          ? info.presets.firstWhere((m) => m.name == 'gpt-6.1-terra')
              .withOption('reasoningEffort', 'none') : info.presets.first;
      final theme = dark ? darkTheme : lightTheme;
      await tester.pumpWidget(MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Noto Sans SC'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Noto Sans SC')),
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: ModelListEditor(models: [model], presets: info.presets,
            nameHint: '模型名', validate: (_) => null, suggestChat: info.guess,
            onAdd: (_, _, _) {}, onAddPreset: (_) {}, onSetDefault: (_) {},
            onRemove: (_) {}, onOptionChanged: (_, _, _) {}, onChatChanged: (_) {}))),
      ));
      await tester.tap(find.text('配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高级接入配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上下文与输出预算'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(Scaffold), matchesGoldenFile('translation_model_$id.png'));
    });
  }
}
