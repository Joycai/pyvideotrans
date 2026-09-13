/// 一段时间区间，毫秒。
typedef TimeRange = ({int startMs, int endMs});

/// 把静音检测结果变成可以逐段送去识别的语音片段。
///
/// 阿里百炼的 Qwen3-ASR 只返回整段文本、不带时间戳，所以字幕的时间码只能
/// 来自「送去识别的那一段音频本身在哪」。原 Python 实现用 VAD 切分，
/// 这里改用 ffmpeg 的 silencedetect：两段静音之间就是一句话。
///
/// 规则与原实现一致：
/// - 单段不超过 [maxMs]（接口对单次音频时长有限制，且越长越容易漏字）；
///   超长的按等分切开，而不是切在句子中间某个固定秒数上。
/// - 短于 [minMs] 的并入前一段（多半是一个语气词或噪声），
///   没有前一段就并入后一段。
abstract final class SpeechSegments {
  static const defaultMaxMs = 25000;
  static const defaultMinMs = 1000;

  /// [silences] 是静音区间（无需有序、允许越界），[totalMs] 是音频总长。
  static List<TimeRange> fromSilences(
    List<TimeRange> silences,
    int totalMs, {
    int maxMs = defaultMaxMs,
    int minMs = defaultMinMs,
  }) {
    if (totalMs <= 0) return const [];

    // 静音按起点排序并裁进 [0, total]，重叠的合并。
    final sorted = [
      for (final s in silences)
        (startMs: s.startMs.clamp(0, totalMs), endMs: s.endMs.clamp(0, totalMs)),
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final merged = <TimeRange>[];
    for (final s in sorted) {
      if (s.endMs <= s.startMs) continue;
      if (merged.isNotEmpty && s.startMs <= merged.last.endMs) {
        final last = merged.removeLast();
        merged.add((startMs: last.startMs, endMs: s.endMs > last.endMs ? s.endMs : last.endMs));
      } else {
        merged.add(s);
      }
    }

    // 静音的补集就是语音。
    final speech = <TimeRange>[];
    var cursor = 0;
    for (final s in merged) {
      if (s.startMs > cursor) speech.add((startMs: cursor, endMs: s.startMs));
      cursor = s.endMs;
    }
    if (cursor < totalMs) speech.add((startMs: cursor, endMs: totalMs));

    // 短段并入邻居。
    final joined = <TimeRange>[];
    for (final seg in speech) {
      if (seg.endMs - seg.startMs >= minMs || joined.isEmpty) {
        joined.add(seg);
      } else {
        final prev = joined.removeLast();
        joined.add((startMs: prev.startMs, endMs: seg.endMs));
      }
    }
    if (joined.length >= 2 && joined.first.endMs - joined.first.startMs < minMs) {
      final first = joined.removeAt(0);
      final next = joined.removeAt(0);
      joined.insert(0, (startMs: first.startMs, endMs: next.endMs));
    }

    // 超长段等分。
    final result = <TimeRange>[];
    for (final seg in joined) {
      final length = seg.endMs - seg.startMs;
      if (length <= maxMs) {
        result.add(seg);
        continue;
      }
      final parts = (length / maxMs).ceil();
      for (var i = 0; i < parts; i++) {
        result.add((
          startMs: seg.startMs + (length * i / parts).round(),
          endMs: seg.startMs + (length * (i + 1) / parts).round(),
        ));
      }
    }
    return result;
  }

  /// 解析 ffmpeg `silencedetect` 写在 stderr 里的行。
  ///
  /// 形如 `[silencedetect @ 0x…] silence_start: 12.345` 与
  /// `… silence_end: 13.9 | silence_duration: 1.555`。文件末尾的静音可能
  /// 只有 start 没有 end，那就一直静到 [totalMs]。
  static List<TimeRange> parseSilenceDetect(String stderr, int totalMs) {
    final starts = RegExp(r'silence_start:\s*(-?[\d.]+)');
    final ends = RegExp(r'silence_end:\s*(-?[\d.]+)');
    final result = <TimeRange>[];
    int? open;
    for (final line in stderr.split('\n')) {
      final s = starts.firstMatch(line);
      if (s != null) {
        open = _ms(s.group(1)!);
        continue;
      }
      final e = ends.firstMatch(line);
      if (e != null && open != null) {
        result.add((startMs: open, endMs: _ms(e.group(1)!)));
        open = null;
      }
    }
    if (open != null) result.add((startMs: open, endMs: totalMs));
    return result;
  }

  static int _ms(String seconds) =>
      ((double.tryParse(seconds) ?? 0) * 1000).round().clamp(0, 1 << 31);
}
