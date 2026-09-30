import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/core/widgets/indicators.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/tasks/stage_bar.dart';

import 'helpers.dart';

/// 进度条的填充块：进度条里唯一带渐变的 DecoratedBox。
Size _fillSize(WidgetTester tester, Finder bar) {
  final fill = find.descendant(
    of: bar,
    matching: find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null,
    ),
  );
  return tester.getSize(fill);
}

Widget _host(Widget child) => MaterialApp(
  theme: lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  // Align 会放松子节点的高度约束，填充块曾经因此缩成 0 高：
  // 进度数字在涨，条却一直是空的。
  testWidgets('GradientProgressBar 的填充有高度、宽度跟着进度走', (tester) async {
    await tester.pumpWidget(
      _host(const GradientProgressBar(value: 0.5, width: 100)),
    );
    final size = _fillSize(tester, find.byType(GradientProgressBar));
    expect(size.height, 4);
    expect(size.width, 50);
  });

  // 夹具里只有识别段带填充，是阶段条里唯一一条 GradientProgressBar：取它的填充占比。
  Future<double> segmentFill(WidgetTester tester, SubtitleTask task) async {
    await tester.pumpWidget(
      _host(SizedBox(width: 200, child: StageBar(task: task))),
    );
    final bar = find.byType(GradientProgressBar);
    final fill = _fillSize(tester, bar);
    expect(fill.height, 4);
    return fill.width / tester.getSize(bar).width;
  }

  SubtitleTask transcribeAt(StageState current, {TaskStatus? status}) =>
      SubtitleTask(
        id: 't1',
        sourcePath: '/v/a.mp4',
        kind: TaskKind.transcribe,
        options: testOptions(),
        status: status ?? TaskStatus.running,
        stage: TaskStage.recognize,
        progress: 0.5,
        stages: {
          for (final s in TaskStage.values)
            s: StageRecord(
              state: switch (s) {
                TaskStage.queued || TaskStage.prepare => StageState.done,
                TaskStage.recognize => current,
                _ => StageState.pending,
              },
            ),
        },
      );

  testWidgets('StageBar 进行中的阶段按进度填充', (tester) async {
    final ratio = await segmentFill(tester, transcribeAt(StageState.active));
    expect(ratio, closeTo(0.5, 0.01));
  });

  testWidgets('StageBar 取消的阶段填到中断处，失败的阶段填 40%', (tester) async {
    final cancelled = await segmentFill(
      tester,
      transcribeAt(StageState.cancelled, status: TaskStatus.cancelled),
    );
    expect(cancelled, closeTo(0.5, 0.01));
    final failed = await segmentFill(
      tester,
      transcribeAt(StageState.failed, status: TaskStatus.failed),
    );
    expect(failed, closeTo(0.4, 0.01));
  });
}
