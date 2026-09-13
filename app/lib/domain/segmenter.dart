import 'cue.dart';

/// 断句：识别结果交给翻译前的时间轴规整。
///
/// 纯函数，不碰 IO，方便单测。各识别渠道的原始结果质量参差不齐，统一在
/// 这里兜底，而不是指望每个渠道自己处理干净。
class Segmenter {
  const Segmenter({this.minDurationMs = 500, this.mergeGapMs = 200});

  /// 短于这个时长的字幕尝试并进上一条，避免闪一下就过去。
  final int minDurationMs;

  /// 与上一条间隔小于这个值才合并；相隔较远说明是独立的短应答。
  final int mergeGapMs;

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
        );
        joined++;
      } else {
        merged.add(cue);
      }
    }

    return SegmentResult(
      cues: [for (final (i, c) in merged.indexed) c.copyWith(index: i + 1)],
      joined: joined,
    );
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
  const SegmentResult({required this.cues, required this.joined});

  final List<Cue> cues;

  /// 被并进上一条的短句数。
  final int joined;
}
