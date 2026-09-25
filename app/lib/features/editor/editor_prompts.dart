import '../../domain/file_stamp.dart';

/// 离开编辑器时主按钮做完写入之后要干什么。
enum LeaveIntent {
  open('写入并打开'),
  exit('写入并退出');

  const LeaveIntent(this.label);

  final String label;
}

/// 「先写入字幕文件？」的回答。
enum LeaveChoice { write, later, cancel }

/// 字幕文件在别处被改过时的回答。
enum ConflictChoice { overwrite, saveAs, cancel }

/// 编辑器的写入流程里要问用户、告诉用户的事。
///
/// 流程本身（离开前先写编辑进度、只读时不问、冲突了覆盖还是另存）在
/// `EditorController.confirmLeave` / `writeFiles` 里，这里只管问和说：
/// 界面上是对话框与 SnackBar（`editor_leave_dialog.dart`，由 `main.dart`
/// 接线），测试里换成按剧本回答的假实现。返回 null 按「取消」处理。
abstract interface class EditorPrompts {
  /// 「先写入字幕文件？」：[title] 有 [edits] 处修改还没写进 [files]。
  Future<LeaveChoice?> askLeave({
    required String title,
    required int edits,
    required List<String> files,
    required LeaveIntent intent,
  });

  /// 字幕文件在别处被改过：覆盖、另存为还是取消。[remounts] 表示另存为
  /// 之后编辑器挂到新文件上（本地会话），否则只是另存一份（任务会话）。
  Future<ConflictChoice?> askConflict(
    List<FileChange> changes, {
    required bool remounts,
  });

  /// 挑一个目录；用户取消时为 null。
  Future<String?> pickDir({
    required String initialDirectory,
    required String confirmText,
  });

  /// 轻提示（SnackBar）。
  void say(String message);
}
