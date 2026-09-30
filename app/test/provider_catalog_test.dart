import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_name.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/domain/providers/provider_info.dart';

void main() {
  const all = <ProviderInfo>[
    ...ProviderCatalog.asr,
    ...ProviderCatalog.translation,
  ];

  group('登记表', () {
    test('服务 id 不重复，按 id 查得到', () {
      final ids = [for (final info in all) info.id];
      expect(ids.toSet().length, ids.length);
      for (final info in ProviderCatalog.asr) {
        expect(ProviderCatalog.asrInfo(info.id), same(info));
      }
      for (final info in ProviderCatalog.translation) {
        expect(ProviderCatalog.translationInfo(info.id), same(info));
      }
      expect(ProviderCatalog.asrInfo('不存在'), isNull);
      // 识别与翻译是两张表：同一家厂商在两边的 id 不通用。
      expect(ProviderCatalog.asrInfo('deepseek'), isNull);
      expect(ProviderCatalog.translationInfo('openai'), isNull);
    });

    test('每个已实施的服务都有默认地址（自定义接口除外）', () {
      for (final info in all) {
        if (!info.implemented || info.id.contains('custom')) continue;
        expect(info.defaultBaseUrl, isNotEmpty, reason: info.id);
      }
    });

    test('预置模型名都合法，同一家服务里不重名', () {
      for (final info in all) {
        final names = <String>[];
        for (final preset in info.presets) {
          expect(
            ModelName.validate(preset.name, existing: names),
            isNull,
            reason: '${info.id} · ${preset.name}',
          );
          names.add(preset.name);
        }
      }
    });

    // 这张表是重构前登记表里每家的 defaultModel。什么都没配的用户，
    // 升级之后请求里的模型名不能变。
    test('每家服务的默认模型与重构前一致', () {
      expect(
        {
          for (final info in ProviderCatalog.asr)
            info.id: ProviderCatalog.defaultAsrSpec(info.id).name,
        },
        {
          'openai': 'whisper-1',
          'groq': 'whisper-large-v3',
          'siliconflow': 'FunAudioLLM/SenseVoiceSmall',
          'asr_custom': '',
          'local_backend': 'whisper-large-v3',
          'dashscope_qwen_asr': 'qwen3-asr-flash',
        },
      );
      expect(
        {
          for (final info in ProviderCatalog.translation)
            info.id: ProviderCatalog.defaultChatSpec(info.id).name,
        },
        {
          'deepseek': 'deepseek-chat',
          'openai_chat': 'gpt-4o-mini',
          'siliconflow_chat': 'Qwen/Qwen2.5-14B-Instruct',
          'openrouter': 'google/gemini-2.0-flash-001',
          'ollama': 'qwen2.5:14b',
          'lmstudio': '',
          'mt_custom': '',
          'local_backend_chat': '',
        },
      );
    });

    test('不认识的服务：默认模型是空名的占位，不抛', () {
      expect(ProviderCatalog.defaultAsrSpec('不存在').isUnset, isTrue);
      expect(ProviderCatalog.defaultChatSpec('不存在').isUnset, isTrue);
    });

    test('只有阿里百炼的模型有不同接法', () {
      expect(
        [
          for (final info in ProviderCatalog.asr)
            if (info.multiTransport) info.id,
        ],
        ['dashscope_qwen_asr'],
      );
      for (final info in ProviderCatalog.asr) {
        for (final preset in info.presets) {
          expect(
            info.transports,
            contains(preset.transport),
            reason: '${info.id} · ${preset.name}',
          );
        }
      }
    });

    test('语种受限的预置只有 SenseVoiceSmall', () {
      final limited = {
        for (final info in ProviderCatalog.asr)
          for (final preset in info.presets)
            if (preset.languages != null) preset.name: preset.languages,
      };
      expect(limited, {
        'FunAudioLLM/SenseVoiceSmall': {'zh', 'yue', 'en', 'ja', 'ko'},
      });
    });
  });

  group('只有模型名的旧存档', () {
    // 性质：预置模型写明的接法，必须与按名字推断出来的一样 —— 旧存档里
    // 这些名字就是按推断的规则在跑，两边不一致说明登记表写错了。
    test('预置模型：按名字推断的接法与登记表写明的一致', () {
      for (final info in ProviderCatalog.asr) {
        for (final preset in info.presets) {
          final guessed = AsrModelSpec.guessFromName(
            preset.name,
            transports: info.transports,
          );
          expect(
            (guessed.transport, guessed.dialect),
            (preset.transport, preset.dialect),
            reason: '${info.id} · ${preset.name}',
          );
        }
      }
    });

    test('预置模型：得到的就是预置声明', () {
      for (final info in ProviderCatalog.asr) {
        for (final preset in info.presets) {
          expect(ProviderCatalog.legacyAsrSpec(info.id, preset.name), preset);
        }
      }
      for (final info in ProviderCatalog.translation) {
        for (final preset in info.presets) {
          expect(ProviderCatalog.legacyChatSpec(info.id, preset.name), preset);
        }
      }
      // 语种限制跟着预置一起带上。
      expect(
        ProviderCatalog.legacyAsrSpec(
          'siliconflow',
          ' FunAudioLLM/SenseVoiceSmall ',
        ).languages,
        isNotNull,
      );
    });

    test('自填的模型：按名字推断', () {
      final custom = ProviderCatalog.legacyAsrSpec(
        'dashscope_qwen_asr',
        'my-model-filetrans',
      );
      expect(custom.transport, AsrTransport.dashscopeFileTrans);
      expect(custom.dialect, DashScopeDialect.qwenAudio3);

      final openai = ProviderCatalog.legacyAsrSpec('openai', ' my-whisper ');
      expect(openai.name, 'my-whisper');
      expect(openai.transport, AsrTransport.openaiTranscription);

      expect(
        ProviderCatalog.legacyChatSpec('deepseek', ' my-chat '),
        const ChatModelSpec(name: 'my-chat'),
      );
    });

    test('服务也认不出来：不抛，当成 OpenAI 转写接口', () {
      final spec = ProviderCatalog.legacyAsrSpec('不存在', 'x-filetrans');
      expect(spec.name, 'x-filetrans');
      expect(spec.transport, AsrTransport.openaiTranscription);
      expect(
        ProviderCatalog.legacyChatSpec('不存在', 'x'),
        const ChatModelSpec(name: 'x'),
      );
    });
  });
}
