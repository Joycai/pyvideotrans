import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'openai_compatible.dart';
import 'provider_api.dart';

/// 单个服务的连接配置。
class ProviderConfig {
  const ProviderConfig({this.baseUrl, this.model, this.apiKey});

  final String? baseUrl;
  final String? model;
  final String? apiKey;

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

  String get translationProviderId =>
      _prefs.getString(_kMtId) ?? 'deepseek';
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

  ProviderConfig configFor(String providerId) =>
      _configs[providerId] ?? const ProviderConfig();

  void setConfig(String providerId, ProviderConfig config) {
    _configs = {..._configs, providerId: config};
    _prefs.setString(
      _kConfigs,
      jsonEncode({
        for (final e in _configs.entries) e.key: e.value.toJson(),
      }),
    );
    notifyListeners();
  }

  /// 用户填的值优先，没填就用登记表里的默认值。
  Endpoint endpointFor(ProviderInfo info) {
    final config = configFor(info.id);
    return Endpoint(
      baseUrl: _firstNonEmpty(config.baseUrl, info.defaultBaseUrl) ?? '',
      model: _firstNonEmpty(config.model, info.defaultModel) ?? '',
      apiKey: config.apiKey ?? '',
    );
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
