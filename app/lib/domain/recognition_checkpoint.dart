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

  /// 切分出来的总段数。识别服务切完音频后写入；记录只覆盖跑到过的段，
  /// 所以「已完成 / 总数」要用它而不是 [length]。
  int? total;

  /// 一段最多失败几次，之后放弃并跳过。
  static const maxFailures = 3;

  /// 「自动重试并跳过失败段」模式：失败的段在同一次运行里自动重试，
  /// 达到 [maxFailures] 就跳过继续；限流与断网不算失败，等恢复后再试。
  /// 用户点「从识别阶段继续」时关掉，点「自动重试」时打开。
  bool autoRetry = false;

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
  ///
  /// 记录只覆盖跑到过的段（中途失败时后面的段还没记），所以只要求
  /// 记录过的每一段都能在新切分里找到，不要求数量相等。
  bool matches(Iterable<({int startMs, int endMs})> clips) {
    if (_segments.isEmpty) return true;
    final keys = {for (final c in clips) '${c.startMs}-${c.endMs}'};
    return _segments.keys.every(keys.contains);
  }

  void clear() {
    _segments.clear();
    total = null;
  }

  /// 记一次失败。达到上限就放弃这一段。返回是否已放弃。
  bool fail(SegmentRecord s, String error) {
    s
      ..failures += 1
      ..lastError = error;
    if (s.failures >= maxFailures) s.skipped = true;
    return s.skipped;
  }
}
