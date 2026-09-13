import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/segmenter.dart';

Cue _cue(int start, int end, String text, {int? speaker}) =>
    Cue(index: 0, startMs: start, endMs: end, source: text, speaker: speaker);

List<(int, int)> _times(List<Cue> cues) => [
  for (final c in cues) (c.startMs, c.endMs),
];

void main() {
  group('重叠修正', () {
    test('前一条终点越过后一条起点时收回到后一条起点', () {
      final out = Segmenter.fixOverlaps([
        _cue(0, 2500, '第一句'),
        _cue(2000, 4000, '第二句'),
      ]);
      expect(_times(out), [(0, 2000), (2000, 4000)]);
    });

    test('乱序输入按起点排好', () {
      final out = Segmenter.fixOverlaps([
        _cue(3000, 4000, 'b'),
        _cue(0, 1000, 'a'),
      ]);
      expect(out.map((c) => c.source), ['a', 'b']);
    });

    test('起点相同时后一条往后推，且仍保持 start < end', () {
      final out = Segmenter.fixOverlaps([
        _cue(1000, 3000, 'a'),
        _cue(1000, 2000, 'b'),
      ]);
      expect(_times(out), [(1000, 3000), (3000, 3001)]);
      expect(out.map((c) => c.source), ['a', 'b']);
    });

    test('零长或倒挂的字幕至少 1 ms', () {
      final out = Segmenter.fixOverlaps([_cue(500, 400, 'a')]);
      expect(_times(out), [(500, 501)]);
    });

    test('断句结果里没有重叠，行号连续', () {
      final result = const Segmenter().run([
        _cue(0, 3000, 'hello there'),
        _cue(2800, 6000, 'general kenobi'),
      ], cjk: false);
      expect(_times(result.cues), [(0, 2800), (2800, 6000)]);
      expect(result.cues.map((c) => c.index), [1, 2]);
    });
  });

  group('合并短句', () {
    test('紧邻的短句并进上一条', () {
      final result = const Segmenter().run([
        _cue(0, 2000, '你好'),
        _cue(2100, 2400, '啊'),
      ], cjk: true);
      expect(result.joined, 1);
      expect(result.cues.single.source, '你好啊');
      expect(_times(result.cues), [(0, 2400)]);
    });

    test('换说话人不并', () {
      final result = const Segmenter().run([
        _cue(0, 2000, '你好', speaker: 0),
        _cue(2100, 2400, '嗯', speaker: 1),
      ], cjk: true);
      expect(result.cues, hasLength(2));
    });
  });
}
