import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../domain/cue.dart';
import '../../domain/media_kinds.dart';
import '../../domain/mux/merge_options.dart';
import '../../domain/mux/merge_rules.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../domain/task_control.dart';
import '../../domain/task_options.dart';
import '../../domain/transcode/codecs.dart';
import '../../domain/transcode/command.dart';
import '../../domain/transcode/probe.dart';
import '../../pipeline/merge_task_pipeline.dart';
import '../../services/file_io.dart';
import '../../services/settings.dart';
import '../../services/transcoder.dart';
import '../shared/footer_message.dart';

/// 合并收的字幕。ASS / SSA 进 mp4 会丢样式，等做 mkv 时一起支持。
const mergeSubtitleExtensions = {'srt', 'vtt'};

/// 列表里的一段：页面上的运行态，提交时收成 [MergeSegment]。
@immutable
class StagedSegment {
  const StagedSegment({
    required this.id,
    required this.videoPath,
    required this.chapterTitle,
    this.probe,
    this.probing = true,
    this.probeError,
    this.subtitlePath,
    this.subtitleAuto = false,
    this.subtitleParsing = false,
    this.cues,
    this.subtitleError,
    this.chapterEdited = false,
  });

  /// 稳定的 key：同一个文件可以加两次，异步结果回来按它找段。
  final String id;
  final String videoPath;

  /// 探测结果；还没读完或读不出时为 null。
  final MediaProbe? probe;
  final bool probing;

  /// ffprobe 读不出时的原因。
  final String? probeError;

  final String? subtitlePath;

  /// 添加视频时按同名自动挂上的（界面上标一下，用户可以摘）。
  final bool subtitleAuto;
  final bool subtitleParsing;

  /// 解析出的字幕；没挂、还在读或读不出时为 null。
  final List<Cue>? cues;
  final String? subtitleError;

  final String chapterTitle;
  final bool chapterEdited;

  String get fileName => baseName(videoPath);
  String get directory => dirName(videoPath);
  int? get subtitleCues => cues?.length;
  Duration? get duration => probe?.duration;

  VideoStreamInfo? get video => probe?.video.firstOrNull;
  AudioStreamInfo? get audio => probe?.audio.firstOrNull;

  /// 「H.264」与「1920×1080 · 30p」。
  String? get videoCodecLabel =>
      video == null ? null : MediaProbe.codecLabel(video!.codec);
  String? get videoShape => video?.shape;

  /// 「AAC」与「48 kHz · 2ch」；没有音轨时第一行是「无音频」。
  String? get audioCodecLabel => probe == null
      ? null
      : audio == null
      ? '无音频'
      : MediaProbe.codecLabel(audio!.codec);
  String? get audioShape => audio == null
      ? null
      : [
          if (audio!.sampleRate != null) sampleRateLabel(audio!.sampleRate!),
          if (audio!.channels != null) '${audio!.channels}ch',
        ].join(' · ');

  static const _unset = Object();

  StagedSegment copyWith({
    Object? probe = _unset,
    bool? probing,
    Object? probeError = _unset,
    Object? subtitlePath = _unset,
    bool? subtitleAuto,
    bool? subtitleParsing,
    Object? cues = _unset,
    Object? subtitleError = _unset,
    String? chapterTitle,
    bool? chapterEdited,
  }) => StagedSegment(
    id: id,
    videoPath: videoPath,
    probe: identical(probe, _unset) ? this.probe : probe as MediaProbe?,
    probing: probing ?? this.probing,
    probeError: identical(probeError, _unset)
        ? this.probeError
        : probeError as String?,
    subtitlePath: identical(subtitlePath, _unset)
        ? this.subtitlePath
        : subtitlePath as String?,
    subtitleAuto: subtitleAuto ?? this.subtitleAuto,
    subtitleParsing: subtitleParsing ?? this.subtitleParsing,
    cues: identical(cues, _unset) ? this.cues : cues as List<Cue>?,
    subtitleError: identical(subtitleError, _unset)
        ? this.subtitleError
        : subtitleError as String?,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    chapterEdited: chapterEdited ?? this.chapterEdited,
  );

  /// 摘下字幕后的样子。
  StagedSegment withoutSubtitle() => copyWith(
    subtitlePath: null,
    subtitleAuto: false,
    subtitleParsing: false,
    cues: null,
    subtitleError: null,
  );
}

/// 「合并」页的表单状态：有序段列表、每段的探测与字幕、输出参数、校验与提交。
///
/// 不继承 `NewTaskFormBase`：那个基类的前提是「每行独立成一个任务、同参数」，
/// 合并是 N 行成一个任务，行有顺序、各挂各的字幕，硬套会让基类长出特例。
/// 与其他表单同一个套路：不碰任务队列，[submit] 只把参数交出去。
class MergeFormController extends ChangeNotifier {
  MergeFormController({
    required this.settings,
    required this.transcoder,
    Future<String> Function(String path)? readSubtitle,
    Future<List<String>> Function(String dir)? listDir,
    Future<String?> Function()? pickDirectory,
    Future<List<String>> Function()? pickVideos,
    Future<String?> Function(String initialDirectory)? pickSubtitle,
  }) : _readSubtitle = readSubtitle ?? readSubtitleText,
       _listDir = listDir ?? listFiles,
       _pickDirectory = pickDirectory ?? getDirectoryPath,
       _pickVideos = pickVideos ?? _openVideos,
       _pickSubtitle = pickSubtitle ?? _openSubtitle,
       _options = settings.lastMergeOptions ?? const MergeOptions();

  final AppSettings settings;

  /// 与转码页共用同一个实例（main.dart 注入），ffmpeg 只定位一次。
  final Transcoder transcoder;

  // 平台插件与文件系统在测试里换成假的。
  final Future<String> Function(String path) _readSubtitle;
  final Future<List<String>> Function(String dir) _listDir;
  final Future<String?> Function() _pickDirectory;
  final Future<List<String>> Function() _pickVideos;
  final Future<String?> Function(String initialDirectory) _pickSubtitle;

  static const _videoTypes = XTypeGroup(
    label: '视频与字幕',
    extensions: [...MediaKinds.video, ...mergeSubtitleExtensions],
  );
  static const _subtitleTypes = XTypeGroup(
    label: '字幕',
    extensions: ['srt', 'vtt'],
  );

  static Future<List<String>> _openVideos() async => [
    for (final f in await openFiles(acceptedTypeGroups: [_videoTypes])) f.path,
  ];

  static Future<String?> _openSubtitle(String initialDirectory) async =>
      (await openFile(
        acceptedTypeGroups: [_subtitleTypes],
        initialDirectory: initialDirectory,
      ))?.path;

  // —— 状态 ————————————————————————————————————————————————

  final _segments = <StagedSegment>[];
  List<StagedSegment> get segments => List.unmodifiable(_segments);

  /// 当前参数（段不在里面，[submit] 时组装）。
  MergeOptions _options;
  MergeOptions get options => _options;

  /// 文件名被用户改过就不再跟着第 1 段走。
  bool _stemEdited = false;

  /// 上一次添加时被拒收的说明；下一次添加时清掉。
  String? _rejected;
  String? get rejected => _rejected;

  bool _advancedOpen = false;
  bool get advancedOpen => _advancedOpen;
  set advancedOpen(bool v) {
    if (_advancedOpen == v) return;
    _advancedOpen = v;
    _notify();
  }

  var _nextId = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 探测、解析、选文件都是异步的，回来时表单可能已随页面销毁。
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 字幕用不用得上：两个开关都关时，字幕读不出来也不拦开始。
  bool get _usesSubtitles =>
      _options.embedSubtitles || _options.sidecarSubtitles;

  // —— 派生 ————————————————————————————————————————————————

  /// 与 [segments] 同序；还在探测、读不出的段为 null。
  List<MergeIssue?> get issues =>
      mergeIssues([for (final s in _segments) s.probe], _options.container);

  /// 各段起点。某段之前有时长未知的段，之后都是 null。
  List<Duration?> get offsets {
    final out = <Duration?>[];
    Duration? at = Duration.zero;
    for (final s in _segments) {
      out.add(at);
      final d = s.duration;
      at = at == null || d == null ? null : at + d;
    }
    return out;
  }

  Duration? get totalDuration {
    var total = Duration.zero;
    for (final s in _segments) {
      final d = s.duration;
      if (d == null) return null;
      total += d;
    }
    return _segments.isEmpty ? null : total;
  }

  /// 挂了字幕（且解析成功）的段数。
  int get subtitledCount => _segments.where((s) => s.cues != null).length;

  /// 拼好后的字幕条数：时长都已知时按平移截尾后的算，与产物一致。
  int get cueCount {
    final starts = offsets;
    if (starts.every((o) => o != null) && totalDuration != null) {
      return concatCues([
        for (final (i, s) in _segments.indexed)
          (cues: s.cues, offset: starts[i]!, length: s.duration!),
      ]).length;
    }
    return _segments.fold(0, (n, s) => n + (s.cues?.length ?? 0));
  }

  /// 第 1 段的「H.264 1920×1080 · 30p」，顶栏用。
  String? get baseSummary {
    final first = _segments.firstOrNull;
    if (first?.video == null) return null;
    return '${first!.videoCodecLabel} ${first.videoShape}';
  }

  /// 顶栏副标题：没段时说这页做什么，有段时是段数、总长、第 1 段的参数与去向。
  String get summary {
    if (_segments.isEmpty) return '把几段视频按顺序拼成一个文件，不转码，每段一个章节';
    final n = _segments.length;
    final issues = this.issues;
    // 按种类说：第 1 段自己放不进容器时写「参数与第 1 段不一致」就自相矛盾了。
    final bad = [
      for (final (i, s) in _segments.indexed)
        if (s.probeError != null)
          '第 ${i + 1} 段读不出'
        else if (issues[i] case final issue?)
          switch (issue) {
            MergeIssue(field: _?) => '第 ${i + 1} 段参数与第 1 段不一致',
            MergeIssue(kind: MergeIssueKind.duration) => '第 ${i + 1} 段读不出时长',
            MergeIssue(:final message) => '第 ${i + 1} 段：$message',
          },
    ];
    final total = totalDuration;
    final probing = [
      for (final (i, s) in _segments.indexed)
        if (s.probing) i + 1,
    ];
    return [
      '$n 段',
      if (probing.isNotEmpty)
        '第 ${probing.first} 段读取中'
      else if (total != null)
        '共 ${Srt.formatDuration(total)}',
      if (bad.isNotEmpty)
        bad.first
      else ...[
        ?baseSummary,
        '无转码 → ${_options.container.label}',
        if (_options.chapters && probing.isEmpty) '$n 个章节',
      ],
    ].join(' · ');
  }

  String get outputFileName =>
      '${_options.outputStem.trim()}.${_options.container.extension}';

  /// 提交时要交出去的完整参数。
  MergeOptions get _full => _options.copyWith(
    segments: [
      for (final s in _segments)
        MergeSegment(
          videoPath: s.videoPath,
          // 两个字幕开关都关时字幕用不上，不交出去：排队期间字幕被挪走，
          // 准备阶段就不会因为一份用不上的文件失败。
          subtitlePath: s.cues == null || !_usesSubtitles
              ? null
              : s.subtitlePath,
          chapterTitle: s.chapterTitle.trim().isEmpty
              ? MergeSegment.defaultTitle(s.videoPath)
              : s.chapterTitle,
        ),
    ],
  );

  /// 页脚那行：挡住开始的第一条原因，都没有时是就绪那句。
  FooterMessage get footer =>
      _blocker ?? (text: _readyText, tone: FooterTone.info);

  /// 开始按钮与快捷键共用。
  bool get canStart => _blocker == null;

  /// 挡住开始的原因，按优先级取第一条：没段、段不够、参数不一致或读不出、
  /// 字幕读不出、文件名等参数问题、还在读取。
  FooterMessage? get _blocker {
    if (_segments.isEmpty) {
      return (text: '先添加至少 2 段视频', tone: FooterTone.add);
    }
    if (_segments.length < 2) {
      return (text: '至少要 2 段才能合并', tone: FooterTone.add);
    }
    final issues = this.issues;
    for (final (i, s) in _segments.indexed) {
      final n = i + 1;
      if (s.probeError != null) {
        return (text: '第 $n 段读不出音视频流，移除或换一个文件', tone: FooterTone.error);
      }
      if (issues[i] case final issue?) {
        final text = switch (issue) {
          MergeIssue(:final field?, :final expected?) =>
            '第 $n 段$field与第 1 段不同，不能无转码拼接。换掉它，或先用「转码」转成 $expected',
          MergeIssue(:final field?) => '第 $n 段$field与第 1 段不同，不能无转码拼接。换掉它',
          MergeIssue(:final message) => '第 $n 段：$message',
        };
        return (text: text, tone: FooterTone.error);
      }
    }
    if (_usesSubtitles) {
      for (final (i, s) in _segments.indexed) {
        if (s.subtitleError != null) {
          return (text: '第 ${i + 1} 段的字幕读不出来，摘下或换一个', tone: FooterTone.error);
        }
      }
    }
    if (_full.problem case final problem?) {
      return (text: problem, tone: FooterTone.error);
    }
    for (final (i, s) in _segments.indexed) {
      if (s.probing) {
        return (text: '第 ${i + 1} 段还在读取参数，读完才能开始', tone: FooterTone.info);
      }
      if (s.subtitleParsing && _usesSubtitles) {
        return (text: '第 ${i + 1} 段的字幕还在读取', tone: FooterTone.info);
      }
    }
    return null;
  }

  String get _readyText {
    final cues = cueCount;
    final subs = switch ((_options.embedSubtitles, _options.sidecarSubtitles)) {
      _ when cues == 0 => null,
      (true, true) => '字幕内嵌并旁挂 $cues 条',
      (true, false) => '字幕内嵌 $cues 条',
      (false, true) => '字幕旁挂 $cues 条',
      (false, false) => null,
    };
    return [
      '将合并成 $outputFileName',
      if (_options.chapters) '${_segments.length} 个章节',
      ?subs,
    ].join(' · ');
  }

  /// 命令预览：临时文件用占位名，与任务详情里存的命令同一套写法。
  String get commandPreview {
    return TranscodeCommand.display(
      MergeTaskPipeline.plan(
        _full,
        list: MergeTaskPipeline.listName,
        chapters: MergeTaskPipeline.chaptersName,
        subtitles: MergeTaskPipeline.subtitlesName,
        hasCues: cueCount > 0,
      ).args(outputFileName),
    );
  }

  // —— 段 ————————————————————————————————————————————————

  /// 多选时系统给的顺序不一定按文件名，按自然序排好再加 —— 列表顺序就是成片顺序。
  /// 拖入保持系统给的顺序（那是用户在访达里看到的顺序）。
  Future<void> browse() async {
    final picked = await _pickVideos();
    await addPaths(
      picked..sort((a, b) => naturalCompare(baseName(a), baseName(b))),
    );
  }

  /// 拖入与选择共用：视频追加为段（旁边有同名字幕就挂上），字幕配给同名、
  /// 还没挂字幕的段，其余拒收并说明。
  Future<void> addPaths(List<String> paths) async {
    _rejected = null;
    final videos = <String>[];
    final subtitles = <String>[];
    var ass = 0;
    var other = 0;
    for (final p in paths) {
      final ext = extensionOf(p);
      if (MediaKinds.isVideo(p)) {
        videos.add(p);
      } else if (mergeSubtitleExtensions.contains(ext)) {
        subtitles.add(p);
      } else if (ext == 'ass' || ext == 'ssa') {
        ass++;
      } else {
        other++;
      }
    }

    final fresh = [
      for (final v in videos)
        StagedSegment(
          id: '${_nextId++}',
          videoPath: v,
          chapterTitle: MergeSegment.defaultTitle(v),
        ),
    ];
    _segments.addAll(fresh);

    // 拖进来的字幕先配，再给还空着的新段找旁边的同名字幕：用户明确拖进来的优先。
    var unmatched = 0;
    // 同名的段可能不止一个（相机按日期分目录、文件名都叫 video.mp4）：
    // 同目录的优先，其次本次拖进来的新段，最后才是列表里别的段。
    final freshIds = {for (final s in fresh) s.id};
    for (final sub in subtitles) {
      int rank(StagedSegment s) =>
          sameSeparators(s.directory) == sameSeparators(dirName(sub))
          ? 0
          : freshIds.contains(s.id)
          ? 1
          : 2;
      final candidates = [
        for (final (i, s) in _segments.indexed)
          if (s.subtitlePath == null && _matches(sub, s.videoPath)) (i, s),
      ]..sort((a, b) => rank(a.$2).compareTo(rank(b.$2)));
      final i = candidates.firstOrNull?.$1 ?? -1;
      if (i < 0) {
        unmatched++;
      } else {
        _attach(i, sub, auto: false);
      }
    }

    _rejected = [
      if (ass + other > 0)
        '忽略了 ${ass + other} 个文件：${[if (ass > 0) '$ass 个 ASS 字幕（本期只支持 SRT / VTT）', if (other > 0) '$other 个不是视频或字幕'].join('，')}',
      if (unmatched > 0) '$unmatched 个字幕找不到同名的段，请在对应段上点「挂字幕…」',
    ].join('；').emptyAsNull;
    _followFirstSegment();
    _notify();

    await Future.wait([
      for (final s in fresh) ...[_probe(s.id), _findSibling(s.id)],
    ]);
  }

  /// 字幕 [subtitle] 是不是视频 [video] 的同名字幕：文件名去扩展名一样，
  /// 或去掉语言后缀（`.zh`、`.en-US`、`.zh-Hans`）后一样。
  ///
  /// 后缀限定成语言代码的样子：上次合并旁挂的 `a.merged.srt`、`ep1.old.srt`
  /// 不是 `a.mp4` / `ep1.mp4` 的字幕，挂上去会把整份时间轴压到第 1 段上。
  static bool _matches(String subtitle, String video) {
    final stem = stemOf(baseName(video));
    final sub = stemOf(baseName(subtitle));
    if (sub == stem) return true;
    if (stemOf(sub) != stem) return false;
    return _languageTag.hasMatch(sub.substring(stem.length + 1));
  }

  static final _languageTag = RegExp(r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$');

  Future<void> _probe(String id) async {
    final path = _byId(id)?.videoPath;
    if (path == null) return;
    try {
      final probe = await transcoder.probe(path);
      _update(id, (s) => s.copyWith(probe: probe, probing: false));
    } on ActionableException catch (e) {
      _update(
        id,
        (s) => s.copyWith(probing: false, probeError: e.detail ?? e.message),
      );
    } catch (e) {
      // ffprobe 输出不是合法 UTF-8 / JSON 时抛的是别的异常；不兜住的话这段
      // 永远停在「读取中」，开始按钮一直禁用又不说为什么。
      _update(id, (s) => s.copyWith(probing: false, probeError: '$e'));
    }
  }

  /// 视频旁的同名字幕：完全同名优先，其次带语言后缀的按文件名排第一个。
  Future<void> _findSibling(String id) async {
    final seg = _byId(id);
    if (seg == null || seg.subtitlePath != null) return;
    final stem = stemOf(seg.fileName);
    final List<String> listing;
    try {
      listing = await _listDir(seg.directory);
    } catch (_) {
      // 找不到同名字幕不算错，用户可以自己挂。
      return;
    }
    final candidates = [
      for (final p in listing)
        if (mergeSubtitleExtensions.contains(extensionOf(p)) &&
            _matches(p, seg.videoPath))
          p,
    ]..sort((a, b) => baseName(a).compareTo(baseName(b)));
    if (candidates.isEmpty) return;
    final exact = candidates.where((p) => stemOf(baseName(p)) == stem);
    final i = _indexOf(id);
    // 期间用户自己挂了字幕或移除了这段，就不动。
    if (i < 0 || _segments[i].subtitlePath != null) return;
    _attach(i, exact.firstOrNull ?? candidates.first, auto: true);
  }

  void _attach(int i, String path, {required bool auto}) {
    final id = _segments[i].id;
    _segments[i] = _segments[i].withoutSubtitle().copyWith(
      subtitlePath: path,
      subtitleAuto: auto,
      subtitleParsing: true,
    );
    _notify();
    unawaited(_parse(id, path));
  }

  Future<void> _parse(String id, String path) async {
    String? error;
    List<Cue>? cues;
    try {
      cues = Srt.parse(await _readSubtitle(path));
      if (cues.isEmpty) error = '没有可用的字幕条目，确认是 SRT / VTT 且时间码格式正确';
    } on FormatException {
      error = '不是 UTF-8 编码，用文本编辑器另存为 UTF-8';
    } on FileSystemException catch (e) {
      error = e.message;
    }
    // 期间换了别的字幕或摘掉了，这份结果作废。
    if (_byId(id)?.subtitlePath != path) return;
    _update(
      id,
      (s) => s.copyWith(
        subtitleParsing: false,
        cues: error == null ? cues : null,
        subtitleError: error,
      ),
    );
  }

  void clearRejected() {
    if (_rejected == null) return;
    _rejected = null;
    _notify();
  }

  Future<void> browseSubtitle(int i) async {
    final dir = _segments[i].directory;
    final id = _segments[i].id;
    final path = await _pickSubtitle(dir);
    if (path == null || _disposed) return;
    final at = _indexOf(id);
    if (at >= 0) attachSubtitle(at, path);
  }

  void attachSubtitle(int i, String path) {
    _rejected = null;
    _attach(i, path, auto: false);
  }

  void detachSubtitle(int i) {
    _segments[i] = _segments[i].withoutSubtitle();
    _notify();
  }

  void remove(int i) {
    _segments.removeAt(i);
    _followFirstSegment();
    _notify();
  }

  /// 清空视为换一批：文件名回到跟着新的第 1 段走，与提交后一致。
  void clear() {
    _segments.clear();
    _rejected = null;
    _stemEdited = false;
    _followFirstSegment();
    _notify();
  }

  /// 把第 [oldIndex] 段挪到第 [newIndex] 位（挪完之后的位置，与
  /// `ReorderableListView.onReorderItem` 一致）。
  void reorder(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    _segments.insert(newIndex, _segments.removeAt(oldIndex));
    _followFirstSegment();
    _notify();
  }

  void moveUp(int i) {
    if (i > 0) reorder(i, i - 1);
  }

  void moveDown(int i) {
    if (i < _segments.length - 1) reorder(i, i + 1);
  }

  /// 输入即写回；清空时先留着空串，失焦后再回填默认（[commitChapterTitle]）。
  void setChapterTitle(int i, String title) {
    _segments[i] = _segments[i].copyWith(
      chapterTitle: title,
      chapterEdited: true,
    );
    _notify();
  }

  void commitChapterTitle(int i) {
    if (_segments[i].chapterTitle.trim().isNotEmpty) return;
    _segments[i] = _segments[i].copyWith(
      chapterTitle: MergeSegment.defaultTitle(_segments[i].videoPath),
      chapterEdited: false,
    );
    _notify();
  }

  // —— 参数 ————————————————————————————————————————————————

  void setContainer(OutputContainer c) {
    if (!MergeOptions.containers.contains(c)) return;
    _set(_options.copyWith(container: c));
  }

  void setChapters(bool v) => _set(_options.copyWith(chapters: v));
  void setEmbedSubtitles(bool v) => _set(_options.copyWith(embedSubtitles: v));
  void setSidecarSubtitles(bool v) =>
      _set(_options.copyWith(sidecarSubtitles: v));

  void setOutputStem(String stem) {
    _stemEdited = true;
    _set(_options.copyWith(outputStem: stem));
  }

  /// 选「指定目录」而还没有目录时先弹选择框，选了才切过去 —— 与其他建任务页一致。
  void chooseOutputLocation(OutputLocation location) {
    if (location == OutputLocation.custom &&
        (_options.outputDir?.trim().isEmpty ?? true)) {
      unawaited(pickOutputDir());
      return;
    }
    _set(_options.copyWith(outputLocation: location));
  }

  Future<void> pickOutputDir() async {
    final dir = await _pickDirectory();
    if (dir == null || _disposed) return;
    _set(
      _options.copyWith(outputLocation: OutputLocation.custom, outputDir: dir),
    );
  }

  /// 恢复默认：容器、三个开关、输出位置与文件名；不动段列表、章节标题与字幕。
  void reset() {
    _stemEdited = false;
    _options = const MergeOptions();
    _followFirstSegment();
    _notify();
  }

  /// 不能开始时返回 null。成功时记住容器与三个开关、清空段列表；
  /// 输出位置保留，文件名等下一批的第 1 段决定。
  MergeOptions? submit() {
    if (!canStart) return null;
    final full = _full.copyWith(outputStem: _options.outputStem.trim());
    settings.lastMergeOptions = full;
    _segments.clear();
    _rejected = null;
    _stemEdited = false;
    _followFirstSegment();
    _notify();
    return full;
  }

  // —— 内部 ————————————————————————————————————————————————

  void _set(MergeOptions next) {
    _options = next;
    _notify();
  }

  /// 文件名没被改过时跟着第 1 段：`<第 1 段文件名>.merged`。
  void _followFirstSegment() {
    if (_stemEdited) return;
    final first = _segments.firstOrNull;
    _options = _options.copyWith(
      outputStem: first == null
          ? ''
          : MergeOptions.defaultStem(first.videoPath),
    );
  }

  int _indexOf(String id) => _segments.indexWhere((s) => s.id == id);

  StagedSegment? _byId(String id) {
    final i = _indexOf(id);
    return i < 0 ? null : _segments[i];
  }

  /// 异步结果回来按 id 找段：期间可能被移除或重排，找不到就丢弃。
  void _update(String id, StagedSegment Function(StagedSegment) change) {
    if (_disposed) return;
    final i = _indexOf(id);
    if (i < 0) return;
    _segments[i] = change(_segments[i]);
    _notify();
  }
}

extension on String {
  String? get emptyAsNull => isEmpty ? null : this;
}
