import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/media_kinds.dart';
import '../../domain/numbers.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/task_kind.dart';
import '../../domain/task_options.dart';
import '../../services/ffmpeg.dart';
import '../../services/readiness.dart';
import '../../services/settings.dart';
import '../shared/enqueue_request.dart';

/// 字幕列表里一行的解析状态。
enum StagedSubtitleState {
  /// 正在读条数与时间跨度。不阻断提交 —— 任务跑起来会再解析一遍。
  parsing,
  ready,

  /// 一条都读不出来：空文件、编码坏、或根本不是字幕。不入队，也不计入总数。
  broken,
}

/// 加进「翻译」列表里的一个字幕文件。
class StagedSubtitle {
  const StagedSubtitle({required this.path, this.info, required this.state});

  final String path;
  final MediaFileInfo? info;
  final StagedSubtitleState state;

  String get fileName => baseName(path);

  /// 所在目录，用于列表副信息。
  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }

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
class TranslateFormController extends ChangeNotifier {
  TranslateFormController({
    required this.settings,
    Ffmpeg? media,
    TaskOptions? initial,
  }) : media = media ?? Ffmpeg(),
       _options = initial ?? settings.defaultTaskOptions();

  final AppSettings settings;
  final Ffmpeg media;

  TaskOptions _options;
  TaskOptions get options => _options;

  final _files = <StagedSubtitle>[];
  List<StagedSubtitle> get files => List.unmodifiable(_files);

  /// 被忽略的音视频路径。留着是为了「改用新建转写」能把它们原样带过去。
  final _ignoredMedia = <String>[];
  List<String> get ignoredMedia => List.unmodifiable(_ignoredMedia);

  /// 拖进来的东西既不是字幕也不是音视频时的说明。落下即清掉上一次的。
  String? _dropError;
  String? get dropError => _dropError;

  bool _advancedOpen = false;
  bool get advancedOpen => _advancedOpen;
  set advancedOpen(bool v) {
    if (_advancedOpen == v) return;
    _advancedOpen = v;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— 参数 ————————————————————————————————————————————————

  /// 改一项参数。多行输入框每个字符都会调，传 `notify: false` 省掉重建。
  void update(TaskOptions Function(TaskOptions) change, {bool notify = true}) {
    _options = change(_options);
    if (notify) _notify();
  }

  /// 恢复为设置页的默认值，不动文件列表。
  void reset() {
    _options = settings.defaultTaskOptions();
    _notify();
  }

  /// 把最近一次成功提交的参数整份填回。没有存档时返回 false，界面据此禁用按钮。
  bool applyLastUsed() {
    final last = settings.lastTranslateOptions;
    if (last == null) return false;
    _options = last;
    _notify();
    return true;
  }

  bool get hasLastUsed => settings.lastTranslateOptions != null;

  /// 原文是「自动检测」时没有东西可以换到目标那边去。
  bool get canSwapLanguages => !_options.sourceLanguage.isAuto;

  /// 原文与目标对换。不能换时什么都不做。
  void swapLanguages() {
    if (!canSwapLanguages) return;
    _options = _options.copyWith(
      sourceLanguage: _options.targetLanguage,
      targetLanguage: _options.sourceLanguage,
    );
    _notify();
  }

  Future<void> pickOutputDir() async {
    final dir = await getDirectoryPath();
    if (dir == null || _disposed) return;
    _options = _options.copyWith(
      outputDir: dir,
      outputLocation: OutputLocation.custom,
    );
    _notify();
  }

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
  Future<void> add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(MediaKinds.isSubtitle).where(known.add).toList();
    if (fresh.isEmpty) return;
    _files.addAll([
      for (final p in fresh)
        StagedSubtitle(path: p, state: StagedSubtitleState.parsing),
    ]);
    _notify();
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
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return; // 解析期间被移除了。
    final ok = info.exists && (info.cueCount ?? 0) > 0;
    _files[i] = StagedSubtitle(
      path: path,
      info: info,
      state: ok ? StagedSubtitleState.ready : StagedSubtitleState.broken,
    );
    _notify();
  }

  Future<void> browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '字幕', extensions: MediaKinds.subtitle.toList()),
      ],
    );
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  /// 落下一批路径：音视频记到「已忽略」，不认识的格式记一句说明，其余收下。
  void handleDrop(List<String> paths) {
    final known = _ignoredMedia.toSet();
    _ignoredMedia.addAll(paths.where(MediaKinds.isMedia).where(known.add));
    _dropError = rejection(paths);
    _notify();
    add(paths);
  }

  /// 预填的一批里可能混着音视频（任务页把整把拖放原样转过来），说清楚它们去哪儿了。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }

  void remove(StagedSubtitle file) {
    _files.removeWhere((f) => f.path == file.path);
    _notify();
  }

  void clear() {
    _files.clear();
    _ignoredMedia.clear();
    _dropError = null;
    _notify();
  }

  void clearDropError() {
    if (_dropError == null) return;
    _dropError = null;
    _notify();
  }

  /// 「改用新建转写」：交出被忽略的音视频并从这里清掉。调用方把它们带去转写。
  List<String> takeIgnoredMedia() {
    final media = List<String>.from(_ignoredMedia);
    _ignoredMedia.clear();
    _notify();
    return media;
  }

  /// 文件区顶部那条中性说明。没有忽略任何东西时为 null。
  String? get ignoredNote => _ignoredMedia.isEmpty
      ? null
      : '已忽略 ${_ignoredMedia.length} 个音视频文件，音视频请用「新建转写」';

  /// 会入队的文件（解析不出内容的不算）。
  List<StagedSubtitle> get enqueueable =>
      _files.where((f) => f.willEnqueue).toList();

  int get parsingCount =>
      _files.where((f) => f.state == StagedSubtitleState.parsing).length;

  int get brokenCount =>
      _files.where((f) => f.state == StagedSubtitleState.broken).length;

  /// 已解析出的总条数。仍在解析的文件不计。
  int get totalCues => _files.fold(0, (sum, f) => sum + (f.cueCount ?? 0));

  /// 已解析出的总时间跨度。
  Duration get totalDuration => _files.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  /// 按每批条数估算要调用几次翻译接口。用户调批次大小时这个数跟着变，
  /// 是「调大省调用」最直观的证据。
  int get batchCount => totalCues == 0
      ? 0
      : (totalCues + _options.translationBatchSize - 1) ~/
            _options.translationBatchSize;

  // —— 校验 ————————————————————————————————————————————————

  Readiness get readiness => ProviderReadiness.translation(
    _options.translationProviderId,
    settings,
    model: _options.translationModel,
  );

  bool get canStart => enqueueable.isNotEmpty && !readiness.isBlocked;

  String get direction =>
      '${_options.sourceLanguage.name} → ${_options.targetLanguage.name}';

  /// 顶栏副标题：有文件时汇总条数与方向，没有时说这页是干什么的。
  String get summary {
    final n = enqueueable.length;
    if (_files.isEmpty) return '把字幕文件翻译成目标语言';
    return '$n 个文件 · 共 ${grouped(totalCues)} 条 · $direction · '
        '将创建 $n 个翻译任务';
  }

  /// 文件表下面那句：参数怎么应用，以及这批要花几次调用。
  String get applyNote {
    final cost = totalCues == 0
        ? ''
        : '；共 ${grouped(totalCues)} 条，每批 ${_options.translationBatchSize} 条，'
              '约 $batchCount 次调用';
    return '参数统一应用到每个文件$cost；单个失败不影响其余';
  }

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get footer {
    if (_dropError != null) {
      return (text: _dropError!, icon: Symbols.error, error: true);
    }
    if (_files.isEmpty) {
      return (text: '先添加字幕文件', icon: Symbols.add_circle, error: false);
    }
    final r = readiness;
    if (r.isBlocked) {
      return (
        text: [r.message, r.hint].nonNulls.join('，'),
        icon: Symbols.error,
        error: true,
      );
    }
    final n = enqueueable.length;
    if (n == 0 && parsingCount == 0) {
      return (text: '选中的文件都解析不出字幕内容，换几个文件再试', icon: Symbols.error, error: true);
    }
    if (r.level == ReadinessLevel.advisory) {
      return (text: r.message, icon: Symbols.info, error: false);
    }
    final extras = [
      // 一个就绪的都没有时开头那句已经说了「仍在解析」，不再重复。
      if (n > 0 && parsingCount > 0) '$parsingCount 个文件仍在解析，可先开始',
      if (brokenCount > 0) '$brokenCount 个文件无法解析，将跳过',
    ];
    final lead = n == 0
        ? '文件仍在解析，解析完即可开始'
        : n == 1
        ? '将创建 1 个翻译任务，加入队列后在任务页查看进度'
        : '将创建 $n 个翻译任务，按列表顺序排队';
    return (
      text: [lead, ...extras].join('；'),
      icon: Symbols.info,
      error: false,
    );
  }

  /// 对话框的页脚：文件区就在按钮上方，不必再说「将创建几个任务」，
  /// 改为汇总条数与语言方向。拦住或没文件时与 [footer] 相同。
  ({String text, IconData icon, bool error}) get compactFooter {
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
      icon: extras.isEmpty ? Symbols.check_circle : Symbols.warning,
      error: false,
    );
  }

  /// 「原文件名.en.srt」这样的产物名示例，与流水线实际写出的同一条规则。
  String get outputNameExample => [
    for (final field in OutputNaming.fields(TaskKind.translate, _options))
      OutputNaming.fileName('原文件名', field, _options),
  ].join('、');

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    _options.resolvedBilingual.label,
    '${_options.cjkLineLength} / ${_options.latinLineLength} 字',
    _options.format.extension.toUpperCase(),
    _options.outputLocation.label,
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  EnqueueRequest? submit() {
    if (!canStart) return null;
    settings.lastTranslateOptions = _options;
    return EnqueueRequest(
      paths: enqueueable.map((f) => f.path).toList(),
      options: _options,
    );
  }
}
