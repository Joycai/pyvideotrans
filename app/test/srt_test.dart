import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/line_wrap.dart';
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

    test('WebVTT 允许省略小时', () {
      expect(Srt.parseTimecode('02:03.450'), 123450);
      final cues = Srt.parse('''WEBVTT

02:03.450 --> 02:05.000
hello
''');
      expect(cues.single.startMs, 123450);
      expect(cues.single.endMs, 125000);
    });

    test('时长省略零小时', () {
      expect(
        Srt.formatDuration(const Duration(minutes: 48, seconds: 12)),
        '48:12',
      );
      expect(
        Srt.formatDuration(const Duration(hours: 1, minutes: 32, seconds: 5)),
        '1:32:05',
      );
    });
  });

  group('说话人标签', () {
    const cues = [
      Cue(
        index: 1,
        startMs: 0,
        endMs: 1000,
        source: '你好',
        translation: 'Hi',
        speaker: 0,
      ),
      Cue(
        index: 2,
        startMs: 1000,
        endMs: 2000,
        source: '你好',
        translation: 'Hi',
        speaker: 1,
      ),
      Cue(
        index: 3,
        startMs: 2000,
        endMs: 3000,
        source: '再见',
        translation: 'Bye',
      ),
    ];
    String label(int n) => '说话人${n + 1}：';

    test('传了标签函数才写，没说话人的条目不写', () {
      final srt = Srt.serialize(cues, speakerLabel: label);
      expect(srt, contains('说话人1：你好'));
      expect(srt, contains('说话人2：你好'));
      expect(srt, contains('\n再见\n'));
      expect(Srt.serialize(cues), isNot(contains('说话人')));
    });

    test('双语只在第一行加标签', () {
      final text = Srt.textOf(
        cues.first,
        SrtField.bilingualTargetAbove,
        speakerLabel: label,
      );
      expect(text, '说话人1：Hi\n你好');
    });

    test('VTT 与纯文本同样带标签', () {
      expect(Srt.serializeVtt(cues, speakerLabel: label), contains('说话人2：你好'));
      expect(
        Srt.serializePlain(
          cues,
          field: SrtField.translation,
          speakerLabel: label,
        ),
        '说话人1：Hi\n说话人2：Hi\nBye\n',
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
      expect(
        Srt.parse(Srt.serialize(cues)).map((c) => c.source),
        cues.map((c) => c.source),
      );
    });

    test('译文缺失的条目被跳过并重新编号', () {
      final cues = [
        const Cue(
          index: 1,
          startMs: 0,
          endMs: 1000,
          source: 'a',
          translation: 'A',
        ),
        const Cue(index: 2, startMs: 1000, endMs: 2000, source: 'b'),
        const Cue(
          index: 3,
          startMs: 2000,
          endMs: 3000,
          source: 'c',
          translation: 'C',
        ),
      ];
      final out = Srt.parse(Srt.serialize(cues, field: SrtField.translation));
      expect(out.map((c) => c.source), ['A', 'C']);
      expect(out.map((c) => c.index), [1, 2]);
    });

    test('双语两种排版分别把译文放在上下', () {
      final cues = [
        const Cue(
          index: 1,
          startMs: 0,
          endMs: 1000,
          source: '原',
          translation: '译',
        ),
      ];
      expect(
        Srt.serialize(cues, field: SrtField.bilingualTargetAbove),
        contains('译\n原'),
      );
      expect(
        Srt.serialize(cues, field: SrtField.bilingualTargetBelow),
        contains('原\n译'),
      );
    });

    test('双语遇到缺译文的条目只写原文，不留空行', () {
      final cues = [const Cue(index: 1, startMs: 0, endMs: 1000, source: '原')];
      for (final field in [
        SrtField.bilingualTargetAbove,
        SrtField.bilingualTargetBelow,
      ]) {
        final out = Srt.serialize(cues, field: field);
        expect(Srt.parse(out).single.source, '原', reason: '$field');
        expect(out, isNot(contains('\n\n\n')), reason: '$field');
      }
    });

    test('双语两行各按自己的语言折行', () {
      final cues = [
        const Cue(
          index: 1,
          startMs: 0,
          endMs: 1000,
          source: '这是一句相当长的中文原文需要折行处理',
          translation: 'this is a fairly long english translation line',
        ),
      ];
      final out = Srt.serialize(
        cues,
        field: SrtField.bilingualTargetBelow,
        wrapSource: (t) => LineWrap.wrap(t, limit: 8, cjk: true),
        wrapTranslation: (t) => LineWrap.wrap(t, limit: 40, cjk: false),
      );
      final body = Srt.parse(out).single.source.split('\n');
      // 中文按 8 字折成多行，英文 40 字以内保持一行。
      expect(body.length, greaterThan(2));
      expect(body.last, 'this is a fairly long english translation line');
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

    test('拆分会清掉无法对应的旧译文', () {
      final translated = SubtitleDocument(
        cues: [
          const Cue(
            index: 1,
            startMs: 0,
            endMs: 1000,
            source: 'abcdef',
            translation: 'translated',
            reviewed: true,
          ),
        ],
      );
      final split = translated.splitAt(0, 3);
      expect(split.cues.every((cue) => !cue.hasTranslation), isTrue);
      expect(split.cues.every((cue) => !cue.reviewed), isTrue);
    });

    test('文档时长取最晚结束时间而非列表最后一条', () {
      final document = SubtitleDocument(
        cues: [
          const Cue(index: 1, startMs: 0, endMs: 5000, source: 'late'),
          const Cue(index: 2, startMs: 0, endMs: 1000, source: 'early'),
        ],
      );
      expect(document.duration, const Duration(seconds: 5));
    });
  });

  group('校对状态', () {
    test('没有译文即未翻译', () {
      const cue = Cue(index: 1, startMs: 0, endMs: 1, source: 'a');
      expect(cue.state, CueState.untranslated);
    });

    test('低置信度标为待校对', () {
      const cue = Cue(
        index: 1,
        startMs: 0,
        endMs: 1,
        source: 'a',
        translation: 'A',
        confidence: 0.58,
      );
      expect(cue.state, CueState.review);
    });

    test('人工确认后不再是待校对', () {
      const cue = Cue(
        index: 1,
        startMs: 0,
        endMs: 1,
        source: 'a',
        translation: 'A',
        confidence: 0.58,
        reviewed: true,
      );
      expect(cue.state, CueState.ok);
    });
  });
}
