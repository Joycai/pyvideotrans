import 'language.dart';

/// 一条字幕的校对状态。
enum CueState {
  /// 已校对 / 正常。
  ok,

  /// 待校对 —— 置信度偏低或人工标记。界面上用字幕黄。
  review,

  /// 尚未翻译。
  untranslated,

  /// 只有译文、找不到对应原文 —— 挂载本地原文与译文配对时留下的行。
  unpaired,
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
    if (source.trim().isEmpty && hasTranslation) return CueState.unpaired;
    if (!hasTranslation) return CueState.untranslated;
    if (reviewed) return CueState.ok;
    if (confidence != null && confidence! < lowConfidence) {
      return CueState.review;
    }
    return CueState.ok;
  }

  /// 两条字幕合并后的置信度：取较低的一方。
  ///
  /// 取平均会把一段低置信度的内容「稀释」掉，合并后不再标待校对；而合并后
  /// 的字幕里确实含有可疑内容，仍该让人看一眼。编辑器与断句阶段共用这条规则。
  static double? mergedConfidence(double? a, double? b) => switch ((a, b)) {
    (final x?, final y?) => x < y ? x : y,
    (final x?, null) => x,
    (null, final y?) => y,
    _ => null,
  };

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
    bool clearSpeaker = false,
  }) => Cue(
    index: index ?? this.index,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    source: source ?? this.source,
    translation: clearTranslation ? null : (translation ?? this.translation),
    confidence: confidence ?? this.confidence,
    reviewed: reviewed ?? this.reviewed,
    speaker: clearSpeaker ? null : (speaker ?? this.speaker),
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
    this.speakers = const {},
    this.speakerLabels = true,
  });

  final List<Cue> cues;
  final String? sourceLanguage;
  final String? targetLanguage;

  /// 说话人编号 → 名字。没起名的说话人不在表里，显示成「说话人N」。
  ///
  /// 名字放在文档上而不是每条字幕上：改一次名整份文档一起变，
  /// 撤销也只是换回一份快照。
  final Map<int, String> speakers;

  /// 写出产物时是否在字幕前面加说话人标签（「周老师：」）。
  final bool speakerLabels;

  static const empty = SubtitleDocument(cues: []);

  Map<String, Object?> toJson() => {
    'cues': [for (final c in cues) c.toJson()],
    if (sourceLanguage != null) 'sourceLanguage': sourceLanguage,
    if (targetLanguage != null) 'targetLanguage': targetLanguage,
    // JSON 的键只能是字符串。
    if (speakers.isNotEmpty)
      'speakers': {for (final e in speakers.entries) '${e.key}': e.value},
    if (!speakerLabels) 'speakerLabels': false,
  };

  factory SubtitleDocument.fromJson(Map<String, Object?> json) =>
      SubtitleDocument(
        cues: [
          for (final c in json['cues'] as List? ?? const [])
            Cue.fromJson((c as Map).cast<String, Object?>()),
        ],
        sourceLanguage: json['sourceLanguage'] as String?,
        targetLanguage: json['targetLanguage'] as String?,
        speakers: {
          for (final e in (json['speakers'] as Map? ?? const {}).entries)
            if (int.tryParse('${e.key}') case final id? when e.value is String)
              id: e.value as String,
        },
        speakerLabels: json['speakerLabels'] as bool? ?? true,
      );

  int get reviewCount => cues.where((c) => c.state == CueState.review).length;
  int get untranslatedCount =>
      cues.where((c) => c.state == CueState.untranslated).length;
  int get unpairedCount =>
      cues.where((c) => c.state == CueState.unpaired).length;
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
    Map<int, String>? speakers,
    bool? speakerLabels,
  }) => SubtitleDocument(
    cues: cues ?? this.cues,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    speakers: speakers ?? this.speakers,
    speakerLabels: speakerLabels ?? this.speakerLabels,
  );

  /// 文档里出现过或起过名字的说话人编号，从小到大。
  List<int> get speakerIds =>
      {for (final c in cues) ?c.speaker, ...speakers.keys}.toList()..sort();

  bool get hasSpeakers => cues.any((c) => c.speaker != null);

  /// 下一个没用过的说话人编号。
  int get nextSpeakerId {
    final ids = speakerIds;
    return ids.isEmpty ? 0 : ids.last + 1;
  }

  /// 界面上显示的名字。
  String speakerName(int id) => speakers[id] ?? '说话人${id + 1}';

  /// 写进产物的说话人标签：中日韩「周老师：」，其他「Mia: 」；没起名的
  /// 写「说话人1：」/「Speaker 1: 」。关掉了标签时返回 null，写出方就不加。
  String Function(int)? speakerLabeler(Language language) {
    if (!speakerLabels) return null;
    return language.cjk
        ? (n) => '${speakers[n] ?? '说话人${n + 1}'}：'
        : (n) => '${speakers[n] ?? 'Speaker ${n + 1}'}: ';
  }

  /// 改名。名字清空等于去掉名字，回到「说话人N」。
  SubtitleDocument renameSpeaker(int id, String name) {
    final trimmed = name.trim();
    if (speakers[id] == (trimmed.isEmpty ? null : trimmed)) return this;
    final next = {...speakers};
    if (trimmed.isEmpty) {
      next.remove(id);
    } else {
      next[id] = trimmed;
    }
    return copyWith(speakers: next);
  }

  /// 把 [from] 名下的字幕全部改给 [into]，并从名单里去掉 [from]。
  /// 识别服务常把应答声单独分成一个人，合并是最常用的修正。
  SubtitleDocument mergeSpeaker(int from, int into) {
    if (from == into) return this;
    return copyWith(
      cues: [
        for (final c in cues)
          c.speaker == from ? c.copyWith(speaker: into) : c,
      ],
      speakers: {...speakers}..remove(from),
    );
  }

  /// 把 [positions] 上的字幕改给 [speaker]；传 null 表示清除说话人。
  SubtitleDocument assignSpeaker(Iterable<int> positions, int? speaker) {
    final next = [...cues];
    for (final p in positions) {
      next[p] = speaker == null
          ? next[p].copyWith(clearSpeaker: true)
          : next[p].copyWith(speaker: speaker);
    }
    return copyWith(cues: next);
  }

  /// [position] 所在的「同一人连续说的一段」的首尾位置（含）。
  /// 识别在换人处切歪时往往一连错好几条，改说话人时要能整段改。
  /// 这一条没有说话人时只有它自己。
  ({int start, int end}) speakerRun(int position) {
    final speaker = cues[position].speaker;
    var start = position;
    var end = position;
    if (speaker == null) return (start: start, end: end);
    while (start > 0 && cues[start - 1].speaker == speaker) {
      start--;
    }
    while (end < cues.length - 1 && cues[end + 1].speaker == speaker) {
      end++;
    }
    return (start: start, end: end);
  }

  /// 去掉全部译文：清空每条的译文，删掉只有译文的未配对行。
  SubtitleDocument withoutTranslations() => copyWith(
    cues: _renumber([
      for (final c in cues)
        if (c.state != CueState.unpaired) c.copyWith(clearTranslation: true),
    ]),
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
      speaker: cue.speaker,
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
      // 任一边为空（未配对的译文行没有原文）时不留多余的空格。
      source: [
        a.source,
        b.source,
      ].where((t) => t.trim().isNotEmpty).join(join),
      translation: a.hasTranslation || b.hasTranslation
          ? [a.translation, b.translation]
                .whereType<String>()
                .where((t) => t.trim().isNotEmpty)
                .join(join)
          : null,
      confidence: Cue.mergedConfidence(a.confidence, b.confidence),
      reviewed: a.reviewed && b.reviewed,
      // 未配对行没有说话人，并入时沿用有说话人的那一边。
      speaker: a.speaker ?? b.speaker,
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

/// 界面上显示的状态。整份文档都没有译文时（只挂了原文），「未翻译」没有
/// 意义，按置信度与校对标记显示成「待校对」或「已校对」。
CueState displayStateOf(Cue cue, {required bool translated}) {
  final state = cue.state;
  if (translated || state != CueState.untranslated) return state;
  final low = cue.confidence != null && cue.confidence! < Cue.lowConfidence;
  return low && !cue.reviewed ? CueState.review : CueState.ok;
}

/// [ms] 落在哪一条字幕里（含开始、不含结束）。几条重叠时优先 [preferred]，
/// 这样播放头在重叠段里不会来回跳；都不含时返回 null。
int? cueIndexAt(List<Cue> cues, int ms, {int? preferred}) {
  bool contains(Cue c) => ms >= c.startMs && ms < c.endMs;
  if (preferred != null &&
      preferred >= 0 &&
      preferred < cues.length &&
      contains(cues[preferred])) {
    return preferred;
  }
  final index = cues.indexWhere(contains);
  return index < 0 ? null : index;
}
