import '../domain/glossary.dart';
import '../domain/providers/asr_transport.dart';
import '../domain/providers/model_params.dart';
import '../domain/providers/model_spec.dart';
import '../domain/providers/provider_catalog.dart';
import '../domain/speech_segments.dart';
import 'audio_splitter.dart';
import 'dashscope_asr.dart';
import 'dashscope_filetrans.dart';
import 'ffmpeg.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';
import 'settings.dart';

/// 服务实例的工厂：按服务 id 与模型声明建出识别 / 翻译的实现。
///
/// 「有哪些服务、各自有哪些模型」是只读数据，在 `ProviderCatalog`
/// （domain/providers）。这里只管把一条登记项变成能发请求的实例 ——
/// 所以只有这个文件需要同时认识设置与各个实现类。
///
/// 用哪个实现类、发哪一族报文，全看传进来的模型声明，不看模型名：
/// 声明随任务入队冻结，名字合不合某种规律与走哪个接口无关。
abstract final class Registry {
  /// 建一个识别服务实例。
  ///
  /// [model]、[prompt]、[glossary] 都是任务入队时定死的，这里不再回头读
  /// 设置里的默认值 —— 设置只提供地址与密钥。
  ///
  /// [media] 给需要本地切分音频的服务用（阿里百炼）；不传就临时建一个。
  ///
  /// [diarize] 开说话人分离：模型不支持时服务端会忽略它。
  static AsrProvider buildAsr(
    String id,
    AppSettings settings, {
    required AsrModelSpec model,
    String prompt = '',
    List<GlossaryEntry> glossary = const [],
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
    if (!info.transports.contains(model.transport)) {
      // 声明与服务对不上（存档被手改过，或任务带着别家服务的模型）。
      // 照着发只会把一种接口的请求打到另一种接口的地址上。
      throw ActionableException(
        '${info.name}不能按「${model.transport.label}」的方式接入 ${model.name}',
        hint: '重新选一个模型；要用这个名字，去设置里删掉它，再按正确的接入方式添加。',
      );
    }
    final endpoint = settings.endpointFor(info, model);
    final context = GlossaryText.asrPrompt(glossary, prompt);
    switch (model.transport) {
      case AsrTransport.openaiTranscription:
        return OpenAiCompatibleAsrProvider(
          info: info,
          endpoint: endpoint,
          prompt: context,
          temperature: model.options.number(ModelParams.asrTemperature),
        );
      case AsrTransport.dashscopeSync:
        return DashScopeAsrProvider(
          info: info,
          endpoint: endpoint,
          dialect: _dialectOf(model),
          options: model.options,
          prompt: context,
          diarize: diarize,
          // 说话人编号只在同一次请求里一致：开分离时把片段切得长一些，
          // 跨片段对不上号的机会就少得多。同步接口其实不分离说话人，
          // 建任务页也不再让同步的模型开这个开关；会带着它到这里的只有
          // 旧版本建的任务，照它入队时的样子跑。
          splitter: FfmpegAudioSplitter(
            media ?? Ffmpeg(),
            maxMs: diarize
                ? DashScopeAsrProvider.diarizeClipMs
                : SpeechSegments.defaultMaxMs,
          ),
        );
      case AsrTransport.dashscopeFileTrans:
        return DashScopeFileTransProvider(
          info: info,
          endpoint: endpoint,
          dialect: _dialectOf(model),
          diarize: diarize,
          media: media ?? Ffmpeg(),
        );
    }
  }

  static TranslationProvider buildTranslation(
    String id,
    AppSettings settings, {
    required ChatModelSpec model,
    String guidance = '',
    List<GlossaryEntry> glossary = const [],
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
    return OpenAiCompatibleTranslationProvider(
      info: info,
      endpoint: settings.endpointFor(info, model),
      extraGuidance: guidance,
      glossary: glossary,
      temperature: model.options.number(ModelParams.chatTemperature),
    );
  }

  /// 百炼的两种接入方式必须知道报文族。声明的构造断言在发布版里不执行，
  /// 残缺的声明走到这里时给一句能照着做的话，而不是空指针。
  static DashScopeDialect _dialectOf(AsrModelSpec model) =>
      model.dialect ??
      (throw ActionableException(
        '${model.name} 没有声明报文族',
        hint: '去设置里删掉它，再添加一次并选好它属于哪一族。',
      ));
}
