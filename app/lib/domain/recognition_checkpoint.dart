/// 一段识别结果里的一小块：带自己的时间与说话人。开说话人分离时一段
/// 音频会回来多块（按说话人 / 句子切开），不开就只有整段一块。
class SegmentPiece {
  const SegmentPiece({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speaker,
  });

  final int startMs;
  final int endMs;
  final String text;
  final int? speaker;

  Map<String, Object?> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
    if (speaker != null) 'speaker': speaker,
  };

  factory SegmentPiece.fromJson(Map<String, Object?> json) => SegmentPiece(
    startMs: json['startMs']! as int,
    endMs: json['endMs']! as int,
    text: json['text']! as String,
    speaker: json['speaker'] as int?,
  );
}

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

  /// 细分结果（说话人分离时按说话人 / 句子切开的小块）。没有就整段一条。
  List<SegmentPiece>? pieces;

  /// 累计失败次数，跨多次续跑累加。
  int failures;

  /// 反复失败后被放弃。产物里留一条空文本、低置信度的占位字幕。
  bool skipped;
  String? lastError;

  bool get done => text != null || skipped;

  String get key => '$startMs-$endMs';

  Map<String, Object?> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    if (text != null) 'text': text,
    if (pieces != null) 'pieces': [for (final p in pieces!) p.toJson()],
    if (failures > 0) 'failures': failures,
    if (skipped) 'skipped': true,
    if (lastError != null) 'lastError': lastError,
  };

  factory SegmentRecord.fromJson(Map<String, Object?> json) =>
      SegmentRecord(
          startMs: json['startMs']! as int,
          endMs: json['endMs']! as int,
          text: json['text'] as String?,
          failures: json['failures'] as int? ?? 0,
          skipped: json['skipped'] as bool? ?? false,
          lastError: json['lastError'] as String?,
        )
        ..pieces = switch (json['pieces']) {
          final List list => [
            for (final p in list)
              SegmentPiece.fromJson((p as Map).cast<String, Object?>()),
          ],
          _ => null,
        };
}

/// 识别阶段的检查点：逐段识别的服务把每段的结果记在这里，失败或取消后
/// 续跑时跳过已完成的段。随任务一起持久化，应用重启后仍能续跑。
///
/// 静音切分是确定性的：同一份音频再切一遍得到同样的片段，所以按
/// 时间范围就能对上。切分结果对不上（音频被重新抽取过）就整份作废。
class RecognitionCheckpoint {
  RecognitionCheckpoint();

  factory RecognitionCheckpoint.fromJson(Map<String, Object?> json) {
    final cp = RecognitionCheckpoint()
      ..total = json['total'] as int?
      ..asyncFileUrl = json['asyncFileUrl'] as String?
      ..asyncTaskId = json['asyncTaskId'] as String?
      ..autoRetry = json['autoRetry'] as bool? ?? false;
    for (final raw in json['segments'] as List? ?? const []) {
      final s = SegmentRecord.fromJson((raw as Map).cast<String, Object?>());
      cp._segments[s.key] = s;
    }
    return cp;
  }

  final Map<String, SegmentRecord> _segments = {};

  Map<String, Object?> toJson() => {
    'segments': [for (final s in _segments.values) s.toJson()],
    if (total != null) 'total': total,
    if (asyncFileUrl != null) 'asyncFileUrl': asyncFileUrl,
    if (asyncTaskId != null) 'asyncTaskId': asyncTaskId,
    if (autoRetry) 'autoRetry': true,
  };

  /// 切分出来的总段数。识别服务切完音频后写入；记录只覆盖跑到过的段，
  /// 所以「已完成 / 总数」要用它而不是 [length]。
  int? total;

  /// 异步整文件转写（阿里百炼 filetrans）的断点：已上传的音频地址
  /// （`oss://…`，48 小时有效）与已提交的任务号。中途停下再继续时，
  /// 有任务号就直接查任务；只有地址就用它重新提交，不重新上传。
  String? asyncFileUrl;
  String? asyncTaskId;

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
    asyncFileUrl = null;
    asyncTaskId = null;
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
