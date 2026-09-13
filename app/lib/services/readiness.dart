import '../domain/language.dart';
import 'provider_api.dart';
import 'registry.dart';
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
  /// 识别服务。[language] 为 null 或 auto 时跳过语种检查。
  static Readiness asr(
    String id,
    AppSettings settings, {
    Language? language,
    String? model,
    bool diarize = false,
  }) {
    final info = Registry.asrInfo(id);
    if (info == null) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '未知的识别服务：$id',
        hint: '重新选择一个识别服务。',
      );
    }
    final basic = _checkEndpoint(info, settings, model: model);
    if (basic != null) return basic;

    final chosen = model ?? settings.endpointFor(info).model;
    final unsupported = _languageNote(info.id, chosen, language);
    if (unsupported != null) {
      return Readiness(
        ReadinessLevel.advisory,
        message: unsupported,
        hint: '换一个模型，或把源语言留给「自动检测」。',
      );
    }
    if (diarize) {
      if (!info.supportsDiarization) {
        return Readiness(
          ReadinessLevel.advisory,
          message: '${info.name}不支持说话人分离',
          hint: '这一项会被忽略；需要分离请改用阿里百炼 · Qwen3-ASR。',
        );
      }
      // 实测：同步接口忽略 diarization_enabled，只有录音文件转写
      // （-filetrans）真会给说话人编号；qwen3 族在文档里就不支持。
      if (!chosen.endsWith('-filetrans') || chosen.startsWith('qwen3-asr')) {
        return Readiness(
          ReadinessLevel.advisory,
          message: '$chosen 不支持说话人分离',
          hint: '换 qwen-audio-3.0-asr-flash-filetrans（整段上传、异步转写）。',
        );
      }
    }
    return Readiness.ok;
  }

  /// 翻译服务。
  static Readiness translation(
    String id,
    AppSettings settings, {
    String? model,
  }) {
    final info = Registry.translationInfo(id);
    if (info == null) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '未知的翻译服务：$id',
        hint: '重新选择一个翻译服务。',
      );
    }
    return _checkEndpoint(info, settings, model: model) ?? Readiness.ok;
  }

  /// 未实施 / 缺地址 / 缺密钥 —— 三种一定跑不起来的情况。
  static Readiness? _checkEndpoint(
    ProviderInfo info,
    AppSettings settings, {
    String? model,
  }) {
    if (!info.implemented) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}尚未实施',
        hint: info.runsLocally ? '本地模型服务是第二期内容，先选一个在线服务。' : '先选一个已实施的服务。',
      );
    }
    final endpoint = settings.endpointFor(info);
    if (endpoint.baseUrl.trim().isEmpty) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}未填服务地址',
        hint: '去设置里填入 baseUrl 后可开始。',
      );
    }
    final chosenModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : endpoint.model.trim();
    if (chosenModel.isEmpty) {
      return Readiness(
        ReadinessLevel.blocked,
        message: '${info.name}未选择模型',
        hint: '去设置里填入模型名后可开始。',
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

  /// 模型支持哪些语种。
  ///
  /// Whisper 系列号称支持全部语种，不必检查；真正会翻车的是那些
  /// 只训了少数语种的小模型 —— 原实现在 `recognition/__init__.py`
  /// 的 `is_allow_lang` 里做同样的事。
  static const _limited = <String, Set<String>>{
    'FunAudioLLM/SenseVoiceSmall': {'zh', 'yue', 'en', 'ja', 'ko'},
  };

  static String? _languageNote(
    String providerId,
    String model,
    Language? language,
  ) {
    if (language == null || language.isAuto) return null;
    final supported = _limited[model];
    if (supported == null || supported.contains(language.code)) return null;
    return '$model 对${language.name}的支持有限';
  }
}
