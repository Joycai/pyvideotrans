import 'language.dart';
import 'srt.dart';
import 'task.dart';

/// 产物格式。
///
/// 第一期实现 SRT、VTT 与纯文本 —— 它们都只是 [SubtitleDocument] 的另一种
/// 序列化，成本几乎为零。ASS 要带样式（字体、字号、描边、位置），
/// 是一整块配置，留到第二期。
enum SubtitleFormat {
  srt('SRT', 'srt'),
  vtt('WebVTT', 'vtt'),
  txt('纯文本', 'txt'),
  ass('ASS', 'ass', implemented: false);

  const SubtitleFormat(this.label, this.extension, {this.implemented = true});

  final String label;
  final String extension;

  /// false 时界面上要灰显并说明原因，不能让用户选中后才失败。
  final bool implemented;

  static SubtitleFormat byExtension(String value) => values.firstWhere(
    (f) => f.extension == value.trim().toLowerCase(),
    orElse: () => SubtitleFormat.srt,
  );
}

/// 译文产物的排版。
///
/// 双语指**同一条字幕里两行文字**，不是两个文件 —— 播放器只能挂一轨字幕，
/// 想同时看原文和译文只有这一条路。
enum BilingualLayout {
  targetOnly('仅译文', SrtField.translation),
  targetAbove('双语 · 译文在上', SrtField.bilingualTargetAbove),
  targetBelow('双语 · 译文在下', SrtField.bilingualTargetBelow);

  const BilingualLayout(this.label, this.field);

  final String label;

  /// 写出时对应的文本路数。
  final SrtField field;

  bool get isBilingual => this != targetOnly;

  static BilingualLayout byName(String value) => values.firstWhere(
    (l) => l.name == value.trim(),
    orElse: () => BilingualLayout.targetOnly,
  );
}

/// 产物放哪儿。
enum OutputLocation {
  /// 与源文件同目录、同名（原实现里那个「移动字幕」勾选项的默认行为）。
  besideSource('与源文件同目录'),

  /// 用户指定的目录。
  custom('指定目录');

  const OutputLocation(this.label);

  final String label;
}

/// 建一个任务需要的全部参数。
///
/// 为什么不直接读全局设置：任务是排队串行跑的，用户很可能在排队期间改设置
/// 去建下一个任务。参数必须在**入队那一刻**定死，否则前面排着的任务会被
/// 后面的改动影响——这类 bug 事后极难复现。全局设置只作为这里的默认值。
class TaskOptions {
  const TaskOptions({
    required this.sourceLanguage,
    required this.asrProviderId,
    this.asrModel,
    this.asrPrompt = '',
    this.translate = true,
    required this.targetLanguage,
    required this.translationProviderId,
    this.translationModel,
    this.translationBatchSize = 20,
    this.translationGuidance = '',
    this.bilingual = BilingualLayout.targetOnly,
    this.cjkLineLength = 15,
    this.latinLineLength = 40,
    this.format = SubtitleFormat.srt,
    this.outputLocation = OutputLocation.besideSource,
    this.outputDir,
  });

  /// 识别的源语言。[Languages.auto] 表示交给服务自己判断。
  final Language sourceLanguage;
  final String asrProviderId;

  /// 覆盖服务的默认模型；null 表示用登记表/设置里的值。
  final String? asrModel;

  /// 给识别服务的提示词，用来固定专有名词的写法。
  final String asrPrompt;

  /// 转写完成后是否接着翻译。
  final bool translate;
  final Language targetLanguage;
  final String translationProviderId;
  final String? translationModel;

  /// 每批送给模型的字幕条数。太大容易丢条，太小费 token。
  final int translationBatchSize;

  /// 术语表与语气要求，拼进系统提示词。
  final String translationGuidance;

  /// 译文产物的排版。只影响写出，不影响文档本身。
  final BilingualLayout bilingual;

  /// 单行字数上限：中日韩一档，其他语言一档。
  final int cjkLineLength;
  final int latinLineLength;

  final SubtitleFormat format;
  final OutputLocation outputLocation;

  /// [outputLocation] 为 [OutputLocation.custom] 时的目录。
  final String? outputDir;

  /// 识别源语言用的换行上限 —— 断句阶段折原文用它。
  int get sourceLineLength =>
      sourceLanguage.cjk ? cjkLineLength : latinLineLength;

  /// 译文用的换行上限。
  int get targetLineLength =>
      targetLanguage.cjk ? cjkLineLength : latinLineLength;

  /// 实际生效的排版。纯文本没有「两行」的概念，选了双语也回落到仅译文 ——
  /// 界面上这一项会跟着灰显，这里再兜一次底，免得靠界面保证数据合法。
  BilingualLayout get resolvedBilingual =>
      format == SubtitleFormat.txt ? BilingualLayout.targetOnly : bilingual;

  /// 这份参数对应的任务类型。字幕文件入队时由调用方改成 [TaskKind.translate]。
  TaskKind get kind =>
      translate ? TaskKind.transcribeAndTranslate : TaskKind.transcribe;

  TaskOptions copyWith({
    Language? sourceLanguage,
    String? asrProviderId,
    String? asrModel,
    String? asrPrompt,
    bool? translate,
    Language? targetLanguage,
    String? translationProviderId,
    String? translationModel,
    int? translationBatchSize,
    String? translationGuidance,
    BilingualLayout? bilingual,
    int? cjkLineLength,
    int? latinLineLength,
    SubtitleFormat? format,
    OutputLocation? outputLocation,
    String? outputDir,
  }) => TaskOptions(
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    asrProviderId: asrProviderId ?? this.asrProviderId,
    asrModel: asrModel ?? this.asrModel,
    asrPrompt: asrPrompt ?? this.asrPrompt,
    translate: translate ?? this.translate,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    translationProviderId:
        translationProviderId ?? this.translationProviderId,
    translationModel: translationModel ?? this.translationModel,
    translationBatchSize: translationBatchSize ?? this.translationBatchSize,
    translationGuidance: translationGuidance ?? this.translationGuidance,
    bilingual: bilingual ?? this.bilingual,
    cjkLineLength: cjkLineLength ?? this.cjkLineLength,
    latinLineLength: latinLineLength ?? this.latinLineLength,
    format: format ?? this.format,
    outputLocation: outputLocation ?? this.outputLocation,
    outputDir: outputDir ?? this.outputDir,
  );
}
