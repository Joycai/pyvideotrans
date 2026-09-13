/// 一条字幕的校对状态。
enum CueState {
  /// 已校对 / 正常。
  ok,

  /// 待校对 —— 置信度偏低或人工标记。界面上用字幕黄。
  review,

  /// 尚未翻译。
  untranslated,
}

/// 一条字幕。时间以毫秒记，避免浮点累积误差。
class Cue {
  const Cue({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.source,
    this.translation,
    this.confidence,
    this.reviewed = false,
    this.speaker,
  });

  /// 1 起的行号。
  final int index;
  final int startMs;
  final int endMs;
  final String source;
  final String? translation;

  /// ASR 置信度 0..1，没有则为 null。
  final double? confidence;

  /// 人工确认过。
  final bool reviewed;

  /// 说话人编号（0 起），开了说话人分离的识别服务给出；没有则为 null。
  /// 只是标签，不参与文本；写出产物时由写出方决定怎么显示。
  final int? speaker;

  int get durationMs => endMs - startMs;

  bool get hasTranslation =>
      translation != null && translation!.trim().isNotEmpty;

  /// 置信度低于 0.65 的自动标为待校对，与原 Python 实现的阈值一致。
  static const lowConfidence = 0.65;

  CueState get state {
    if (!hasTranslation) return CueState.untranslated;
    if (reviewed) return CueState.ok;
    if (confidence != null && confidence! < lowConfidence) {
      return CueState.review;
    }
    return CueState.ok;
  }

  Cue copyWith({
    int? index,
    int? startMs,
    int? endMs,
    String? source,
    String? translation,
    bool clearTranslation = false,
    double? confidence,
    bool? reviewed,
    int? speaker,
  }) => Cue(
    index: index ?? this.index,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    source: source ?? this.source,
    translation: clearTranslation ? null : (translation ?? this.translation),
    confidence: confidence ?? this.confidence,
    reviewed: reviewed ?? this.reviewed,
    speaker: speaker ?? this.speaker,
  );

  Map<String, Object?> toJson() => {
    'index': index,
    'startMs': startMs,
    'endMs': endMs,
    'source': source,
    if (translation != null) 'translation': translation,
    if (confidence != null) 'confidence': confidence,
    if (reviewed) 'reviewed': true,
    if (speaker != null) 'speaker': speaker,
  };

  factory Cue.fromJson(Map<String, Object?> json) => Cue(
    index: json['index']! as int,
    startMs: json['startMs']! as int,
    endMs: json['endMs']! as int,
    source: json['source']! as String,
    translation: json['translation'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble(),
    reviewed: json['reviewed'] as bool? ?? false,
    speaker: json['speaker'] as int?,
  );
}

/// 一份字幕文档。
class SubtitleDocument {
  const SubtitleDocument({
    required this.cues,
    this.sourceLanguage,
    this.targetLanguage,
  });

  final List<Cue> cues;
  final String? sourceLanguage;
  final String? targetLanguage;

  static const empty = SubtitleDocument(cues: []);

  int get reviewCount => cues.where((c) => c.state == CueState.review).length;
  int get untranslatedCount =>
      cues.where((c) => c.state == CueState.untranslated).length;
  int get okCount => cues.where((c) => c.state == CueState.ok).length;

  Duration get duration => cues.isEmpty
      ? Duration.zero
      : Duration(
          milliseconds: cues.fold<int>(
            0,
            (maxEnd, cue) => cue.endMs > maxEnd ? cue.endMs : maxEnd,
          ),
        );

  SubtitleDocument copyWith({
    List<Cue>? cues,
    String? sourceLanguage,
    String? targetLanguage,
  }) => SubtitleDocument(
    cues: cues ?? this.cues,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
  );

  /// 替换一条并保持行号连续。
  SubtitleDocument replaceAt(int position, Cue cue) {
    final next = [...cues]..[position] = cue;
    return copyWith(cues: next);
  }

  /// 在指定位置按字符偏移拆分成两条，时间按字符比例分配。
  SubtitleDocument splitAt(int position, int charOffset) {
    final cue = cues[position];
    final text = cue.source;
    // 先判长度：不足两个字时 clamp 的下限会大于上限，直接抛 ArgumentError。
    // 识别被跳过的段会留下空文本的占位条，正好会走到这里。
    if (text.length < 2) return this;
    final cut = charOffset.clamp(1, text.length - 1);

    final ratio = cut / text.length;
    final mid = cue.startMs + (cue.durationMs * ratio).round();
    // Editing the source invalidates any old translation/review state. A
    // split cannot reliably divide a translation between the two new cues.
    final head = cue.copyWith(
      endMs: mid,
      source: text.substring(0, cut).trim(),
      clearTranslation: true,
      reviewed: false,
    );
    final tail = Cue(
      index: cue.index + 1,
      startMs: mid,
      endMs: cue.endMs,
      source: text.substring(cut).trim(),
      confidence: cue.confidence,
    );

    final next = [...cues]
      ..removeAt(position)
      ..insertAll(position, [head, tail]);
    return copyWith(cues: _renumber(next));
  }

  /// 与下一条合并。译文用空格/直连拼接（中日韩直连）。
  SubtitleDocument mergeWithNext(int position, {bool cjk = false}) {
    if (position >= cues.length - 1) return this;
    final a = cues[position];
    final b = cues[position + 1];
    final join = cjk ? '' : ' ';
    final merged = Cue(
      index: a.index,
      startMs: a.startMs,
      endMs: b.endMs,
      source: '${a.source}$join${b.source}',
      translation: a.hasTranslation || b.hasTranslation
          ? '${a.translation ?? ''}${cjk ? '' : ' '}${b.translation ?? ''}'
                .trim()
          : null,
      confidence: switch ((a.confidence, b.confidence)) {
        (final x?, final y?) => (x + y) / 2,
        (final x?, null) => x,
        (null, final y?) => y,
        _ => null,
      },
      reviewed: a.reviewed && b.reviewed,
    );

    final next = [...cues]
      ..removeRange(position, position + 2)
      ..insert(position, merged);
    return copyWith(cues: _renumber(next));
  }

  static List<Cue> _renumber(List<Cue> list) => [
    for (final (i, c) in list.indexed) c.copyWith(index: i + 1),
  ];
}
