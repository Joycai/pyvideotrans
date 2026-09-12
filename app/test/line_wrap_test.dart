import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/line_wrap.dart';

void main() {
  group('折行', () {
    test('短句原样返回', () {
      expect(
        LineWrap.lines('很短的一句', limit: 15, cjk: true),
        ['很短的一句'],
      );
    });

    test('比上限多几个字不折 —— 硬折反而多出一行', () {
      final text = '一' * 18;
      expect(LineWrap.lines(text, limit: 15, cjk: true), [text]);
    });

    test('中文长句按上限折，且优先断在标点后', () {
      final out = LineWrap.lines(
        '今天我们来讲一个很长的故事，这个故事发生在很久以前的一个小村庄里。',
        limit: 15,
        cjk: true,
      );
      expect(out.length, greaterThan(1));
      expect(out.first, endsWith('，'));
      expect(out.every((l) => l.runes.length <= 15 + 4), isTrue);
    });

    test('西文不把单词劈开', () {
      final out = LineWrap.lines(
        'the quick brown fox jumps over the lazy dog and keeps running',
        limit: 20,
        cjk: false,
      );
      expect(out.length, greaterThan(1));
      for (final line in out) {
        expect(line.startsWith(' '), isFalse);
        expect(line.endsWith(' '), isFalse);
      }
      // 折完再拼起来，除了换行位置之外一个字都不能少。
      expect(
        out.join(' ').replaceAll(RegExp(r'\s+'), ' '),
        'the quick brown fox jumps over the lazy dog and keeps running',
      );
    });

    test('识别结果里的换行与多余空格先归一', () {
      expect(LineWrap.normalize('第一行\n 第二行  末尾 '), '第一行 第二行 末尾');
    });

    test('末行只剩一两个字时并回上一行', () {
      final out = LineWrap.lines('一' * 17 + '。' + '二', limit: 15, cjk: true);
      expect(out.last.runes.length * 3, greaterThanOrEqualTo(15));
    });

    test('上限小到离谱也不死循环', () {
      final out = LineWrap.lines('一' * 50, limit: 1, cjk: true);
      expect(out.join().runes, hasLength(50));
    });

    test('wrap 用换行符连起来', () {
      final text = '一' * 40;
      expect(
        LineWrap.wrap(text, limit: 15, cjk: true).split('\n').length,
        LineWrap.lines(text, limit: 15, cjk: true).length,
      );
    });
  });
}
