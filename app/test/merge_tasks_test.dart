import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_filter.dart';
import 'package:subtitle_studio/features/tasks/task_table.dart';
import 'package:subtitle_studio/features/tasks/tasks_board.dart';
import 'package:subtitle_studio/services/reveal.dart';

import 'merge_task_fixtures.dart';

void main() {
  Future<List<(SubtitleTask, TaskAction)>> pumpBoard(
    WidgetTester tester, {
    required List<SubtitleTask> tasks,
    required String selectedId,
  }) async {
    final actions = <(SubtitleTask, TaskAction)>[];
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: TasksBoard(
            tasks: tasks,
            filter: TaskFilter.all,
            counts: const {},
            selectedId: selectedId,
            onFilterChanged: (_) {},
            onSelect: (_) {},
            onAction: (t, a) => actions.add((t, a)),
            onFiles: (_) {},
            onBrowse: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    return actions;
  }

  testWidgets('进行中：服务列「3 段 · 无转码」、阶段带倍速、详情有章节与起点', (tester) async {
    await pumpBoard(tester, tasks: [mergeRunning()], selectedId: 'mg1');
    expect(find.text('3 段 · 无转码'), findsOneWidget);
    expect(find.text('-c copy · 3 个章节'), findsOneWidget);
    expect(find.text('合并 · 38.0x'), findsOneWidget);
    expect(find.textContaining('3 段 → MP4'), findsWidgets);
    // 详情：标签、章节分区的起点与字幕条数、产物还在生成。
    expect(find.text('无转码 · stream copy'), findsOneWidget);
    expect(find.text('3 个章节'), findsOneWidget);
    expect(find.text('字幕内嵌'), findsOneWidget);
    expect(find.text('章节'), findsOneWidget);
    expect(find.text('00:32:10'), findsOneWidget);
    expect(find.text('00:56:46'), findsOneWidget);
    expect(find.text('字幕 402 条'), findsOneWidget);
    expect(find.text('无字幕'), findsOneWidget);
    expect(find.text('合并中 · 62%'), findsOneWidget);
    expect(find.text('打开编辑器'), findsNothing);
  });

  testWidgets('完成：在访达中显示产物，旁挂 SRT 一行，说明字幕去向', (tester) async {
    final actions = await pumpBoard(
      tester,
      tasks: [mergeDone()],
      selectedId: 'mg2',
    );
    expect(find.text('interview_ep12_part1.merged.mp4'), findsWidgets);
    expect(find.text('interview_ep12_part1.merged.srt'), findsOneWidget);
    expect(find.text('字幕内嵌并旁挂'), findsOneWidget);
    expect(find.text('字幕作为软字幕轨写进视频，并在旁边另存一份 SRT（713 条）'), findsOneWidget);
    await tester.tap(find.text(Reveal.label).first);
    expect(actions.single.$2, TaskAction.reveal);
  });

  testWidgets('准备失败、关了章节：分区叫「分段」，起点未知写「—」', (tester) async {
    await pumpBoard(tester, tasks: [mergeFailed()], selectedId: 'mg3');
    expect(find.text('第 2 段的文件找不到了'), findsWidgets);
    expect(find.text('分段'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('lecture_week3_a.mp4 等 2 段'), findsWidgets);
    expect(find.text('2 个章节'), findsNothing);
  });
}
