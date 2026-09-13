import 'cue.dart';

/// 原文与译文两份字幕怎么逐条对上。
enum PairingMode {
  /// 第 N 条原文配第 N 条译文。
  byIndex,

  /// 每条译文配给与它时间重叠最多的原文。
  byTime,
}

/// 一次配对的产物与统计，界面上在打开前把这些数字给用户看。
class PairingResult {
  const PairingResult({
    required this.mode,
    required this.cues,
    required this.paired,
    required this.sourceOnly,
    required this.translationOnly,
    required this.mergedTranslations,
    required this.misalignedFrom,
    required this.sourceCount,
    required this.translationCount,
  });

  final PairingMode mode;

  /// 合并后的字幕：原文条带上译文，找不到原文的译文单独成行（原文为空）。
  final List<Cue> cues;

  /// 有译文的原文条数。
  final int paired;

  /// 没有译文的原文条数。
  final int sourceOnly;

  /// 找不到原文、单独成行的译文条数。
  final int translationOnly;

  /// 因为同一条原文对上了多条译文而被并掉的译文条数。
  final int mergedTranslations;

  /// 按序号配对会从第几条（1 起）开始错位；逐条对得上时为 null。
  final int? misalignedFrom;

  final int sourceCount;
  final int translationCount;

  /// 配上的比例。
  double get pairedRatio {
    final smaller = sourceCount < translationCount
        ? sourceCount
        : translationCount;
    return smaller == 0 ? 0 : paired / smaller;
  }

  /// 按时间轴配上的不到 30% 时，两份多半不是同一个视频的字幕，不该自动打开；
  /// 用户明确选了按序号就照做。
  bool get plausible =>
      mode == PairingMode.byIndex ||
      pairedRatio >= SubtitlePairing.minPairedRatio;
}

/// 把本地挂载的原文与译文合成一份文档。纯函数，不碰文件。
abstract final class SubtitlePairing {
  /// 条数相同且每条起止都在这个误差内，就认为两份是逐条对应的。
  static const toleranceMs = 200;

  /// 时间重叠至少占较短一条的这个比例才算配上。
  static const minOverlapRatio = 0.5;

  static const minPairedRatio = 0.3;

  /// 没指定方式时的默认：逐条对应就按序号，否则按时间轴。
  static PairingMode suggestMode(List<Cue> source, List<Cue> translation) {
    if (source.length != translation.length) return PairingMode.byTime;
    for (var i = 0; i < source.length; i++) {
      final s = source[i];
      final t = translation[i];
      if ((s.startMs - t.startMs).abs() > toleranceMs ||
          (s.endMs - t.endMs).abs() > toleranceMs) {
        return PairingMode.byTime;
      }
    }
    return PairingMode.byIndex;
  }

  /// 配对。[cjk] 指译文语言，决定一条原文对上多条译文时译文怎么拼
  /// （中日韩直连，其他加空格）。
  static PairingResult pair(
    List<Cue> source,
    List<Cue> translation, {
    PairingMode? mode,
    bool cjk = false,
  }) {
    final resolved = mode ?? suggestMode(source, translation);
    final sources = [...source]..sort((a, b) => a.startMs - b.startMs);
    final translations = [...translation]
      ..sort((a, b) => a.startMs - b.startMs);

    final assigned = List.generate(sources.length, (_) => <Cue>[]);
    final orphans = <Cue>[];

    switch (resolved) {
      case PairingMode.byIndex:
        for (final (i, t) in translations.indexed) {
          if (i < sources.length) {
            assigned[i].add(t);
          } else {
            orphans.add(t);
          }
        }
      case PairingMode.byTime:
        _assignByTime(sources, translations, assigned, orphans);
    }

    final join = cjk ? '' : ' ';
    final merged = <Cue>[];
    var paired = 0;
    var sourceOnly = 0;
    var mergedTranslations = 0;
    for (final (i, s) in sources.indexed) {
      final ts = assigned[i];
      if (ts.isEmpty) {
        if (s.source.trim().isNotEmpty) sourceOnly++;
        merged.add(s);
        continue;
      }
      paired++;
      mergedTranslations += ts.length - 1;
      merged.add(
        s.copyWith(
          translation: ts
              .map((t) => t.source.trim())
              .where((t) => t.isNotEmpty)
              .join(join),
        ),
      );
    }

    // 未配对的译文按时间插回去；同一时刻原文排在前面。
    final rows = <Cue>[];
    var o = 0;
    for (final cue in merged) {
      while (o < orphans.length && orphans[o].startMs < cue.startMs) {
        rows.add(_orphanRow(orphans[o++]));
      }
      rows.add(cue);
    }
    while (o < orphans.length) {
      rows.add(_orphanRow(orphans[o++]));
    }

    return PairingResult(
      mode: resolved,
      cues: [for (final (i, c) in rows.indexed) c.copyWith(index: i + 1)],
      paired: paired,
      sourceOnly: sourceOnly,
      translationOnly: orphans.length,
      mergedTranslations: mergedTranslations,
      misalignedFrom: _misalignedFrom(sources, translations),
      sourceCount: sources.length,
      translationCount: translations.length,
    );
  }

  static Cue _orphanRow(Cue t) => Cue(
    index: 0,
    startMs: t.startMs,
    endMs: t.endMs,
    source: '',
    translation: t.source,
  );

  static void _assignByTime(
    List<Cue> sources,
    List<Cue> translations,
    List<List<Cue>> assigned,
    List<Cue> orphans,
  ) {
    final maxDuration = sources.fold<int>(
      0,
      (m, s) => s.durationMs > m ? s.durationMs : m,
    );
    for (final t in translations) {
      // 起点早于 t.start - maxDuration 的原文不可能与 t 重叠，二分跳过。
      var i = _firstStartingAtOrAfter(sources, t.startMs - maxDuration);
      var best = -1;
      var bestOverlap = -1;
      for (; i < sources.length; i++) {
        final s = sources[i];
        if (s.startMs >= t.endMs && s.startMs > t.startMs) break;
        if (!_matches(s, t)) continue;
        final overlap = _overlap(s, t);
        if (overlap > bestOverlap) {
          best = i;
          bestOverlap = overlap;
        }
      }
      if (best < 0) {
        orphans.add(t);
      } else {
        assigned[best].add(t);
      }
    }
  }

  static int _firstStartingAtOrAfter(List<Cue> cues, int ms) {
    var lo = 0;
    var hi = cues.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].startMs < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _overlap(Cue a, Cue b) {
    final start = a.startMs > b.startMs ? a.startMs : b.startMs;
    final end = a.endMs < b.endMs ? a.endMs : b.endMs;
    return end - start;
  }

  static bool _matches(Cue a, Cue b) {
    final shorter = a.durationMs < b.durationMs ? a.durationMs : b.durationMs;
    // 零时长的条目没法算比例，落在对方区间里就算配上。
    if (shorter <= 0) {
      return (a.startMs <= b.startMs && b.startMs < a.endMs) ||
          (b.startMs <= a.startMs && a.startMs < b.endMs) ||
          a.startMs == b.startMs;
    }
    return _overlap(a, b) >= shorter * minOverlapRatio;
  }

  static int? _misalignedFrom(List<Cue> sources, List<Cue> translations) {
    final n = sources.length < translations.length
        ? sources.length
        : translations.length;
    for (var i = 0; i < n; i++) {
      if (!_matches(sources[i], translations[i])) return i + 1;
    }
    return sources.length == translations.length ? null : n + 1;
  }
}
