import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/enum_by_name.dart';
import '../domain/language.dart';
import '../domain/task_options.dart';
import '../domain/transcode/options.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';

/// 单个服务的连接配置。
class ProviderConfig {
  const ProviderConfig({this.baseUrl, this.model, this.apiKey});

  final String? baseUrl;

  /// 模型名。可以用逗号写多个（中英文逗号都认），第一个是默认值，
  /// 其余在「新建转写」「新建翻译」的模型下拉里可选。
  final String? model;
  final String? apiKey;

  /// [model] 拆成的列表：去空白、去空项、去重，保持书写顺序。
  List<String> get models => splitModels(model);

  /// 逗号分隔的模型名 → 列表。中英文逗号都认。
  static List<String> splitModels(String? raw) {
    if (raw == null) return const [];
    final seen = <String>{};
    return [
      for (final part in raw.split(RegExp(r'[,，]')))
        if (part.trim().isNotEmpty && seen.add(part.trim())) part.trim(),
    ];
  }

  ProviderConfig copyWith({String? baseUrl, String? model, String? apiKey}) =>
      ProviderConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );

  Map<String, Object?> toJson() => {
    if (baseUrl != null) 'baseUrl': baseUrl,
    if (model != null) 'model': model,
    if (apiKey != null) 'apiKey': apiKey,
  };

  factory ProviderConfig.fromJson(Map<String, Object?> json) => ProviderConfig(
    baseUrl: json['baseUrl'] as String?,
    model: json['model'] as String?,
    apiKey: json['apiKey'] as String?,
  );
}

/// 设置页上的分区，「恢复默认」按它分组作用。
enum SettingsGroup { appearance, asr, translation, language, defaults, output }

/// 应用设置。用 ChangeNotifier 让设置页与状态栏都跟着变。
///
/// 密钥目前存在 shared_preferences 里（明文）。生产环境应当换成系统钥匙串
/// （macOS Keychain / Windows Credential Manager），见 README 的「已知限制」。
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

  Map<String, ProviderConfig> _configs = {};

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings._(prefs);
    settings._configs = _readConfigs(prefs);
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
    _prefs.setInt(_kBatchSize, v.clamp(1, 100));
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
    _prefs.setInt(_kCjkLineLength, v.clamp(4, 60));
    notifyListeners();
  }

  int get latinLineLength => _prefs.getInt(_kLatinLineLength) ?? 40;
  set latinLineLength(int v) {
    _prefs.setInt(_kLatinLineLength, v.clamp(8, 120));
    notifyListeners();
  }

  /// 断句的字幕时长下限（毫秒）。短于它且紧跟上一条的并进上一条。
  int get minCueMs => _prefs.getInt(_kMinCueMs) ?? 500;
  set minCueMs(int v) {
    _prefs.setInt(_kMinCueMs, v.clamp(0, 3000));
    notifyListeners();
  }

  /// 断句的字幕时长上限（毫秒）。长于它的按标点拆开。
  int get maxCueMs => _prefs.getInt(_kMaxCueMs) ?? 10000;
  set maxCueMs(int v) {
    _prefs.setInt(_kMaxCueMs, v.clamp(2000, 60000));
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
  TaskOptions defaultTaskOptions() => TaskOptions(
    sourceLanguage: Languages.resolve(sourceLanguage),
    asrProviderId: asrProviderId,
    asrPrompt: asrPrompt,
    targetLanguage: Languages.resolve(targetLanguage),
    translationProviderId: translationProviderId,
    translationBatchSize: translationBatchSize,
    translationGuidance: translationGuidance,
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

  TaskOptions? _readLastOptions(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return TaskOptions.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
        fallback: defaultTaskOptions(),
      );
    } catch (_) {
      return null;
    }
  }

  void _writeLastOptions(String key, TaskOptions? v) {
    if (v == null) {
      _prefs.remove(key);
    } else {
      _prefs.setString(key, jsonEncode(v.toJson()));
    }
    // 不 notify：这份参数只被「上次参数」按钮读取，不影响任何常显内容。
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

  /// 全部恢复默认。「上次参数」不在其列 —— 它是历史记录，不是设置。
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

  /// 用户填的值优先，没填就用登记表里的默认值。
  /// 模型框里写了多个时，取第一个作为默认模型。
  Endpoint endpointFor(ProviderInfo info) {
    final config = configFor(info.id);
    return Endpoint(
      baseUrl: _firstNonEmpty(config.baseUrl, info.defaultBaseUrl) ?? '',
      model: _firstNonEmpty(config.models.firstOrNull, info.defaultModel) ?? '',
      apiKey: config.apiKey ?? '',
    );
  }

  /// 「新建转写」「新建翻译」模型下拉的候选：用户在设置里填的那串优先，
  /// 没填才用登记表里的常用列表。为空表示没有候选，只能手填。
  List<String> modelsFor(ProviderInfo info) {
    final own = configFor(info.id).models;
    return own.isNotEmpty ? own : info.models;
  }

  /// 配置是否足以发起请求。设置页用它来标注「未配置」。
  bool isConfigured(ProviderInfo info) {
    if (!info.implemented) return false;
    final endpoint = endpointFor(info);
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
