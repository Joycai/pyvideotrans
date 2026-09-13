import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/subtitle_pairing.dart';

Cue _c(int start, int end, String text, {int? speaker}) =>
    Cue(index: 0, startMs: start, endMs: end, source: text, speaker: speaker);

void main() {
  group('选择配对方式', () {
    test('条数相同且时间码在误差内 → 按序号', () {
      final source = [_c(0, 1000, '一'), _c(1000, 2000, '二')];
      final translation = [_c(150, 1100, 'one'), _c(1000, 1990, 'two')];
      expect(
        SubtitlePairing.suggestMode(source, translation),
        PairingMode.byIndex,
      );
    });

    test('条数不同或时间偏差大 → 按时间轴', () {
      final source = [_c(0, 1000, '一'), _c(1000, 2000, '二')];
      expect(
        SubtitlePairing.suggestMode(source, [_c(0, 1000, 'one')]),
        PairingMode.byTime,
      );
      expect(
        SubtitlePairing.suggestMode(source, [
          _c(0, 1000, 'one'),
          _c(1500, 2600, 'two'),
        ]),
        PairingMode.byTime,
      );
    });
  });

  group('按时间轴配对', () {
    final source = [
      _c(0, 2000, '大家好', speaker: 0),
      _c(2000, 4000, '今天聊部署', speaker: 0),
      _c(4000, 6000, '先说显存'),
      _c(6000, 8000, '没有译文的一句'),
    ];
    final translation = [
      _c(0, 2000, 'Hello'),
      // 一条原文对上两条译文。
      _c(2000, 3000, 'Today'),
      _c(3000, 4000, 'deployment'),
      _c(4100, 5900, 'VRAM first'),
      // 落在两条原文之间、与谁都重叠不够的译文。
      _c(8500, 9000, 'Right.'),
    ];

    test('统计数字', () {
      final r = SubtitlePairing.pair(source, translation);
      expect(r.mode, PairingMode.byTime);
      expect(r.paired, 3);
      expect(r.sourceOnly, 1);
      expect(r.translationOnly, 1);
      expect(r.mergedTranslations, 1);
      expect(r.plausible, isTrue);
    });

    test('合并的译文按语言拼接，原文的说话人保留', () {
      final latin = SubtitlePairing.pair(source, translation);
      expect(latin.cues[1].translation, 'Today deployment');
      expect(latin.cues[1].speaker, 0);

      final cjk = SubtitlePairing.pair(source, translation, cjk: true);
      expect(cjk.cues[1].translation, 'Todaydeployment');
    });

    test('找不到原文的译文按时间插回，原文为空、状态为未配对，行号连续', () {
      final r = SubtitlePairing.pair(source, translation);
      expect(r.cues.map((c) => c.index), [1, 2, 3, 4, 5]);
      final orphan = r.cues.last;
      expect(orphan.source, '');
      expect(orphan.translation, 'Right.');
      expect(orphan.state, CueState.unpaired);
      expect(r.cues[3].state, CueState.untranslated);
    });

    test('未配对行插在时间顺序的正确位置', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一'), _c(5000, 6000, '二')],
        [_c(2000, 3000, 'orphan')],
      );
      expect(r.cues.map((c) => c.source), ['一', '', '二']);
    });

    test('重叠不到较短一条的一半不算配上', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一')],
        [_c(600, 2000, 'mostly later')],
      );
      expect(r.paired, 0);
      expect(r.translationOnly, 1);
    });

    test('与多条原文重叠时配给重叠最多的那条', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一'), _c(1000, 3000, '二')],
        [_c(800, 2600, 'two')],
      );
      expect(r.cues[0].translation, isNull);
      expect(r.cues[1].translation, 'two');
    });

    test('时间轴基本对不上时判为不可信', () {
      final r = SubtitlePairing.pair(
        [for (var i = 0; i < 10; i++) _c(i * 1000, i * 1000 + 900, '$i')],
        [
          for (var i = 0; i < 10; i++)
            _c(60000 + i * 1000, 61000 + i * 1000, 'x'),
        ],
      );
      expect(r.paired, 0);
      expect(r.plausible, isFalse);
    });

    test('零时长的译文落在原文区间里也算配上', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一')],
        [_c(500, 500, 'point')],
      );
      expect(r.paired, 1);
    });
  });

  group('按序号配对', () {
    test('多出来的译文单独成行，多出来的原文没有译文', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一'), _c(1000, 2000, '二')],
        [_c(0, 1000, 'one'), _c(1000, 2000, 'two'), _c(2000, 3000, 'three')],
        mode: PairingMode.byIndex,
      );
      expect(r.paired, 2);
      expect(r.translationOnly, 1);
      expect(r.cues.map((c) => c.translation), ['one', 'two', 'three']);
      expect(r.cues.last.source, '');
    });

    test('用户选了按序号，配对率低也照做', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一')],
        [_c(90000, 91000, 'far away')],
        mode: PairingMode.byIndex,
      );
      expect(r.plausible, isTrue);
      expect(r.cues.single.translation, 'far away');
    });
  });

  group('错位起点', () {
    test('逐条对应时为 null', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一'), _c(1000, 2000, '二')],
        [_c(0, 1000, 'one'), _c(1000, 2000, 'two')],
      );
      expect(r.misalignedFrom, isNull);
    });

    test('中间少一条译文时，从少的那条开始错位', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一'), _c(1000, 2000, '二'), _c(2000, 3000, '三')],
        [_c(0, 1000, 'one'), _c(2000, 3000, 'three')],
      );
      expect(r.misalignedFrom, 2);
    });

    test('前面都对得上、只是末尾多了几条时，指向多出来的第一条', () {
      final r = SubtitlePairing.pair(
        [_c(0, 1000, '一')],
        [_c(0, 1000, 'one'), _c(1000, 2000, 'two')],
      );
      expect(r.misalignedFrom, 2);
    });
  });
}
