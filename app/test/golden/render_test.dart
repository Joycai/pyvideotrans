@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/editor/editor_controller.dart';
import 'package:subtitle_studio/features/editor/editor_open_form.dart';
import 'package:subtitle_studio/features/editor/editor_open_page.dart';
import 'package:subtitle_studio/features/editor/editor_page.dart';
import 'package:subtitle_studio/features/editor/editor_page_actions.dart';
import 'package:subtitle_studio/features/editor/editor_title.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/editor_widgets.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/page_chrome.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/features/tasks/tasks_board.dart';
import 'package:subtitle_studio/features/tasks/tasks_page.dart';
import 'package:subtitle_studio/services/editor_store.dart';
import 'package:subtitle_studio/services/settings.dart';

import '../editor_fixtures.dart';
import '../helpers.dart';

/// 渲染全窗口截图，用来核对实现与设计稿是否一致。
///
/// 重新生成：flutter test --tags golden --run-skipped --update-goldens
/// 测试默认字体不含汉字（会渲染成方框），这里加载系统 CJK 字体让截图可读。
Future<void> _loadCjkFont() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/STHeiti Light.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync().buffer.asByteData();
    // 家族名必须和 AppFonts 里的回退名完全一致，否则不会被选中。
    for (final family in ['Noto Sans SC', 'JetBrains Mono']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    return;
  }
}

/// 造一批覆盖各种状态的任务：进行中、已完成、失败、排队、已取消。
List<SubtitleTask> _fixtures() {
  SubtitleTask make({
    required String id,
    required String path,
    required TaskKind kind,
    required TaskStatus status,
    required TaskStage stage,
    double progress = 0,
    Map<TaskStage, StageState> states = const {},
    SubtitleDocument document = SubtitleDocument.empty,
    TaskError? error,
    Duration? media,
    Duration? eta,
  }) {
    final task = SubtitleTask(
      id: id,
      sourcePath: path,
      kind: kind,
      options: testOptions(asr: 'openai', mt: 'deepseek', source: 'zh', target: 'en'),
      status: status,
      stage: stage,
      progress: progress,
      document: document,
      mediaDuration: media,
      eta: eta,
      // 钉死入队时间。不给的话构造函数取 DateTime.now()，编辑器入口页把它
      // 渲染成「今天 / 昨天 / 9月16日」，截图就会每天自己对不上。
      createdAt: DateTime(2026, 9, 13, 14, 2),
    );
    task.error = error;
    for (final entry in states.entries) {
      task.stages[entry.key] = StageRecord(
        state: entry.value,
        duration: entry.value == StageState.done
            ? const Duration(seconds: 21)
            : null,
        note: switch (entry.value) {
          StageState.skipped => '未选择翻译',
          StageState.active => '第 809 / 1,284 条',
          _ => null,
        },
      );
    }
    task.log
      ..add(LogEntry(DateTime(2026, 1, 1, 14, 2, 11), LogLevel.info, '任务开始，源 48:12'))
      ..add(
        LogEntry(
          DateTime(2026, 1, 1, 14, 2, 32),
          LogLevel.info,
          '识别完成 1,284 段，平均置信度 0.91',
        ),
      )
      ..add(
        LogEntry(
          DateTime(2026, 1, 1, 14, 14, 24),
          LogLevel.warn,
          '3 段置信度 < 0.65，已标记待校对',
        ),
      );
    return task;
  }

  final translated = SubtitleDocument(
    cues: [
      for (var i = 1; i <= 92; i++)
        Cue(
          index: i,
          startMs: i * 2000,
          endMs: i * 2000 + 1800,
          source: '第 $i 句原文',
          translation: 'Line $i',
          confidence: i % 30 == 0 ? 0.55 : 0.95,
        ),
    ],
  );

  return [
    make(
      id: '1',
      path: '/v/interview_ep12.mp4',
      kind: TaskKind.transcribeAndTranslate,
      status: TaskStatus.running,
      stage: TaskStage.translate,
      progress: 0.63,
      media: const Duration(minutes: 48, seconds: 12),
      eta: const Duration(minutes: 4),
      document: translated,
      states: {
        TaskStage.queued: StageState.done,
        TaskStage.prepare: StageState.done,
        TaskStage.recognize: StageState.done,
        TaskStage.segment: StageState.done,
        TaskStage.translate: StageState.active,
      },
    ),
    make(
      id: '2',
      path: '/v/product_demo_en.mov',
      kind: TaskKind.transcribe,
      status: TaskStatus.done,
      stage: TaskStage.finish,
      progress: 1,
      media: const Duration(minutes: 6, seconds: 40),
      document: translated,
      states: {
        TaskStage.queued: StageState.done,
        TaskStage.prepare: StageState.done,
        TaskStage.recognize: StageState.done,
        TaskStage.segment: StageState.done,
        TaskStage.translate: StageState.skipped,
        TaskStage.finish: StageState.done,
      },
    ),
    make(
      id: '3',
      path: '/v/lecture_week3.m4a',
      kind: TaskKind.transcribe,
      status: TaskStatus.failed,
      stage: TaskStage.prepare,
      media: const Duration(hours: 1, minutes: 32, seconds: 5),
      states: {
        TaskStage.queued: StageState.done,
        TaskStage.prepare: StageState.failed,
      },
      error: const TaskError(
        title: '找不到 ffmpeg',
        detail: '已查找：应用目录/ffmpeg、/opt/homebrew/bin、/usr/local/bin、PATH',
        hint: 'macOS 执行 brew install ffmpeg；Windows 把 ffmpeg.exe 放到应用目录。',
      ),
    ),
    make(
      id: '4',
      path: '/v/vlog_tokyo_ja.srt',
      kind: TaskKind.translate,
      status: TaskStatus.queued,
      stage: TaskStage.queued,
      states: {TaskStage.queued: StageState.active},
    ),
    make(
      id: '5',
      path: '/v/podcast_s2e07.mp3',
      kind: TaskKind.transcribe,
      status: TaskStatus.cancelled,
      stage: TaskStage.recognize,
      progress: 0.31,
      media: const Duration(hours: 1, minutes: 5, seconds: 30),
      states: {
        TaskStage.queued: StageState.done,
        TaskStage.prepare: StageState.done,
        TaskStage.recognize: StageState.cancelled,
      },
    ),
  ];
}

ThemeData _readable(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Noto Sans SC'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Noto Sans SC'),
);

void main() {
  setUpAll(_loadCjkFont);

  Future<void> pumpTasks(
    WidgetTester tester, {
    required Brightness brightness,
    required String file,
  }) async {
    final tasks = _fixtures();

    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // 测试环境的默认字体把拉丁字母和数字画成方框，这里把整套文字样式
        // 都指向刚加载的真实字体，截图才读得出来。
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.tasks,
          onSectionChanged: (_) {},
          chrome: () => PageChrome(
            title: '任务',
            subtitle: '${tasks.length} 个任务 · 1 个进行中 · 1 个失败',
            actions: [
              TasksPageActions(
                onNewTranslate: () {},
                onNewTranscribe: () {},
              ),
            ],
          ),
          status: () => const StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: (connected: true, label: 'OpenAI · 已配置'),
            localBackend: (connected: true, label: 'DeepSeek · 已配置'),
            runningTasks: 2,
            overallProgress: 0.63,
            etaText: '剩余约 4 分钟',
          ),
          child: TasksBoard(
            tasks: tasks,
            filter: 'all',
            counts: const {
              'all': 5,
              'running': 2,
              'failed': 1,
              'done': 1,
            },
            // 选中失败的那条，好让详情面板把错误块也一起渲染出来。
            selectedId: '3',
            onFilterChanged: (_) {},
            onSelect: (_) {},
            onAction: (_, _) {},
            onFiles: (_) {},
            onBrowse: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('$file.png'),
    );
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Brightness brightness,
    required String file,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final task = _fixtures().first;
    final controller = EditorController(
      session: TaskSession(task),
      settings: settings,
    )..select(4);

    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.editor,
          onSectionChanged: (_) {},
          chrome: () => PageChrome(
            title: '编辑器',
            subtitle:
                '${task.fileName} · ${task.document.cues.length} 条 · 中文 → 英文',
            titleTrailing: EditorReviewBadge(
              count: task.document.reviewCount,
            ),
            actions: [
              EditorPageActions(
                controller: controller,
                onTranslateMissing: () {},
                onExport: () {},
              ),
            ],
          ),
          status: () => const StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: (connected: true, label: 'OpenAI · 已配置'),
            localBackend: (connected: true, label: 'DeepSeek · 已配置'),
          ),
          child: EditorPage(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
  }

  testWidgets('编辑器 · 浅色', (tester) async {
    await pumpEditor(tester, brightness: Brightness.light, file: 'editor_light');
  });

  testWidgets('任务页 · 浅色', (tester) async {
    await pumpTasks(tester, brightness: Brightness.light, file: 'tasks_light');
  });

  testWidgets('任务页 · 深色', (tester) async {
    await pumpTasks(tester, brightness: Brightness.dark, file: 'tasks_dark');
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    required Brightness brightness,
    required PageChrome Function() chrome,
    required Widget child,
    String? note,
    Size size = const Size(1440, 900),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: AppSection.editor,
          onSectionChanged: (_) {},
          chrome: chrome,
          status: () => StatusSnapshot(
            localEngine: 'ffmpeg · 就绪',
            cloud: (connected: true, label: '阿里百炼 · 已配置'),
            localBackend: (connected: true, label: 'DeepSeek · 已配置'),
            note: note,
          ),
          child: child,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpLocal(
    WidgetTester tester, {
    required Brightness brightness,
    required String file,
    bool withTranslation = true,
    Size size = const Size(1440, 900),
    List<int> review = const [],
    bool speakerManager = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final session = localSession(withTranslation: withTranslation);
    // 本地 SRT 没有置信度；压低几条，验证徽标叠在待校对行上仍可辨。
    for (final i in review) {
      session.document = session.document.replaceAt(
        i,
        session.document.cues[i].copyWith(confidence: 0.5),
      );
    }
    final controller = EditorController(session: session, settings: settings);
    final pageKey = GlobalKey<EditorPageState>();
    // 三处修改，让「保存」带上脏标记。
    for (final i in [0, 1, 2]) {
      controller
        ..select(i)
        ..toggleReviewed();
    }
    controller.select(6);

    await pumpShell(
      tester,
      brightness: brightness,
      size: size,
      note: editorStatusNote(controller),
      chrome: () => PageChrome(
        title: '编辑器',
        subtitle: editorSubtitle(controller),
        titleTrailing: EditorTitleTrailing(controller: controller),
        actions: [
          EditorPageActions(
            controller: controller,
            onTranslateMissing: () {},
            onExport: () {},
            onSave: () {},
          ),
        ],
      ),
      child: EditorPage(
        key: pageKey,
        controller: controller,
        onMountTranslation: withTranslation ? null : () {},
      ),
    );
    if (speakerManager) {
      pageKey.currentState!.manageSpeakers();
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$file.png'),
    );
  }

  testWidgets('编辑器 · 本地会话 · 浅色', (tester) async {
    await pumpLocal(tester, brightness: Brightness.light, file: 'editor_local_light');
  });

  testWidgets('编辑器 · 本地会话 · 深色', (tester) async {
    await pumpLocal(
      tester,
      brightness: Brightness.dark,
      file: 'editor_local_dark',
      review: [4, 7],
    );
  });

  testWidgets('编辑器 · 说话人名单 · 深色', (tester) async {
    await pumpLocal(
      tester,
      brightness: Brightness.dark,
      file: 'editor_speakers_dark',
      review: [4, 7],
      speakerManager: true,
    );
  });

  testWidgets('编辑器 · 本地会话 · 窄窗口', (tester) async {
    await pumpLocal(
      tester,
      brightness: Brightness.light,
      file: 'editor_local_narrow',
      size: const Size(1080, 760),
    );
  });

  testWidgets('编辑器 · 只有原文', (tester) async {
    await pumpLocal(
      tester,
      brightness: Brightness.light,
      file: 'editor_single_light',
      withTranslation: false,
    );
  });

  testWidgets('编辑器入口页 · 两份文件', (tester) async {
    editorClock = () => DateTime(2026, 9, 13, 22);
    addTearDown(() => editorClock = DateTime.now);
    final form = EditorOpenForm(
      defaults: () => testOptions(source: 'zh', target: 'en'),
    )
      ..setFile(OpenSlot.source, localZhFile())
      ..setFile(OpenSlot.translation, localEnFile());
    final done = _fixtures().where((t) => t.document.cues.isNotEmpty).toList();
    await pumpShell(
      tester,
      brightness: Brightness.light,
      chrome: editorOpenChrome,
      child: EditorOpenPage(
        form: form,
        tasks: done,
        recents: [
          RecentSession(
            title: 'interview_ep12',
            openedAt: DateTime(2026, 9, 12, 21, 40),
            cueCount: 488,
            speakerCount: 3,
            sourcePath: '/Users/mia/Movies/采访/interview_ep12.zh.srt',
            translationPath: '/Users/mia/Movies/采访/interview_ep12.en.srt',
          ),
          RecentSession(
            title: 'lecture_week3',
            openedAt: DateTime(2026, 9, 10, 9),
            cueCount: 1284,
            speakerCount: 5,
            taskId: 'x',
          ),
        ],
        onOpenFiles: () {},
        onOpenTask: (_) {},
        onOpenRecent: (_) {},
        onOpenTasks: () {},
      ),
    );
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('editor_open_light.png'),
    );
  });
}
