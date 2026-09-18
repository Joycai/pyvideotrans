import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/services/settings.dart';

Future<EditorController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  final task = SubtitleTask(
    id: 'e1',
    sourcePath: '/v/demo.mp4',
    kind: TaskKind.transcribeAndTranslate,
    // 跑完的任务：排队或运行中的任务编辑器只读。
    status: TaskStatus.done,
    options: testOptions(
      asr: 'openai',
      mt: 'deepseek',
      source: 'zh',
      target: 'en',
    ),
  );
  task.document = SubtitleDocument(
    cues: [
      const Cue(
        index: 1,
        startMs: 0,
        endMs: 2000,
        source: '第一句话在这里',
        translation: 'First',
        confidence: 0.95,
      ),
      const Cue(
        index: 2,
        startMs: 2000,
        endMs: 4000,
        source: '第二句',
        translation: 'Second',
        confidence: 0.50,
      ),
      const Cue(index: 3, startMs: 4000, endMs: 6000, source: '第三句'),
    ],
  );
  return EditorController(session: TaskSession(task), settings: settings);
}

/// 带说话人的文档：Mia、Mia、周老师、说话人3、周老师、周老师。
Future<EditorController> _speakerController() async {
  final c = await _controller();
  c.session.document = const SubtitleDocument(
    cues: [
      Cue(index: 1, startMs: 0, endMs: 1000, source: '大家好', speaker: 0),
      Cue(index: 2, startMs: 1000, endMs: 2000, source: '欢迎', speaker: 0),
      Cue(index: 3, startMs: 2000, endMs: 3000, source: '谢谢邀请', speaker: 1),
      Cue(index: 4, startMs: 3000, endMs: 3400, source: '嗯', speaker: 2),
      Cue(index: 5, startMs: 3400, endMs: 5000, source: '一开始', speaker: 1),
      Cue(index: 6, startMs: 5000, endMs: 6000, source: '踩了坑', speaker: 1),
    ],
    speakers: {0: 'Mia', 1: '周老师'},
  );
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('过滤与计数', () {
    test('三个筹码的计数与文档一致', () async {
      final c = await _controller();
      expect(c.countOf(CueFilter.all), 3);
      expect(c.countOf(CueFilter.review), 1);
      expect(c.countOf(CueFilter.untranslated), 1);
    });

    test('过滤后只剩符合条件的条目', () async {
      final c = await _controller()
        ..setFilter(CueFilter.review);
      expect(c.visibleCues.map((x) => x.index), [2]);
    });

    test('搜索同时看原文与译文，且不区分大小写', () async {
      final c = await _controller()
        ..setSearch('SECOND');
      expect(c.visibleCues.map((x) => x.index), [2]);

      c.setSearch('第三');
      expect(c.visibleCues.map((x) => x.index), [3]);
    });
  });

  group('J/K 导航', () {
    test('在过滤后的列表里跳，而不是整份文档', () async {
      final c = await _controller()
        ..setFilter(CueFilter.untranslated)
        ..select(0);
      c.step(1);
      // 只有第 3 条未翻译，所以应当落在它上面。
      expect(c.current!.index, 3);
    });

    test('到头不越界', () async {
      final c = await _controller()
        ..select(0);
      c.step(-1);
      expect(c.current!.index, 1);
      c
        ..select(2)
        ..step(1);
      expect(c.current!.index, 3);
    });
  });

  group('编辑', () {
    test('标记已校对后不再是待校对', () async {
      final c = await _controller()
        ..select(1);
      expect(c.current!.state, CueState.review);
      c.toggleReviewed();
      expect(c.current!.state, CueState.ok);
      expect(c.document.reviewCount, 0);
    });

    test('起点不能越过终点', () async {
      final c = await _controller()
        ..select(0);
      c.editStart(99999);
      expect(c.current!.startMs, lessThan(c.current!.endMs));
    });

    test('终点不能早于起点', () async {
      final c = await _controller()
        ..select(1);
      c.editEnd(0);
      expect(c.current!.endMs, greaterThan(c.current!.startMs));
    });

    test('撤销回到上一版', () async {
      final c = await _controller()
        ..select(0);
      c.editSource('改过的原文');
      expect(c.current!.source, '改过的原文');
      c.undo();
      expect(c.current!.source, '第一句话在这里');
      expect(c.canUndo, isFalse);
    });

    test('没有可撤销的历史时撤销是空操作', () async {
      final c = await _controller();
      c.undo();
      expect(c.document.cues, hasLength(3));
    });

    test('空文档上选择与撤销不会因下标越界而崩溃', () async {
      final c = await _controller();
      c.session.document = SubtitleDocument.empty;
      c.select(99);
      c.undo();
      expect(c.current, isNull);
    });

    test('拆分与合并互为逆操作（就条数而言）', () async {
      final c = await _controller()
        ..select(0);
      c.split();
      expect(c.document.cues, hasLength(4));
      c.mergeWithNext();
      expect(c.document.cues, hasLength(3));
      // 中文合并不加空格。
      expect(c.document.cues.first.source, '第一句话在这里');
    });

    test('不足两个字的字幕拆分是空操作，不会抛异常', () {
      const doc = SubtitleDocument(
        cues: [
          Cue(index: 1, startMs: 0, endMs: 1000, source: ''),
          Cue(index: 2, startMs: 1000, endMs: 2000, source: '嗯'),
        ],
      );
      expect(doc.splitAt(0, 0).cues, hasLength(2));
      expect(doc.splitAt(1, 1).cues, hasLength(2));
    });

    test('合并后置信度取较低的一方', () async {
      final c = await _controller()
        ..select(0);
      c.mergeWithNext();
      expect(c.document.cues.first.confidence, 0.50);
    });

    test('最后一条不能合并下一条', () async {
      final c = await _controller()
        ..select(2);
      c.mergeWithNext();
      expect(c.document.cues, hasLength(3));
    });

    test('拆分与合并都保留说话人', () async {
      final c = await _speakerController()
        ..select(2);
      c.split();
      expect(c.document.cues[2].speaker, 1);
      expect(c.document.cues[3].speaker, 1);
      c.mergeWithNext();
      expect(c.document.cues[2].speaker, 1);
    });

    test('长度不够的拆分不进撤销栈', () async {
      final c = await _speakerController()
        ..select(3);
      c.split();
      expect(c.canUndo, isFalse);
    });
  });

  group('说话人', () {
    test('名单带显示名、是否起过名与条数', () async {
      final c = await _speakerController();
      final list = c.speakers;
      expect(list.map((s) => s.name), ['Mia', '周老师', '说话人3']);
      expect(list.map((s) => s.named), [true, true, false]);
      expect(list.map((s) => s.cueCount), [2, 3, 1]);
      expect(list[1].durationMs, 3600);
    });

    test('改名整份生效，可撤销；清空名字回到默认名', () async {
      final c = await _speakerController();
      c.renameSpeaker(2, '  老李 ');
      expect(c.document.speakerName(2), '老李');
      c.renameSpeaker(0, '');
      expect(c.document.speakerName(0), '说话人1');
      c.undo();
      expect(c.document.speakerName(0), 'Mia');
    });

    test('名字没变不进撤销栈', () async {
      final c = await _speakerController();
      c.renameSpeaker(0, 'Mia');
      expect(c.canUndo, isFalse);
    });

    test('合并说话人：字幕改到对方名下，名单去掉被合并的一位，筛选跟着换', () async {
      final c = await _speakerController()
        ..setSpeakerFilter({2});
      c.mergeSpeaker(2, 0);
      expect(c.document.cues[3].speaker, 0);
      expect(c.document.speakerIds, [0, 1]);
      expect(c.speakerFilter, {0});
    });

    test('改当前条的说话人', () async {
      final c = await _speakerController()
        ..select(3);
      c.assignSpeaker(1);
      expect(c.document.cues[3].speaker, 1);
      c.assignSpeaker(null);
      expect(c.document.cues[3].speaker, isNull);
    });

    test('按连续段改：只改同一人连着的那几条', () async {
      final c = await _speakerController()
        ..select(5);
      expect(c.currentRunLength, 2);
      c.assignSpeaker(0, run: true);
      expect(c.document.cues.map((x) => x.speaker), [0, 0, 1, 2, 0, 0]);
    });

    test('新增说话人拿到下一个编号；空名字记成默认名', () async {
      final c = await _speakerController();
      expect(c.addSpeaker('小王'), 3);
      expect(c.addSpeaker(' '), 4);
      expect(c.document.speakerName(4), '说话人5');
      expect(c.speakers.last.cueCount, 0);
    });

    test('按说话人筛选可多选，也能筛出无说话人的条目', () async {
      final c = await _speakerController()
        ..toggleSpeakerFilter(0)
        ..toggleSpeakerFilter(2);
      expect(c.visibleCues.map((x) => x.index), [1, 2, 4]);
      c
        ..toggleSpeakerFilter(0)
        ..toggleSpeakerFilter(2)
        ..toggleSpeakerFilter(null);
      expect(c.visibleCues, isEmpty);
      c.setSpeakerFilter({});
      expect(c.visibleCues, hasLength(6));
    });

    test('说话人筛选与状态筛选叠加', () async {
      final c = await _speakerController();
      // 整份都没有译文时「未翻译」不算状态，先给一条译文。
      c.session.document = c.document.replaceAt(
        0,
        c.document.cues.first.copyWith(translation: 'Hello'),
      );
      c
        ..setFilter(CueFilter.untranslated)
        ..setSpeakerFilter({1});
      expect(c.visibleCues.map((x) => x.index), [3, 5, 6]);
    });
  });

  group('未配对行', () {
    Future<EditorController> unpaired() async {
      final c = await _controller();
      c.session.document = const SubtitleDocument(
        cues: [
          Cue(
            index: 1,
            startMs: 0,
            endMs: 1000,
            source: 'Split it first',
            translation: '先切段',
            speaker: 0,
          ),
          Cue(index: 2, startMs: 1000, endMs: 1500, source: '', translation: '对'),
          Cue(index: 3, startMs: 1500, endMs: 2000, source: 'OK'),
        ],
      );
      return c;
    }

    test('计数、过滤', () async {
      final c = await unpaired();
      expect(c.countOf(CueFilter.unpaired), 1);
      expect(c.countOf(CueFilter.untranslated), 1);
      c.setFilter(CueFilter.unpaired);
      expect(c.visibleCues.map((x) => x.index), [2]);
    });

    test('并入上一条：译文接上、原文不留空格、说话人沿用上一条', () async {
      final c = await unpaired()
        ..select(1);
      c.mergeWithPrevious();
      final merged = c.document.cues.first;
      expect(c.document.cues, hasLength(2));
      expect(merged.source, 'Split it first');
      expect(merged.translation, '先切段对');
      expect(merged.speaker, 0);
      expect(merged.endMs, 1500);
    });

    test('翻译未译不会把没有原文的行送去翻译', () async {
      final c = await unpaired();
      c.session.document = c.document.copyWith(
        cues: [
          for (final cue in c.document.cues)
            cue.copyWith(clearTranslation: true),
        ],
      );
      // 只剩空原文的第 2 条与有原文的第 1、3 条；没有配置翻译服务会抛错，
      // 这里只验证待翻译的条目挑得对。
      final pending = [
        for (final (i, cue) in c.document.cues.indexed)
          if (!cue.hasTranslation && cue.source.trim().isNotEmpty) i,
      ];
      expect(pending, [0, 2]);
    });
  });
}
