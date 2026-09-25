import 'package:flutter/widgets.dart';

import '../../domain/paths.dart';
import '../../domain/task.dart';
import '../../pipeline/task_queue.dart';
import '../../services/editor_store.dart';
import '../../services/settings.dart';
import 'editor_controller.dart';
import 'editor_leave_dialog.dart';
import 'editor_open_form.dart';
import 'editor_session.dart';

/// 编辑器分区的会话管理：当前开着哪个会话、入口页是否盖在上面、最近打开。
///
/// 挂在根节点上（切去别的页面再回来，会话与入口页挑好的文件都还在），
/// 但规则不写在 `main.dart` 里：换会话前先问要不要写入字幕文件、草稿恢复、
/// 另存为后「最近打开」跟着换路径，这些都是编辑器自己的事，装配层只负责接线。
class EditorWorkspace extends ChangeNotifier {
  EditorWorkspace({
    required this.settings,
    required this.store,
    required this.queue,
    required this.dialogContext,
    required this.say,
    required this.onShow,
  });

  final AppSettings settings;
  final EditorStore store;
  final TaskQueue queue;

  /// 对话框要一个 MaterialApp 以下的 context，根节点自己没有，由装配层给。
  final BuildContext? Function() dialogContext;

  /// 轻提示（SnackBar）。
  final ValueChanged<String> say;

  /// 切到编辑器分区。打开会话后调用。
  final VoidCallback onShow;

  /// 编辑器入口页的表单。
  late final form = EditorOpenForm(defaults: settings.defaultTaskOptions);

  EditorController? _current;
  EditorController? get current => _current;

  /// 有会话开着时点了「打开其他字幕…」：先显示入口页，真正打开新会话时
  /// 才关掉旧的 —— 用户也可能只是看一眼又返回编辑器。
  bool _showOpen = false;
  bool get showOpen => _showOpen;

  /// 编辑页在前台（而不是入口页）。
  bool get editing => _current != null && !_showOpen;

  List<RecentSession> _recents = const [];
  List<RecentSession> get recents => _recents;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadRecents() async {
    _recents = await store.loadRecents();
    _notify();
  }

  /// 编辑进度写盘（本地会话的草稿；任务会话的进度随任务 JSON 写）。
  Future<void> flushDraft() async => _current?.flushDraft();

  /// 回到编辑页，盖在上面的入口页收起。
  void reveal() {
    _showOpen = false;
    _notify();
    onShow();
  }

  /// 入口页左上角「返回编辑器」。
  void backToEditor() {
    _showOpen = false;
    _notify();
  }

  /// 换成新会话前：字幕文件还没写入最新修改的先问一句。
  Future<bool> _leaveCurrent() async {
    final editor = _current;
    final context = dialogContext();
    if (editor == null || context == null) return true;
    return confirmLeaveEditor(context, editor);
  }

  void _activate(EditorController controller) {
    final previous = _current;
    _current = controller;
    reveal();
    previous?.dispose();
  }

  void _remember(RecentSession entry) {
    store.touchRecent(entry).then((recents) {
      _recents = recents;
      _notify();
    });
  }

  static RecentSession _recentOfFile(FileSession session) => RecentSession(
    title: session.title,
    openedAt: DateTime.now(),
    cueCount: session.document.cues.length,
    speakerCount: session.document.speakerIds.length,
    sourcePath: session.sourcePath,
    translationPath: session.translationPath,
  );

  Future<void> openTask(SubtitleTask task) async {
    final current = _current?.session;
    if (current is TaskSession && current.task.id == task.id) {
      reveal();
      return;
    }
    if (!await _leaveCurrent()) return;
    final controller =
        EditorController(
            session: TaskSession(task),
            settings: settings,
            store: store,
            // 任务在跑时流水线会换掉文档，编辑器跟着刷新、只读。
            follow: queue,
          )
          // 编辑器里的改动（改字、改时间、拆分合并、重新翻译）跟着写盘。
          ..addListener(() => queue.persist(task));
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
  Future<void> discardDraft() async {
    final editor = _current;
    final session = editor?.session;
    if (editor == null || session is! FileSession) return;
    await editor.forgetDraft();
    await form.seed(
      sourcePath: session.sourcePath,
      translationPath: session.translationPath,
    );
    if (form.source == null) {
      say('${baseName(session.sourcePath)} 读不了，可能已经移动或删除');
      return;
    }
    await openFiles(askLeave: false);
  }

  /// 入口页「打开编辑器」。同一对文件上次存过附加状态的直接恢复；
  /// 还有没写回文件的编辑进度的，接着显示并用横幅说明。
  Future<void> openFiles({bool askLeave = true}) async {
    if (!form.canOpen) return;
    if (askLeave && !await _leaveCurrent()) return;
    final state = await store.loadFileDraft(
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
      settings: settings,
      store: store,
      // 文件已经变了，存下的「上次写入的版本」不再是文件里的内容，不能拿来
      // 「撤销到上次写入」。
      saved: state == null || state.changedOutside ? null : state.saved,
      recoveredAt: draft ? state!.draftAt ?? DateTime.now() : null,
    )..recoveredOverChanged = state?.changedOutside ?? false;
    // 另存为之后挂到了新文件上，「最近打开」跟着换成新路径。
    controller.onRemount = () => _remember(_recentOfFile(session));
    _activate(controller);
    form.clear();
    _remember(_recentOfFile(session));
  }

  Future<void> openRecent(RecentSession recent) async {
    if (recent.isTask) {
      final task = queue.byId(recent.taskId!);
      if (task == null) {
        say('这个任务已经删除了');
        return;
      }
      return openTask(task);
    }
    await form.seed(
      sourcePath: recent.sourcePath!,
      translationPath: recent.translationPath,
    );
    if (form.source == null) {
      say('${baseName(recent.sourcePath!)} 读不了，可能已经移动或删除');
      return;
    }
    await openFiles();
  }

  /// 来源浮层「替换…」、「挂载译文」、把文件拖到编辑页：带着当前文件去入口页，
  /// 换上新文件后在那里确认配对，不直接改动正在编辑的会话。
  Future<void> stageReplacement(OpenSlot slot, {String? path}) async {
    final session = _current?.session;
    if (session is FileSession) {
      await form.seed(
        sourcePath: session.sourcePath,
        translationPath: session.mountedTranslationPath,
      );
    } else {
      form.clear();
    }
    if (path != null) {
      await form.load(slot, path);
    } else {
      await form.browse(slot);
    }
    _showOpen = true;
    _notify();
  }

  /// 来源浮层「重新配对…」：带着当前两份文件去入口页。
  Future<void> repair() async {
    final session = _current?.session;
    if (session is! FileSession) return;
    await form.seed(
      sourcePath: session.sourcePath,
      translationPath: session.mountedTranslationPath,
    );
    _showOpen = true;
    _notify();
  }

  /// 「打开其他字幕…」：入口页从空白开始。
  void openOther() {
    form.clear();
    _showOpen = true;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _current?.dispose();
    form.dispose();
    super.dispose();
  }
}
