import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_params.dart';

const _choice = ChoiceModelParam(
  key: 'format',
  label: '格式',
  options: [('json', 'JSON'), ('text', '纯文本')],
  defaultOption: 'json',
);

void main() {
  group('参数的合法值', () {
    test('开关：不是布尔就回落默认', () {
      expect(ModelParams.enableItn.sanitize(false), false);
      expect(ModelParams.enableItn.sanitize('false'), true);
      expect(ModelParams.enableItn.sanitize(null), true);
    });

    test('数字：夹进范围、保留一位小数、整数也认', () {
      const p = ModelParams.chatTemperature;
      expect(p.sanitize(1), 1.0);
      expect(p.sanitize(9), 2.0);
      expect(p.sanitize(-1), 0.0);
      expect(p.sanitize(0.26), 0.3);
      // 3 × 0.1 在二进制里是 0.30000000000000004，不能原样进请求体。
      expect(jsonEncode(p.sanitize(3 * 0.1)), '0.3');
      expect(p.sanitize('0.5'), 0.3);
      expect(p.sanitize(double.nan), 0.3);
    });

    test('可省的数字：null 表示不发送；不可省的 null 回落默认', () {
      expect(ModelParams.chatTemperature.sanitize(null), isNull);
      expect(ModelParams.asrTemperature.sanitize(null), isNull);
      // 坏类型回落到默认；识别温度的默认本来就是不发送。
      expect(ModelParams.asrTemperature.sanitize('x'), isNull);

      const required = NumberModelParam(
        key: 'k',
        label: 'k',
        min: 0,
        max: 10,
        defaultNumber: 5,
      );
      expect(required.sanitize(null), 5.0);
    });

    test('数字：四舍五入后仍在范围内，不出现 -0.0', () {
      const p = NumberModelParam(
        key: 'k',
        label: 'k',
        min: -1,
        max: 0.25,
        defaultNumber: 0,
      );
      expect(p.sanitize(0.25), 0.25);
      expect(jsonEncode(p.sanitize(-0.04)), '0.0');
      expect(p.sanitize(double.infinity), 0.25);
      expect(p.sanitize(double.negativeInfinity), -1.0);
    });

    test('选项：不在列表里的回落默认', () {
      expect(_choice.sanitize('text'), 'text');
      expect(_choice.sanitize('xml'), 'json');
      expect(_choice.sanitize(1), 'json');
    });
  });

  group('参数取值', () {
    test('没动过的取目录默认：识别温度不发送、逆文本规范化开、翻译温度 0.3', () {
      const o = ModelOptions.none;
      expect(o.number(ModelParams.asrTemperature), isNull);
      expect(o.flag(ModelParams.enableItn), isTrue);
      expect(o.number(ModelParams.chatTemperature), 0.3);
      expect(o.choice(_choice), 'json');
    });

    test('「不发送」与「没动过」是两回事', () {
      final off = ModelOptions.none.set('temperature', null);
      expect(off.has('temperature'), isTrue);
      expect(off.number(ModelParams.chatTemperature), isNull);

      final back = off.reset('temperature');
      expect(back.has('temperature'), isFalse);
      expect(back.number(ModelParams.chatTemperature), 0.3);
      expect(back, ModelOptions.none);
    });

    test('读值时顺手收拾：越界的夹住，坏类型回落', () {
      expect(
        const ModelOptions({
          'temperature': 7,
        }).number(ModelParams.chatTemperature),
        2.0,
      );
      expect(
        const ModelOptions({'enable_itn': 'no'}).flag(ModelParams.enableItn),
        isTrue,
      );
    });

    test('按目录清理：丢掉目录外的键，不补没动过的键', () {
      final cleaned = const ModelOptions({
        'temperature': 5,
        'enable_itn': false,
      }).sanitize(ModelParams.chat);
      expect(cleaned.toJson(), {'temperature': 2.0});
      expect(ModelOptions.none.sanitize(ModelParams.chat).isEmpty, isTrue);
    });

    test('按目录清理：类型对不上的值整个丢掉，回到「没动过」', () {
      // 收拾成默认值留着的话，它会被当成用户亲手设的，以后目录改默认值也跟不上。
      final chat = const ModelOptions({
        'temperature': 'x',
      }).sanitize(ModelParams.chat);
      expect(chat.has('temperature'), isFalse);
      expect(chat.number(ModelParams.chatTemperature), 0.3);

      final itn = const ModelOptions({
        'enable_itn': null,
      }).sanitize([ModelParams.enableItn]);
      expect(itn.isEmpty, isTrue);

      // 「不发送」是合法的取值，留着。
      final off = const ModelOptions({
        'temperature': null,
      }).sanitize(ModelParams.chat);
      expect(off.has('temperature'), isTrue);
    });

    test('清理过的值一定写得成 JSON', () {
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        final cleaned = ModelOptions.none
            .set('temperature', bad)
            .sanitize(ModelParams.chat);
        expect(() => jsonEncode(cleaned.toJson()), returnsNormally);
        expect(cleaned, cleaned);
      }
    });

    test('JSON 来回一致，null 不丢', () {
      final o = ModelOptions.none
          .set('temperature', null)
          .set('enable_itn', false);
      final back = ModelOptions.fromJson(jsonDecode(jsonEncode(o.toJson())));
      expect(back, o);
      expect(back.has('temperature'), isTrue);
    });

    test('读坏存档不抛：不是对象当空，值不是标量的键丢掉', () {
      expect(ModelOptions.fromJson(null), ModelOptions.none);
      expect(ModelOptions.fromJson('x'), ModelOptions.none);
      expect(
        ModelOptions.fromJson({
          'a': [1],
          'b': {'c': 1},
          'temperature': 0.5,
        }).toJson(),
        {'temperature': 0.5},
      );
    });

    test('相等不看键的顺序', () {
      const a = ModelOptions({'x': 1, 'y': null});
      const b = ModelOptions({'y': null, 'x': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const ModelOptions({'x': 1})));
      expect(a, isNot(const ModelOptions({'x': 1, 'z': null})));
    });
  });

  group('参数目录', () {
    test('每种接入方式与报文族的组合都有目录，键不重复', () {
      for (final transport in AsrTransport.values) {
        for (final dialect in [
          if (transport.needsDialect) ...DashScopeDialect.values else null,
        ]) {
          final keys = [
            for (final p in ModelParams.asr(transport, dialect)) p.key,
          ];
          expect(
            keys.toSet().length,
            keys.length,
            reason: '$transport $dialect',
          );
        }
      }
    });

    test('第一版登记的三项', () {
      expect(ModelParams.asr(AsrTransport.openaiTranscription, null), [
        ModelParams.asrTemperature,
      ]);
      expect(
        ModelParams.asr(AsrTransport.dashscopeSync, DashScopeDialect.qwen3Asr),
        [ModelParams.enableItn],
      );
      expect(
        ModelParams.asr(
          AsrTransport.dashscopeSync,
          DashScopeDialect.qwenAudio3,
        ),
        isEmpty,
      );
      expect(
        ModelParams.asr(AsrTransport.dashscopeSync, DashScopeDialect.funAsr),
        isEmpty,
      );
      for (final dialect in DashScopeDialect.values) {
        expect(
          ModelParams.asr(AsrTransport.dashscopeFileTrans, dialect),
          isEmpty,
        );
      }
      expect(ModelParams.chat, [ModelParams.chatTemperature]);
    });
  });
}
