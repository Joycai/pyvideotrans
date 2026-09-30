import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_name.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';

const _dashscope = {
  AsrTransport.dashscopeSync,
  AsrTransport.dashscopeFileTrans,
};
const _openai = {AsrTransport.openaiTranscription};

// 登记表里的预置模型就是这样写成常量的。const 构造的断言里写
// identical(枚举, 枚举) 时，编译器前端按求值上下文会得到 false（经常量别名、
// 放进 const 列表时必现），整个应用编不过，而 analyzer 查不出；所以用 ==。
const _topLevelOpenAi = AsrModelSpec(
  name: 'whisper-1',
  transport: AsrTransport.openaiTranscription,
);
const _topLevelUnset = AsrModelSpec.unset(AsrTransport.dashscopeFileTrans);

AsrModelSpec _guess(String name, [Set<AsrTransport> transports = _dashscope]) =>
    AsrModelSpec.guessFromName(name, transports: transports);

void main() {
  group('模型名校验', () {
    test('各家真实的模型名都合法', () {
      for (final name in [
        'whisper-1',
        'FunAudioLLM/SenseVoiceSmall',
        'qwen2.5:14b',
        'google/gemini-2.0-flash-001',
        'qwen-audio-3.0-asr-flash-filetrans',
        'Qwen/Qwen2.5-14B-Instruct',
        'ft:gpt-4o-mini:org::abc123',
      ]) {
        expect(ModelName.validate(name), isNull, reason: name);
      }
    });

    test('首尾空白不算错，校验的是去掉之后的名字', () {
      expect(ModelName.normalize('  whisper-1 \n'), 'whisper-1');
      expect(ModelName.validate('  whisper-1 \n'), isNull);
    });

    test('空、空白与逗号、不可见字符、超长各有一句原因', () {
      expect(ModelName.validate(''), '模型名不能为空');
      expect(ModelName.validate('  '), '模型名不能为空');
      expect(ModelName.validate('whisper 1'), '模型名不能含空格或逗号');
      expect(ModelName.validate('a\tb'), '模型名不能含空格或逗号');
      expect(ModelName.validate('a\nb'), '模型名不能含空格或逗号');
      expect(ModelName.validate('a,b'), '模型名不能含空格或逗号');
      expect(ModelName.validate('a，b'), '模型名不能含空格或逗号');
      String around(int code) => 'a${String.fromCharCode(code)}b';
      expect(ModelName.validate(around(0x3000)), '模型名不能含空格或逗号');
      expect(ModelName.validate(around(0)), '模型名里有不可见字符');
      expect(ModelName.validate(around(0x200B)), '模型名里有不可见字符');
      expect(ModelName.validate(around(0x7F)), '模型名里有不可见字符');
      // 软连字符、双向控制符：网页与聊天软件复制时常带。
      for (final code in [0x00AD, 0x202A, 0x202E, 0x2066, 0x2069, 0x2061]) {
        expect(
          ModelName.validate(around(code)),
          '模型名里有不可见字符',
          reason: code.toRadixString(16),
        );
      }
      expect(ModelName.validate('a' * 128), isNull);
      expect(ModelName.validate('a' * 129), '模型名不能超过 128 个字符');
    });

    test('同一个服务里不能重名，比较的是去空白后的名字，区分大小写', () {
      const existing = ['whisper-1', 'gpt-4o-transcribe'];
      expect(
        ModelName.validate(' whisper-1 ', existing: existing),
        '列表里已经有 whisper-1',
      );
      expect(ModelName.validate('Whisper-1', existing: existing), isNull);
      expect(ModelName.validate('whisper-2', existing: existing), isNull);
    });
  });

  group('能力表', () {
    test('每个合法组合都查得到', () {
      for (final transport in AsrTransport.values) {
        for (final dialect in [
          if (transport.needsDialect) ...DashScopeDialect.values else null,
        ]) {
          expect(
            AsrCapabilities.of(transport, dialect).timing,
            isNotEmpty,
            reason: '$transport $dialect',
          );
        }
      }
    });

    test('说话人分离只有录音文件转写的 Qwen-Audio 3.0 与 Fun-ASR 有', () {
      final able = {
        for (final transport in AsrTransport.values)
          for (final dialect in [
            if (transport.needsDialect) ...DashScopeDialect.values else null,
          ])
            if (AsrCapabilities.of(transport, dialect).diarization)
              (transport, dialect),
      };
      expect(able, {
        (AsrTransport.dashscopeFileTrans, DashScopeDialect.qwenAudio3),
        (AsrTransport.dashscopeFileTrans, DashScopeDialect.funAsr),
      });
    });

    test('上下文提示只有 OpenAI 转写接口与百炼同步的 Qwen3-ASR 接受', () {
      final able = {
        for (final transport in AsrTransport.values)
          for (final dialect in [
            if (transport.needsDialect) ...DashScopeDialect.values else null,
          ])
            if (AsrCapabilities.of(transport, dialect).contextPrompt)
              (transport, dialect),
      };
      expect(able, {
        (AsrTransport.openaiTranscription, null),
        (AsrTransport.dashscopeSync, DashScopeDialect.qwen3Asr),
      });
    });

    test('时间码来源跟接入方式走', () {
      expect(
        AsrCapabilities.of(AsrTransport.openaiTranscription, null).timing,
        '分段时间戳',
      );
      expect(
        AsrCapabilities.of(
          AsrTransport.dashscopeSync,
          DashScopeDialect.funAsr,
        ).timing,
        '切片时间码',
      );
      expect(
        AsrCapabilities.of(
          AsrTransport.dashscopeFileTrans,
          DashScopeDialect.qwen3Asr,
        ).timing,
        '句级时间戳',
      );
    });

    test('百炼的接入方式缺报文族：抛错，不悄悄当成某一族', () {
      for (final transport in [
        AsrTransport.dashscopeSync,
        AsrTransport.dashscopeFileTrans,
      ]) {
        expect(() => AsrCapabilities.of(transport, null), throwsStateError);
      }
    });
  });

  group('识别模型声明', () {
    const sense = AsrModelSpec(
      name: 'FunAudioLLM/SenseVoiceSmall',
      transport: AsrTransport.openaiTranscription,
      languages: {'zh', 'yue', 'en', 'ja', 'ko'},
    );
    const filetrans = AsrModelSpec(
      name: 'qwen-audio-3.0-asr-flash-filetrans',
      transport: AsrTransport.dashscopeFileTrans,
      dialect: DashScopeDialect.qwenAudio3,
    );

    test('能力与参数目录由接入方式和报文族查表得出', () {
      expect(filetrans.capabilities.diarization, isTrue);
      expect(filetrans.params, isEmpty);
      expect(sense.capabilities.contextPrompt, isTrue);
      expect(sense.params, [ModelParams.asrTemperature]);
    });

    test('构造时就拦住不完整的声明', () {
      expect(
        () => AsrModelSpec(name: 'x', transport: AsrTransport.dashscopeSync),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => AsrModelSpec(
          name: 'x',
          transport: AsrTransport.openaiTranscription,
          dialect: DashScopeDialect.funAsr,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('可以写成顶层常量', () {
      expect(_topLevelOpenAi.dialect, isNull);
      expect(_topLevelUnset.dialect, DashScopeDialect.qwen3Asr);
    });

    test('占位声明：空名，百炼的带一个报文族所以查能力不会抛', () {
      for (final transport in AsrTransport.values) {
        final unset = AsrModelSpec.unset(transport);
        expect(unset.isUnset, isTrue);
        expect(unset.capabilities.timing, isNotEmpty);
      }
    });

    test('JSON 来回一致：语种限制、参数、报文族都在', () {
      final withOptions = const AsrModelSpec(
        name: 'qwen3-asr-flash',
        transport: AsrTransport.dashscopeSync,
        dialect: DashScopeDialect.qwen3Asr,
      ).withOptions(const ModelOptions({'enable_itn': false}));

      for (final spec in [sense, filetrans, withOptions]) {
        final json = jsonDecode(jsonEncode(spec.toJson()));
        expect(ModelSpec.fromJson(json), spec, reason: spec.name);
      }
      // 没有的项不写：存档里不留一堆 null。
      expect(filetrans.toJson(), {
        'kind': 'asr',
        'name': 'qwen-audio-3.0-asr-flash-filetrans',
        'transport': 'dashscopeFileTrans',
        'dialect': 'qwenAudio3',
      });
    });

    test('相等看全部字段；语种集合不看顺序', () {
      expect(
        sense,
        const AsrModelSpec(
          name: 'FunAudioLLM/SenseVoiceSmall',
          transport: AsrTransport.openaiTranscription,
          languages: {'ko', 'ja', 'en', 'yue', 'zh'},
        ),
      );
      expect(
        sense.hashCode,
        const AsrModelSpec(
          name: 'FunAudioLLM/SenseVoiceSmall',
          transport: AsrTransport.openaiTranscription,
          languages: {'ko', 'ja', 'en', 'yue', 'zh'},
        ).hashCode,
      );
      expect(
        sense,
        isNot(
          const AsrModelSpec(
            name: 'FunAudioLLM/SenseVoiceSmall',
            transport: AsrTransport.openaiTranscription,
          ),
        ),
      );
      expect(
        filetrans,
        isNot(
          const AsrModelSpec(
            name: 'qwen-audio-3.0-asr-flash-filetrans',
            transport: AsrTransport.dashscopeFileTrans,
            dialect: DashScopeDialect.funAsr,
          ),
        ),
      );
      expect(
        sense,
        isNot(sense.withOptions(const ModelOptions({'temperature': 0.5}))),
      );
    });

    test('读存档时按目录清理参数：越界夹住，别的接入方式的键丢掉', () {
      final spec = ModelSpec.fromJson({
        'kind': 'asr',
        'name': ' whisper-1 ',
        'transport': 'openaiTranscription',
        'dialect': 'qwen3Asr',
        'options': {'temperature': 9, 'enable_itn': false},
      })! as AsrModelSpec;

      expect(spec.name, 'whisper-1');
      // OpenAI 转写接口不带报文族，存档里多写的那个不要。
      expect(spec.dialect, isNull);
      expect(spec.options.toJson(), {'temperature': 1.0});
    });

    test('读坏存档：认不出的整条不要，缺报文族的按名字补', () {
      expect(ModelSpec.fromJson(null), isNull);
      expect(ModelSpec.fromJson('whisper-1'), isNull);
      expect(ModelSpec.fromJson({'name': 'x'}), isNull);
      expect(ModelSpec.fromJson({'kind': 'tts', 'name': 'x'}), isNull);
      expect(ModelSpec.fromJson({'kind': 'asr', 'name': 1}), isNull);
      expect(
        ModelSpec.fromJson({'kind': 'asr', 'name': 'x', 'transport': '将来的'}),
        isNull,
      );

      final patched = ModelSpec.fromJson({
        'kind': 'asr',
        'name': 'fun-asr-flash-2026-06-15',
        'transport': 'dashscopeSync',
        'dialect': '将来的',
        'languages': 'zh',
      })! as AsrModelSpec;
      expect(patched.dialect, DashScopeDialect.funAsr);
      expect(patched.languages, isNull);

      // 补报文族用的是去掉空白之后的名字，与按名字推断同一个口径。
      final padded = ModelSpec.fromJson({
        'kind': 'asr',
        'name': ' qwen3-asr-flash-filetrans',
        'transport': 'dashscopeFileTrans',
      })! as AsrModelSpec;
      expect(padded.name, 'qwen3-asr-flash-filetrans');
      expect(padded.dialect, DashScopeDialect.qwen3Asr);
    });

    test('语种列表为空或全是坏值：当成不限，不是「什么都不支持」', () {
      for (final languages in [<Object>[], <Object>[1, 2]]) {
        final spec = ModelSpec.fromJson({
          'kind': 'asr',
          'name': 'x',
          'transport': 'openaiTranscription',
          'languages': languages,
        })! as AsrModelSpec;
        expect(spec.languages, isNull);
        expect(spec.toJson().containsKey('languages'), isFalse);
      }
    });

    test('换参数时按目录收拾：离谱的值进不了声明，写盘读回相等', () {
      const base = AsrModelSpec(
        name: 'whisper-1',
        transport: AsrTransport.openaiTranscription,
      );
      for (final bad in <Object?>[double.nan, double.infinity, 5, 'x']) {
        final spec = base.withOptions(
          ModelOptions.none.set('temperature', bad).set('enable_itn', false),
        );
        final json = jsonDecode(jsonEncode(spec.toJson()));
        expect(ModelSpec.fromJson(json), spec, reason: '$bad');
        expect(spec.options.has('enable_itn'), isFalse);
      }
      expect(
        const ChatModelSpec(name: 'm')
            .withOptions(const ModelOptions({'temperature': 9}))
            .options
            .toJson(),
        {'temperature': 2.0},
      );
    });
  });

  group('按名字推断（只用于读旧存档与预填）', () {
    test('只有一种接入方式的服务：不看名字', () {
      for (final name in ['whisper-1', 'x-filetrans', 'qwen3-asr-flash']) {
        final spec = _guess(name, _openai);
        expect(spec.transport, AsrTransport.openaiTranscription);
        expect(spec.dialect, isNull);
        expect(spec.name, name);
      }
    });

    // 这张表就是重构前两个百炼实现里的前缀判断。迁移后的报文不能变，
    // 所以连「认不出来时归到哪一族」都照原样：两种接入方式的归属并不相同。
    test('百炼：-filetrans 结尾是异步，报文族按前缀', () {
      const sync = AsrTransport.dashscopeSync;
      const file = AsrTransport.dashscopeFileTrans;
      const q3 = DashScopeDialect.qwen3Asr;
      const qa = DashScopeDialect.qwenAudio3;
      const fun = DashScopeDialect.funAsr;

      final expected = {
        'qwen3-asr-flash': (sync, q3),
        'qwen3-asr-flash-2026-01-01': (sync, q3),
        'qwen-audio-3.0-asr-flash': (sync, qa),
        'qwen-audio-3.0-asr-flash-latest': (sync, qa),
        'fun-asr-flash-2026-06-15': (sync, fun),
        // 同步接口以前把不认识的都当 Qwen3-ASR 的报文发。
        'fun-asr': (sync, q3),
        'my-model': (sync, q3),
        'qwen3-asr-flash-filetrans': (file, q3),
        'qwen-audio-3.0-asr-flash-filetrans': (file, qa),
        'fun-asr-filetrans': (file, fun),
        // 录音文件转写以前只认 qwen3-asr 前缀，其余都按 Qwen-Audio 3.0 发。
        'my-model-filetrans': (file, qa),
      };
      for (final MapEntry(key: name, value: (transport, dialect))
          in expected.entries) {
        final spec = _guess(name);
        expect(
          (spec.transport, spec.dialect),
          (transport, dialect),
          reason: name,
        );
      }
    });

    test('名字先去首尾空白', () {
      final spec = _guess(' qwen3-asr-flash-filetrans \n');
      expect(spec.name, 'qwen3-asr-flash-filetrans');
      expect(spec.transport, AsrTransport.dashscopeFileTrans);
    });

    test('预置里有同名的直接用预置，连语种限制一起带上', () {
      const preset = AsrModelSpec(
        name: 'my-model',
        transport: AsrTransport.dashscopeFileTrans,
        dialect: DashScopeDialect.funAsr,
        languages: {'zh'},
      );
      final spec = AsrModelSpec.guessFromName(
        'my-model',
        transports: _dashscope,
        presets: const [preset],
      );
      expect(spec, preset);
      // 不同名的照常推断。
      expect(
        AsrModelSpec.guessFromName(
          'other',
          transports: _dashscope,
          presets: const [preset],
        ).transport,
        AsrTransport.dashscopeSync,
      );
    });
  });

  group('翻译模型声明', () {
    test('占位声明是空名', () {
      expect(ChatModelSpec.unset.isUnset, isTrue);
      expect(const ChatModelSpec(name: 'deepseek-chat').isUnset, isFalse);
    });

    test('JSON 来回一致；「不发送温度」存得住', () {
      final spec = const ChatModelSpec(
        name: 'deepseek-reasoner',
      ).withOptions(ModelOptions.none.set('temperature', null));

      final back = ModelSpec.fromJson(jsonDecode(jsonEncode(spec.toJson())));
      expect(back, spec);
      expect(back!.options.number(ModelParams.chatTemperature), isNull);
      expect(const ChatModelSpec(name: 'm').toJson(), {
        'kind': 'chat',
        'name': 'm',
      });
    });

    test('读存档时按目录清理参数', () {
      final spec = ModelSpec.fromJson({
        'kind': 'chat',
        'name': 'm',
        'options': {'temperature': 5, 'enable_itn': false},
      })!;
      expect(spec, isA<ChatModelSpec>());
      expect(spec.options.toJson(), {'temperature': 2.0});
      expect(spec.params, ModelParams.chat);
    });

    test('识别与翻译的声明即使同名也不相等', () {
      expect(
        const ChatModelSpec(name: 'm'),
        isNot(
          const AsrModelSpec(
            name: 'm',
            transport: AsrTransport.openaiTranscription,
          ),
        ),
      );
    });
  });
}
