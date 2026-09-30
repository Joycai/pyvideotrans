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

  /// 只有名字时补出一份声明：预置里有同名的用预置，否则按名字推断。
  /// 只给读旧存档、手填模型名时用；任务跑的时候只看声明。
  ModelSpec guess(String name);
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

  @override
  AsrModelSpec guess(String name) => AsrModelSpec.guessFromName(
    name,
    transports: transports,
    presets: presets,
  );

  /// 用户在设置里添加模型时写下的声明。
  ///
  /// 只有一种接入方式的服务不用声明什么，[transport] 不给，结果就是
  /// [guess]。多接入方式的服务由用户选定接入方式与报文族：与按名字补出
  /// 来的一致时用那一份（预置带着语种限制这类信息），不一致时以用户选的
  /// 为准 —— 名字只是建议，怎么接用户说了算。
  AsrModelSpec declare(
    String name, {
    AsrTransport? transport,
    DashScopeDialect? dialect,
  }) {
    final guessed = guess(name);
    if (transport == null || !transports.contains(transport)) return guessed;
    final declared = transport.needsDialect
        ? dialect ?? guessed.dialect ?? DashScopeDialect.qwen3Asr
        : null;
    if (guessed.transport == transport && guessed.dialect == declared) {
      return guessed;
    }
    return AsrModelSpec(
      name: guessed.name,
      transport: transport,
      dialect: declared,
    );
  }
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

  @override
  ChatModelSpec guess(String name) {
    final trimmed = name.trim();
    for (final preset in presets) {
      if (preset.name == trimmed) return preset;
    }
    return ChatModelSpec(name: trimmed);
  }
}
