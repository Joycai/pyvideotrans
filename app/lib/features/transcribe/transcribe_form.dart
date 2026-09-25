import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/media_kinds.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/task_options.dart';
import '../../services/ffmpeg.dart';
import '../../services/readiness.dart';
import '../../services/settings.dart';
import '../shared/enqueue_request.dart';

/// 文件列表里一行的探测状态。
enum StagedFileState {
  /// 正在读时长与大小。不阻断提交 —— 时长只是辅助信息，任务跑起来会再探一遍。
  probing,
  ready,

  /// 文件不存在或读不出来。不入队，也不计入总数。
  unreadable,
}

/// 加进「新建转写」列表里的一个文件。
class StagedFile {
  const StagedFile({required this.path, this.info, required this.state});

  final String path;
  final MediaFileInfo? info;
  final StagedFileState state;

  String get fileName => baseName(path);

  /// 所在目录，用于列表副信息。
  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }

  bool get isVideo => MediaKinds.isMedia(path) && !MediaKinds.isAudio(path);

  bool get willEnqueue => state != StagedFileState.unreadable;
}

/// 「新建转写」的表单状态：文件列表、参数、校验与提交。
///
/// 对话框与导航栏的「新建转写」页共用这一份 —— 两处的字段、校验文案与就绪
/// 判断必须逐字相同，各写一份必然走形。它不碰任务队列：`submit` 只把文件与
/// 参数打包交出去，入队由调用方完成，进度归任务页。
class TranscribeFormController extends ChangeNotifier {
  TranscribeFormController({
    required this.settings,
    Ffmpeg? media,
    TaskOptions? initial,
  }) : media = media ?? Ffmpeg(),
       _options = initial ?? settings.defaultTaskOptions();

  final AppSettings settings;
  final Ffmpeg media;

  TaskOptions _options;
  TaskOptions get options => _options;

  final _files = <StagedFile>[];
  List<StagedFile> get files => List.unmodifiable(_files);

  /// 拖进来的东西不是音视频时的说明。落下即清掉上一次的。
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
    final last = settings.lastTranscribeOptions;
    if (last == null) return false;
    _options = last;
    _notify();
    return true;
  }

  bool get hasLastUsed => settings.lastTranscribeOptions != null;

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
  Future<void> add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(MediaKinds.isMedia).where(known.add).toList();
    if (fresh.isEmpty) return;
    _files.addAll([
      for (final p in fresh)
        StagedFile(path: p, state: StagedFileState.probing),
    ]);
    _notify();
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

  void _setProbeResult(String path, MediaFileInfo info) {
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return; // 探测期间被移除了。
    _files[i] = StagedFile(
      path: path,
      info: info,
      state: info.exists ? StagedFileState.ready : StagedFileState.unreadable,
    );
    _notify();
  }

  Future<void> browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList()),
      ],
    );
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  /// 落下一批路径：记下被拒的说明，收下其余。
  void handleDrop(List<String> paths) {
    _dropError = rejection(paths);
    _notify();
    add(paths);
  }

  /// 预填的一批里可能混着字幕（任务页把整把拖放原样转过来），说清楚它们去哪儿了。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }

  void remove(StagedFile file) {
    _files.removeWhere((f) => f.path == file.path);
    _notify();
  }

  void clear() {
    _files.clear();
    _dropError = null;
    _notify();
  }

  void clearDropError() {
    if (_dropError == null) return;
    _dropError = null;
    _notify();
  }

  /// 会入队的文件（读不出来的不算）。
  /// 输出位置下面那行示例：`interview_ep12.mp4 → interview_ep12.zh.srt`，
  /// 开了翻译再加上译文那份。与流水线实际写出的同一条规则。
  String get outputNameExample {
    final sample = enqueueable.firstOrNull?.fileName ?? 'interview_ep12.mp4';
    final stem = stemOf(sample);
    final names = [
      for (final field in OutputNaming.fields(_options.kind, _options))
        OutputNaming.fileName(stem, field, _options),
    ];
    return '$sample → ${names.join('、')}';
  }

  List<StagedFile> get enqueueable =>
      _files.where((f) => f.willEnqueue).toList();

  int get probingCount =>
      _files.where((f) => f.state == StagedFileState.probing).length;

  int get unreadableCount =>
      _files.where((f) => f.state == StagedFileState.unreadable).length;

  /// 已探明的总时长。仍在探测的文件不计。
  Duration get totalDuration => _files.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  // —— 校验 ————————————————————————————————————————————————

  Readiness get asrReadiness => ProviderReadiness.asr(
    _options.asrProviderId,
    settings,
    language: _options.sourceLanguage,
    model: _options.asrModel,
    diarize: _options.diarize,
  );

  Readiness get translationReadiness => ProviderReadiness.translation(
    _options.translationProviderId,
    settings,
    model: _options.translationModel,
  );

  List<Readiness> get _checks => [
    asrReadiness,
    if (_options.translate) translationReadiness,
  ];

  bool get canStart =>
      enqueueable.isNotEmpty && !_checks.any((r) => r.isBlocked);

  String get kindLabel => _options.translate ? '转写并翻译' : '转写';

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get footer {
    if (_dropError != null) {
      return (text: _dropError!, icon: Symbols.error, error: true);
    }
    final n = enqueueable.length;
    if (n == 0) {
      return (
        text: unreadableCount > 0 ? '列表里的文件都读不出来，移除或替换后再开始' : '先选择音视频文件',
        icon: unreadableCount > 0 ? Symbols.error : Symbols.add_circle,
        error: unreadableCount > 0,
      );
    }
    for (final r in _checks) {
      if (r.isBlocked) {
        return (
          text: [r.message, r.hint].nonNulls.join('，'),
          icon: Symbols.error,
          error: true,
        );
      }
    }
    for (final r in _checks) {
      if (r.level == ReadinessLevel.advisory) {
        return (text: r.message, icon: Symbols.info, error: false);
      }
    }
    final probing = probingCount > 0 ? '；$probingCount 个文件仍在探测，可先开始' : '';
    return (
      text: n == 1
          ? '将创建 1 个$kindLabel任务，加入队列后在任务页查看进度$probing'
          : '将创建 $n 个$kindLabel任务，按列表顺序排队$probing',
      icon: Symbols.info,
      error: false,
    );
  }

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    if (_options.asrPrompt.trim().isNotEmpty) '识别提示词已填' else '识别提示词',
    '每行 ${_options.cjkLineLength} / ${_options.latinLineLength}',
    '输出 ${_options.format.extension.toUpperCase()}',
    _options.outputLocation.label,
  ].join(' · ');

  /// 页面参数面板只有 400 宽，用更短的一版：格式 · 位置 · 每行字数[ · 提示词已填]。
  String get compactAdvancedSummary => [
    _options.format.extension.toUpperCase(),
    _options.outputLocation.label,
    '每行 ${_options.cjkLineLength} / ${_options.latinLineLength} 字',
    if (_options.asrPrompt.trim().isNotEmpty) '识别提示词已填',
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  EnqueueRequest? submit() {
    if (!canStart) return null;
    settings.lastTranscribeOptions = _options;
    return EnqueueRequest(
      paths: enqueueable.map((f) => f.path).toList(),
      options: _options,
    );
  }
}
