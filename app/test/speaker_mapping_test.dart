import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/speaker_mapping.dart';

void main() {
  final doc = SubtitleDocument(
    cues: [
      for (var i = 0; i < 5; i++)
        Cue(
          index: i + 1,
          startMs: i * 1000,
          endMs: (i + 1) * 1000,
          source: '原文$i',
          translation: '译文$i',
          reviewed: true,
          speaker: i == 4 ? null : i % 2,
        ),
    ],
    speakers: const {0: '甲', 1: '乙'},
  );

  test('互换使用原始身份且不影响区外字幕', () {
    final next = mapSelectedSpeakers(doc, [0, 1], {0: 1, 1: 0});
    expect(next.cues.map((c) => c.speaker), [1, 0, 0, 1, null]);
    expect(next.cues[0].source, doc.cues[0].source);
    expect(next.cues[0].translation, doc.cues[0].translation);
    expect(next.cues[0].reviewed, isTrue);
    expect(next.cues[0].startMs, doc.cues[0].startMs);
    expect(next.cues[2], same(doc.cues[2]));
  });
  test('不连续选区命名与无说话人合并，往返 JSON 保留新身份', () {
    final next = mapSelectedSpeakers(
      doc,
      [0, 4],
      {0: 2, null: 2},
      newSpeakers: {2: '丙', 3: '未使用'},
    );
    expect(next.cues.map((c) => c.speaker), [2, 1, 0, 1, 2]);
    expect(next.speakers, {0: '甲', 1: '乙', 2: '丙'});
    expect(SubtitleDocument.fromJson(next.toJson()).speakers, next.speakers);
  });
  test('清除不删除名单，无变化不产生新快照', () {
    expect(mapSelectedSpeakers(doc, [0], {0: null}).cues.first.speaker, isNull);
    expect(mapSelectedSpeakers(doc, [0], {0: 0}), same(doc));
    expect(mapSelectedSpeakers(doc, [], {0: 1}), same(doc));
  });
  test('拒绝无效选区、目标和空名字', () {
    expect(() => mapSelectedSpeakers(doc, [99], {0: 1}), throwsArgumentError);
    expect(() => mapSelectedSpeakers(doc, [0], {0: 9}), throwsArgumentError);
    expect(
      () => mapSelectedSpeakers(doc, [0], {0: 2}, newSpeakers: {2: ' '}),
      throwsArgumentError,
    );
  });
}
