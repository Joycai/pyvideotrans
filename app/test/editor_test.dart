import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/services/settings.dart';

Future<EditorController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  final task = SubtitleTask(
    id: 'e1',
    sourcePath: '/v/demo.mp4',
    kind: TaskKind.transcribeAndTranslate,
    asrProviderId: 'openai',
    translationProviderId: 'deepseek',
    sourceLanguage: '中文',
    targetLanguage: '英文',
  );
  task.document = SubtitleDocument(
    cues: [
      const Cue(
        index: 1, startMs: 0, endMs: 2000,
        source: '第一句话在这里', translation: 'First', confidence: 0.95,
      ),
      const Cue(
        index: 2, startMs: 2000, endMs: 4000,
        source: '第二句', translation: 'Second', confidence: 0.50,
      ),
      const Cue(index: 3, startMs: 4000, endMs: 6000, source: '第三句'),
    ],
  );
  return EditorController(task: task, settings: settings);
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
      final c = await _controller()..select(0);
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
      final c = await _controller()..select(1);
      expect(c.current!.state, CueState.review);
      c.toggleReviewed();
      expect(c.current!.state, CueState.ok);
      expect(c.document.reviewCount, 0);
    });

    test('起点不能越过终点', () async {
      final c = await _controller()..select(0);
      c.editStart(99999);
      expect(c.current!.startMs, lessThan(c.current!.endMs));
    });

    test('终点不能早于起点', () async {
      final c = await _controller()..select(1);
      c.editEnd(0);
      expect(c.current!.endMs, greaterThan(c.current!.startMs));
    });

    test('撤销回到上一版', () async {
      final c = await _controller()..select(0);
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

    test('拆分与合并互为逆操作（就条数而言）', () async {
      final c = await _controller()..select(0);
      c.split();
      expect(c.document.cues, hasLength(4));
      c.mergeWithNext();
      expect(c.document.cues, hasLength(3));
      // 中文合并不加空格。
      expect(c.document.cues.first.source, '第一句话在这里');
    });

    test('最后一条不能合并下一条', () async {
      final c = await _controller()..select(2);
      c.mergeWithNext();
      expect(c.document.cues, hasLength(3));
    });
  });
}
