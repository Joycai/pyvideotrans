import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/enum_by_name.dart';
import '../domain/glossary.dart';
import '../domain/language.dart';
import '../domain/mux/merge_options.dart';
import '../domain/providers/model_spec.dart';
import '../domain/providers/provider_catalog.dart';
import '../domain/task_options.dart';
import '../domain/transcode/options.dart';
import 'provider_api.dart';

/// 单个服务的连接配置。
class ProviderConfig {
  const ProviderConfig({
    this.baseUrl,
    this.apiKey,
    this.models = const [],
    this.legacyModelText,
  });

  final String? baseUrl;
  final String? apiKey;

  /// 用户给这家服务配的模型声明，第一个是默认。空表示没配过，
  /// 用 [legacyModelText]，再没有就用登记表的预置。
  final List<ModelSpec> models;

  /// 旧版本存的模型名：一串逗号分隔的文本（中英文逗号都认）。
  ///
  /// 只在 [models] 为空时有意义。留着原文而不是读的时候就转成声明：
  /// 转换要知道这家服务有哪些接入方式，这里不知道；而且不写盘就不会
  /// 把推断的结果固化下来。见 [AppSettings.asrModelsFor]。
  final String? legacyModelText;

  /// [legacyModelText] 拆成的名字列表。
  List<String> get legacyModelNames => _splitModels(legacyModelText);

  /// 逗号分隔的模型名 → 列表：去空白、去空项、去重，保持书写顺序。
  static List<String> _splitModels(String? raw) {
    if (raw == null) return const [];
    final seen = <String>{};
    return [
      for (final part in raw.split(RegExp(r'[,，]')))
        if (part.trim().isNotEmpty && seen.add(part.trim())) part.trim(),
    ];
  }

  ProviderConfig copyWith({
    String? baseUrl,
    String? apiKey,
    List<ModelSpec>? models,
    String? legacyModelText,
  }) => ProviderConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    models: models ?? this.models,
    legacyModelText: legacyModelText ?? this.legacyModelText,
  );

  Map<String, Object?> toJson() => {
    if (baseUrl != null) 'baseUrl': baseUrl,
    // 有了声明就只写声明；旧的那串文本到此为止。还没有声明时照旧写回去，
    // 否则用户只是改了一下密钥，以前填的模型名就丢了。
    if (models.isNotEmpty)
      'models': [for (final model in models) model.toJson()]
    else if (legacyModelText != null)
      'model': legacyModelText,
    if (apiKey != null) 'apiKey': apiKey,
  };

  factory ProviderConfig.fromJson(Map<String, Object?> json) {
    final models = json['models'];
    return ProviderConfig(
      baseUrl: json['baseUrl'] as String?,
      apiKey: json['apiKey'] as String?,
      // 读不出来的那一条丢掉，其余照常。
      models: List.unmodifiable([
        if (models is List)
          for (final model in models) ?ModelSpec.fromJson(model),
      ]),
      legacyModelText: json['model'] as String?,
    );
  }
}

/// 设置页上的分区，「恢复默认」按它分组作用。
enum SettingsGroup { appearance, asr, translation, language, defaults, output }

/// 应用设置。用 ChangeNotifier 让设置页与状态栏都跟着变。
///
/// 密钥目前存在 shared_preferences 里（明文）。生产环境应当换成系统钥匙串
/// （macOS Keychain / Windows Credential Manager），见 README 的「第一期没做的事」。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static const _kConfigs = 'providerConfigs';
  static const _kAsrId = 'asrProviderId';
  static const _kMtId = 'translationProviderId';
  static const _kSourceLang = 'sourceLanguage';
  static const _kTargetLang = 'targetLanguage';
  static const _kBatchSize = 'translationBatchSize';
  static const _kAsrPrompt = 'asrPrompt';
  static const _kGuidance = 'translationGuidance';
  static const _kThemeMode = 'themeMode';
  static const _kOutputDir = 'outputDir';
  static const _kCjkLineLength = 'cjkLineLength';
  static const _kLatinLineLength = 'latinLineLength';
  static const _kMinCueMs = 'minCueMs';
  static const _kMaxCueMs = 'maxCueMs';
  static const _kOutputFormat = 'outputFormat';
  static const _kBilingual = 'bilingualLayout';
  static const _kLastTranscribe = 'lastTranscribeOptions';
  static const _kLastTranslate = 'lastTranslateOptions';
  static const _kLastTranscode = 'lastTranscodeOptions';
  static const _kLastMerge = 'lastMergeOptions';
  static const _kGlossaries = 'glossaries';

  Map<String, ProviderConfig> _configs = {};
  List<Glossary> _glossaries = const [];

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings._(prefs);
    settings._configs = _readConfigs(prefs);
    settings._glossaries = _readGlossaries(prefs);
    return settings;
  }

  static Map<String, ProviderConfig> _readConfigs(SharedPreferences prefs) {
    final raw = prefs.getString(_kConfigs);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final entry in decoded.entries)
          entry.key: ProviderConfig.fromJson(
            entry.value! as Map<String, Object?>,
          ),
      };
    } catch (_) {
      // 配置损坏时宁可回到默认值，也不要让应用起不来。
      return {};
    }
  }

  static List<Glossary> _readGlossaries(SharedPreferences prefs) {
    final raw = prefs.getString(_kGlossaries);
    if (raw == null) return const [];
    try {
      final seen = <String>{};
      return List.unmodifiable([
        for (final item in jsonDecode(raw) as List)
          // 读不出来的那一份丢掉，其余照常；id 撞了的只留前一份。
          if (Glossary.fromJson(item) case final glossary?
              when seen.add(glossary.id))
            glossary,
      ]);
    } catch (_) {
      return const [];
    }
  }

  String get asrProviderId => _prefs.getString(_kAsrId) ?? 'openai';
  set asrProviderId(String v) => _write(_kAsrId, v);

  String get translationProviderId => _prefs.getString(_kMtId) ?? 'deepseek';
  set translationProviderId(String v) => _write(_kMtId, v);

  String get sourceLanguage => _prefs.getString(_kSourceLang) ?? 'auto';
  set sourceLanguage(String v) => _write(_kSourceLang, v);

  String get targetLanguage => _prefs.getString(_kTargetLang) ?? '英文';
  set targetLanguage(String v) => _write(_kTargetLang, v);

  /// 每批送给模型的字幕条数。太大容易丢条，太小费 token。
  int get translationBatchSize => _prefs.getInt(_kBatchSize) ?? 20;
  set translationBatchSize(int v) {
    _prefs.setInt(_kBatchSize, TaskOptions.batchSizeRange.clamp(v));
    notifyListeners();
  }

  String get asrPrompt => _prefs.getString(_kAsrPrompt) ?? '';
  set asrPrompt(String v) => _write(_kAsrPrompt, v);

  String get translationGuidance => _prefs.getString(_kGuidance) ?? '';
  set translationGuidance(String v) => _write(_kGuidance, v);

  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  set themeMode(String v) => _write(_kThemeMode, v);

  String? get outputDir => _prefs.getString(_kOutputDir);
  set outputDir(String? v) {
    if (v == null) {
      _prefs.remove(_kOutputDir);
    } else {
      _prefs.setString(_kOutputDir, v);
    }
    notifyListeners();
  }

  /// 单行字数上限。默认值沿用原 Python 实现：中日韩 15、其他 40。
  int get cjkLineLength => _prefs.getInt(_kCjkLineLength) ?? 15;
  set cjkLineLength(int v) {
    _prefs.setInt(_kCjkLineLength, TaskOptions.cjkLineLengthRange.clamp(v));
    notifyListeners();
  }

  int get latinLineLength => _prefs.getInt(_kLatinLineLength) ?? 40;
  set latinLineLength(int v) {
    _prefs.setInt(_kLatinLineLength, TaskOptions.latinLineLengthRange.clamp(v));
    notifyListeners();
  }

  /// 断句的字幕时长下限（毫秒）。短于它且紧跟上一条的并进上一条。
  int get minCueMs => _prefs.getInt(_kMinCueMs) ?? 500;
  set minCueMs(int v) {
    _prefs.setInt(_kMinCueMs, TaskOptions.minCueMsRange.clamp(v));
    notifyListeners();
  }

  /// 断句的字幕时长上限（毫秒）。长于它的按标点拆开。
  int get maxCueMs => _prefs.getInt(_kMaxCueMs) ?? 10000;
  set maxCueMs(int v) {
    _prefs.setInt(_kMaxCueMs, TaskOptions.maxCueMsRange.clamp(v));
    notifyListeners();
  }

  SubtitleFormat get outputFormat =>
      SubtitleFormat.byExtension(_prefs.getString(_kOutputFormat) ?? 'srt');
  set outputFormat(SubtitleFormat v) => _write(_kOutputFormat, v.extension);

  BilingualLayout get bilingual =>
      BilingualLayout.values.tryByName(_prefs.getString(_kBilingual)?.trim()) ??
      BilingualLayout.targetOnly;
  set bilingual(BilingualLayout v) => _write(_kBilingual, v.name);

  /// 「新建转写」「新建翻译」打开时的默认参数。用户在对话框里改动的是这份拷贝，
  /// 全局设置不会被顺手改掉。
  ///
  /// 默认启用的词表在这里就展开成条目：有的调用方不经过建任务表单，拿到
  /// 这份参数就直接用（拖进来直接入队、编辑器里的本地字幕文件）。
  TaskOptions defaultTaskOptions() {
    final glossaryIds = defaultGlossaryIds;
    return TaskOptions(
      sourceLanguage: Languages.resolve(sourceLanguage),
      asrProviderId: asrProviderId,
      asrModel: defaultAsrModelOf(asrProviderId),
      asrPrompt: asrPrompt,
      targetLanguage: Languages.resolve(targetLanguage),
      translationProviderId: translationProviderId,
      translationModel: defaultChatModelOf(translationProviderId),
      translationBatchSize: translationBatchSize,
      translationGuidance: translationGuidance,
      glossaryIds: glossaryIds,
      glossary: glossaryEntries(glossaryIds),
      bilingual: bilingual,
      cjkLineLength: cjkLineLength,
      latinLineLength: latinLineLength,
      minCueMs: minCueMs,
      maxCueMs: maxCueMs,
      format: outputFormat,
      outputLocation: outputDir == null
          ? OutputLocation.besideSource
          : OutputLocation.custom,
      outputDir: outputDir,
    );
  }

  /// 最近一次成功提交的「新建转写」参数，供页面上的「上次参数」整份填回。
  /// 只留最近一份；没有或存档损坏时为 null。
  TaskOptions? get lastTranscribeOptions => _readLastOptions(_kLastTranscribe);

  set lastTranscribeOptions(TaskOptions? v) =>
      _writeLastOptions(_kLastTranscribe, v);

  /// 最近一次成功提交的「翻译」参数。与转写分开存：两边的语言方向、
  /// 服务与排版习惯往往不同，共用一份会互相覆盖。
  TaskOptions? get lastTranslateOptions => _readLastOptions(_kLastTranslate);

  set lastTranslateOptions(TaskOptions? v) =>
      _writeLastOptions(_kLastTranslate, v);

  /// 最近一次成功提交的「转码」参数（含当时所选编码器的参数值）。
  TranscodeOptions? get lastTranscodeOptions {
    final raw = _prefs.getString(_kLastTranscode);
    if (raw == null) return null;
    try {
      return TranscodeOptions.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  set lastTranscodeOptions(TranscodeOptions? v) {
    if (v == null) {
      _prefs.remove(_kLastTranscode);
    } else {
      _prefs.setString(_kLastTranscode, jsonEncode(v.toJson()));
    }
  }

  /// 最近一次成功提交的「合并」参数：只有容器与三个开关，段与输出位置不记
  /// （下一批的第 1 段决定默认位置与文件名）。
  MergeOptions? get lastMergeOptions {
    final raw = _prefs.getString(_kLastMerge);
    if (raw == null) return null;
    try {
      return MergeOptions.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  set lastMergeOptions(MergeOptions? v) {
    if (v == null) {
      _prefs.remove(_kLastMerge);
    } else {
      _prefs.setString(
        _kLastMerge,
        jsonEncode(
          MergeOptions(
            container: v.container,
            chapters: v.chapters,
            embedSubtitles: v.embedSubtitles,
            sidecarSubtitles: v.sidecarSubtitles,
          ).toJson(),
        ),
      );
    }
  }

  TaskOptions? _readLastOptions(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return TaskOptions.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
        fallback: defaultTaskOptions(),
        defaultModels: defaultModels,
      );
    } catch (_) {
      return null;
    }
  }

  void _writeLastOptions(String key, TaskOptions? v) {
    if (v == null) {
      _prefs.remove(key);
    } else {
      // 只记勾选了哪几份词表，不把条目也存进偏好：整份词表已经在
      // [glossaries] 里了，再提交时按勾选重新展开。
      _prefs.setString(
        key,
        jsonEncode(v.copyWith(glossary: const []).toJson()),
      );
    }
    // 不 notify：这份参数只被「上次参数」按钮读取，不影响任何常显内容。
  }

  /// 用户建的词表，按建立的先后排。
  ///
  /// 词表是用户数据，不是设置：[reset] / [resetAll] 都不动它，和「上次参数」
  /// 同类 —— 攒了几百条的词表不该因为「恢复默认」没了。
  List<Glossary> get glossaries => _glossaries;

  /// 新建任务时默认勾上的那几份。
  List<String> get defaultGlossaryIds => [
    for (final glossary in _glossaries)
      if (glossary.enabledByDefault) glossary.id,
  ];

  /// 存一份词表：id 已有的就地换掉（位置不变），没有的加在末尾。
  void setGlossary(Glossary glossary) {
    final cleaned = glossary.normalized();
    final at = _glossaries.indexWhere((g) => g.id == cleaned.id);
    _writeGlossaries([
      for (final (i, existing) in _glossaries.indexed)
        i == at ? cleaned : existing,
      if (at < 0) cleaned,
    ]);
  }

  void removeGlossary(String id) {
    if (!_glossaries.any((g) => g.id == id)) return;
    _writeGlossaries([
      for (final glossary in _glossaries)
        if (glossary.id != id) glossary,
    ]);
  }

  /// 把勾选的几份词表展开成一份条目，给任务入队时冻结用。
  ///
  /// 顺序跟着 [glossaries]，不跟着 [ids]：勾选的先后不该改变发出去的提示词。
  /// 同一个原文在两份词表里都有时留排在前面那份的译法；已经删掉的 id 跳过。
  List<GlossaryEntry> glossaryEntries(Iterable<String> ids) {
    final wanted = ids.toSet();
    return GlossaryText.clean([
      for (final glossary in _glossaries)
        if (wanted.contains(glossary.id)) ...glossary.entries,
    ]);
  }

  void _writeGlossaries(List<Glossary> glossaries) {
    _glossaries = List.unmodifiable(glossaries);
    _prefs.setString(
      _kGlossaries,
      jsonEncode([for (final glossary in _glossaries) glossary.toJson()]),
    );
    notifyListeners();
  }

  /// 把一组设置恢复成默认值。
  ///
  /// 「恢复默认」按分区作用：用户来设置页多半只想重置某一块（比如把识别
  /// 服务的地址改坏了），整份清空会把翻译密钥也一起抹掉。
  void reset(
    SettingsGroup group, {
    Iterable<String> providerIds = const [],
  }) {
    switch (group) {
      case SettingsGroup.appearance:
        _prefs.remove(_kThemeMode);
      case SettingsGroup.asr:
        _prefs.remove(_kAsrId);
        _prefs.remove(_kAsrPrompt);
        _removeConfigs(providerIds);
      case SettingsGroup.translation:
        _prefs.remove(_kMtId);
        _prefs.remove(_kBatchSize);
        _prefs.remove(_kGuidance);
        _removeConfigs(providerIds);
      case SettingsGroup.language:
        _prefs.remove(_kSourceLang);
        _prefs.remove(_kTargetLang);
      case SettingsGroup.defaults:
        _prefs.remove(_kOutputFormat);
        _prefs.remove(_kBilingual);
        _prefs.remove(_kCjkLineLength);
        _prefs.remove(_kLatinLineLength);
      case SettingsGroup.output:
        _prefs.remove(_kOutputDir);
    }
    notifyListeners();
  }

  /// 全部恢复默认。「上次参数」不在其列 —— 它是历史记录，不是设置；
  /// 词表也不在其列，见 [glossaries]。
  void resetAll({
    Iterable<String> asrProviderIds = const [],
    Iterable<String> translationProviderIds = const [],
  }) {
    for (final group in SettingsGroup.values) {
      reset(
        group,
        providerIds: switch (group) {
          SettingsGroup.asr => asrProviderIds,
          SettingsGroup.translation => translationProviderIds,
          _ => const [],
        },
      );
    }
  }

  void _removeConfigs(Iterable<String> providerIds) {
    final ids = providerIds.toSet();
    _configs = {
      for (final e in _configs.entries)
        if (!ids.contains(e.key)) e.key: e.value,
    };
    _prefs.setString(
      _kConfigs,
      jsonEncode({for (final e in _configs.entries) e.key: e.value.toJson()}),
    );
  }

  ProviderConfig configFor(String providerId) =>
      _configs[providerId] ?? const ProviderConfig();

  void setConfig(String providerId, ProviderConfig config) {
    _configs = {..._configs, providerId: config};
    _prefs.setString(
      _kConfigs,
      jsonEncode({for (final e in _configs.entries) e.key: e.value.toJson()}),
    );
    notifyListeners();
  }

  /// 这家识别服务可选的模型声明，第一个是默认。
  ///
  /// 三层来源，前面的有就不看后面的：用户配的声明 → 旧版本存的那串模型名
  /// （逐个按名字补成声明）→ 登记表的预置。旧存档是**读的时候**补，不写盘：
  /// 升级后什么都不碰的用户，发出去的请求与升级前一样。
  List<AsrModelSpec> asrModelsFor(AsrProviderInfo info) {
    final config = configFor(info.id);
    final own = config.models.whereType<AsrModelSpec>().toList();
    if (own.isNotEmpty) return own;
    final legacy = config.legacyModelNames;
    if (legacy.isNotEmpty) return [for (final name in legacy) info.guess(name)];
    return info.presets;
  }

  /// 这家翻译服务可选的模型声明，规则同 [asrModelsFor]。
  List<ChatModelSpec> chatModelsFor(ChatProviderInfo info) {
    final config = configFor(info.id);
    final own = config.models.whereType<ChatModelSpec>().toList();
    if (own.isNotEmpty) return own;
    final legacy = config.legacyModelNames;
    if (legacy.isNotEmpty) return [for (final name in legacy) info.guess(name)];
    return info.presets;
  }

  /// 默认模型：列表里的第一个。一个都没有时是空名的占位。
  AsrModelSpec defaultAsrModel(AsrProviderInfo info) =>
      asrModelsFor(info).firstOrNull ?? info.unsetModel;

  ChatModelSpec defaultChatModel(ChatProviderInfo info) =>
      chatModelsFor(info).firstOrNull ?? ChatModelSpec.unset;

  ModelSpec defaultModel(ProviderInfo info) => switch (info) {
    AsrProviderInfo() => defaultAsrModel(info),
    ChatProviderInfo() => defaultChatModel(info),
  };

  /// 不分识别还是翻译的候选列表，给两边共用的界面零件用。
  List<ModelSpec> modelChoices(ProviderInfo info) => switch (info) {
    AsrProviderInfo() => asrModelsFor(info),
    ChatProviderInfo() => chatModelsFor(info),
  };

  /// 按服务 id 取默认模型。服务不认识时是空名的占位，不抛 —— 旧存档、
  /// 手改过的偏好里可能有登记表里已经没有的 id，由就绪检查去说。
  AsrModelSpec defaultAsrModelOf(String providerId) {
    final info = ProviderCatalog.asrInfo(providerId);
    return info == null
        ? ProviderCatalog.defaultAsrSpec(providerId)
        : defaultAsrModel(info);
  }

  ChatModelSpec defaultChatModelOf(String providerId) {
    final info = ProviderCatalog.translationInfo(providerId);
    return info == null
        ? ProviderCatalog.defaultChatSpec(providerId)
        : defaultChatModel(info);
  }

  /// 读旧存档时用：没写模型的旧任务，跑的是设置里给那家服务配的模型。
  DefaultModels get defaultModels =>
      (asr: defaultAsrModelOf, chat: defaultChatModelOf);

  /// 这家服务有没有用户自己配的模型（声明，或旧版本那串模型名）。
  /// 没有时候选来自登记表的预置。
  bool hasOwnModels(String providerId) {
    final config = configFor(providerId);
    return config.models.isNotEmpty || config.legacyModelNames.isNotEmpty;
  }

  /// 存这家服务的模型列表。存过之后旧版本那串模型名就不再用了。
  void setModels(String providerId, List<ModelSpec> models) {
    final config = configFor(providerId);
    setConfig(
      providerId,
      ProviderConfig(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        models: List.unmodifiable(models),
      ),
    );
  }

  /// 发请求用的连接参数：地址与密钥取用户填的，没填地址就用登记表的默认；
  /// 模型名取 [model] 的。
  Endpoint endpointFor(ProviderInfo info, ModelSpec model) {
    final config = configFor(info.id);
    return Endpoint(
      baseUrl: _firstNonEmpty(config.baseUrl, info.defaultBaseUrl) ?? '',
      model: model.name,
      apiKey: config.apiKey ?? '',
    );
  }

  /// 配置是否足以发起请求。设置页用它来标注「未配置」。
  bool isConfigured(ProviderInfo info) {
    if (!info.implemented) return false;
    final endpoint = endpointFor(info, defaultModel(info));
    if (endpoint.baseUrl.isEmpty || endpoint.model.isEmpty) return false;
    return !info.needsApiKey || endpoint.apiKey.isNotEmpty;
  }

  void _write(String key, String value) {
    _prefs.setString(key, value);
    notifyListeners();
  }

  static String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return null;
  }
}
