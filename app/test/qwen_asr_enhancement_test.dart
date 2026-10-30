import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/services/dashscope_filetrans.dart';
import 'package:subtitle_studio/services/dashscope_message.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/qwen_asr_enhancement.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('热词去重，只发送原词，校验数量及长度边界', () {
    expect(QwenAsrEnhancement.vocabulary(const [
      GlossaryEntry(term: ' 张三 ', translation: 'Zhang'),
      GlossaryEntry(term: '张三'), GlossaryEntry(term: '  '),
    ]), {'张三': 4});
    for (final term in ['中' * 16, List.filled(8, 'word').join(' ')]) {
      expect(() => QwenAsrEnhancement.vocabulary([GlossaryEntry(term: term)]), throwsA(isA<ActionableException>()));
    }
    for (final term in ['中' * 15, List.filled(7, 'word').join(' ')]) {
      expect(QwenAsrEnhancement.vocabulary([GlossaryEntry(term: term)]), hasLength(1));
    }
    expect(QwenAsrEnhancement.vocabulary(List.generate(2000, (i) => GlossaryEntry(term: 'term$i'))), hasLength(2000));
    expect(() => QwenAsrEnhancement.vocabulary(List.generate(2001, (i) => GlossaryEntry(term: 'term$i'))), throwsA(isA<ActionableException>()));
  });
  test('上下文按 Unicode 字符截取，空提示不发送', () {
    expect(QwenAsrEnhancement.context('  '), isEmpty);
    final content = QwenAsrEnhancement.context('😀' * 401).single['content'] as List;
    expect((content.single as Map)['text'], '😀' * 400);
  });
  test('工厂传递任务词表及提示，其他方言不泄漏参数', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    const entries = [GlossaryEntry(term: '张三', translation: 'Zhang')];
    for (final transport in [AsrTransport.dashscopeFileTrans, AsrTransport.dashscopeMessage]) {
      final provider = Registry.buildAsr('dashscope_qwen_asr', settings,
        model: AsrModelSpec(name: 'custom-name', transport: transport, dialect: DashScopeDialect.qwenAudio3),
        prompt: '医学会议', glossary: entries);
      final body = provider is DashScopeFileTransProvider
          ? provider.submitPayload('oss://audio', 'zh')
          : (provider as DashScopeMessageProvider).startPayload('id', 'zh')['payload'] as Map;
      expect((body['parameters'] as Map)['vocabulary'], {'张三': 4});
      final input = body['input'] as Map;
      expect(((input['context'] as List).single as Map)['content'], [
        {'type': 'input_text', 'text': '医学会议'},
      ]);
      if (transport == AsrTransport.dashscopeFileTrans) expect(input['file_urls'], ['oss://audio']);
    }
    for (final dialect in [DashScopeDialect.qwen3Asr, DashScopeDialect.funAsr]) {
      final provider = Registry.buildAsr('dashscope_qwen_asr', settings,
        model: AsrModelSpec(name: 'custom-name', transport: AsrTransport.dashscopeFileTrans, dialect: dialect),
        prompt: '医学会议', glossary: entries) as DashScopeFileTransProvider;
      final body = provider.submitPayload('oss://audio', null);
      expect((body['input'] as Map).containsKey('context'), isFalse);
      expect((body['parameters'] as Map).containsKey('vocabulary'), isFalse);
    }
  });
}
