/// 字幕单行换行。
///
/// 一条字幕在屏幕上占几行是可读性的关键：太长会挡画面，断在词中间会很难读。
/// 原 Python 实现里这件事由 `util/_srt_wrap.py` 的 `simple_wrap` 做，
/// 默认中日韩每行 15 字、其他语言每行 40 字。这里是同样规则的重写版
/// ——原实现用了一段难以复现的指针回退，这里改成「先找断点，找不到再硬断」，
/// 行为更好预测，也更好测。
abstract final class LineWrap {
  /// 可以在其后断行的字符。逗号句号之后断，读起来最自然。
  static const _breakAfter = {
    ',', '.', '?', '!', ';', ':',
    '，', '。', '？', '！', '；', '：', '、',
    ' ',
  };

  /// 短到这个程度就不折了 —— 比上限多几个字并不影响阅读，
  /// 硬折反而多出一行。
  static const _tolerance = 4;

  /// 把 [text] 折成若干行。[limit] 是每行字符数上限。
  ///
  /// [cjk] 影响找断点时往前后看多远：中日韩没有空格，能断的位置密集，
  /// 看 2 个字就够；西文要跨过整个单词，得看 8 个。
  static List<String> lines(
    String text, {
    required int limit,
    required bool cjk,
  }) {
    final clean = normalize(text);
    if (clean.isEmpty) return const [];

    final max = limit < 3 ? 3 : limit;
    final chars = clean.runes.toList();
    if (chars.length <= max + _tolerance) return [clean];

    final window = (cjk ? 2 : 8).clamp(1, max ~/ 2);
    final out = <String>[];
    var start = 0;

    while (start < chars.length) {
      if (chars.length - start <= max + _tolerance) {
        out.add(_slice(chars, start, chars.length));
        break;
      }

      final cut = _findCut(chars, start, max, window);
      out.add(_slice(chars, start, cut));
      start = cut;
      // 跳过断点后的空格，否则下一行会以空格开头。
      while (start < chars.length && chars[start] == 0x20) {
        start++;
      }
    }

    // 末行只剩一两个字时并回上一行，避免孤字成行。
    if (out.length > 1 && out.last.runes.length * 3 < max) {
      final tail = out.removeLast();
      out[out.length - 1] = '${out.last}${cjk ? '' : ' '}$tail';
    }
    return out;
  }

  /// 折好后用换行符连起来，直接可写进 SRT。
  static String wrap(String text, {required int limit, required bool cjk}) =>
      lines(text, limit: limit, cjk: cjk).join('\n');

  /// 去掉换行与重复空格 —— 识别服务返回的文本里这两样都不少。
  static String normalize(String text) => text
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  /// 在 [start] + [max] 附近找一个断点，返回切分位置（不含）。
  static int _findCut(List<int> chars, int start, int max, int window) {
    final ideal = start + max;

    // 先往回找：宁可短一点，也不要超过上限。
    for (var i = ideal; i > ideal - window && i > start + 1; i--) {
      if (_isBreak(chars[i - 1])) return i;
    }
    // 再往后看一点点：差一两个字就能断在标点上时值得多带上。
    for (var i = ideal + 1; i <= ideal + window && i <= chars.length; i++) {
      if (_isBreak(chars[i - 1])) return i;
    }
    // 西文还可以退到本行最后一个空格，别把单词劈开。
    for (var i = ideal; i > start + 1; i--) {
      if (chars[i - 1] == 0x20) return i;
    }
    return ideal;
  }

  static bool _isBreak(int rune) =>
      _breakAfter.contains(String.fromCharCode(rune));

  static String _slice(List<int> chars, int from, int to) =>
      String.fromCharCodes(chars.sublist(from, to)).trim();
}
