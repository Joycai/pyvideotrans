/// 识别检查点里的一段：按片段的时间范围记，续跑时用同样的切分点对上。
class SegmentRecord {
  SegmentRecord({
    required this.startMs,
    required this.endMs,
    this.text,
    this.failures = 0,
    this.skipped = false,
    this.lastError,
  });

  final int startMs;
  final int endMs;

  /// 识别出来的文本。null 表示还没成功过；空串表示这段确实没有话。
  String? text;

  /// 累计失败次数，跨多次续跑累加。
  int failures;

  /// 反复失败后被放弃。产物里留一条空文本、低置信度的占位字幕。
  bool skipped;
  String? lastError;

  bool get done => text != null || skipped;

  String get key => '$startMs-$endMs';
}

/// 识别阶段的检查点：逐段识别的服务把每段的结果记在这里，失败或取消后
/// 续跑时跳过已完成的段。只存在内存里，随任务一起丢弃。
///
/// 静音切分是确定性的：同一份音频再切一遍得到同样的片段，所以按
/// 时间范围就能对上。切分结果对不上（音频被重新抽取过）就整份作废。
class RecognitionCheckpoint {
  final Map<String, SegmentRecord> _segments = {};

  /// 一段最多失败几次，之后放弃并跳过。
  static const maxFailures = 3;

  int get length => _segments.length;
  Iterable<SegmentRecord> get segments => _segments.values;

  int get doneCount => _segments.values.where((s) => s.done).length;
  int get skippedCount => _segments.values.where((s) => s.skipped).length;

  /// 失败过但还没放弃的段。
  Iterable<SegmentRecord> get pending =>
      _segments.values.where((s) => !s.done && s.failures > 0);

  /// 取这一段的记录，没有就建一条。
  SegmentRecord segment(int startMs, int endMs) => _segments.putIfAbsent(
    '$startMs-$endMs',
    () => SegmentRecord(startMs: startMs, endMs: endMs),
  );

  /// 这一批切分点与记录是否吻合。不吻合说明音频变了，记录不能用。
  bool matches(Iterable<({int startMs, int endMs})> clips) {
    if (_segments.isEmpty) return true;
    var n = 0;
    for (final c in clips) {
      n++;
      if (!_segments.containsKey('${c.startMs}-${c.endMs}')) return false;
    }
    return n == _segments.length;
  }

  void clear() => _segments.clear();

  /// 记一次失败。达到上限就放弃这一段。返回是否已放弃。
  bool fail(SegmentRecord s, String error) {
    s
      ..failures += 1
      ..lastError = error;
    if (s.failures >= maxFailures) s.skipped = true;
    return s.skipped;
  }
}
