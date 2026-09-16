import 'language.dart';
import 'paths.dart';
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
  static const _unset = Object();

  const TaskOptions({
    required this.sourceLanguage,
    required this.asrProviderId,
    this.asrModel,
    this.asrPrompt = '',
    this.diarize = false,
    this.translate = true,
    required this.targetLanguage,
    required this.translationProviderId,
    this.translationModel,
    this.translationBatchSize = 20,
    this.translationGuidance = '',
    this.bilingual = BilingualLayout.targetOnly,
    this.cjkLineLength = 15,
    this.latinLineLength = 40,
    this.minCueMs = 500,
    this.maxCueMs = 10000,
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

  /// 说话人分离：给每条字幕标上说话人编号。只有支持的识别服务理会。
  final bool diarize;

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

  /// 断句阶段的字幕时长下限（毫秒）：短于它且紧跟上一条的并进上一条。
  final int minCueMs;

  /// 断句阶段的字幕时长上限（毫秒）：长于它的按标点拆开。
  final int maxCueMs;

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

  /// 持久化用。语言只存代码，读回时按代码解析；未知服务 id 原样保留，
  /// 由就绪检查在界面上指出「服务不存在」。
  Map<String, Object?> toJson() => {
    'sourceLanguage': sourceLanguage.code,
    'asrProviderId': asrProviderId,
    'asrModel': asrModel,
    'asrPrompt': asrPrompt,
    'diarize': diarize,
    'translate': translate,
    'targetLanguage': targetLanguage.code,
    'translationProviderId': translationProviderId,
    'translationModel': translationModel,
    'translationBatchSize': translationBatchSize,
    'translationGuidance': translationGuidance,
    'bilingual': bilingual.name,
    'cjkLineLength': cjkLineLength,
    'latinLineLength': latinLineLength,
    'minCueMs': minCueMs,
    'maxCueMs': maxCueMs,
    'format': format.extension,
    'outputLocation': outputLocation.name,
    'outputDir': outputDir,
  };

  /// 缺字段或类型不对的项回落到 [fallback] 里的值，绝不因为一份旧存档抛异常。
  factory TaskOptions.fromJson(
    Map<String, Object?> json, {
    required TaskOptions fallback,
  }) {
    T pick<T>(String key, T orElse) {
      final v = json[key];
      return v is T ? v : orElse;
    }

    final location = OutputLocation.values.firstWhere(
      (l) => l.name == json['outputLocation'],
      orElse: () => fallback.outputLocation,
    );
    final dir = pick<String?>('outputDir', fallback.outputDir);
    return TaskOptions(
      sourceLanguage: Languages.resolve(
        pick('sourceLanguage', fallback.sourceLanguage.code),
      ),
      asrProviderId: pick('asrProviderId', fallback.asrProviderId),
      asrModel: pick<String?>('asrModel', fallback.asrModel),
      asrPrompt: pick('asrPrompt', fallback.asrPrompt),
      diarize: pick('diarize', fallback.diarize),
      translate: pick('translate', fallback.translate),
      targetLanguage: Languages.resolve(
        pick('targetLanguage', fallback.targetLanguage.code),
      ),
      translationProviderId: pick(
        'translationProviderId',
        fallback.translationProviderId,
      ),
      translationModel: pick<String?>(
        'translationModel',
        fallback.translationModel,
      ),
      translationBatchSize: pick(
        'translationBatchSize',
        fallback.translationBatchSize,
      ).clamp(1, 100),
      translationGuidance: pick(
        'translationGuidance',
        fallback.translationGuidance,
      ),
      bilingual: BilingualLayout.byName(
        pick('bilingual', fallback.bilingual.name),
      ),
      cjkLineLength: pick('cjkLineLength', fallback.cjkLineLength).clamp(4, 60),
      latinLineLength: pick(
        'latinLineLength',
        fallback.latinLineLength,
      ).clamp(8, 120),
      minCueMs: pick('minCueMs', fallback.minCueMs).clamp(0, 3000),
      maxCueMs: pick('maxCueMs', fallback.maxCueMs).clamp(2000, 60000),
      format: SubtitleFormat.byExtension(
        pick('format', fallback.format.extension),
      ),
      // 指定目录却没有目录，等于没指定。
      outputLocation: location == OutputLocation.custom && dir == null
          ? OutputLocation.besideSource
          : location,
      outputDir: dir,
    );
  }

  TaskOptions copyWith({
    Language? sourceLanguage,
    String? asrProviderId,
    Object? asrModel = _unset,
    String? asrPrompt,
    bool? diarize,
    bool? translate,
    Language? targetLanguage,
    String? translationProviderId,
    Object? translationModel = _unset,
    int? translationBatchSize,
    String? translationGuidance,
    BilingualLayout? bilingual,
    int? cjkLineLength,
    int? latinLineLength,
    int? minCueMs,
    int? maxCueMs,
    SubtitleFormat? format,
    OutputLocation? outputLocation,
    Object? outputDir = _unset,
  }) => TaskOptions(
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    asrProviderId: asrProviderId ?? this.asrProviderId,
    asrModel: identical(asrModel, _unset) ? this.asrModel : asrModel as String?,
    asrPrompt: asrPrompt ?? this.asrPrompt,
    diarize: diarize ?? this.diarize,
    translate: translate ?? this.translate,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    translationProviderId: translationProviderId ?? this.translationProviderId,
    translationModel: identical(translationModel, _unset)
        ? this.translationModel
        : translationModel as String?,
    translationBatchSize: translationBatchSize ?? this.translationBatchSize,
    translationGuidance: translationGuidance ?? this.translationGuidance,
    bilingual: bilingual ?? this.bilingual,
    cjkLineLength: cjkLineLength ?? this.cjkLineLength,
    latinLineLength: latinLineLength ?? this.latinLineLength,
    minCueMs: minCueMs ?? this.minCueMs,
    maxCueMs: maxCueMs ?? this.maxCueMs,
    format: format ?? this.format,
    outputLocation: outputLocation ?? this.outputLocation,
    outputDir: identical(outputDir, _unset)
        ? this.outputDir
        : outputDir as String?,
  );

  /// 产物目录：设了自定义输出目录就用它，否则与源文件同目录。
  String outputDirFor(String sourcePath) => switch (outputLocation) {
    OutputLocation.custom when outputDir?.trim().isNotEmpty == true =>
      outputDir!.trim(),
    _ => dirName(sourcePath),
  };
}
