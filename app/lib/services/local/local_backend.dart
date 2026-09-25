import '../openai_compatible.dart';
import '../provider_api.dart';
import '../registry.dart';
import '../settings.dart';

/// 本地模型后端的客户端。**第一期不实施**，这里只把位置留好。
///
/// 方案（见 docs/local-backend.md）：本地模型跑在一个独立的 Python 进程里，
/// 对外暴露 **OpenAI 兼容**接口。因此客户端这边不需要任何新代码 ——
/// [OpenAiCompatibleAsrProvider] 和 [OpenAiCompatibleTranslationProvider]
/// 把 baseUrl 指向 `http://127.0.0.1:8765/v1` 就能直接驱动它。
///
/// 这个类只负责 OpenAI 协议之外的事：进程发现、健康检查、模型下载进度。
/// 启用时要做的事仅仅是：
///   1. 把 `Registry` 里 `local_backend` / `local_backend_chat` 的
///      `implemented` 改成 true；
///   2. 实现下面这几个方法。
/// 流水线、进度、断点续跑、取消、日志、错误处理全部不动。
class LocalBackend {
  const LocalBackend({required this.settings});

  final AppSettings settings;

  static const asrProviderId = 'local_backend';
  static const translationProviderId = 'local_backend_chat';

  /// 后端的服务地址。与在线服务走同一套配置存储。
  Endpoint get endpoint {
    final info = Registry.asrInfo(asrProviderId)!;
    return settings.endpointFor(info);
  }

  /// 第一期恒为 false。
  bool get implemented =>
      Registry.asrInfo(asrProviderId)?.implemented ?? false;

  /// GET {baseUrl}/local/health
  Future<LocalBackendHealth> checkHealth() async =>
      throw const ActionableException(
        '本地模型服务尚未实施',
        hint: '第一期只对接在线 API。方案见 docs/local-backend.md。',
      );

  /// GET {baseUrl}/local/models
  Future<List<LocalModel>> listModels() async =>
      throw const ActionableException(
        '本地模型服务尚未实施',
        hint: '第一期只对接在线 API。方案见 docs/local-backend.md。',
      );

  /// POST {baseUrl}/local/models/{id}/download —— 流式返回下载进度。
  Stream<double> downloadModel(String modelId) =>
      Stream.error(
        const ActionableException(
          '本地模型服务尚未实施',
          hint: '第一期只对接在线 API。方案见 docs/local-backend.md。',
        ),
      );
}

/// `GET /local/health` 的响应形状。
class LocalBackendHealth {
  const LocalBackendHealth({
    required this.running,
    this.gpu,
    this.vramUsedMb,
    this.vramTotalMb,
  });

  final bool running;
  final String? gpu;
  final int? vramUsedMb;
  final int? vramTotalMb;

  static const offline = LocalBackendHealth(running: false);
}

/// `GET /local/models` 里的一项。
class LocalModel {
  const LocalModel({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.installed,
    this.sha256,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final bool installed;

  /// 校验和。原 Python 实现里「模型文件校验不通过」是最常见的本地故障，
  /// 后端应当在下载后自行校验并把结果如实报上来。
  final String? sha256;
}
