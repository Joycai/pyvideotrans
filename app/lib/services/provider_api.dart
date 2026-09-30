import '../domain/cue.dart';
import '../domain/providers/provider_info.dart';
import '../domain/recognition_checkpoint.dart';
import '../domain/task_control.dart';

// 接口签名里用到服务元信息、取消与进度类型，实现者只 import 这一个文件就够。
export '../domain/providers/provider_info.dart';
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
