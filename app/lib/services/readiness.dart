import '../domain/language.dart';
import '../domain/providers/model_spec.dart';
import '../domain/providers/provider_catalog.dart';
import 'provider_api.dart';
import 'settings.dart';

/// 一项检查的严重程度。
enum ReadinessLevel {
  /// 可以直接开始。
  ready,

  /// 提醒一句，但不拦着 —— 比如所选模型对这个语种支持有限。
  advisory,

  /// 现在开始一定会失败，必须先解决。
  blocked,
}

/// 「这个服务现在能用吗」的答复。
///
/// 原 Python 实现遇到没配密钥时直接弹出该渠道的设置窗，把用户从当前流程里
/// 拽走；语言不匹配时则只在日志行写一句。这里把两种情况统一成同一个结构，
/// 由界面决定是拦住还是提示。
class Readiness {
  const Readiness(this.level, {this.message = '', this.hint});

  final ReadinessLevel level;

  /// 一句话说清楚状况，可直接显示。
  final String message;

  /// 建议用户做什么。
  final String? hint;

  bool get isBlocked => level == ReadinessLevel.blocked;
  bool get isReady => level == ReadinessLevel.ready;

  static const ok = Readiness(ReadinessLevel.ready, message: '已配置');
}

/// 服务可用性检查。界面拿它决定「开始转写」是否可点、状态行显示什么。
abstract final class ProviderReadiness {
  /// 识别服务。[language] 为 null 或 auto 时跳过语种检查；[model] 不给就
  /// 查这家服务的默认模型。
  static Readiness asr(
    String id,
    AppSettings settings, {
    Language? language,
    AsrModelSpec? model,
    bool diarize = false,
  }) {
    final info = ProviderCatalog.asrInfo(id);
    if (info == null) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '未知的识别服务：$id',
        hint: '重新选择一个识别服务。',
      );
    }
    final chosen = model ?? settings.defaultAsrModel(info);
    final basic = _checkEndpoint(info, settings, chosen);
    if (basic != null) return basic;
    // 声明与服务对不上（存档被手改过、登记表换过接法）：建实例时会报错，
    // 在这里先拦住，别让任务排到了才失败。
    if (!info.transports.contains(chosen.transport) ||
        (chosen.transport.needsDialect && chosen.dialect == null)) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}不能按现在的声明接入 ${chosen.name}',
        hint: '重新选一个模型；要用这个名字，去设置里删掉它，再按正确的接入方式添加。',
      );
    }

    final unsupported = _languageNote(chosen, language);
    if (unsupported != null) {
      return Readiness(
        ReadinessLevel.advisory,
        message: unsupported,
        hint: '换一个模型，或把源语言留给「自动检测」。',
      );
    }
    // 转写表单会在模型换成不能分离的那一刻把开关关掉，从表单走不到这里；
    // 留着是防别的来路（手改的存档、以后不经表单的入队）。
    if (diarize && !chosen.capabilities.diarization) {
      // 能不能分离看模型声明的能力表，不看名字。推荐的得是用户在下拉里
      // 选得到的：先看这家服务现在的候选，没有再看登记表预置里有没有
      // （有就说去设置里加上）；预置里也没有，说明这家服务整个做不了。
      bool capable(AsrModelSpec m) => m.capabilities.diarization;
      final offered = settings.asrModelsFor(info).where(capable).firstOrNull;
      if (offered != null) {
        return Readiness(
          ReadinessLevel.advisory,
          message: '${chosen.name} 不支持说话人分离',
          hint: '换 ${offered.name}（${offered.transport.label}）。',
        );
      }
      final preset = info.presets.where(capable).firstOrNull;
      if (preset != null) {
        return Readiness(
          ReadinessLevel.advisory,
          message: '${chosen.name} 不支持说话人分离',
          hint:
              '去设置里把 ${preset.name}（${preset.transport.label}）'
              '加进模型列表，再换过去。',
        );
      }
      return Readiness(
        ReadinessLevel.advisory,
        message: '${info.name}不支持说话人分离',
        hint: '这一项会被忽略；需要分离请改用${_diarizingService ?? '支持分离的服务'}。',
      );
    }
    return Readiness.ok;
  }

  /// 登记表里第一家有模型能分离说话人的服务，给「改用哪家」的提示用。
  static String? get _diarizingService => ProviderCatalog.asr
      .where((info) => info.presets.any((p) => p.capabilities.diarization))
      .firstOrNull
      ?.name;

  /// 翻译服务。[model] 不给就查这家服务的默认模型。
  static Readiness translation(
    String id,
    AppSettings settings, {
    ChatModelSpec? model,
  }) {
    final info = ProviderCatalog.translationInfo(id);
    if (info == null) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '未知的翻译服务：$id',
        hint: '重新选择一个翻译服务。',
      );
    }
    return _checkEndpoint(
          info,
          settings,
          model ?? settings.defaultChatModel(info),
        ) ??
        Readiness.ok;
  }

  /// 未实施 / 缺地址 / 缺模型 / 缺密钥 —— 几种一定跑不起来的情况。
  static Readiness? _checkEndpoint(
    ProviderInfo info,
    AppSettings settings,
    ModelSpec model,
  ) {
    if (!info.implemented) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}尚未实施',
        hint: info.runsLocally ? '本地模型服务是第二期内容，先选一个在线服务。' : '先选一个已实施的服务。',
      );
    }
    final endpoint = settings.endpointFor(info, model);
    if (endpoint.baseUrl.trim().isEmpty) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}未填服务地址',
        hint: '去设置里填入 baseUrl 后可开始。',
      );
    }
    if (model.isUnset) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}未选择模型',
        hint: '选一个模型，或去设置里添加。',
      );
    }
    if (info.needsApiKey && endpoint.apiKey.trim().isEmpty) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}未配置密钥',
        hint: '去设置里填入 API Key 后可开始。',
      );
    }
    return null;
  }

  /// 模型对这个语种的支持有限时给一句提示。
  ///
  /// Whisper 系列号称支持全部语种，不必检查；真正会翻车的是那些只训了
  /// 少数语种的小模型 —— 原实现在 `recognition/__init__.py` 的
  /// `is_allow_lang` 里做同样的事。支持哪些语种写在模型声明里。
  static String? _languageNote(AsrModelSpec model, Language? language) {
    if (language == null || language.isAuto) return null;
    final supported = model.languages;
    if (supported == null || supported.contains(language.code)) return null;
    return '${model.name} 对${language.name}的支持有限';
  }
}
