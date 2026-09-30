import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/domain/task_options.dart';

/// 测试用的任务参数。只写关心的那几项，其余给合理默认值。
TaskOptions testOptions({
  String asr = 'fake_asr',
  String mt = 'fake_mt',
  String source = 'zh',
  String target = 'en',
  String? asrModel,
  String? translationModel,
  bool translate = true,
  int batchSize = 20,
  BilingualLayout bilingual = BilingualLayout.targetOnly,
  int cjkLineLength = 15,
  int latinLineLength = 40,
  SubtitleFormat format = SubtitleFormat.srt,
  OutputLocation outputLocation = OutputLocation.besideSource,
  String? outputDir,
}) => TaskOptions(
  sourceLanguage: Languages.resolve(source),
  asrProviderId: asr,
  // 模型只给名字：服务在登记表里就按登记表补成声明，测试用的假服务
  // （fake_asr 之类）得到一份 OpenAI 转写的声明。不给名字就是那家的默认。
  asrModel: asrModel == null
      ? ProviderCatalog.defaultAsrSpec(asr)
      : ProviderCatalog.legacyAsrSpec(asr, asrModel),
  targetLanguage: Languages.resolve(target),
  translationProviderId: mt,
  translationModel: translationModel == null
      ? ProviderCatalog.defaultChatSpec(mt)
      : ProviderCatalog.legacyChatSpec(mt, translationModel),
  translate: translate,
  translationBatchSize: batchSize,
  bilingual: bilingual,
  cjkLineLength: cjkLineLength,
  latinLineLength: latinLineLength,
  format: format,
  outputLocation: outputLocation,
  outputDir: outputDir,
);
