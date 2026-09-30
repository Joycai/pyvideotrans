import 'asr_transport.dart';
import 'model_spec.dart';
import 'provider_info.dart';

/// 所有可选服务的登记表。
///
/// 关键设计：**「本地」不是一条单独的代码路径**。Ollama、LM Studio 和第二期的
/// 本地 Python 后端都说 OpenAI 兼容协议，因此它们与在线服务共用同一个实现类，
/// 区别只在 baseUrl、是否需要密钥，以及界面上的一个图标。加一家在线服务
/// 通常只是在这里加一条。
///
/// 每个预置模型写成完整的声明：怎么接、属于哪一族、有什么限制都在这里写明，
/// 别处不再按模型名去猜。
abstract final class ProviderCatalog {
  static const _openai = AsrTransport.openaiTranscription;

  static const asr = <AsrProviderInfo>[
    AsrProviderInfo(
      id: 'openai',
      name: 'OpenAI',
      vendor: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      presets: [
        AsrModelSpec(name: 'whisper-1', transport: _openai),
        AsrModelSpec(name: 'gpt-4o-transcribe', transport: _openai),
        AsrModelSpec(name: 'gpt-4o-mini-transcribe', transport: _openai),
      ],
    ),
    AsrProviderInfo(
      id: 'groq',
      name: 'Groq',
      vendor: 'Groq',
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
      presets: [
        AsrModelSpec(name: 'whisper-large-v3', transport: _openai),
        AsrModelSpec(name: 'whisper-large-v3-turbo', transport: _openai),
      ],
    ),
    AsrProviderInfo(
      id: 'siliconflow',
      name: '硅基流动',
      vendor: '硅基流动',
      defaultBaseUrl: 'https://api.siliconflow.cn/v1',
      presets: [
        // Whisper 系列号称支持全部语种，不必限制；真正会翻车的是这种只训了
        // 少数语种的小模型 —— 原实现在 `recognition/__init__.py` 的
        // `is_allow_lang` 里做同样的事。
        AsrModelSpec(
          name: 'FunAudioLLM/SenseVoiceSmall',
          transport: _openai,
          languages: {'zh', 'yue', 'en', 'ja', 'ko'},
        ),
      ],
    ),
    AsrProviderInfo(
      id: 'asr_custom',
      name: '自定义（OpenAI 兼容）',
      vendor: '自定义服务',
      defaultBaseUrl: '',
    ),
    // 第二期：本地 Python 后端。协议与上面完全一致，只是跑在 localhost。
    AsrProviderInfo(
      id: 'local_backend',
      name: '本地模型服务',
      vendor: '本地服务',
      runsLocally: true,
      implemented: false,
      needsApiKey: false,
      defaultBaseUrl: 'http://127.0.0.1:8765/v1',
      presets: [AsrModelSpec(name: 'whisper-large-v3', transport: _openai)],
    ),
    // 阿里百炼的识别接口不是 OpenAI 兼容形态，走单独的实现类。同步接口
    // （多模态 generation + base64 音频）不返回时间戳，只能先按静音切句再
    // 逐段识别；录音文件转写是异步的：先把音频上传到百炼的临时存储，再提交
    // 任务轮询结果，不切片，一次拿回带时间戳（和说话人）的整份结果。
    AsrProviderInfo(
      id: 'dashscope_qwen_asr',
      name: '阿里百炼 · Qwen3-ASR',
      vendor: '阿里百炼',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/api/v1',
      transports: {
        AsrTransport.dashscopeSync,
        AsrTransport.dashscopeFileTrans,
      },
      presets: [
        AsrModelSpec(
          name: 'qwen3-asr-flash',
          transport: AsrTransport.dashscopeSync,
          dialect: DashScopeDialect.qwen3Asr,
        ),
        AsrModelSpec(
          name: 'qwen-audio-3.0-asr-flash',
          transport: AsrTransport.dashscopeSync,
          dialect: DashScopeDialect.qwenAudio3,
        ),
        AsrModelSpec(
          name: 'fun-asr-flash-2026-06-15',
          transport: AsrTransport.dashscopeSync,
          dialect: DashScopeDialect.funAsr,
        ),
        AsrModelSpec(
          name: 'qwen-audio-3.0-asr-flash-filetrans',
          transport: AsrTransport.dashscopeFileTrans,
          dialect: DashScopeDialect.qwenAudio3,
        ),
        AsrModelSpec(
          name: 'qwen3-asr-flash-filetrans',
          transport: AsrTransport.dashscopeFileTrans,
          dialect: DashScopeDialect.qwen3Asr,
        ),
      ],
    ),
  ];

  static const translation = <ChatProviderInfo>[
    ChatProviderInfo(
      id: 'deepseek',
      name: 'DeepSeek',
      vendor: 'DeepSeek',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      presets: [
        ChatModelSpec(name: 'deepseek-chat'),
        ChatModelSpec(name: 'deepseek-reasoner'),
      ],
    ),
    ChatProviderInfo(
      id: 'openai_chat',
      name: 'OpenAI',
      vendor: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      presets: [
        ChatModelSpec(name: 'gpt-4o-mini'),
        ChatModelSpec(name: 'gpt-4o'),
        ChatModelSpec(name: 'gpt-4.1-mini'),
      ],
    ),
    ChatProviderInfo(
      id: 'siliconflow_chat',
      name: '硅基流动',
      vendor: '硅基流动',
      defaultBaseUrl: 'https://api.siliconflow.cn/v1',
      presets: [ChatModelSpec(name: 'Qwen/Qwen2.5-14B-Instruct')],
    ),
    ChatProviderInfo(
      id: 'openrouter',
      name: 'OpenRouter',
      vendor: 'OpenRouter',
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
      presets: [ChatModelSpec(name: 'google/gemini-2.0-flash-001')],
    ),
    ChatProviderInfo(
      id: 'ollama',
      name: 'Ollama',
      vendor: 'Ollama',
      runsLocally: true,
      needsApiKey: false,
      defaultBaseUrl: 'http://localhost:11434/v1',
      presets: [ChatModelSpec(name: 'qwen2.5:14b')],
    ),
    ChatProviderInfo(
      id: 'lmstudio',
      name: 'LM Studio',
      vendor: 'LM Studio',
      runsLocally: true,
      needsApiKey: false,
      defaultBaseUrl: 'http://localhost:1234/v1',
    ),
    ChatProviderInfo(
      id: 'mt_custom',
      name: '自定义（OpenAI 兼容）',
      vendor: '自定义服务',
      defaultBaseUrl: '',
    ),
    ChatProviderInfo(
      id: 'local_backend_chat',
      name: '本地模型服务',
      vendor: '本地服务',
      runsLocally: true,
      implemented: false,
      needsApiKey: false,
      defaultBaseUrl: 'http://127.0.0.1:8765/v1',
    ),
  ];

  static AsrProviderInfo? asrInfo(String id) =>
      asr.where((p) => p.id == id).firstOrNull;

  static ChatProviderInfo? translationInfo(String id) =>
      translation.where((p) => p.id == id).firstOrNull;

  /// 旧存档里只有模型名时补出一份识别模型声明。
  ///
  /// 服务 id 也认不出来（登记表里删掉的服务）时当成 OpenAI 转写接口：
  /// 这种任务反正跑不起来，就绪检查会说「未知的识别服务」，这里只保证不抛。
  static AsrModelSpec legacyAsrSpec(String providerId, String name) =>
      asrInfo(providerId)?.guess(name) ??
      AsrModelSpec(name: name.trim(), transport: _openai);

  /// 旧存档里只有模型名时补出一份翻译模型声明。
  static ChatModelSpec legacyChatSpec(String providerId, String name) =>
      translationInfo(providerId)?.guess(name) ??
      ChatModelSpec(name: name.trim());

  /// 这家服务什么都没配时的默认模型；没有预置（或服务不认识）时是空名的占位。
  static AsrModelSpec defaultAsrSpec(String providerId) {
    final info = asrInfo(providerId);
    return info?.presets.firstOrNull ??
        info?.unsetModel ??
        const AsrModelSpec.unset(_openai);
  }

  static ChatModelSpec defaultChatSpec(String providerId) =>
      translationInfo(providerId)?.presets.firstOrNull ?? ChatModelSpec.unset;
}
