import 'dart:io';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path_provider/path_provider.dart';

import 'core/theme/app_theme.dart';
import 'domain/app_branding.dart';
import 'domain/paths.dart';
import 'domain/task.dart';
import 'features/editor/editor_controller.dart';
import 'features/editor/editor_leave_dialog.dart';
import 'features/editor/editor_open_form.dart';
import 'features/editor/editor_open_page.dart';
import 'features/editor/editor_page.dart';
import 'features/editor/editor_page_actions.dart';
import 'features/editor/editor_session.dart';
import 'features/editor/editor_title.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/nav_rail.dart';
import 'features/shell/page_chrome.dart';
import 'features/shell/status_bar.dart';
import 'features/tasks/new_transcribe_page.dart';
import 'features/tasks/new_translate_page.dart';
import 'features/tasks/tasks_page.dart';
import 'features/tasks/transcribe_form.dart';
import 'features/tasks/translate_form.dart';
import 'features/transcode/transcode_form.dart';
import 'features/transcode/transcode_page.dart';
import 'pipeline/task_queue.dart';
import 'pipeline/task_runner.dart';
import 'services/editor_store.dart';
import 'services/ffmpeg.dart';
import 'services/registry.dart';
import 'services/settings.dart';
import 'services/task_store.dart';
import 'services/transcoder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 编辑器预览用 media_kit 播放音视频，得在建播放器之前初始化一次。
  MediaKit.ensureInitialized();

  final settings = await AppSettings.load();
  final support = (await getApplicationSupportDirectory()).path;
  final workDir = '$support/work';
  await Directory(workDir).create(recursive: true);

  // 用户投放 ffmpeg 的目录。放在应用支持目录下而不是安装目录：Windows 上
  // 安装目录在 Program Files 里，用户往里拖文件要过 UAC。
  // 用平台分隔符拼：这个路径要交给资源管理器打开，Windows 的 explorer
  // 对正斜杠的路径经常不认。
  Ffmpeg.dropInDir = '$support${Platform.pathSeparator}ffmpeg';

  final media = Ffmpeg();
  // 转码页（检测编码器、读源文件）与流水线（跑转码）共用一份，
  // 编码器检测结果只做一次。
  final transcoder = Transcoder(media: media);
  final queue = TaskQueue(
    runner: TaskRunner(
      settings: settings,
      workDir: workDir,
      media: media,
      transcoder: transcoder,
    ),
    settings: settings,
    // 任务数据（参数、阶段、字幕文档、识别检查点）存成 JSON，重启后还在。
    store: TaskStore('$support/tasks'),
  );
  await queue.restore();

  runApp(
    SubtitleStudioApp(
      settings: settings,
      queue: queue,
      media: media,
      transcoder: transcoder,
      // 本地字幕会话的附加状态（已校对标记、说话人名单）与最近打开。
      editorStore: EditorStore('$support/editor'),
    ),
  );
}

class SubtitleStudioApp extends StatefulWidget {
  const SubtitleStudioApp({
    super.key,
    required this.settings,
    required this.queue,
    required this.media,
    required this.transcoder,
    required this.editorStore,
  });

  final AppSettings settings;
  final TaskQueue queue;
  final Ffmpeg media;
  final Transcoder transcoder;
  final EditorStore editorStore;

  @override
  State<SubtitleStudioApp> createState() => _SubtitleStudioAppState();
}

class _SubtitleStudioAppState extends State<SubtitleStudioApp> {
  final _tasksKey = GlobalKey<TasksPageState>();
  final _editorKey = GlobalKey<EditorPageState>();
  final _settingsKey = GlobalKey<SettingsPageState>();
  AppSection _section = AppSection.tasks;
  EditorController? _editor;

  /// 对话框与 SnackBar 要一个 MaterialApp 以下的 context，根节点自己没有。
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 编辑器入口页的表单。挂在根节点上，切去别的页面再回来，挑好的文件还在。
  late final _openForm = EditorOpenForm(
    defaults: widget.settings.defaultTaskOptions,
  );

  /// 有会话开着时点了「打开其他字幕…」：先显示入口页，真正打开新会话时
  /// 才关掉旧的 —— 用户也可能只是看一眼又返回编辑器。
  bool _showOpen = false;

  List<RecentSession> _recents = const [];

  /// 退出前把还没写盘的编辑进度写掉，字幕文件还没写入的先问一句。
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

  /// 「转码」页的表单，同样挂在根节点上。
  late final _transcodeForm = TranscodeFormController(
    settings: widget.settings,
    transcoder: widget.transcoder,
  );

  @override
  void initState() {
    super.initState();
    // 根节点只关心主题模式这类真正全局的设置；任务进度、编辑器改动
    // 由 [_live] 通过 ListenableBuilder 局部驱动顶栏、状态栏与任务页，
    // 否则每一次进度回调都会重建 MaterialApp 以下整棵树。
    widget.settings.addListener(_refresh);
    _lifecycle = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onPause: _flushProgress,
      onDetach: _flushProgress,
    );
    widget.editorStore.loadRecents().then((recents) {
      if (mounted) setState(() => _recents = recents);
    });
  }

  /// 编辑进度写盘：任务 JSON 与本地会话的草稿。
  Future<void> _flushProgress() async {
    await widget.queue.flush();
    await _editor?.flushDraft();
  }

  /// 退出应用：编辑进度先落盘，再看字幕文件是不是最新的。修改已经存下来了，
  /// 用户选「稍后再写」照样退出；只有「取消」才留下。
  Future<AppExitResponse> _onExitRequested() async {
    await _flushProgress();
    final editor = _editor;
    final context = _navigatorKey.currentContext;
    if (editor != null &&
        context != null &&
        context.mounted &&
        editor.unsavedEdits > 0) {
      if (_section != AppSection.editor || _showOpen) {
        setState(() {
          _section = AppSection.editor;
          _showOpen = false;
        });
      }
      final ok = await confirmLeaveEditor(
        context,
        editor,
        intent: LeaveIntent.exit,
      );
      if (!ok) return AppExitResponse.cancel;
      // 写入产物后任务记下了新的时间戳，再落一次盘。
      await _flushProgress();
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    widget.settings.removeListener(_refresh);
    _lifecycle.dispose();
    _editor?.dispose();
    _openForm.dispose();
    _transcribeForm.dispose();
    _translateForm.dispose();
    _transcodeForm.dispose();
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
    // 「重新检测」之后状态栏那行 ffmpeg 状态要跟着更新。
    widget.media,
    _transcribeForm,
    _translateForm,
    _transcodeForm,
    _openForm,
    ?_editor,
  ]);

  ThemeMode get _themeMode => switch (widget.settings.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void _say(String message) => _messengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message)),
  );

  /// 换成新会话前：字幕文件还没写入最新修改的先问一句。
  Future<bool> _leaveCurrent() async {
    final editor = _editor;
    final context = _navigatorKey.currentContext;
    if (editor == null || context == null) return true;
    return confirmLeaveEditor(context, editor);
  }

  void _activate(EditorController controller) {
    final previous = _editor;
    setState(() {
      _editor = controller;
      _showOpen = false;
      _section = AppSection.editor;
    });
    previous?.dispose();
  }

  void _remember(RecentSession entry) {
    widget.editorStore.touchRecent(entry).then((recents) {
      if (mounted) setState(() => _recents = recents);
    });
  }

  Future<void> _openEditor(SubtitleTask task) async {
    final current = _editor?.session;
    if (current is TaskSession && current.task.id == task.id) {
      setState(() {
        _showOpen = false;
        _section = AppSection.editor;
      });
      return;
    }
    if (!await _leaveCurrent()) return;
    final controller = EditorController(
      session: TaskSession(task),
      settings: widget.settings,
      store: widget.editorStore,
      // 任务在跑时流水线会换掉文档，编辑器跟着刷新、只读。
      follow: widget.queue,
    )
      // 编辑器里的改动（改字、改时间、拆分合并、重新翻译）跟着写盘。
      ..addListener(() => widget.queue.persist(task));
    _activate(controller);
    _remember(
      RecentSession(
        title: task.fileName,
        openedAt: DateTime.now(),
        cueCount: task.document.cues.length,
        speakerCount: task.document.speakerIds.length,
        taskId: task.id,
      ),
    );
  }

  /// 恢复横幅「丢弃，按文件重新打开」：扔掉草稿，按文件现在的内容重开。
  /// 用户就是要丢弃，不再问「先写入字幕文件？」。
  Future<void> _discardDraft() async {
    final editor = _editor;
    final session = editor?.session;
    if (editor == null || session is! FileSession) return;
    await editor.forgetDraft();
    await _openForm.seed(
      sourcePath: session.sourcePath,
      translationPath: session.translationPath,
    );
    if (_openForm.source == null) {
      _say('${baseName(session.sourcePath)} 读不了，可能已经移动或删除');
      return;
    }
    await _openFiles(askLeave: false);
  }

  /// 入口页「打开编辑器」。同一对文件上次存过附加状态的直接恢复；
  /// 还有没写回文件的编辑进度的，接着显示并用横幅说明。
  Future<void> _openFiles({bool askLeave = true}) async {
    final form = _openForm;
    if (!form.canOpen) return;
    if (askLeave && !await _leaveCurrent()) return;
    final state = await widget.editorStore.loadFileDraft(
      form.source!.path,
      form.translation?.path,
    );
    final session = form.build(restored: state?.current)
      ..pendingEdits = state?.pendingEdits ?? 0;
    if (state != null && state.changedOutside) {
      // 草稿之后文件被别的程序改过：沿用草稿记下的时间戳，保存时才会
      // 发现冲突、问用户覆盖还是另存。
      session.trackedStamps.addAll(state.stamps);
    } else {
      await session.captureStamps();
    }
    final draft = state?.draft != null && session.pendingEdits > 0;
    final controller = EditorController(
      session: session,
      settings: widget.settings,
      store: widget.editorStore,
      // 文件已经变了，存下的「上次写入的版本」不再是文件里的内容，不能拿来
      // 「撤销到上次写入」。
      saved: state == null || state.changedOutside ? null : state.saved,
      recoveredAt: draft ? state!.draftAt ?? DateTime.now() : null,
    )..recoveredOverChanged = state?.changedOutside ?? false;
    // 另存为之后挂到了新文件上，「最近打开」跟着换成新路径。
    controller.onRemount = () => _remember(
      RecentSession(
        title: session.title,
        openedAt: DateTime.now(),
        cueCount: session.document.cues.length,
        speakerCount: session.document.speakerIds.length,
        sourcePath: session.sourcePath,
        translationPath: session.translationPath,
      ),
    );
    _activate(controller);
    form.clear();
    _remember(
      RecentSession(
        title: session.title,
        openedAt: DateTime.now(),
        cueCount: session.document.cues.length,
        speakerCount: session.document.speakerIds.length,
        sourcePath: session.sourcePath,
        translationPath: session.translationPath,
      ),
    );
  }

  Future<void> _openRecent(RecentSession recent) async {
    if (recent.isTask) {
      final task = widget.queue.byId(recent.taskId!);
      if (task == null) {
        _say('这个任务已经删除了');
        return;
      }
      return _openEditor(task);
    }
    await _openForm.seed(
      sourcePath: recent.sourcePath!,
      translationPath: recent.translationPath,
    );
    if (_openForm.source == null) {
      _say('${baseName(recent.sourcePath!)} 读不了，可能已经移动或删除');
      return;
    }
    await _openFiles();
  }

  /// 来源浮层「替换…」、「挂载译文」、把文件拖到编辑页：带着当前文件去入口页，
  /// 换上新文件后在那里确认配对，不直接改动正在编辑的会话。
  Future<void> _stageReplacement(OpenSlot slot, {String? path}) async {
    final session = _editor?.session;
    if (session is FileSession) {
      await _openForm.seed(
        sourcePath: session.sourcePath,
        translationPath: session.mountedTranslationPath,
      );
    } else {
      _openForm.clear();
    }
    if (path != null) {
      await _openForm.load(slot, path);
    } else {
      await _openForm.browse(slot);
    }
    if (mounted) setState(() => _showOpen = true);
  }

  Future<void> _repair() async {
    final session = _editor?.session;
    if (session is! FileSession) return;
    await _openForm.seed(
      sourcePath: session.sourcePath,
      translationPath: session.mountedTranslationPath,
    );
    if (mounted) setState(() => _showOpen = true);
  }

  void _openOther() {
    _openForm.clear();
    setState(() => _showOpen = true);
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
      note: _section == AppSection.editor && _editor != null && !_showOpen
          ? editorStatusNote(_editor!)
          : null,
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
      case AppSection.transcode:
        return transcodeChrome(_transcodeForm);
      case AppSection.settings:
        return settingsChrome(
          onReset: () => _settingsKey.currentState?.confirmReset(),
        );
      case AppSection.editor:
        final editor = _editor;
        if (editor == null || _showOpen) {
          return editorOpenChrome(
            onBack: editor == null
                ? null
                : () => setState(() => _showOpen = false),
          );
        }
        return PageChrome(
          title: '编辑器',
          subtitle: editorSubtitle(editor),
          titleTrailing: EditorTitleTrailing(
            controller: editor,
            onReplace: (slot) => _stageReplacement(slot),
            onRepair: _repair,
            onOpenOther: _openOther,
            onSave: () => _editorKey.currentState?.save(),
          ),
          actions: [
            EditorPageActions(
              controller: editor,
              onTranslateMissing: () =>
                  _editorKey.currentState?.translateMissing(),
              onExport: () => _editorKey.currentState?.export(),
              onSave: () => _editorKey.currentState?.save(),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: appNameFor(PlatformDispatcher.instance.locale.languageCode),
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
    AppSection.transcode => TranscodePage(
      form: _transcodeForm,
      queue: widget.queue,
      onOpenTasks: () => setState(() => _section = AppSection.tasks),
    ),
    AppSection.settings => SettingsPage(
      key: _settingsKey,
      settings: widget.settings,
      media: widget.media,
    ),
    AppSection.editor when _editor != null && !_showOpen => EditorPage(
      key: _editorKey,
      controller: _editor!,
      onMountTranslation: () => _stageReplacement(OpenSlot.translation),
      onDropFiles: (path, slot) => _stageReplacement(slot, path: path),
      onDiscardDraft: _discardDraft,
    ),
    AppSection.editor => ListenableBuilder(
      listenable: widget.queue,
      builder: (_, _) => EditorOpenPage(
        form: _openForm,
        tasks: [
          for (final t in widget.queue.tasks)
            if (t.status == TaskStatus.done && t.document.cues.isNotEmpty) t,
        ],
        recents: _recents,
        onOpenFiles: _openFiles,
        onOpenTask: _openEditor,
        onOpenRecent: _openRecent,
        onOpenTasks: () => setState(() => _section = AppSection.tasks),
      ),
    ),
  };
}
