import 'package:subtitle_studio/domain/language.dart';
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
  asrModel: asrModel,
  targetLanguage: Languages.resolve(target),
  translationProviderId: mt,
  translationModel: translationModel,
  translate: translate,
  translationBatchSize: batchSize,
  bilingual: bilingual,
  cjkLineLength: cjkLineLength,
  latinLineLength: latinLineLength,
  format: format,
  outputLocation: outputLocation,
  outputDir: outputDir,
);
