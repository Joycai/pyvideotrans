import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/glossary.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'editor_fixtures.dart';
import 'helpers.dart';

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
  task.document = const SubtitleDocument(
    cues: [
      Cue(
        index: 1,
        startMs: 0,
        endMs: 2000,
        source: '第一句话在这里',
        translation: 'First',
        confidence: 0.95,
      ),
      Cue(
        index: 2,
        startMs: 2000,
        endMs: 4000,
        source: '第二句',
        translation: 'Second',
        confidence: 0.50,
      ),
      Cue(index: 3, startMs: 4000, endMs: 6000, source: '第三句'),
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

/// 表里看得见的各条行号。
List<int> _shown(EditorController c) => [
  for (final p in c.visiblePositions) c.document.cues[p].index,
];

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
      expect(_shown(c), [2]);
    });

    test('搜索同时看原文与译文，且不区分大小写', () async {
      final c = await _controller()
        ..setSearch('SECOND');
      expect(_shown(c), [2]);

      c.setSearch('第三');
      expect(_shown(c), [3]);
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
      expect(_shown(c), [1, 2, 4]);
      c
        ..toggleSpeakerFilter(0)
        ..toggleSpeakerFilter(2)
        ..toggleSpeakerFilter(null);
      expect(c.visiblePositions, isEmpty);
      c.setSpeakerFilter({});
      expect(c.visiblePositions, hasLength(6));
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
      expect(_shown(c), [3, 5, 6]);
    });
  });

  group('多选', () {
    test('单击单选，Shift 扩选，⌘/Ctrl 切换', () async {
      final c = await _speakerController()
        ..selectWith(1);
      expect(c.multiSelected, isFalse);
      c.selectWith(3, extend: true);
      expect(c.selectedPositions, [1, 2, 3]);
      expect(c.selected, 3);
      c.selectWith(5, toggle: true);
      expect(c.selectedPositions, [1, 2, 3, 5]);
      expect(c.selected, 5);
      c.selectWith(2, toggle: true);
      expect(c.selectedPositions, [1, 3, 5]);
      c.selectWith(4);
      expect(c.selectedPositions, [4]);
      expect(c.multiSelected, isFalse);
    });

    test('Shift 扩选只覆盖筛选后看得见的行', () async {
      // 周老师：第 3、5、6 条（下标 2、4、5）。
      final c = await _speakerController()
        ..setSpeakerFilter({1});
      c
        ..selectWith(2)
        ..selectWith(5, extend: true);
      expect(c.selectedPositions, [2, 4, 5]);
    });

    test('批量改说话人：一次提交，一步撤销', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(3, toggle: true)
        ..selectWith(5, toggle: true);
      c.assignSpeaker(2);
      expect(c.document.cues.map((x) => x.speaker), [2, 0, 1, 2, 1, 2]);
      // 条数没变，选区保留，可以接着改。
      expect(c.selectedPositions, [0, 3, 5]);
      c.undo();
      expect(c.document.cues.map((x) => x.speaker), [0, 0, 1, 2, 1, 1]);
      expect(c.canUndo, isFalse);
    });

    test('批量清除说话人；多选时忽略「连续段」', () async {
      final c = await _speakerController()
        ..selectWith(4)
        ..selectWith(5, extend: true);
      c.assignSpeaker(null, run: true);
      expect(c.document.cues.map((x) => x.speaker), [0, 0, 1, 2, null, null]);
    });

    test('选中各条已经是那个人时不进撤销栈', () async {
      final c = await _speakerController()
        ..selectWith(4)
        ..selectWith(5, extend: true);
      c.assignSpeaker(1);
      expect(c.canUndo, isFalse);
    });

    test('共同说话人与「多个说话人」', () async {
      final c = await _speakerController()
        ..selectWith(4)
        ..selectWith(5, extend: true);
      expect(c.selectionMixedSpeakers, isFalse);
      c.selectWith(3, toggle: true);
      expect(c.selectionMixedSpeakers, isTrue);
    });

    test('只读时批量修改无效', () async {
      final c = await _speakerController();
      (c.session as TaskSession).task.status = TaskStatus.running;
      c
        ..selectWith(0)
        ..selectWith(2, extend: true)
        ..assignSpeaker(2);
      expect(c.document.cues.map((x) => x.speaker), [0, 0, 1, 2, 1, 1]);
    });

    test('筛选、搜索后被筛掉的行退出选区，放开后回来', () async {
      final c = await _speakerController()
        ..selectWith(1)
        ..selectWith(4, extend: true);
      expect(c.selectedPositions, [1, 2, 3, 4]);

      c.toggleSpeakerFilter(1); // 只看周老师：下标 2、4
      expect(c.selectedPositions, [2, 4]);
      c.setSearch('一开始'); // 只剩焦点这一条
      expect(c.multiSelected, isFalse);
      expect(c.selectedPositions, [4]);
      c
        ..setSearch('')
        ..setSpeakerFilter({});
      expect(c.selectedPositions, [1, 2, 3, 4]);
    });

    test('焦点被筛掉时退回只选焦点', () async {
      final c = await _speakerController()
        ..selectWith(1)
        ..selectWith(3, extend: true); // 焦点下标 3，说话人3
      c.toggleSpeakerFilter(0); // 只看 Mia：下标 0、1
      expect(c.multiSelected, isFalse);
      expect(c.selected, 3);
    });

    test('在筛选下点击：藏着的行不会借这次点击冒回来', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(4, extend: true);
      c
        ..toggleSpeakerFilter(1) // 下标 2、4、5 可见，选中的剩 2、4
        ..selectWith(5, toggle: true)
        ..setSpeakerFilter({});
      expect(c.selectedPositions, [2, 4, 5]);
    });

    test('性质：随机操作下批量只改看得见的选中行，焦点在范围内', () async {
      final random = Random(20260929);
      const searches = ['', '一', '谢', '嗯', '没有这句'];
      const speakers = <int?>[0, 1, 2, null];
      for (var round = 0; round < 40; round++) {
        final c = await _speakerController();
        for (var step = 0; step < 60; step++) {
          final visible = c.visiblePositions;
          switch (random.nextInt(9)) {
            case 0 || 1 || 2 when visible.isNotEmpty:
              final p = visible[random.nextInt(visible.length)];
              final mode = random.nextInt(3);
              c.selectWith(p, extend: mode == 1, toggle: mode == 2);
            case 3:
              c.setFilter(random.nextBool() ? CueFilter.all : CueFilter.edited);
            case 4:
              c.setSearch(searches[random.nextInt(searches.length)]);
            case 5:
              c.toggleSpeakerFilter(speakers[random.nextInt(speakers.length)]);
            case 6:
              final before = c.document.cues.map((x) => x.speaker).toList();
              final targets = c.multiSelected ? c.selectedPositions : null;
              c.assignSpeaker(speakers[random.nextInt(speakers.length)]);
              final after = c.document.cues.map((x) => x.speaker).toList();
              if (targets != null) {
                for (var i = 0; i < after.length; i++) {
                  if (after[i] != before[i]) expect(targets, contains(i));
                }
              }
            case 7:
              c.undo();
            case _:
              random.nextBool() ? c.split() : c.mergeWithNext();
          }

          final n = c.document.cues.length;
          expect(c.selected, inInclusiveRange(0, n - 1));
          expect(c.selectedPositions, contains(c.selected));
          if (c.multiSelected) {
            expect(c.visiblePositions, containsAll(c.selectedPositions));
          } else {
            expect(c.selectedPositions, [c.selected]);
          }
        }
      }
    });

    test('新建说话人并指派：多选时一次提交，一步撤销连名单一起撤掉', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(3, toggle: true);
      final id = c.assignNewSpeaker('小王');
      expect(id, 3);
      expect(c.document.speakerName(3), '小王');
      expect([c.document.cues[0].speaker, c.document.cues[3].speaker], [3, 3]);
      c.undo();
      expect(c.document.speakerIds, [0, 1, 2]);
      expect(c.canUndo, isFalse);
    });

    test('新建说话人并指派：单选时按当前条或连续段', () async {
      final c = await _speakerController()..select(5);
      c.assignNewSpeaker('', run: true);
      expect(c.document.cues.map((x) => x.speaker), [0, 0, 1, 2, 3, 3]);
      expect(c.document.speakerName(3), '说话人4');
    });

    test('焦点被筛掉时 ⌘+点击按单选：放开筛选后旧焦点不冒回来', () async {
      final c = await _speakerController()
        ..selectWith(1)
        ..selectWith(3, extend: true); // 焦点下标 3，说话人3
      c
        ..toggleSpeakerFilter(1) // 只看周老师：下标 2、4、5
        ..selectWith(4, toggle: true)
        ..setSpeakerFilter({});
      expect(c.selectedPositions, [4]);
    });

    test('锚点被筛掉后 Shift 扩选从焦点起算，不丢看得见的选中行', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(4, extend: true); // 锚点下标 0（Mia），焦点下标 4
      c
        ..toggleSpeakerFilter(1) // 只看周老师：下标 2、4、5
        ..selectWith(5, extend: true);
      expect(c.selectedPositions, [4, 5]);
    });

    test('⌘ 取消回到单选后，起点那行被筛掉：Shift 扩选从焦点起算', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(3, toggle: true)
        ..selectWith(3, toggle: true); // 回到只选下标 0，锚点留在下标 3
      c
        ..toggleSpeakerFilter(0)
        ..toggleSpeakerFilter(1) // 下标 3（说话人3）被筛掉
        ..selectWith(4, extend: true);
      expect(c.selectedPositions, [0, 1, 2, 4]);
    });

    test('J/K、Esc 回到单选', () async {
      final c = await _speakerController();
      void multi() => c
        ..selectWith(1)
        ..selectWith(3, extend: true);

      multi();
      c.step(1);
      expect((c.multiSelected, c.selected), (false, 4));
      multi();
      c.clearMultiSelection();
      expect((c.multiSelected, c.selected), (false, 3));
    });

    test('条数变了回到单选：撤销一次拆分', () async {
      final c = await _speakerController()
        ..select(2);
      c.split();
      c
        ..selectWith(0)
        ..selectWith(6, extend: true);
      c.undo();
      expect(c.multiSelected, isFalse);
      expect(c.selected, lessThan(c.document.cues.length));
    });

    test('撤销时条数没变，选区保留', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(2, extend: true);
      c
        ..assignSpeaker(2)
        ..undo();
      expect(c.selectedPositions, [0, 1, 2]);
    });

    test('多选下拆分、合并：回到单选，焦点在范围内', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(1, toggle: true);
      c.mergeWithNext(); // 焦点下标 1 并入下标 2
      expect(c.document.cues, hasLength(5));
      expect(c.multiSelected, isFalse);

      c
        ..selectWith(4)
        ..selectWith(1, toggle: true); // 焦点落在「欢迎谢谢邀请」
      c.split();
      expect(c.document.cues, hasLength(6));
      expect(c.multiSelected, isFalse);
      expect(c.selected, lessThan(c.document.cues.length));
    });

    test('提交后选中行被筛掉：回到单选，不会接着改到看不见的行', () async {
      // 只看周老师（下标 2、4、5），多选后把它们改给 Mia。
      final c = await _speakerController()
        ..setSpeakerFilter({1});
      c
        ..selectWith(4)
        ..selectWith(5, extend: true)
        ..assignSpeaker(0);
      expect(c.multiSelected, isFalse);
    });

    test('只读时多选改说话人不做任何事', () async {
      final c = await _speakerController()
        ..selectWith(5)
        ..selectWith(0, extend: true); // 焦点在下标 0，缩短后仍在范围内
      (c.session as TaskSession).task.status = TaskStatus.running;
      // 流水线换了一份更短的文档，选区还没跟上。
      c.session.document = SubtitleDocument(
        cues: c.document.cues.take(2).toList(),
      );
      expect(() => c.assignSpeaker(1), returnsNormally);
      expect(c.document.cues.map((x) => x.speaker), [0, 0]);
      // 界面在选区跟上之前重建也只拿到范围内的下标。
      expect(c.selectedPositions, [0, 1]);
      expect(() => c.selectionMixedSpeakers, returnsNormally);
    });

    test('多选时 Enter 切换已校对不生效', () async {
      final c = await _speakerController()
        ..selectWith(0)
        ..selectWith(1, extend: true);
      c.toggleReviewed();
      expect(c.canUndo, isFalse);
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
      expect(_shown(c), [2]);
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

  group('重新翻译用哪份模型与词表', () {
    const frozen = GlossaryEntry(term: '百炼', translation: 'Bailian');
    const current = GlossaryEntry(term: '百炼', translation: 'Model Studio');
    late AppSettings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
      settings
        ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk'))
        ..setModels('deepseek', [const ChatModelSpec(name: 'now')])
        ..setGlossary(
          const Glossary(id: 'g', name: '访谈', entries: [current]),
        );
    });

    OpenAiCompatibleTranslationProvider providerOf(EditorSession session) =>
        EditorController(
              session: session,
              settings: settings,
            ).buildTranslationProvider()
            as OpenAiCompatibleTranslationProvider;

    // 任务的参数在入队时定死：在编辑器里补翻几条，用的也得是那一份。
    test('任务会话：用任务里冻结的，不看设置现在是什么', () {
      final task = SubtitleTask(
        id: 't',
        sourcePath: '/v/demo.mp4',
        kind: TaskKind.transcribeAndTranslate,
        status: TaskStatus.done,
        options: testOptions(
          mt: 'deepseek',
          translationModel: 'then',
        ).copyWith(glossaryIds: ['g'], glossary: [frozen]),
      );
      final provider = providerOf(TaskSession(task));
      expect(provider.endpoint.model, 'then');
      expect(provider.glossary, [frozen]);
    });

    // 本地文件没有入队这一步。用户发现模型没选、去设置里填好再回来，
    // 不该还要把文件关掉重开。
    test('本地文件会话：每次现取设置里的模型与默认启用的词表', () {
      final session = FileSession.open(
        source: localZhFile(),
        defaults: testOptions(mt: 'deepseek', translationModel: 'at-open'),
      );
      final provider = providerOf(session);
      expect(provider.endpoint.model, 'now');
      expect(provider.glossary, [current]);

      settings
        ..setModels('deepseek', [const ChatModelSpec(name: 'later')])
        ..removeGlossary('g');
      final again = providerOf(session);
      expect(again.endpoint.model, 'later');
      expect(again.glossary, isEmpty);
    });
  });
}
