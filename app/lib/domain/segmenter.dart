import 'cue.dart';

/// 断句：识别结果交给翻译前的时间轴规整。
///
/// 纯函数，不碰 IO，方便单测。各识别渠道的原始结果质量参差不齐，统一在
/// 这里兜底，而不是指望每个渠道自己处理干净。
class Segmenter {
  const Segmenter({
    this.minDurationMs = 500,
    this.mergeGapMs = 200,
    this.maxDurationMs = 10000,
  });

  /// 短于这个时长的字幕尝试并进上一条，避免闪一下就过去。
  final int minDurationMs;

  /// 与上一条间隔小于这个值才合并；相隔较远说明是独立的短应答。
  final int mergeGapMs;

  /// 长于这个时长的字幕按文字拆开。没有词级时间戳的识别渠道整段语音就是
  /// 一条字幕，最长可达切片上限（25 秒，开说话人分离时 2 分钟）。
  /// 默认与词级切分的单条上限一致。
  final int maxDurationMs;

  SegmentResult run(List<Cue> input, {required bool cjk}) {
    final cues = fixOverlaps(input);
    final merged = <Cue>[];
    var joined = 0;

    for (final cue in cues) {
      final last = merged.isEmpty ? null : merged.last;
      // 不同说话人的不并 —— 短应答恰恰常是换人。
      if (last != null &&
          cue.durationMs < minDurationMs &&
          cue.startMs - last.endMs < mergeGapMs &&
          last.speaker == cue.speaker) {
        merged[merged.length - 1] = last.copyWith(
          endMs: cue.endMs,
          source: '${last.source}${cjk ? '' : ' '}${cue.source}',
          confidence: Cue.mergedConfidence(last.confidence, cue.confidence),
        );
        joined++;
      } else {
        merged.add(cue);
      }
    }

    final out = <Cue>[];
    var split = 0;
    for (final cue in merged) {
      final pieces = splitLong(cue, cjk: cjk);
      if (pieces.length > 1) split++;
      out.addAll(pieces);
    }

    return SegmentResult(
      cues: [for (final (i, c) in out.indexed) c.copyWith(index: i + 1)],
      joined: joined,
      split: split,
    );
  }

  /// 把超过 [maxDurationMs] 的一条拆成若干条，时间按字符比例分配。
  ///
  /// 切点优先落在标点或空白之后：中日韩只在目标位置附近找，找不到就按字数
  /// 硬切；拉丁文宁可切得不均匀也不把一个词劈开。说话人与置信度沿用原条。
  List<Cue> splitLong(Cue cue, {required bool cjk}) {
    final text = cue.source;
    if (cue.durationMs <= maxDurationMs || text.trim().length < 2) {
      return [cue];
    }
    final parts = (cue.durationMs / maxDurationMs).ceil();
    final len = text.length;
    final window = cjk ? len ~/ (parts * 2) : len;

    final cuts = <int>[];
    for (var k = 1; k < parts; k++) {
      final target = (len * k / parts).round();
      final cut = _nearestBreak(text, target, window) ?? target;
      final prev = cuts.isEmpty ? 0 : cuts.last;
      if (cut <= prev || cut >= len) continue;
      if (text.substring(prev, cut).trim().isEmpty) continue;
      if (text.substring(cut).trim().isEmpty) continue;
      cuts.add(cut);
    }
    if (cuts.isEmpty) return [cue];

    int at(int offset) => cue.startMs + (cue.durationMs * offset / len).round();
    final bounds = [0, ...cuts, len];
    return [
      for (var i = 0; i < bounds.length - 1; i++)
        cue.copyWith(
          startMs: at(bounds[i]),
          endMs: at(bounds[i + 1]),
          source: text.substring(bounds[i], bounds[i + 1]).trim(),
        ),
    ];
  }

  static final _break = RegExp(r'[\s，。！？；：、,.!?;:]');

  /// 离 [target] 最近、在 [window] 范围内的切点；切点紧跟在标点或空白之后。
  static int? _nearestBreak(String text, int target, int window) {
    for (var d = 0; d <= window; d++) {
      for (final i in [target + d, target - d]) {
        if (i > 0 && i < text.length && _break.hasMatch(text[i - 1])) {
          return i;
        }
      }
    }
    return null;
  }

  /// 按起点排序，并把与下一条重叠的字幕终点收到下一条起点。
  ///
  /// Whisper 系幻听、或服务端分段本身有交叠时会出现重叠；播放器里表现为
  /// 两条字幕同时显示。与原 Python 实现 `_post_fix` 的规则一致：动前一条的
  /// 终点，不动后一条的起点。每条至少保留 1 ms，保证 start < end。
  static List<Cue> fixOverlaps(List<Cue> input) {
    // List.sort 不保证稳定；带上原下标，起点相同时保持识别顺序。
    final indexed = input.indexed.toList()
      ..sort((a, b) {
        final byStart = a.$2.startMs.compareTo(b.$2.startMs);
        return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
      });

    final out = <Cue>[];
    for (var (_, cue) in indexed) {
      if (cue.endMs <= cue.startMs) {
        cue = cue.copyWith(endMs: cue.startMs + 1);
      }
      if (out.isNotEmpty) {
        final prev = out.last;
        if (prev.endMs > cue.startMs) {
          if (cue.startMs > prev.startMs) {
            out[out.length - 1] = prev.copyWith(endMs: cue.startMs);
          } else {
            // 起点相同：前一条没法缩，只能把这条往后推。
            final start = prev.endMs;
            cue = cue.copyWith(
              startMs: start,
              endMs: cue.endMs > start ? cue.endMs : start + 1,
            );
          }
        }
      }
      out.add(cue);
    }
    return out;
  }
}

class SegmentResult {
  const SegmentResult({
    required this.cues,
    required this.joined,
    this.split = 0,
  });

  final List<Cue> cues;

  /// 被并进上一条的短句数。
  final int joined;

  /// 因过长被拆开的字幕数。
  final int split;
}
