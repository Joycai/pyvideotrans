import '../enum_by_name.dart';
import 'asr_transport.dart';
import 'model_params.dart';

/// 一个模型的完整声明：叫什么、怎么接、参数取什么值。
///
/// 以前模型只是一个名字，「怎么接」「能做什么」散在各处按名字前后缀去猜。
/// 现在这些都写在声明里，设置里存的、任务入队时冻结的、服务实现拿到的
/// 是同一份东西。
sealed class ModelSpec {
  const ModelSpec({required this.name, this.options = ModelOptions.none});

  /// 原样进请求体的模型名。空串表示「还没选模型」，由就绪检查拦住。
  final String name;

  final ModelOptions options;

  bool get isUnset => name.isEmpty;

  /// 这个模型有哪些可调参数。
  List<ModelParam> get params;

  ModelSpec withOptions(ModelOptions options);

  Map<String, Object?> toJson();

  /// 读存档。认不出来（不是对象、kind 未知、缺必填项）返回 null，
  /// 由调用方决定丢掉还是回落，这里绝不抛。
  static ModelSpec? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['kind']) {
      AsrModelSpec.kind => AsrModelSpec.fromJson(raw),
      ChatModelSpec.kind => ChatModelSpec.fromJson(raw),
      _ => null,
    };
  }
}

/// 识别模型的声明。
final class AsrModelSpec extends ModelSpec {
  const AsrModelSpec({
    required super.name,
    required this.transport,
    this.dialect,
    this.languages,
    super.options,
  }) : assert(
         identical(transport, AsrTransport.openaiTranscription) ==
             identical(dialect, null),
         '百炼的接入方式必须带报文族，OpenAI 转写接口不带',
       );

  /// 还没选模型时的占位声明。
  const AsrModelSpec.unset(AsrTransport transport)
    : this(
        name: '',
        transport: transport,
        dialect: identical(transport, AsrTransport.openaiTranscription)
            ? null
            : DashScopeDialect.qwen3Asr,
      );

  static const kind = 'asr';

  final AsrTransport transport;

  /// 百炼两种接入方式必填，其余为 null。
  final DashScopeDialect? dialect;

  /// 只支持这些语种（语言代码）；null 表示不限。
  ///
  /// 挂在声明上而不是能力表里：它是某个具体模型的事（只训了少数语种的
  /// 小模型），同一种接入方式下的别的模型不受限。
  final Set<String>? languages;

  AsrCapabilities get capabilities => AsrCapabilities.of(transport, dialect);

  @override
  List<ModelParam> get params => ModelParams.asr(transport, dialect);

  @override
  AsrModelSpec withOptions(ModelOptions options) => AsrModelSpec(
    name: name,
    transport: transport,
    dialect: dialect,
    languages: languages,
    options: options,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    'transport': transport.name,
    if (dialect != null) 'dialect': dialect!.name,
    if (languages != null) 'languages': languages!.toList(),
    if (!options.isEmpty) 'options': options.toJson(),
  };

  static AsrModelSpec? fromJson(Map<Object?, Object?> json) {
    final name = json['name'];
    final transport = AsrTransport.values.tryByName(json['transport']);
    // 接入方式认不出来（更新的版本写的）就没法分派，整条不要。
    if (name is! String || transport == null) return null;
    final dialect = transport.needsDialect
        // 报文族缺了或认不出来时按名字补，别让一条残缺的存档把界面弄崩。
        ? DashScopeDialect.values.tryByName(json['dialect']) ??
              _guessDialect(name, transport)
        : null;
    final languages = json['languages'];
    return AsrModelSpec(
      name: name.trim(),
      transport: transport,
      dialect: dialect,
      languages: languages is List ? languages.whereType<String>().toSet() : null,
      options: ModelOptions.fromJson(
        json['options'],
      ).sanitize(ModelParams.asr(transport, dialect)),
    );
  }

  /// 按模型名推断接入方式与报文族。
  ///
  /// **只用于两处**：读旧存档（那时模型只有名字），以及新增模型时给界面
  /// 预填一个建议。运行时任何地方都不调它 —— 任务跑的时候只看声明。
  ///
  /// 规则与重构前服务实现里的判断逐条一致，这样旧存档迁过来之后发出的
  /// 请求不变。[presets] 里有同名的直接用预置声明（带语种限制等信息）。
  static AsrModelSpec guessFromName(
    String name, {
    required Set<AsrTransport> transports,
    List<AsrModelSpec> presets = const [],
  }) {
    final trimmed = name.trim();
    for (final preset in presets) {
      if (preset.name == trimmed) return preset;
    }
    final transport = _guessTransport(trimmed, transports);
    return AsrModelSpec(
      name: trimmed,
      transport: transport,
      dialect: transport.needsDialect ? _guessDialect(trimmed, transport) : null,
    );
  }

  static AsrTransport _guessTransport(
    String name,
    Set<AsrTransport> transports,
  ) {
    if (transports.length == 1) return transports.first;
    final wanted = name.endsWith('-filetrans')
        ? AsrTransport.dashscopeFileTrans
        : AsrTransport.dashscopeSync;
    return transports.contains(wanted) ? wanted : transports.first;
  }

  /// 两种接入方式以前各有一套前缀判断，认不出来时的归属也不一样：
  /// 同步接口把不认识的当 Qwen3-ASR，录音文件转写把不认识的当
  /// Qwen-Audio 3.0。照原样保留，否则用户自填的模型迁移后报文会变。
  static DashScopeDialect _guessDialect(String name, AsrTransport transport) {
    if (transport == AsrTransport.dashscopeFileTrans) {
      if (name.startsWith('qwen3-asr')) return DashScopeDialect.qwen3Asr;
      if (name.startsWith('fun-asr')) return DashScopeDialect.funAsr;
      return DashScopeDialect.qwenAudio3;
    }
    if (name.startsWith('qwen-audio-3.0-asr-flash')) {
      return DashScopeDialect.qwenAudio3;
    }
    if (name.startsWith('fun-asr-flash')) return DashScopeDialect.funAsr;
    return DashScopeDialect.qwen3Asr;
  }

  @override
  bool operator ==(Object other) =>
      other is AsrModelSpec &&
      other.name == name &&
      other.transport == transport &&
      other.dialect == dialect &&
      _sameSet(other.languages, languages) &&
      other.options == options;

  @override
  int get hashCode => Object.hash(
    name,
    transport,
    dialect,
    languages == null ? null : Object.hashAllUnordered(languages!),
    options,
  );

  static bool _sameSet(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == b;
    return a.length == b.length && a.containsAll(b);
  }

  @override
  String toString() =>
      'AsrModelSpec($name, ${transport.name}'
      '${dialect == null ? '' : ', ${dialect!.name}'})';
}

/// 翻译（对话）模型的声明。所有翻译服务都说 OpenAI 对话协议，没有接入方式之分。
final class ChatModelSpec extends ModelSpec {
  const ChatModelSpec({required super.name, super.options});

  /// 还没选模型时的占位声明。
  static const unset = ChatModelSpec(name: '');

  static const kind = 'chat';

  @override
  List<ModelParam> get params => ModelParams.chat;

  @override
  ChatModelSpec withOptions(ModelOptions options) =>
      ChatModelSpec(name: name, options: options);

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    if (!options.isEmpty) 'options': options.toJson(),
  };

  static ChatModelSpec? fromJson(Map<Object?, Object?> json) {
    final name = json['name'];
    if (name is! String) return null;
    return ChatModelSpec(
      name: name.trim(),
      options: ModelOptions.fromJson(
        json['options'],
      ).sanitize(ModelParams.chat),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatModelSpec && other.name == name && other.options == options;

  @override
  int get hashCode => Object.hash(name, options);

  @override
  String toString() => 'ChatModelSpec($name)';
}
