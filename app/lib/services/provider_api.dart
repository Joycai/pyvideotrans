import '../domain/cue.dart';
import '../domain/recognition_checkpoint.dart';
import '../domain/task_control.dart';

// 接口签名里用到取消与进度类型，实现者只 import 这一个文件就够。
export '../domain/task_control.dart';

/// 连接参数。本地后端与在线服务用的是同一个结构 —— 这正是本地模型方案的前提：
/// 客户端只认 baseUrl + model，不关心对面跑在哪台机器上。
class Endpoint {
  const Endpoint({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.timeout = const Duration(minutes: 10),
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration timeout;

  /// 拼接路径，容忍 baseUrl 带不带结尾斜杠。
  Uri resolve(String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> get authHeaders =>
      apiKey.isEmpty ? const {} : {'Authorization': 'Bearer $apiKey'};
}

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
    this.supportsDiarization = false,
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

  /// 能按说话人分离（给每条字幕标说话人编号）。「新建转写」里只有支持的
  /// 服务才显示那个开关。
  final bool supportsDiarization;
}

/// 语音识别。
///
/// 实现者只需要把音频变成 [Cue] 列表；抽音、分段、重试由流水线负责。
/// 逐段识别的实现可以用 [checkpoint] 记录每段结果，续跑时跳过已完成的段。
abstract interface class AsrProvider {
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
abstract interface class TranslationProvider {
  ProviderInfo get info;

  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  });
}
