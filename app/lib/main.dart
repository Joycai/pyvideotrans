import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/theme/app_theme.dart';
import 'domain/task.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/nav_rail.dart';
import 'features/editor/editor_controller.dart';
import 'features/editor/editor_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/status_bar.dart';
import 'features/tasks/new_transcribe_page.dart';
import 'features/tasks/new_translate_page.dart';
import 'features/tasks/tasks_page.dart';
import 'features/tasks/transcribe_form.dart';
import 'features/tasks/translate_form.dart';
import 'pipeline/task_queue.dart';
import 'pipeline/task_runner.dart';
import 'services/media.dart';
import 'services/registry.dart';
import 'services/settings.dart';
import 'services/task_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await AppSettings.load();
  final support = (await getApplicationSupportDirectory()).path;
  final workDir = '$support/work';
  await Directory(workDir).create(recursive: true);

  final media = Media();
  final queue = TaskQueue(
    runner: TaskRunner(settings: settings, workDir: workDir, media: media),
    settings: settings,
    // 任务数据（参数、阶段、字幕文档、识别检查点）存成 JSON，重启后还在。
    store: TaskStore('$support/tasks'),
  );
  await queue.restore();

  runApp(SubtitleStudioApp(settings: settings, queue: queue, media: media));
}

class SubtitleStudioApp extends StatefulWidget {
  const SubtitleStudioApp({
    super.key,
    required this.settings,
    required this.queue,
    required this.media,
  });

  final AppSettings settings;
  final TaskQueue queue;
  final Media media;

  @override
  State<SubtitleStudioApp> createState() => _SubtitleStudioAppState();
}

class _SubtitleStudioAppState extends State<SubtitleStudioApp> {
  final _tasksKey = GlobalKey<TasksPageState>();
  final _editorKey = GlobalKey<EditorPageState>();
  final _settingsKey = GlobalKey<SettingsPageState>();
  AppSection _section = AppSection.tasks;
  EditorController? _editor;

  /// 退出前把还没写盘的任务改动写掉。
  late final AppLifecycleListener _lifecycle;

  /// 「新建转写」页的表单。挂在根节点上，切去设置页再回来文件与参数还在。
  late final _transcribeForm = TranscribeFormController(
    settings: widget.settings,
    media: widget.media,
  );

  /// 「翻译」页的表单，同样挂在根节点上。
  late final _translateForm = TranslateFormController(
    settings: widget.settings,
    media: widget.media,
  );

  @override
  void initState() {
    super.initState();
    // 根节点只关心主题模式这类真正全局的设置；任务进度、编辑器改动
    // 由 [_live] 通过 ListenableBuilder 局部驱动顶栏、状态栏与任务页，
    // 否则每一次进度回调都会重建 MaterialApp 以下整棵树。
    widget.settings.addListener(_refresh);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.queue.flush();
        return AppExitResponse.exit;
      },
      onPause: widget.queue.flush,
      onDetach: widget.queue.flush,
    );
  }

  @override
  void dispose() {
    widget.settings.removeListener(_refresh);
    _lifecycle.dispose();
    _editor?.dispose();
    _transcribeForm.dispose();
    _translateForm.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 顶栏与状态栏的数据源。编辑器打开时把它也并进来，标题里的条数
  /// 与待校对徽标才会跟着文档变。
  Listenable get _live => Listenable.merge([
    widget.queue,
    widget.settings,
    _transcribeForm,
    _translateForm,
    ?_editor,
  ]);

  ThemeMode get _themeMode => switch (widget.settings.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void _openEditor(SubtitleTask task) {
    final previous = _editor;
    final controller = EditorController(task: task, settings: widget.settings)
      // 编辑器里的改动（改字、改时间、拆分合并、重新翻译）跟着写盘。
      ..addListener(() => widget.queue.persist(task));
    setState(() {
      _editor = controller;
      _section = AppSection.editor;
    });
    previous?.dispose();
  }

  StatusSnapshot get _status {
    final queue = widget.queue;
    final running = queue.countWhere(
      (t) => t.status == TaskStatus.running || t.status == TaskStatus.queued,
    );
    final asr = Registry.asrInfo(widget.settings.asrProviderId);
    final mt = Registry.translationInfo(widget.settings.translationProviderId);

    return StatusSnapshot(
      localEngine: widget.media.available ? 'ffmpeg · 就绪' : 'ffmpeg · 未找到',
      cloud: (
        connected: asr != null && widget.settings.isConfigured(asr),
        label: asr == null
            ? '识别 · 未选择'
            : widget.settings.isConfigured(asr)
            ? '${asr.name} · 已配置'
            : '${asr.name} · 未配置',
      ),
      localBackend: (
        connected: mt != null && widget.settings.isConfigured(mt),
        label: mt == null
            ? '翻译 · 未选择'
            : widget.settings.isConfigured(mt)
            ? '${mt.name} · 已配置'
            : '${mt.name} · 未配置',
      ),
      runningTasks: running,
      overallProgress: queue.overallProgress,
      etaText: queue.running?.eta == null
          ? null
          : '剩余约 ${queue.running!.eta!.inMinutes} 分钟',
    );
  }

  PageChrome get _chrome {
    final queue = widget.queue;
    switch (_section) {
      case AppSection.tasks:
        final running = queue.countWhere((t) => t.status == TaskStatus.running);
        final failed = queue.countWhere((t) => t.status == TaskStatus.failed);
        return PageChrome(
          title: '任务',
          subtitle: '${queue.tasks.length} 个任务 · $running 个进行中 · $failed 个失败',
          actions: [
            TasksPageActions(
              onNewTranslate: () => _tasksKey.currentState?.newTranslate(),
              onNewTranscribe: () => _tasksKey.currentState?.newTranscribe(),
            ),
          ],
        );
      case AppSection.newTranscribe:
        return newTranscribeChrome(_transcribeForm);
      case AppSection.newTranslate:
        return newTranslateChrome(_translateForm);
      case AppSection.settings:
        return settingsChrome(
          onReset: () => _settingsKey.currentState?.confirmReset(),
        );
      case AppSection.editor:
        final editor = _editor;
        if (editor == null) {
          return const PageChrome(title: '编辑器', subtitle: '从任务页打开一个任务开始校对');
        }
        return PageChrome(
          title: '编辑器',
          subtitle:
              '${editor.task.fileName} · ${editor.document.cues.length} 条 · '
              '${editor.task.sourceLanguage.name} → ${editor.task.targetLanguage.name}',
          titleTrailing: EditorReviewBadge(count: editor.document.reviewCount),
          actions: [
            EditorPageActions(
              controller: editor,
              onTranslateMissing: () =>
                  _editorKey.currentState?.translateMissing(),
              onExport: () => _editorKey.currentState?.export(),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '字幕工具',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: AppShell(
        section: _section,
        onSectionChanged: (s) => setState(() => _section = s),
        chrome: () => _chrome,
        status: () => _status,
        live: _live,
        child: _body,
      ),
    );
  }

  Widget get _body => switch (_section) {
    // 任务页自己不监听队列，靠这里的 ListenableBuilder 跟进度走。
    AppSection.tasks => ListenableBuilder(
      listenable: widget.queue,
      builder: (_, _) => TasksPage(
        key: _tasksKey,
        queue: widget.queue,
        onOpenEditor: _openEditor,
        onOpenSettings: () => setState(() => _section = AppSection.settings),
      ),
    ),
    AppSection.newTranscribe => NewTranscribePage(
      form: _transcribeForm,
      queue: widget.queue,
      onOpenSettings: () => setState(() => _section = AppSection.settings),
      onOpenTasks: () => setState(() => _section = AppSection.tasks),
    ),
    AppSection.newTranslate => NewTranslatePage(
      form: _translateForm,
      queue: widget.queue,
      onOpenSettings: () => setState(() => _section = AppSection.settings),
      onOpenTasks: () => setState(() => _section = AppSection.tasks),
      // 拖错了门的音视频原样带去「新建转写」页，不让用户再拖一次。
      onSwitchToTranscribe: (media) {
        _transcribeForm.seed(media);
        setState(() => _section = AppSection.newTranscribe);
      },
    ),
    AppSection.settings => SettingsPage(
      key: _settingsKey,
      settings: widget.settings,
    ),
    AppSection.editor when _editor != null => EditorPage(
      key: _editorKey,
      controller: _editor!,
    ),
    _ => _Placeholder(section: _section),
  };
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 32, weight: 400, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              section.label,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
