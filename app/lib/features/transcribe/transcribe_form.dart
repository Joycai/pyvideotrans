import 'package:file_selector/file_selector.dart';

import '../../domain/media_kinds.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/task_options.dart';
import '../../services/ffmpeg.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../shared/enqueue_request.dart';
import '../shared/footer_message.dart';
import '../shared/new_task_form.dart';

/// 文件列表里一行的探测状态。
enum StagedFileState {
  /// 正在读时长与大小。不阻断提交 —— 时长只是辅助信息，任务跑起来会再探一遍。
  probing,
  ready,

  /// 文件不存在或读不出来。不入队，也不计入总数。
  unreadable,
}

/// 加进「新建转写」列表里的一个文件。
class StagedFile extends StagedPath {
  const StagedFile({required super.path, this.info, required this.state});

  final MediaFileInfo? info;
  final StagedFileState state;

  bool get isVideo => MediaKinds.isMedia(path) && !MediaKinds.isAudio(path);

  bool get willEnqueue => state != StagedFileState.unreadable;
}

/// 「新建转写」的表单状态：文件列表、参数、校验与提交。
///
/// 对话框与导航栏的「新建转写」页共用这一份 —— 两处的字段、校验文案与就绪
/// 判断必须逐字相同，各写一份必然走形。它不碰任务队列：`submit` 只把文件与
/// 参数打包交出去，入队由调用方完成，进度归任务页。
///
/// 参数、文件列表、拖放说明与输出位置这些与另两个表单共有的部分在
/// [NewTaskFormBase]。
class TranscribeFormController extends TaskOptionsFormBase<StagedFile> {
  TranscribeFormController({
    required super.settings,
    Ffmpeg? media,
    super.initial,
    super.pickDirectory,
  }) : media = media ?? Ffmpeg();

  final Ffmpeg media;

  @override
  TaskOptions? get lastUsedOptions => settings.lastTranscribeOptions;

  @override
  XTypeGroup get browseTypes =>
      XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList());

  // —— 参数 ————————————————————————————————————————————————

  /// 换识别服务（规则见 [TaskOptions.withAsrProvider]）。
  void selectAsrProvider(String id) => update(
    (o) => o.withAsrProvider(
      id,
      supportsDiarization: Registry.asrInfo(id)?.supportsDiarization ?? false,
    ),
  );

  /// 换翻译服务（规则见 [TaskOptions.withTranslationProvider]）。
  void selectTranslationProvider(String id) =>
      update((o) => o.withTranslationProvider(id));

  // —— 文件 ————————————————————————————————————————————————

  /// 这批路径里不是音视频的那些该怎么跟用户解释。全都收下时返回 null。
  static String? rejection(List<String> paths) {
    final rejected = paths.where((p) => !MediaKinds.isMedia(p)).toList();
    if (rejected.isEmpty) return null;
    final subtitles = rejected.where(MediaKinds.isSubtitle).length;
    if (subtitles == rejected.length) {
      return '已忽略 $subtitles 个字幕文件，字幕请用「新建翻译」';
    }
    return '不认识的格式：'
        '${rejected.map(extensionOf).where((e) => e.isNotEmpty).toSet().join('、')}';
  }

  /// 加一批路径。非音视频与已在列表里的跳过；先以「探测中」入列，探完再更新，
  /// 用户不必等 ffprobe 跑完才看到文件出现。
  @override
  Future<void> add(List<String> paths) async {
    final fresh = stageNew(
      paths.where(MediaKinds.isMedia),
      (p) => StagedFile(path: p, state: StagedFileState.probing),
    );
    if (fresh.isEmpty) return;
    await Future.wait(fresh.map(_probe));
  }

  Future<void> _probe(String path) async {
    final MediaFileInfo info;
    try {
      info = await media.probeFile(path);
    } catch (_) {
      // A single unreadable path must not leave the row stuck in "probing"
      // or reject the whole batch.
      final fallback = MediaFileInfo(path: path, sizeBytes: 0, exists: false);
      _setProbeResult(path, fallback);
      return;
    }
    _setProbeResult(path, info);
  }

  void _setProbeResult(String path, MediaFileInfo info) => replaceStaged(
    StagedFile(
      path: path,
      info: info,
      state: info.exists ? StagedFileState.ready : StagedFileState.unreadable,
    ),
  );

  /// 落下一批路径：记下被拒的说明（比如混进来的字幕该去哪儿），收下其余。
  @override
  void handleDrop(List<String> paths) {
    dropError = rejection(paths);
    notifyIfAlive();
    add(paths);
  }

  /// 输出位置下面那行示例：`interview_ep12.mp4 → interview_ep12.zh.srt`，
  /// 开了翻译再加上译文那份。与流水线实际写出的同一条规则。
  String get outputNameExample {
    final sample = enqueueable.firstOrNull?.fileName ?? 'interview_ep12.mp4';
    final stem = stemOf(sample);
    final names = [
      for (final field in OutputNaming.fields(options.kind, options))
        OutputNaming.fileName(stem, field, options),
    ];
    return '$sample → ${names.join('、')}';
  }

  /// 会入队的文件（读不出来的不算）。
  List<StagedFile> get enqueueable =>
      stagedFiles.where((f) => f.willEnqueue).toList();

  int get probingCount =>
      stagedFiles.where((f) => f.state == StagedFileState.probing).length;

  int get unreadableCount =>
      stagedFiles.where((f) => f.state == StagedFileState.unreadable).length;

  /// 已探明的总时长。仍在探测的文件不计。
  Duration get totalDuration => stagedFiles.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  // —— 校验 ————————————————————————————————————————————————

  Readiness get asrReadiness => ProviderReadiness.asr(
    options.asrProviderId,
    settings,
    language: options.sourceLanguage,
    model: options.asrModel,
    diarize: options.diarize,
  );

  Readiness get translationReadiness => ProviderReadiness.translation(
    options.translationProviderId,
    settings,
    model: options.translationModel,
  );

  List<Readiness> get _checks => [
    asrReadiness,
    if (options.translate) translationReadiness,
  ];

  bool get canStart =>
      enqueueable.isNotEmpty && !_checks.any((r) => r.isBlocked);

  String get kindLabel => options.translate ? '转写并翻译' : '转写';

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  FooterMessage get footer {
    if (dropErrorFooter case final dropped?) return dropped;
    final n = enqueueable.length;
    if (n == 0) {
      return (
        text: unreadableCount > 0 ? '列表里的文件都读不出来，移除或替换后再开始' : '先选择音视频文件',
        tone: unreadableCount > 0 ? FooterTone.error : FooterTone.add,
      );
    }
    final checks = _checks;
    if (blockedFooter(checks) ?? advisoryFooter(checks) case final gate?) {
      return gate;
    }
    return queuedFooter(n, kindLabel, [
      if (probingCount > 0) '$probingCount 个文件仍在探测，可先开始',
    ]);
  }

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    if (options.asrPrompt.trim().isNotEmpty) '识别提示词已填' else '识别提示词',
    '每行 ${options.cjkLineLength} / ${options.latinLineLength}',
    '输出 ${options.format.extension.toUpperCase()}',
    options.outputLocation.label,
  ].join(' · ');

  /// 页面参数面板只有 400 宽，用更短的一版：格式 · 位置 · 每行字数[ · 提示词已填]。
  String get compactAdvancedSummary => [
    options.format.extension.toUpperCase(),
    options.outputLocation.label,
    '每行 ${options.cjkLineLength} / ${options.latinLineLength} 字',
    if (options.asrPrompt.trim().isNotEmpty) '识别提示词已填',
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  EnqueueRequest? submit() {
    if (!canStart) return null;
    settings.lastTranscribeOptions = options;
    return EnqueueRequest(
      paths: enqueueable.map((f) => f.path).toList(),
      options: options,
    );
  }
}
