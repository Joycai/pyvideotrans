import '../domain/speech_segments.dart';
import 'audio_splitter.dart';
import 'dashscope_asr.dart';
import 'media.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';
import 'settings.dart';

/// 所有可选服务的登记表。
///
/// 关键设计：**「本地」不是一条单独的代码路径**。Ollama、LM Studio 和第二期的
/// 本地 Python 后端都说 OpenAI 兼容协议，因此它们与在线服务共用同一个实现类，
/// 区别只在 baseUrl、是否需要密钥，以及界面上的一个图标。
abstract final class Registry {
  static const asr = <ProviderInfo>[
    ProviderInfo(
      id: 'openai',
      name: 'OpenAI',
      vendor: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'whisper-1',
      models: ['whisper-1', 'gpt-4o-transcribe', 'gpt-4o-mini-transcribe'],
    ),
    ProviderInfo(
      id: 'groq',
      name: 'Groq',
      vendor: 'Groq',
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'whisper-large-v3',
      models: ['whisper-large-v3', 'whisper-large-v3-turbo'],
    ),
    ProviderInfo(
      id: 'siliconflow',
      name: '硅基流动',
      vendor: '硅基流动',
      defaultBaseUrl: 'https://api.siliconflow.cn/v1',
      defaultModel: 'FunAudioLLM/SenseVoiceSmall',
      models: ['FunAudioLLM/SenseVoiceSmall'],
    ),
    ProviderInfo(
      id: 'asr_custom',
      name: '自定义（OpenAI 兼容）',
      vendor: '自定义服务',
      defaultBaseUrl: '',
      defaultModel: '',
    ),
    // 第二期：本地 Python 后端。协议与上面完全一致，只是跑在 localhost。
    ProviderInfo(
      id: 'local_backend',
      name: '本地模型服务',
      vendor: '本地服务',
      runsLocally: true,
      implemented: false,
      needsApiKey: false,
      defaultBaseUrl: 'http://127.0.0.1:8765/v1',
      defaultModel: 'whisper-large-v3',
    ),
    // 阿里百炼的识别接口不是 OpenAI 兼容形态（多模态 generation + base64 音频，
    // 且不返回时间戳）：走单独的实现类，先按静音切句再逐段识别。
    ProviderInfo(
      id: 'dashscope_qwen_asr',
      name: '阿里百炼 · Qwen3-ASR',
      vendor: '阿里百炼',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/api/v1',
      defaultModel: 'qwen3-asr-flash',
      models: [
        'qwen3-asr-flash',
        'qwen-audio-3.0-asr-flash',
        'fun-asr-flash-2026-06-15',
      ],
      // 文档：说话人分离只有 Qwen-Audio-3.0-ASR 与 Fun-ASR 两族支持。
      supportsDiarization: true,
    ),
  ];

  static const translation = <ProviderInfo>[
    ProviderInfo(
      id: 'deepseek',
      name: 'DeepSeek',
      vendor: 'DeepSeek',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      models: ['deepseek-chat', 'deepseek-reasoner'],
    ),
    ProviderInfo(
      id: 'openai_chat',
      name: 'OpenAI',
      vendor: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini'],
    ),
    ProviderInfo(
      id: 'siliconflow_chat',
      name: '硅基流动',
      vendor: '硅基流动',
      defaultBaseUrl: 'https://api.siliconflow.cn/v1',
      defaultModel: 'Qwen/Qwen2.5-14B-Instruct',
    ),
    ProviderInfo(
      id: 'openrouter',
      name: 'OpenRouter',
      vendor: 'OpenRouter',
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'google/gemini-2.0-flash-001',
    ),
    ProviderInfo(
      id: 'ollama',
      name: 'Ollama',
      vendor: 'Ollama',
      runsLocally: true,
      needsApiKey: false,
      defaultBaseUrl: 'http://localhost:11434/v1',
      defaultModel: 'qwen2.5:14b',
    ),
    ProviderInfo(
      id: 'lmstudio',
      name: 'LM Studio',
      vendor: 'LM Studio',
      runsLocally: true,
      needsApiKey: false,
      defaultBaseUrl: 'http://localhost:1234/v1',
      defaultModel: '',
    ),
    ProviderInfo(
      id: 'mt_custom',
      name: '自定义（OpenAI 兼容）',
      vendor: '自定义服务',
      defaultBaseUrl: '',
      defaultModel: '',
    ),
    ProviderInfo(
      id: 'local_backend_chat',
      name: '本地模型服务',
      vendor: '本地服务',
      runsLocally: true,
      implemented: false,
      needsApiKey: false,
      defaultBaseUrl: 'http://127.0.0.1:8765/v1',
      defaultModel: '',
    ),
  ];

  static ProviderInfo? asrInfo(String id) =>
      asr.where((p) => p.id == id).firstOrNull;

  static ProviderInfo? translationInfo(String id) =>
      translation.where((p) => p.id == id).firstOrNull;

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
    Media? media,
    bool diarize = false,
  }) {
    final info = asrInfo(id);
    if (info == null) {
      throw ProviderException('未知的识别服务：$id', hint: '在设置里重新选择识别服务。');
    }
    if (!info.implemented) {
      throw ProviderException(
        '${info.name} 尚未实施',
        hint: '第一期只对接在线 API。改选 OpenAI、Groq 或硅基流动。',
      );
    }
    final endpoint = settings.endpointFor(info);
    if (info.id == 'dashscope_qwen_asr') {
      return DashScopeAsrProvider(
        info: info,
        endpoint: _withModel(endpoint, model),
        prompt: prompt ?? settings.asrPrompt,
        diarize: diarize,
        // 说话人编号只在同一次请求里一致：开分离时把片段切得长一些，
        // 跨片段对不上号的机会就少得多。
        splitter: FfmpegAudioSplitter(
          media ?? Media(),
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
    final info = translationInfo(id);
    if (info == null) {
      throw ProviderException('未知的翻译服务：$id', hint: '在设置里重新选择翻译服务。');
    }
    if (!info.implemented) {
      throw ProviderException(
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
