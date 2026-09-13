import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/speech_segments.dart';

void main() {
  group('静音 → 语音段', () {
    test('静音的补集就是语音，首尾都算', () {
      final segs = SpeechSegments.fromSilences(
        [(startMs: 3000, endMs: 4000), (startMs: 8000, endMs: 9000)],
        12000,
      );
      expect(segs, [
        (startMs: 0, endMs: 3000),
        (startMs: 4000, endMs: 8000),
        (startMs: 9000, endMs: 12000),
      ]);
    });

    test('开头就是静音时第一段从静音结束处开始', () {
      final segs = SpeechSegments.fromSilences(
        [(startMs: 0, endMs: 1500)],
        5000,
      );
      expect(segs, [(startMs: 1500, endMs: 5000)]);
    });

    test('超长段等分，而不是切在固定秒数', () {
      final segs = SpeechSegments.fromSilences(const [], 60000, maxMs: 25000);
      expect(segs, [
        (startMs: 0, endMs: 20000),
        (startMs: 20000, endMs: 40000),
        (startMs: 40000, endMs: 60000),
      ]);
    });

    test('短段并入前一段；第一段太短就并入后一段', () {
      final segs = SpeechSegments.fromSilences(
        [
          (startMs: 500, endMs: 1200), // 前面只有 500ms
          (startMs: 5000, endMs: 5800),
          (startMs: 6200, endMs: 7000), // 中间夹着 400ms
        ],
        10000,
      );
      // 开头 500ms 并入后一段；中间 400ms 并入前一段（连同那段静音）。
      expect(segs, [
        (startMs: 0, endMs: 6200),
        (startMs: 7000, endMs: 10000),
      ]);
    });

    test('重叠与越界的静音被合并、裁剪', () {
      final segs = SpeechSegments.fromSilences(
        [
          (startMs: 2000, endMs: 4000),
          (startMs: 3000, endMs: 5000),
          (startMs: -100, endMs: 500),
          (startMs: 9000, endMs: 99999),
        ],
        10000,
      );
      expect(segs, [
        (startMs: 500, endMs: 2000),
        (startMs: 5000, endMs: 9000),
      ]);
    });

    test('全静音或零时长返回空', () {
      expect(SpeechSegments.fromSilences([(startMs: 0, endMs: 5000)], 5000), isEmpty);
      expect(SpeechSegments.fromSilences(const [], 0), isEmpty);
    });
  });

  group('解析 silencedetect', () {
    test('成对的 start / end', () {
      const stderr = '''
[silencedetect @ 0x1] silence_start: 1.5
[silencedetect @ 0x1] silence_end: 2.25 | silence_duration: 0.75
size=N/A time=00:00:10.00
[silencedetect @ 0x1] silence_start: 7
[silencedetect @ 0x1] silence_end: 8.1 | silence_duration: 1.1
''';
      expect(SpeechSegments.parseSilenceDetect(stderr, 10000), [
        (startMs: 1500, endMs: 2250),
        (startMs: 7000, endMs: 8100),
      ]);
    });

    test('文件末尾只有 start 没有 end 时静到结尾', () {
      const stderr = '[silencedetect @ 0x1] silence_start: 9.2\n';
      expect(SpeechSegments.parseSilenceDetect(stderr, 10000), [
        (startMs: 9200, endMs: 10000),
      ]);
    });
  });
}
