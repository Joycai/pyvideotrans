import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/services/readiness.dart';
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

    test('说话人分离：同步逐段的模型提示不支持，不拦着开始', () async {
      final s = await freshSettings()
        ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'k'));
      final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
      AsrModelSpec preset(String name) =>
          info.presets.singleWhere((p) => p.name == name);
      // 推荐的模型从登记表里取：预置里第一个能分离的。
      final capable = info.presets.firstWhere(
        (p) => p.capabilities.diarization,
      );
      expect(capable.name, 'qwen-audio-3.0-asr-flash-filetrans');

      final r = ProviderReadiness.asr(
        info.id,
        s,
        model: preset('qwen3-asr-flash'),
        diarize: true,
      );
      expect(r.level, ReadinessLevel.advisory);
      expect(r.message, 'qwen3-asr-flash 不支持说话人分离');
      expect(r.hint, '换 ${capable.name}（异步整文件）。');

      // 实测同步接口不给说话人；qwen3 族的录音文件转写在文档里就不支持。
      for (final name in [
        'qwen-audio-3.0-asr-flash',
        'fun-asr-flash-2026-06-15',
        'qwen3-asr-flash-filetrans',
      ]) {
        expect(
          ProviderReadiness.asr(
            info.id,
            s,
            model: preset(name),
            diarize: true,
          ).level,
          ReadinessLevel.advisory,
          reason: name,
        );
      }
      expect(
        ProviderReadiness.asr(
          info.id,
          s,
          model: capable,
          diarize: true,
        ).isReady,
        isTrue,
      );

      // 不给模型时查的是这家的默认模型（qwen3-asr-flash）。
      expect(
        ProviderReadiness.asr(info.id, s, diarize: true).message,
        'qwen3-asr-flash 不支持说话人分离',
      );

      // 不开就不管模型。
      expect(
        ProviderReadiness.asr(
          info.id,
          s,
          model: preset('qwen3-asr-flash'),
        ).isReady,
        isTrue,
      );
    });

    // 推荐的得是下拉里选得到的。用户配过模型列表之后，预置不在候选里。
    test('说话人分离：推荐用户自己列表里能分离的；没有就说去设置里加', () async {
      final s = await freshSettings()
        ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'k'));
      const sync = AsrModelSpec(
        name: 'qwen3-asr-flash',
        transport: AsrTransport.dashscopeSync,
        dialect: DashScopeDialect.qwen3Asr,
      );
      const mine = AsrModelSpec(
        name: 'my-diarizer',
        transport: AsrTransport.dashscopeFileTrans,
        dialect: DashScopeDialect.funAsr,
      );
      Readiness check() => ProviderReadiness.asr(
        'dashscope_qwen_asr',
        s,
        model: sync,
        diarize: true,
      );

      s.setModels('dashscope_qwen_asr', [sync, mine]);
      expect(check().hint, '换 my-diarizer（异步整文件）。');

      s.setModels('dashscope_qwen_asr', [sync]);
      expect(check().level, ReadinessLevel.advisory);
      expect(check().message, 'qwen3-asr-flash 不支持说话人分离');
      expect(
        check().hint,
        '去设置里把 qwen-audio-3.0-asr-flash-filetrans（异步整文件）'
        '加进模型列表，再换过去。',
      );
    });

    test('说话人分离：看声明的接入方式与报文族，不看模型名', () async {
      final s = await freshSettings()
        ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'k'));
      Readiness check(AsrTransport transport, DashScopeDialect dialect) =>
          ProviderReadiness.asr(
            'dashscope_qwen_asr',
            s,
            model: AsrModelSpec(
              name: 'my-model',
              transport: transport,
              dialect: dialect,
            ),
            diarize: true,
          );

      // 自填的名字没有 -filetrans 后缀：以前按名字会被判成不支持。
      expect(
        check(AsrTransport.dashscopeFileTrans, DashScopeDialect.funAsr).isReady,
        isTrue,
      );
      expect(
        check(AsrTransport.dashscopeSync, DashScopeDialect.funAsr).level,
        ReadinessLevel.advisory,
      );
    });

    test('说话人分离：不支持的服务提示会被忽略', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr('openai', s, diarize: true);
      expect(r.level, ReadinessLevel.advisory);
      expect(r.message, 'OpenAI不支持说话人分离');
      // 改用哪家也从登记表里取：第一家有模型能分离的服务。
      expect(r.hint, '这一项会被忽略；需要分离请改用阿里百炼 · Qwen3-ASR。');
    });

    test('声明的接入方式这家服务没有：拦住，别等任务排到了才失败', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr(
        'openai',
        s,
        model: const AsrModelSpec(
          name: 'qwen3-asr-flash',
          transport: AsrTransport.dashscopeSync,
          dialect: DashScopeDialect.qwen3Asr,
        ),
      );
      expect(r.isBlocked, isTrue);
      expect(r.message, contains('qwen3-asr-flash'));
      // 设置页改不了已添加模型的接入方式：提示得是能照着做的。
      expect(r.hint, contains('重新选一个模型'));
      expect(r.hint, contains('删掉它，再按正确的接入方式添加'));
    });

    test('语种限制跟着模型声明走', () async {
      final s = await freshSettings()
        ..setConfig('openai', const ProviderConfig(apiKey: 'k'));
      final r = ProviderReadiness.asr(
        'openai',
        s,
        language: Languages.byCode('fr'),
        model: const AsrModelSpec(
          name: 'my-small-model',
          transport: AsrTransport.openaiTranscription,
          languages: {'zh', 'en'},
        ),
      );
      expect(r.level, ReadinessLevel.advisory);
      expect(r.message, 'my-small-model 对法语的支持有限');
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
          model: const ChatModelSpec(name: 'local-model'),
        ).isReady,
        isTrue,
      );
      // 给了声明但名字是空的：同样算没选模型。
      final unset = ProviderReadiness.translation(
        'lmstudio',
        s,
        model: ChatModelSpec.unset,
      );
      expect(unset.isBlocked, isTrue);
      expect(unset.message, contains('未选择模型'));
    });

    test('登记表里每个已实施的服务都有默认地址', () async {
      final s = await freshSettings();
      for (final info in [
        ...ProviderCatalog.asr,
        ...ProviderCatalog.translation,
      ]) {
        if (!info.implemented || info.id.contains('custom')) continue;
        expect(
          s.endpointFor(info, s.defaultModel(info)).baseUrl,
          isNotEmpty,
          reason: '${info.id} 缺默认 baseUrl',
        );
      }
    });
  });
}
