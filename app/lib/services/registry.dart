import '../domain/providers/provider_catalog.dart';
import '../domain/speech_segments.dart';
import 'audio_splitter.dart';
import 'dashscope_asr.dart';
import 'dashscope_filetrans.dart';
import 'ffmpeg.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';
import 'settings.dart';

/// 服务实例的工厂：按服务 id 建出识别 / 翻译的实现。
///
/// 「有哪些服务、各自有哪些模型」是只读数据，在 `ProviderCatalog`
/// （domain/providers）。这里只管把一条登记项变成能发请求的实例 ——
/// 所以只有这个文件需要同时认识设置与各个实现类。
abstract final class Registry {
  /// 建一个识别服务实例。
  ///
  /// [model] 与 [prompt] 是**任务级覆盖**：任务入队时把参数定死了，
  /// 之后用户改设置不应该影响已经排上队的任务。传 null 表示沿用设置里的值。
  ///
  /// [media] 给需要本地切分音频的服务用（阿里百炼）；不传就临时建一个。
  ///
  /// [diarize] 开说话人分离：只有 [ProviderInfo.supportsDiarization] 的服务
  /// 理会它，其余忽略。
  static AsrProvider buildAsr(
    String id,
    AppSettings settings, {
    String? model,
    String? prompt,
    Ffmpeg? media,
    bool diarize = false,
  }) {
    final info = ProviderCatalog.asrInfo(id);
    if (info == null) {
      throw ActionableException('未知的识别服务：$id', hint: '在设置里重新选择识别服务。');
    }
    if (!info.implemented) {
      throw ActionableException(
        '${info.name} 尚未实施',
        hint: '第一期只对接在线 API。改选 OpenAI、Groq 或硅基流动。',
      );
    }
    final endpoint = settings.endpointFor(info);
    if (info.id == 'dashscope_qwen_asr') {
      final resolved = _withModel(endpoint, model);
      if (DashScopeFileTransProvider.isFileTransModel(resolved.model)) {
        return DashScopeFileTransProvider(
          info: info,
          endpoint: resolved,
          diarize: diarize,
          media: media ?? Ffmpeg(),
        );
      }
      return DashScopeAsrProvider(
        info: info,
        endpoint: _withModel(endpoint, model),
        prompt: prompt ?? settings.asrPrompt,
        diarize: diarize,
        // 说话人编号只在同一次请求里一致：开分离时把片段切得长一些，
        // 跨片段对不上号的机会就少得多。
        splitter: FfmpegAudioSplitter(
          media ?? Ffmpeg(),
          maxMs: diarize
              ? DashScopeAsrProvider.diarizeClipMs
              : SpeechSegments.defaultMaxMs,
        ),
      );
    }
    return OpenAiCompatibleAsrProvider(
      info: info,
      endpoint: _withModel(endpoint, model),
      prompt: prompt ?? settings.asrPrompt,
    );
  }

  static TranslationProvider buildTranslation(
    String id,
    AppSettings settings, {
    String? model,
    String? guidance,
  }) {
    final info = ProviderCatalog.translationInfo(id);
    if (info == null) {
      throw ActionableException('未知的翻译服务：$id', hint: '在设置里重新选择翻译服务。');
    }
    if (!info.implemented) {
      throw ActionableException(
        '${info.name} 尚未实施',
        hint: '第一期只对接在线 API 与 Ollama / LM Studio。',
      );
    }
    final endpoint = settings.endpointFor(info);
    return OpenAiCompatibleTranslationProvider(
      info: info,
      endpoint: _withModel(endpoint, model),
      extraGuidance: guidance ?? settings.translationGuidance,
    );
  }

  static Endpoint _withModel(Endpoint endpoint, String? model) =>
      model == null || model.trim().isEmpty
      ? endpoint
      : Endpoint(
          baseUrl: endpoint.baseUrl,
          model: model.trim(),
          apiKey: endpoint.apiKey,
          timeout: endpoint.timeout,
        );
}
