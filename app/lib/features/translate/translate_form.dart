import 'package:file_selector/file_selector.dart';

import '../../domain/media_kinds.dart';
import '../../domain/numbers.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/task_kind.dart';
import '../../domain/task_options.dart';
import '../../services/ffmpeg.dart';
import '../../services/readiness.dart';
import '../shared/enqueue_request.dart';
import '../shared/footer_message.dart';
import '../shared/new_task_form.dart';

/// 字幕列表里一行的解析状态。
enum StagedSubtitleState {
  /// 正在读条数与时间跨度。不阻断提交 —— 任务跑起来会再解析一遍。
  parsing,
  ready,

  /// 一条都读不出来：空文件、编码坏、或根本不是字幕。不入队，也不计入总数。
  broken,
}

/// 加进「翻译」列表里的一个字幕文件。
class StagedSubtitle extends StagedPath {
  const StagedSubtitle({required super.path, this.info, required this.state});

  final MediaFileInfo? info;
  final StagedSubtitleState state;

  /// 解析出的条数；未解析完或解析不出时为 null。
  int? get cueCount =>
      state == StagedSubtitleState.ready ? info?.cueCount : null;

  bool get willEnqueue => state == StagedSubtitleState.ready;
}

/// 「翻译」的表单状态：字幕列表、参数、校验与提交。
///
/// 对话框与导航栏的「翻译」页共用这一份 —— 两处的字段、校验文案与就绪判断
/// 必须逐字相同，各写一份必然走形。它不碰任务队列：`submit` 只把文件与参数
/// 打包交出去，入队由调用方完成，进度归任务页。
///
/// 与 [TranscribeFormController] 的差别就是翻译与转写的差别：输入是字幕，
/// 计量单位是条数而不是时长；拖进来的音视频不算错，记下来让用户一键改走
/// 「新建转写」；语言是一对，可以对换。
class TranslateFormController extends TaskOptionsFormBase<StagedSubtitle> {
  TranslateFormController({
    required super.settings,
    Ffmpeg? media,
    super.initial,
    super.pickDirectory,
  }) : media = media ?? Ffmpeg();

  final Ffmpeg media;

  /// 被忽略的音视频路径。留着是为了「改用新建转写」能把它们原样带过去。
  /// （[dropError] 只说既不是字幕也不是音视频的那些。）
  final _ignoredMedia = <String>[];
  List<String> get ignoredMedia => List.unmodifiable(_ignoredMedia);

  @override
  TaskOptions? get lastUsedOptions => settings.lastTranslateOptions;

  @override
  XTypeGroup get browseTypes =>
      XTypeGroup(label: '字幕', extensions: MediaKinds.subtitle.toList());

  // —— 参数 ————————————————————————————————————————————————

  /// 原文是「自动检测」时没有东西可以换到目标那边去。
  bool get canSwapLanguages => !options.sourceLanguage.isAuto;

  /// 原文与目标对换。不能换时什么都不做。
  void swapLanguages() {
    if (!canSwapLanguages) return;
    options = options.copyWith(
      sourceLanguage: options.targetLanguage,
      targetLanguage: options.sourceLanguage,
    );
    notifyIfAlive();
  }

  /// 换翻译服务（规则见 [TaskOptions.withTranslationProvider]）。
  void selectTranslationProvider(String id) =>
      update((o) => o.withTranslationProvider(id));

  // —— 文件 ————————————————————————————————————————————————

  /// 这批路径里既不是字幕也不是音视频的那些该怎么跟用户解释。
  /// 音视频不算被拒 —— 它们另有去处（见 [ignoredNote]）。全都认识时返回 null。
  static String? rejection(List<String> paths) {
    final unknown = paths
        .where((p) => !MediaKinds.isSubtitle(p) && !MediaKinds.isMedia(p))
        .map(extensionOf)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (unknown.isEmpty) return null;
    return '不认识的格式：${unknown.join('、')}';
  }

  /// 加一批路径。非字幕与已在列表里的跳过；先以「解析中」入列，解析完再更新，
  /// 用户不必等所有文件读完才看到它们出现。
  @override
  Future<void> add(List<String> paths) async {
    final fresh = stageNew(
      paths.where(MediaKinds.isSubtitle),
      (p) => StagedSubtitle(path: p, state: StagedSubtitleState.parsing),
    );
    if (fresh.isEmpty) return;
    await Future.wait(fresh.map(_parse));
  }

  Future<void> _parse(String path) async {
    final MediaFileInfo info;
    try {
      info = await media.probeFile(path);
    } catch (_) {
      _setParseResult(
        path,
        MediaFileInfo(path: path, sizeBytes: 0, exists: false),
      );
      return;
    }
    _setParseResult(path, info);
  }

  void _setParseResult(String path, MediaFileInfo info) {
    final ok = info.exists && (info.cueCount ?? 0) > 0;
    replaceStaged(
      StagedSubtitle(
        path: path,
        info: info,
        state: ok ? StagedSubtitleState.ready : StagedSubtitleState.broken,
      ),
    );
  }

  /// 落下一批路径：音视频记到「已忽略」，不认识的格式记一句说明，其余收下。
  @override
  void handleDrop(List<String> paths) {
    final known = _ignoredMedia.toSet();
    _ignoredMedia.addAll(paths.where(MediaKinds.isMedia).where(known.add));
    dropError = rejection(paths);
    notifyIfAlive();
    add(paths);
  }

  @override
  void clear() {
    _ignoredMedia.clear();
    super.clear();
  }

  /// 「改用新建转写」：交出被忽略的音视频并从这里清掉。调用方把它们带去转写。
  List<String> takeIgnoredMedia() {
    final media = List<String>.from(_ignoredMedia);
    _ignoredMedia.clear();
    notifyIfAlive();
    return media;
  }

  /// 文件区顶部那条中性说明。没有忽略任何东西时为 null。
  String? get ignoredNote => _ignoredMedia.isEmpty
      ? null
      : '已忽略 ${_ignoredMedia.length} 个音视频文件，音视频请用「新建转写」';

  /// 会入队的文件（解析不出内容的不算）。
  List<StagedSubtitle> get enqueueable =>
      stagedFiles.where((f) => f.willEnqueue).toList();

  int get parsingCount =>
      stagedFiles.where((f) => f.state == StagedSubtitleState.parsing).length;

  int get brokenCount =>
      stagedFiles.where((f) => f.state == StagedSubtitleState.broken).length;

  /// 已解析出的总条数。仍在解析的文件不计。
  int get totalCues => stagedFiles.fold(0, (sum, f) => sum + (f.cueCount ?? 0));

  /// 已解析出的总时间跨度。
  Duration get totalDuration => stagedFiles.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  /// 按每批条数估算要调用几次翻译接口。用户调批次大小时这个数跟着变，
  /// 是「调大省调用」最直观的证据。
  int get batchCount => totalCues == 0
      ? 0
      : (totalCues + options.translationBatchSize - 1) ~/
            options.translationBatchSize;

  // —— 校验 ————————————————————————————————————————————————

  Readiness get readiness => ProviderReadiness.translation(
    options.translationProviderId,
    settings,
    model: options.translationModel,
  );

  bool get canStart => enqueueable.isNotEmpty && !readiness.isBlocked;

  String get direction =>
      '${options.sourceLanguage.name} → ${options.targetLanguage.name}';

  /// 顶栏副标题：有文件时汇总条数与方向，没有时说这页是干什么的。
  String get summary {
    final n = enqueueable.length;
    if (stagedFiles.isEmpty) return '把字幕文件翻译成目标语言';
    return '$n 个文件 · 共 ${grouped(totalCues)} 条 · $direction · '
        '将创建 $n 个翻译任务';
  }

  /// 文件表下面那句：参数怎么应用，以及这批要花几次调用。
  String get applyNote {
    final cost = totalCues == 0
        ? ''
        : '；共 ${grouped(totalCues)} 条，每批 ${options.translationBatchSize} 条，'
              '约 $batchCount 次调用';
    return '参数统一应用到每个文件$cost；单个失败不影响其余';
  }

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  FooterMessage get footer {
    if (dropErrorFooter case final dropped?) return dropped;
    if (stagedFiles.isEmpty) {
      return (text: '先添加字幕文件', tone: FooterTone.add);
    }
    final checks = [readiness];
    if (blockedFooter(checks) case final blocked?) return blocked;
    final n = enqueueable.length;
    if (n == 0 && parsingCount == 0) {
      return (text: '选中的文件都解析不出字幕内容，换几个文件再试', tone: FooterTone.error);
    }
    if (advisoryFooter(checks) case final advisory?) return advisory;
    final extras = [
      // 一个就绪的都没有时开头那句已经说了「仍在解析」，不再重复。
      if (n > 0 && parsingCount > 0) '$parsingCount 个文件仍在解析，可先开始',
      if (brokenCount > 0) '$brokenCount 个文件无法解析，将跳过',
    ];
    if (n == 0) {
      return (
        text: ['文件仍在解析，解析完即可开始', ...extras].join('；'),
        tone: FooterTone.info,
      );
    }
    return queuedFooter(n, '翻译', extras);
  }

  /// 对话框的页脚：文件区就在按钮上方，不必再说「将创建几个任务」，
  /// 改为汇总条数与语言方向。拦住或没文件时与 [footer] 相同。
  FooterMessage get compactFooter {
    final foot = footer;
    final n = enqueueable.length;
    if (foot.error || n == 0) return foot;
    final extras = [
      if (parsingCount > 0) '$parsingCount 个文件仍在解析，可先开始',
      if (brokenCount > 0) '$brokenCount 个文件无法解析，将跳过',
    ];
    return (
      text: [
        '$n 个文件 · 共 ${grouped(totalCues)} 条 · $direction',
        ...extras,
      ].join('；'),
      tone: extras.isEmpty ? FooterTone.ok : FooterTone.warning,
    );
  }

  /// 「原文件名.en.srt」这样的产物名示例，与流水线实际写出的同一条规则。
  String get outputNameExample => [
    for (final field in OutputNaming.fields(TaskKind.translate, options))
      OutputNaming.fileName('原文件名', field, options),
  ].join('、');

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    options.resolvedBilingual.label,
    '${options.cjkLineLength} / ${options.latinLineLength} 字',
    options.format.extension.toUpperCase(),
    options.outputLocation.label,
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  EnqueueRequest? submit() {
    if (!canStart) return null;
    settings.lastTranslateOptions = options;
    return EnqueueRequest(
      paths: enqueueable.map((f) => f.path).toList(),
      options: options,
    );
  }
}
