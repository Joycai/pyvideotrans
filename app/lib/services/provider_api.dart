import '../domain/cue.dart';
import '../domain/recognition_checkpoint.dart';

export '../domain/recognition_checkpoint.dart';

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

/// provider 抛出的、带可行动建议的错误。
class ProviderException implements Exception {
  const ProviderException(
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

/// provider 的元信息，用于设置页与任务列表的「服务 / 模型」列。
class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.vendor,
    this.runsLocally = false,
    this.implemented = true,
    this.needsApiKey = true,
    this.defaultBaseUrl,
    this.defaultModel,
    this.models = const [],
  });

  /// 注册 id，任务里存的就是它。
  final String id;

  /// 界面显示名：「OpenAI · whisper-1」里的后半段由 model 提供。
  final String name;
  final String vendor;

  /// 在用户机器上跑（本地后端 / Ollama）。只影响图标与状态栏，不影响调用链路。
  final bool runsLocally;

  /// 第一期是否已实施。未实施的在设置页里灰显并标注。
  final bool implemented;

  final bool needsApiKey;
  final String? defaultBaseUrl;
  final String? defaultModel;
  final List<String> models;
}

/// 语音识别。
///
/// 实现者只需要把音频变成 [Cue] 列表；抽音、分段、重试由流水线负责。
/// 逐段识别的实现可以用 [checkpoint] 记录每段结果，续跑时跳过已完成的段。
abstract class AsrProvider {
  ProviderInfo get info;

  /// [audioPath] 是流水线已经转好的 16kHz 单声道音频。
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
    RecognitionCheckpoint? checkpoint,
  });
}

/// 字幕翻译。
///
/// 按批调用：流水线把字幕切成每批 N 条交给实现者，实现者必须
/// **返回与输入等长的列表**，顺序一一对应。返回长度不符会被流水线视为失败并重试。
abstract class TranslationProvider {
  ProviderInfo get info;

  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  });
}
