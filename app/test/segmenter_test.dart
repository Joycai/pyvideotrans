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

    test('合并后置信度取较低的一方，低置信度短句仍标待校对', () {
      final result = const Segmenter().run([
        const Cue(
          index: 1,
          startMs: 0,
          endMs: 2000,
          source: '你好',
          confidence: 0.95,
        ),
        const Cue(
          index: 2,
          startMs: 2100,
          endMs: 2400,
          source: '啊',
          confidence: 0.3,
        ),
      ], cjk: true);
      expect(result.cues.single.confidence, 0.3);
    });

    test('换说话人不并', () {
      final result = const Segmenter().run([
        _cue(0, 2000, '你好', speaker: 0),
        _cue(2100, 2400, '嗯', speaker: 1),
      ], cjk: true);
      expect(result.cues, hasLength(2));
    });
  });

  group('拆分过长字幕', () {
    test('25 秒的中文字幕按标点拆成不超过上限附近的几条，时间首尾相接', () {
      const text =
          '今天我们来聊一聊字幕时间轴，这是一个很常见的问题，'
          '识别服务不给时间戳的时候，整段话只能挂在一条字幕上。';
      final result = const Segmenter().run([_cue(0, 25000, text)], cjk: true);
      final cues = result.cues;
      expect(result.split, 1);
      expect(cues, hasLength(3));
      expect(cues.first.startMs, 0);
      expect(cues.last.endMs, 25000);
      for (var i = 1; i < cues.length; i++) {
        expect(cues[i].startMs, cues[i - 1].endMs);
      }
      expect(cues.map((c) => c.source).join(), text);
      // 切点落在标点之后。
      for (final c in cues.take(cues.length - 1)) {
        expect(c.source, matches(RegExp(r'[，。]$')));
      }
      expect(cues.map((c) => c.index), [1, 2, 3]);
    });

    test('拉丁文不把单词劈开', () {
      const text =
          'the quick brown fox jumps over the lazy dog again and again';
      final cues = const Segmenter().run([
        _cue(0, 21000, text),
      ], cjk: false).cues;
      expect(cues.length, greaterThan(1));
      expect(cues.map((c) => c.source).join(' '), text);
    });

    test('说话人与置信度沿用原条', () {
      final cues = const Segmenter().splitLong(
        const Cue(
          index: 1,
          startMs: 0,
          endMs: 30000,
          source: '第一句话，第二句话，第三句话',
          speaker: 2,
          confidence: 0.4,
        ),
        cjk: true,
      );
      expect(cues.length, greaterThan(1));
      expect(cues.every((c) => c.speaker == 2 && c.confidence == 0.4), isTrue);
    });

    test('未超长或空文本的占位条不动', () {
      const s = Segmenter();
      expect(s.splitLong(_cue(0, 9000, '短句'), cjk: true), hasLength(1));
      expect(s.splitLong(_cue(0, 60000, ''), cjk: true), hasLength(1));
    });
  });
}
