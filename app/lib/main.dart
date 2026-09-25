import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path_provider/path_provider.dart';

import 'core/theme/app_theme.dart';
import 'domain/app_branding.dart';
import 'domain/task.dart';
import 'features/editor/editor_chrome.dart';
import 'features/editor/editor_leave_dialog.dart';
import 'features/editor/editor_open_form.dart';
import 'features/editor/editor_open_page.dart';
import 'features/editor/editor_page.dart';
import 'features/editor/editor_workspace.dart';
import 'features/settings/settings_page.dart';
import 'features/shared/page_chrome.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/nav_rail.dart';
import 'features/shell/status_bar.dart';
import 'features/tasks/tasks_page.dart';
import 'features/transcode/transcode_form.dart';
import 'features/transcode/transcode_page.dart';
import 'features/transcribe/new_transcribe_dialog.dart';
import 'features/transcribe/new_transcribe_page.dart';
import 'features/transcribe/transcribe_form.dart';
import 'features/translate/new_translate_dialog.dart';
import 'features/translate/new_translate_page.dart';
import 'features/translate/translate_form.dart';
import 'pipeline/task_queue.dart';
import 'pipeline/task_runner.dart';
import 'services/editor_store.dart';
import 'services/media.dart';
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
  Media.dropInDir = '$support${Platform.pathSeparator}ffmpeg';

  final media = Media();
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
  final Media media;
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

  /// 对话框与 SnackBar 要一个 MaterialApp 以下的 context，根节点自己没有。
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// 编辑器分区的会话与入口页表单。挂在根节点上，切去别的页面再回来都还在。
  late final _workspace = EditorWorkspace(
    settings: widget.settings,
    store: widget.editorStore,
    queue: widget.queue,
    dialogContext: () => _navigatorKey.currentContext,
    say: _say,
    onShow: () => _go(AppSection.editor),
  );

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
    // 根节点只关心主题模式与编辑器换会话这类会换掉整页的变化；任务进度、
    // 编辑器改动由 [_live] 通过 ListenableBuilder 局部驱动顶栏、状态栏与任务页，
    // 否则每一次进度回调都会重建 MaterialApp 以下整棵树。
    widget.settings.addListener(_refresh);
    _workspace.addListener(_refresh);
    _lifecycle = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onPause: _flushProgress,
      onDetach: _flushProgress,
    );
    unawaited(_workspace.loadRecents());
  }

  /// 编辑进度写盘：任务 JSON 与本地会话的草稿。
  Future<void> _flushProgress() async {
    await widget.queue.flush();
    await _workspace.flushDraft();
  }

  /// 退出应用：编辑进度先落盘，再看字幕文件是不是最新的。修改已经存下来了，
  /// 用户选「稍后再写」照样退出；只有「取消」才留下。
  Future<AppExitResponse> _onExitRequested() async {
    await _flushProgress();
    final editor = _workspace.current;
    final context = _navigatorKey.currentContext;
    if (editor != null &&
        context != null &&
        context.mounted &&
        editor.unsavedEdits > 0) {
      if (_section != AppSection.editor || _workspace.showOpen) {
        _workspace.reveal();
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
    _workspace.removeListener(_refresh);
    _lifecycle.dispose();
    _workspace.dispose();
    _transcribeForm.dispose();
    _translateForm.dispose();
    _transcodeForm.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _go(AppSection section) {
    if (mounted) setState(() => _section = section);
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
    _workspace.form,
    ?_workspace.current,
  ]);

  ThemeMode get _themeMode => switch (widget.settings.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void _say(String message) => _messengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message)),
  );

  StatusSnapshot get _status => StatusSnapshot.from(
    settings: widget.settings,
    media: widget.media,
    queue: widget.queue,
    note: _section == AppSection.editor && _workspace.editing
        ? editorStatusNote(_workspace.current!)
        : null,
  );

  PageChrome get _chrome => switch (_section) {
    AppSection.tasks => tasksChrome(
      widget.queue,
      onNewTranslate: () => _tasksKey.currentState?.newTranslate(),
      onNewTranscribe: () => _tasksKey.currentState?.newTranscribe(),
    ),
    AppSection.newTranscribe => newTranscribeChrome(_transcribeForm),
    AppSection.newTranslate => newTranslateChrome(_translateForm),
    AppSection.transcode => transcodeChrome(_transcodeForm),
    AppSection.settings => settingsChrome(
      onReset: () => _settingsKey.currentState?.confirmReset(),
    ),
    AppSection.editor => editorChrome(
      _workspace,
      onSave: () => _editorKey.currentState?.save(),
      onExport: () => _editorKey.currentState?.export(),
      onTranslateMissing: () => _editorKey.currentState?.translateMissing(),
    ),
  };

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
        onSectionChanged: _go,
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
        onOpenEditor: _workspace.openTask,
        showNewTranscribe: (context, paths) => showNewTranscribeDialog(
          context,
          settings: widget.settings,
          initialPaths: paths,
          onOpenSettings: () => _go(AppSection.settings),
        ),
        showNewTranslate: (context, paths, onSwitchToTranscribe) =>
            showNewTranslateDialog(
              context,
              settings: widget.settings,
              initialPaths: paths,
              onOpenSettings: () => _go(AppSection.settings),
              onSwitchToTranscribe: onSwitchToTranscribe,
            ),
      ),
    ),
    AppSection.newTranscribe => NewTranscribePage(
      form: _transcribeForm,
      queue: widget.queue,
      onOpenSettings: () => _go(AppSection.settings),
      onOpenTasks: () => _go(AppSection.tasks),
    ),
    AppSection.newTranslate => NewTranslatePage(
      form: _translateForm,
      queue: widget.queue,
      onOpenSettings: () => _go(AppSection.settings),
      onOpenTasks: () => _go(AppSection.tasks),
      // 拖错了门的音视频原样带去「新建转写」页，不让用户再拖一次。
      onSwitchToTranscribe: (media) {
        _transcribeForm.seed(media);
        _go(AppSection.newTranscribe);
      },
    ),
    AppSection.transcode => TranscodePage(
      form: _transcodeForm,
      queue: widget.queue,
      onOpenTasks: () => _go(AppSection.tasks),
    ),
    AppSection.settings => SettingsPage(
      key: _settingsKey,
      settings: widget.settings,
      media: widget.media,
    ),
    AppSection.editor when _workspace.editing => EditorPage(
      key: _editorKey,
      controller: _workspace.current!,
      onMountTranslation: () =>
          _workspace.stageReplacement(OpenSlot.translation),
      onDropFiles: (path, slot) =>
          _workspace.stageReplacement(slot, path: path),
      onDiscardDraft: _workspace.discardDraft,
    ),
    AppSection.editor => ListenableBuilder(
      listenable: widget.queue,
      builder: (_, _) => EditorOpenPage(
        form: _workspace.form,
        tasks: [
          for (final t in widget.queue.tasks)
            if (t.status == TaskStatus.done && t.document.cues.isNotEmpty) t,
        ],
        recents: _workspace.recents,
        onOpenFiles: _workspace.openFiles,
        onOpenTask: _workspace.openTask,
        onOpenRecent: _workspace.openRecent,
        onOpenTasks: () => _go(AppSection.tasks),
      ),
    ),
  };
}
