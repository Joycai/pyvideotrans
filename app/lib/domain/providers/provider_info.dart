import 'asr_transport.dart';
import 'model_spec.dart';

/// 一家服务的元信息：设置页、服务下拉、任务列表的「服务 / 模型」列都读它。
///
/// 是 domain 里的只读数据而不是 services 里的东西：设置层要查它取默认模型，
/// 任务参数读旧存档时也要查它，它们都不该为此依赖服务实现。
sealed class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.vendor,
    this.runsLocally = false,
    this.implemented = true,
    this.needsApiKey = true,
    this.defaultBaseUrl,
  });

  /// 注册 id，任务里存的就是它。
  final String id;

  /// 界面显示名：「OpenAI · whisper-1」里的后半段由模型提供。
  final String name;
  final String vendor;

  /// 在用户机器上跑（本地后端 / Ollama）。只影响图标与状态栏，不影响调用链路。
  final bool runsLocally;

  /// 第一期是否已实施。未实施的在设置页里灰显并标注。
  final bool implemented;

  final bool needsApiKey;
  final String? defaultBaseUrl;

  /// 随软件发布的常用模型。第一个是用户什么都没配时的默认模型；
  /// 为空表示只能自己填（自定义接口）。
  List<ModelSpec> get presets;

  // ——— 过渡：下面三个是重构前的字段，现在由 [presets] 派生。————————
  // 界面与设置层改用模型声明之后删掉（见任务参数冻结模型声明的那次提交）。

  String? get defaultModel => presets.firstOrNull?.name;

  List<String> get models => [for (final p in presets) p.name];

  bool get supportsDiarization => false;
}

/// 识别服务。
final class AsrProviderInfo extends ProviderInfo {
  const AsrProviderInfo({
    required super.id,
    required super.name,
    required super.vendor,
    super.runsLocally,
    super.implemented,
    super.needsApiKey,
    super.defaultBaseUrl,
    this.transports = const {AsrTransport.openaiTranscription},
    this.presets = const [],
  });

  /// 这家服务的模型可以怎么接。绝大多数只有一种；只有一种时界面上
  /// 不出现任何接入方式的控件，用户不必知道有这回事。
  final Set<AsrTransport> transports;

  @override
  final List<AsrModelSpec> presets;

  /// 模型之间接法不同，新增模型时要让用户声明。
  bool get multiTransport => transports.length > 1;

  /// 还没选模型时的占位声明。
  AsrModelSpec get unsetModel => AsrModelSpec.unset(transports.first);

  /// 只有名字时补出一份声明：预置里有同名的用预置，否则按名字推断。
  /// 只给读旧存档、新增模型时预填用。
  AsrModelSpec guess(String name) => AsrModelSpec.guessFromName(
    name,
    transports: transports,
    presets: presets,
  );

  @override
  bool get supportsDiarization =>
      presets.any((p) => p.capabilities.diarization);
}

/// 翻译服务。都说 OpenAI 对话协议。
final class ChatProviderInfo extends ProviderInfo {
  const ChatProviderInfo({
    required super.id,
    required super.name,
    required super.vendor,
    super.runsLocally,
    super.implemented,
    super.needsApiKey,
    super.defaultBaseUrl,
    this.presets = const [],
  });

  @override
  final List<ChatModelSpec> presets;

  /// 只有名字时补出一份声明：预置里有同名的用预置。
  ChatModelSpec guess(String name) {
    final trimmed = name.trim();
    for (final preset in presets) {
      if (preset.name == trimmed) return preset;
    }
    return ChatModelSpec(name: trimmed);
  }
}
