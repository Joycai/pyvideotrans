import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/srt.dart';

const _sample = '''
1
00:00:01,200 --> 00:00:03,850
大家好，欢迎收看本期节目。

2
00:00:03,850 --> 00:00:07,100
今天我们聊一聊本地模型的部署。
''';

void main() {
  group('时间码', () {
    test('毫秒与文本互转', () {
      expect(Srt.formatTimecode(3661450), '01:01:01,450');
      expect(Srt.parseTimecode('01:01:01,450'), 3661450);
      expect(Srt.formatTimecode(0), '00:00:00,000');
    });

    test('负值夹到零', () {
      expect(Srt.formatTimecode(-5), '00:00:00,000');
    });

    test('格式不合法返回 null', () {
      expect(Srt.parseTimecode('乱码'), isNull);
      expect(Srt.parseTimecode('1:2'), isNull);
    });

    test('时长省略零小时', () {
      expect(Srt.formatDuration(const Duration(minutes: 48, seconds: 12)), '48:12');
      expect(
        Srt.formatDuration(const Duration(hours: 1, minutes: 32, seconds: 5)),
        '1:32:05',
      );
    });
  });

  group('解析', () {
    test('标准 SRT', () {
      final cues = Srt.parse(_sample);
      expect(cues, hasLength(2));
      expect(cues.first.startMs, 1200);
      expect(cues.first.endMs, 3850);
      expect(cues.first.source, '大家好，欢迎收看本期节目。');
      expect(cues.last.index, 2);
    });

    test('容忍 CRLF、BOM、缺失序号与多余空行', () {
      final cues = Srt.parse(
        '﻿00:00:01.000 --> 00:00:02.50\r\nHello\r\n\r\n\r\n'
        '00:00:02,500 --> 00:00:03,000\r\nWorld\r\n',
      );
      expect(cues, hasLength(2));
      // VTT 的两位小数补齐成毫秒。
      expect(cues.first.endMs, 2500);
      expect(cues.last.source, 'World');
    });

    test('跳过坏块而不是整份失败', () {
      final cues = Srt.parse('这里没有时间码\n\n$_sample');
      expect(cues, hasLength(2));
    });

    test('多行正文保留换行', () {
      final cues = Srt.parse('00:00:00,000 --> 00:00:01,000\n第一行\n第二行\n');
      expect(cues.single.source, '第一行\n第二行');
    });

    test('结束早于开始时夹到开始', () {
      final cues = Srt.parse('00:00:05,000 --> 00:00:01,000\n倒置\n');
      expect(cues.single.endMs, 5000);
    });
  });

  group('序列化', () {
    test('原文往返一致', () {
      final cues = Srt.parse(_sample);
      expect(Srt.parse(Srt.serialize(cues)).map((c) => c.source),
          cues.map((c) => c.source));
    });

    test('译文缺失的条目被跳过并重新编号', () {
      final cues = [
        const Cue(index: 1, startMs: 0, endMs: 1000, source: 'a', translation: 'A'),
        const Cue(index: 2, startMs: 1000, endMs: 2000, source: 'b'),
        const Cue(index: 3, startMs: 2000, endMs: 3000, source: 'c', translation: 'C'),
      ];
      final out = Srt.parse(Srt.serialize(cues, field: SrtField.translation));
      expect(out.map((c) => c.source), ['A', 'C']);
      expect(out.map((c) => c.index), [1, 2]);
    });

    test('双语把译文放在原文之上', () {
      final cues = [
        const Cue(index: 1, startMs: 0, endMs: 1000, source: '原', translation: '译'),
      ];
      expect(Srt.serialize(cues, field: SrtField.bilingual), contains('译\n原'));
    });
  });

  group('编辑', () {
    final doc = SubtitleDocument(cues: Srt.parse(_sample));

    test('拆分按字符比例分配时间并重排号', () {
      final split = doc.splitAt(0, 3);
      expect(split.cues, hasLength(3));
      expect(split.cues[0].endMs, split.cues[1].startMs);
      expect(split.cues.map((c) => c.index), [1, 2, 3]);
      expect(split.cues[0].source, '大家好');
    });

    test('合并下一条时首尾时间取两端', () {
      final merged = doc.mergeWithNext(0, cjk: true);
      expect(merged.cues, hasLength(1));
      expect(merged.cues.single.startMs, 1200);
      expect(merged.cues.single.endMs, 7100);
      expect(merged.cues.single.source, contains('大家好，欢迎收看本期节目。今天'));
    });

    test('合并最后一条是空操作', () {
      expect(doc.mergeWithNext(1).cues, hasLength(2));
    });
  });

  group('校对状态', () {
    test('没有译文即未翻译', () {
      const cue = Cue(index: 1, startMs: 0, endMs: 1, source: 'a');
      expect(cue.state, CueState.untranslated);
    });

    test('低置信度标为待校对', () {
      const cue = Cue(
        index: 1, startMs: 0, endMs: 1, source: 'a',
        translation: 'A', confidence: 0.58,
      );
      expect(cue.state, CueState.review);
    });

    test('人工确认后不再是待校对', () {
      const cue = Cue(
        index: 1, startMs: 0, endMs: 1, source: 'a',
        translation: 'A', confidence: 0.58, reviewed: true,
      );
      expect(cue.state, CueState.ok);
    });
  });
}
