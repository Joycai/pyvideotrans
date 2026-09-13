import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/services/readiness.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';

Future<AppSettings> freshSettings() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettings.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('识别服务是否可用', () {
    test('没填密钥时拦住，并说清楚去哪儿填', () async {
      final s = await freshSettings();
      final r = ProviderReadiness.asr('openai', s);
      expect(r.isBlocked, isTrue);
      expect(r.message, contains('未配置密钥'));
      expect(r.hint, contains('设置'));
    });

    test('填了密钥就放行', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'sk-test'));
      expect(ProviderReadiness.asr('openai', s).isReady, isTrue);
    });

    test('未实施的服务拦住，并说明是第二期', () async {
      final s = await freshSettings();
      final r = ProviderReadiness.asr('local_backend', s);
      expect(r.isBlocked, isTrue);
      expect(r.message, contains('尚未实施'));
      expect(r.hint, contains('第二期'));
    });

    test('自定义服务没填地址时拦住', () async {
      final s = await freshSettings()
        ..setConfig('asr_custom', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr('asr_custom', s);
      expect(r.isBlocked, isTrue);
      expect(r.message, contains('未填服务地址'));
    });

    test('未知 id 不抛异常，按拦住处理', () async {
      final s = await freshSettings();
      expect(ProviderReadiness.asr('nope', s).isBlocked, isTrue);
    });
  });

  group('语种支持', () {
    // 原实现在 is_allow_lang 里做同样的事：提示但不拦。
    test('小模型遇到没训过的语种时提示，但不拦着开始', () async {
      final s = await freshSettings()
        ..setConfig('siliconflow', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr(
        'siliconflow',
        s,
        language: Languages.byCode('fr'),
      );
      expect(r.level, ReadinessLevel.advisory);
      expect(r.isBlocked, isFalse);
      expect(r.message, contains('法语'));
    });

    test('说话人分离：qwen3-asr-flash 提示不支持，不拦着开始', () async {
      final s = await freshSettings()
        ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr(
        'dashscope_qwen_asr',
        s,
        model: 'qwen3-asr-flash',
        diarize: true,
      );
      expect(r.level, ReadinessLevel.advisory);
      expect(r.message, contains('不支持说话人分离'));
      expect(r.hint, contains('qwen-audio-3.0-asr-flash'));

      final ok = ProviderReadiness.asr(
        'dashscope_qwen_asr',
        s,
        model: 'qwen-audio-3.0-asr-flash',
        diarize: true,
      );
      expect(ok.isReady, isTrue);

      // 不开就不管模型。
      expect(
        ProviderReadiness.asr(
          'dashscope_qwen_asr',
          s,
          model: 'qwen3-asr-flash',
        ).isReady,
        isTrue,
      );
    });

    test('说话人分离：不支持的服务提示会被忽略', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr('openai', s, diarize: true);
      expect(r.level, ReadinessLevel.advisory);
      expect(r.message, contains('不支持说话人分离'));
    });

    test('支持的语种不提示', () async {
      final s = await freshSettings()
        ..setConfig('siliconflow', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr(
        'siliconflow',
        s,
        language: Languages.byCode('zh'),
      );
      expect(r.isReady, isTrue);
    });

    test('自动检测时不检查语种', () async {
      final s = await freshSettings()
        ..setConfig('siliconflow', const ProviderConfig(apiKey: 'k'));
      expect(
        ProviderReadiness.asr(
          'siliconflow',
          s,
          language: Languages.auto,
        ).isReady,
        isTrue,
      );
    });

    test('whisper 系列不限语种', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'k'));
      expect(
        ProviderReadiness.asr(
          'openai',
          s,
          language: Languages.byCode('fr'),
        ).isReady,
        isTrue,
      );
    });
  });

  group('翻译服务', () {
    test('本机服务不需要密钥', () async {
      final s = await freshSettings();
      expect(ProviderReadiness.translation('ollama', s).isReady, isTrue);
    });

    test('自定义模型可满足模型检查，空模型则拦住', () async {
      final s = await freshSettings();
      expect(ProviderReadiness.translation('lmstudio', s).isBlocked, isTrue);
      expect(
        ProviderReadiness.translation(
          'lmstudio',
          s,
          model: 'local-model',
        ).isReady,
        isTrue,
      );
    });

    test('登记表里每个已实施的服务都有默认地址', () async {
      final s = await freshSettings();
      for (final info in [...Registry.asr, ...Registry.translation]) {
        if (!info.implemented || info.id.contains('custom')) continue;
        expect(
          s.endpointFor(info).baseUrl,
          isNotEmpty,
          reason: '${info.id} 缺默认 baseUrl',
        );
      }
    });
  });
}
