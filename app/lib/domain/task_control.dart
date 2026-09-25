/// 任务执行期间跨层共用的控制信号：取消、进度回报、带建议的失败。
///
/// 放在 domain 而不是 services：抛出与捕获它们的远不止识别 / 翻译服务 ——
/// ffmpeg 调用、转码、字幕写出、编辑器保存都用同一套。挂在 provider 接口上，
/// 流水线和编辑器就得为了一个异常类型去依赖服务层。
library;

/// 协作式取消。所有 provider 在每个可中断点检查 [throwIfCancelled]。
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const TaskCancelled();
  }
}

class TaskCancelled implements Exception {
  const TaskCancelled();

  @override
  String toString() => '任务已取消';
}

/// 用户能据此采取行动的失败：一句话说明、原始细节、建议怎么办。
///
/// 流水线把它原样转成任务上的 `TaskError` 显示给用户；不是这个类型的异常
/// 只能显示成「未预期的错误」，所以凡是知道该怎么补救的地方都应该抛它。
class ActionableException implements Exception {
  const ActionableException(
    this.message, {
    this.detail,
    this.hint,
    this.batchTooLarge = false,
  });

  final String message;
  final String? detail;
  final String? hint;

  /// 这次失败是「一批给太多了」引起的（模型合并了行、上下文超长）。
  /// 流水线看到它会减半批量重试；其他失败（网络、鉴权）减半没有意义。
  final bool batchTooLarge;

  @override
  String toString() => message;
}

/// 阶段内的进度回调：[done]/[total] 为已完成/总数，[note] 是界面上的补充说明。
typedef ProgressSink =
    void Function(int done, int total, {String? note});
