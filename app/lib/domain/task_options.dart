import 'enum_by_name.dart';
import 'glossary.dart';
import 'language.dart';
import 'numbers.dart';
import 'paths.dart';
import 'providers/model_spec.dart';
import 'providers/provider_catalog.dart';
import 'srt.dart';
import 'task_kind.dart';

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

/// 按服务 id 查「这家服务的默认模型」。读旧存档时由上层递进来 ——
/// 默认模型是用户在设置里配的，这一层够不着设置。
typedef DefaultModels = ({
  AsrModelSpec Function(String providerId) asr,
  ChatModelSpec Function(String providerId) chat,
});

/// 建一个任务需要的全部参数。
///
/// 为什么不直接读全局设置：任务是排队串行跑的，用户很可能在排队期间改设置
/// 去建下一个任务。参数必须在**入队那一刻**定死，否则前面排着的任务会被
/// 后面的改动影响——这类 bug 事后极难复现。全局设置只作为这里的默认值。
class TaskOptions {
  static const _unset = Object();

  // 各项的取值范围。设置、建任务页的输入框与读回旧 JSON 都用这一份 ——
  // 各写一份时，任务里能填的与默认值能设的就会对不上。
  static const batchSizeRange = IntRange(1, 100);
  static const cjkLineLengthRange = IntRange(4, 60);
  static const latinLineLengthRange = IntRange(8, 120);
  static const minCueMsRange = IntRange(0, 3000);
  static const maxCueMsRange = IntRange(2000, 60000);

  const TaskOptions({
    required this.sourceLanguage,
    required this.asrProviderId,
    required this.asrModel,
    this.asrPrompt = '',
    this.diarize = false,
    this.translate = true,
    required this.targetLanguage,
    required this.translationProviderId,
    required this.translationModel,
    this.translationBatchSize = 20,
    this.translationGuidance = '',
    this.glossaryIds = const [],
    this.glossary = const [],
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

  /// 用哪个识别模型、怎么接：整份声明，不只是名字。
  ///
  /// 以前这里是个可空的名字，null 表示「跑的时候用设置里的默认模型」——
  /// 排着队的任务会被后来的设置改动换掉模型。现在入队时就是完整的声明，
  /// 接入方式、报文族、参数都跟着冻结。名字为空表示还没选模型，就绪检查
  /// 会拦。
  final AsrModelSpec asrModel;

  /// 给识别服务的提示：风格与说明。专有名词放词表（[glossary]）。
  final String asrPrompt;

  /// 说话人分离：给每条字幕标上说话人编号。只有支持的识别服务理会。
  final bool diarize;

  /// 转写完成后是否接着翻译。
  final bool translate;
  final Language targetLanguage;
  final String translationProviderId;

  /// 用哪个翻译模型，同样是整份声明。
  final ChatModelSpec translationModel;

  /// 每批送给模型的字幕条数。太大容易丢条，太小费 token。
  final int translationBatchSize;

  /// 翻译的风格与语气要求，拼进系统提示词。专有名词放词表（[glossary]）。
  final String translationGuidance;

  /// 勾选了哪几份词表。只给界面恢复勾选用（「上次参数」）；任务跑的时候
  /// 不看它，看 [glossary]。
  final List<String> glossaryIds;

  /// 入队那一刻从勾选的词表里展开的条目，识别与翻译都用它。
  ///
  /// 存内容而不是只存 id：词表之后被改、被删，排着队的任务不受影响。
  final List<GlossaryEntry> glossary;

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
    'asrModel': asrModel.toJson(),
    'asrPrompt': asrPrompt,
    'diarize': diarize,
    'translate': translate,
    'targetLanguage': targetLanguage.code,
    'translationProviderId': translationProviderId,
    'translationModel': translationModel.toJson(),
    'translationBatchSize': translationBatchSize,
    'translationGuidance': translationGuidance,
    'glossaryIds': glossaryIds,
    'glossary': [for (final entry in glossary) entry.toJson()],
    'bilingual': bilingual.name,
    'cjkLineLength': cjkLineLength,
    'latinLineLength': latinLineLength,
    'minCueMs': minCueMs,
    'maxCueMs': maxCueMs,
    'format': format.extension,
    'outputLocation': outputLocation.name,
    'outputDir': outputDir,
  };

  /// 这份存档里的模型是不是读不出声明：旧版本写的名字或 null，或者
  /// 认不出来的对象。
  ///
  /// 这样的存档每读一次都要重新补一遍声明，补出来的东西取决于当时的设置。
  /// 调用方据此把读回来的结果写回去，让它从此定下来。
  static bool isLegacyJson(Map<String, Object?> json) =>
      ModelSpec.fromJson(json['asrModel']) is! AsrModelSpec ||
      ModelSpec.fromJson(json['translationModel']) is! ChatModelSpec;

  /// 缺字段或类型不对的项回落到 [fallback] 里的值，绝不因为一份旧存档抛异常。
  ///
  /// [defaultModels] 只在读旧存档时用得上，见 [_readAsrModel]。
  factory TaskOptions.fromJson(
    Map<String, Object?> json, {
    required TaskOptions fallback,
    DefaultModels? defaultModels,
  }) {
    T pick<T>(String key, T orElse) {
      final v = json[key];
      return v is T ? v : orElse;
    }

    final location =
        OutputLocation.values.tryByName(json['outputLocation']) ??
        fallback.outputLocation;
    final dir = pick<String?>('outputDir', fallback.outputDir);
    final asrProviderId = pick('asrProviderId', fallback.asrProviderId);
    final translationProviderId = pick(
      'translationProviderId',
      fallback.translationProviderId,
    );
    final ids = json['glossaryIds'];
    final glossary = json['glossary'];
    return TaskOptions(
      sourceLanguage: Languages.resolve(
        pick('sourceLanguage', fallback.sourceLanguage.code),
      ),
      asrProviderId: asrProviderId,
      asrModel: _readAsrModel(
        json['asrModel'],
        asrProviderId,
        fallback,
        defaultModels,
      ),
      asrPrompt: pick('asrPrompt', fallback.asrPrompt),
      diarize: pick('diarize', fallback.diarize),
      translate: pick('translate', fallback.translate),
      targetLanguage: Languages.resolve(
        pick('targetLanguage', fallback.targetLanguage.code),
      ),
      translationProviderId: translationProviderId,
      translationModel: _readChatModel(
        json['translationModel'],
        translationProviderId,
        fallback,
        defaultModels,
      ),
      translationBatchSize: batchSizeRange.clamp(
        pick('translationBatchSize', fallback.translationBatchSize),
      ),
      translationGuidance: pick(
        'translationGuidance',
        fallback.translationGuidance,
      ),
      // 词表不从 [fallback] 补：旧存档里没有这两项，意思就是那个任务没用
      // 词表，不能因为现在设置里有默认启用的词表就给它加上。
      glossaryIds: [
        if (ids is List) ...ids.whereType<String>(),
      ],
      glossary: GlossaryText.clean([
        if (glossary is List)
          for (final entry in glossary) ?GlossaryEntry.fromJson(entry),
      ]),
      bilingual:
          BilingualLayout.values.tryByName(
            pick('bilingual', fallback.bilingual.name).trim(),
          ) ??
          BilingualLayout.targetOnly,
      cjkLineLength: cjkLineLengthRange.clamp(
        pick('cjkLineLength', fallback.cjkLineLength),
      ),
      latinLineLength: latinLineLengthRange.clamp(
        pick('latinLineLength', fallback.latinLineLength),
      ),
      minCueMs: minCueMsRange.clamp(pick('minCueMs', fallback.minCueMs)),
      maxCueMs: maxCueMsRange.clamp(pick('maxCueMs', fallback.maxCueMs)),
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

  /// 读模型。新存档是一份声明；旧存档是模型名，或 null（「用设置里的默认」）。
  ///
  /// 旧格式的处理：
  /// - 名字与 [fallback] 里同一家服务的模型同名 → 用 [fallback] 的那份，
  ///   用户在设置里给它调过的参数还在；
  /// - 别的名字 → 登记表预置里有同名的用预置，否则按名字推断接法；
  /// - null → 服务与 [fallback] 相同就用它的模型；不同就问 [defaults]
  ///   要那家服务的默认模型。在建任务页换服务并不改设置里的默认服务，
  ///   所以「服务不是默认服务、模型又没写」的旧任务并不少见，它们以前
  ///   跑的就是设置里给那家配的模型。没给 [defaults] 才用登记表的第一个
  ///   预置 —— 设置不在这一层，只能由调用方递进来。
  static AsrModelSpec _readAsrModel(
    Object? raw,
    String providerId,
    TaskOptions fallback,
    DefaultModels? defaults,
  ) {
    if (ModelSpec.fromJson(raw) case final AsrModelSpec spec) return spec;
    final sameProvider = providerId == fallback.asrProviderId;
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) {
      if (sameProvider) return fallback.asrModel;
      return defaults?.asr(providerId) ??
          ProviderCatalog.defaultAsrSpec(providerId);
    }
    return sameProvider && name == fallback.asrModel.name
        ? fallback.asrModel
        : ProviderCatalog.legacyAsrSpec(providerId, name);
  }

  static ChatModelSpec _readChatModel(
    Object? raw,
    String providerId,
    TaskOptions fallback,
    DefaultModels? defaults,
  ) {
    if (ModelSpec.fromJson(raw) case final ChatModelSpec spec) return spec;
    final sameProvider = providerId == fallback.translationProviderId;
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) {
      if (sameProvider) return fallback.translationModel;
      return defaults?.chat(providerId) ??
          ProviderCatalog.defaultChatSpec(providerId);
    }
    return sameProvider && name == fallback.translationModel.name
        ? fallback.translationModel
        : ProviderCatalog.legacyChatSpec(providerId, name);
  }

  TaskOptions copyWith({
    Language? sourceLanguage,
    String? asrProviderId,
    AsrModelSpec? asrModel,
    String? asrPrompt,
    bool? diarize,
    bool? translate,
    Language? targetLanguage,
    String? translationProviderId,
    ChatModelSpec? translationModel,
    int? translationBatchSize,
    String? translationGuidance,
    List<String>? glossaryIds,
    List<GlossaryEntry>? glossary,
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
    asrModel: asrModel ?? this.asrModel,
    asrPrompt: asrPrompt ?? this.asrPrompt,
    diarize: diarize ?? this.diarize,
    translate: translate ?? this.translate,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    translationProviderId: translationProviderId ?? this.translationProviderId,
    translationModel: translationModel ?? this.translationModel,
    translationBatchSize: translationBatchSize ?? this.translationBatchSize,
    translationGuidance: translationGuidance ?? this.translationGuidance,
    glossaryIds: glossaryIds ?? this.glossaryIds,
    glossary: glossary ?? this.glossary,
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

  /// 换识别服务。模型换成新服务的默认模型（调用方从设置里取），否则会把
  /// 上一家的模型发给下一家；新模型分不了说话人就把开关关掉，别留一个
  /// 界面上看不见的 true。
  TaskOptions withAsrProvider(
    String id, {
    required AsrModelSpec defaultModel,
  }) => copyWith(
    asrProviderId: id,
    asrModel: defaultModel,
    diarize: diarize && defaultModel.capabilities.diarization,
  );

  /// 换翻译服务。模型换成新服务的默认模型，理由同上。
  TaskOptions withTranslationProvider(
    String id, {
    required ChatModelSpec defaultModel,
  }) => copyWith(translationProviderId: id, translationModel: defaultModel);

  /// 产物目录：设了自定义输出目录就用它，否则与源文件同目录。
  String outputDirFor(String sourcePath) => switch (outputLocation) {
    OutputLocation.custom when outputDir?.trim().isNotEmpty == true =>
      outputDir!.trim(),
    _ => dirName(sourcePath),
  };
}
