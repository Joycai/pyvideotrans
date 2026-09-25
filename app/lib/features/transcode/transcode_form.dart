import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/media_kinds.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../domain/task_control.dart';
import '../../domain/task_options.dart';
import '../../domain/transcode/codecs.dart';
import '../../domain/transcode/command.dart';
import '../../domain/transcode/encoder_catalog.dart';
import '../../domain/transcode/encoder_params.dart';
import '../../domain/transcode/options.dart';
import '../../domain/transcode/probe.dart';
import '../../services/ffmpeg.dart';
import '../../services/settings.dart';
import '../../services/transcoder.dart';

/// 文件列表里一行的状态。
enum StagedVideoState {
  /// ffprobe 还在读。
  probing,
  ready,

  /// 读得出来，但按当前参数有一路流放不进容器（只会出现在复制流时）。
  /// 参数一改可能就好了，所以是按参数实时算的，不是读完就定死。
  incompatible,

  /// ffprobe 读不出音视频流。
  broken,
}

/// 加进「转码」列表的一个视频。
class StagedVideo {
  const StagedVideo({
    required this.path,
    this.sizeBytes = 0,
    this.probe,
    this.error,
    this.probing = true,
  });

  final String path;
  final int sizeBytes;
  final MediaProbe? probe;

  /// 读不出来时的原因。
  final String? error;
  final bool probing;

  String get fileName => baseName(path);

  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }

  String get sizeLabel =>
      MediaFileInfo(path: path, sizeBytes: sizeBytes).sizeLabel;

  String get durationLabel => probe?.duration == null
      ? '—'
      : Srt.formatDuration(probe!.duration!);

  VideoStreamInfo? get video => probe?.video.firstOrNull;
  AudioStreamInfo? get audio => probe?.audio.firstOrNull;
}

/// 「转码」页的表单状态：视频列表、参数、编码器可用性、校验与提交。
///
/// 与翻译页的表单同一个套路：不碰任务队列，`submit` 只把文件与参数交出去。
/// 多出来的一件事是**按编码器记住参数**：用户在 NVENC 下调好了 CQ 与预设，
/// 切去看一眼 x264 再切回来，NVENC 那一套还在 —— 两家的参数名都不一样，
/// 切换时丢掉就得重调一遍。
class TranscodeFormController extends ChangeNotifier {
  TranscodeFormController({
    required this.settings,
    required this.transcoder,
    TranscodeOptions? initial,
    Future<int> Function(String path)? fileSize,
  }) : _options = initial ?? defaults,
       _fileSize = fileSize ?? _defaultFileSize {
    transcoder.addListener(_notify);
  }

  final AppSettings settings;
  final Transcoder transcoder;

  /// 读文件大小。截图测试里换成假的：真 IO 在测试的假时钟里不会完成。
  final Future<int> Function(String path) _fileSize;

  static Future<int> _defaultFileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  /// 默认参数：H.264 · x264 · CRF 23 · AAC 160k · MP4。
  static TranscodeOptions get defaults => TranscodeOptions(
    encoderParams: VideoEncoders.defaultFor(VideoCodec.h264)!.defaults,
  );

  TranscodeOptions _options;
  TranscodeOptions get options => _options;

  /// 各编码器上次的参数值。
  final _memory = <String, Map<String, Object>>{};

  final _files = <StagedVideo>[];
  List<StagedVideo> get files => List.unmodifiable(_files);

  String? _dropError;
  String? get dropError => _dropError;

  bool _advancedOpen = false;
  bool get advancedOpen => _advancedOpen;
  set advancedOpen(bool v) {
    if (_advancedOpen == v) return;
    _advancedOpen = v;
    _notify();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    transcoder.removeListener(_notify);
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— 参数 ————————————————————————————————————————————————

  void update(
    TranscodeOptions Function(TranscodeOptions) change, {
    bool notify = true,
  }) {
    _options = change(_options);
    if (notify) _notify();
  }

  void reset() {
    _memory.clear();
    _options = defaults;
    _notify();
  }

  bool get hasLastUsed => settings.lastTranscodeOptions != null;

  bool applyLastUsed() {
    final last = settings.lastTranscodeOptions;
    if (last == null) return false;
    _options = last;
    _notify();
    return true;
  }

  void _remember() {
    if (_options.encoder != null) {
      _memory[_options.encoderId] = _options.resolvedParams;
    }
  }

  /// 换编码。优先挑一个可用的编码器：当前编码器属于这种编码就留着，
  /// 否则取目录里第一个可用的（通常是 CPU），参数取它上次的值。
  void setVideoCodec(VideoCodec codec) {
    if (codec == _options.videoCodec) return;
    _remember();
    final candidates = VideoEncoders.forCodec(codec);
    final next =
        candidates.where((e) => transcoder.status(e.id).usable).firstOrNull ??
        candidates.firstOrNull;
    _options = _options.copyWith(
      videoCodec: codec,
      encoderId: next?.id ?? '',
      encoderParams: next == null ? const {} : (_memory[next.id] ?? next.defaults),
    );
    _notify();
  }

  void selectEncoder(String id) {
    final encoder = VideoEncoders.byId(id);
    if (encoder == null || id == _options.encoderId) return;
    _remember();
    _options = _options.copyWith(
      videoCodec: encoder.codec,
      encoderId: id,
      encoderParams: _memory[id] ?? encoder.defaults,
    );
    _notify();
  }

  /// 改当前编码器的一项参数。数字框每次按键都会调，传 `notify: false`。
  void setParam(String key, Object value, {bool notify = true}) {
    final encoder = _options.encoder;
    if (encoder == null) return;
    final next = {..._options.resolvedParams, key: value};
    _options = _options.copyWith(encoderParams: encoder.sanitize(next));
    if (notify) _notify();
  }

  /// 换容器。新容器装不下当前音频编码（MOV 不收 Opus）时改成 AAC ——
  /// 与设计稿一致：不留一个必然被拦下的选择让用户回头去找。
  void setContainer(OutputContainer container) {
    if (container == _options.container) return;
    final audio = container.acceptsAudio(_options.audioCodec)
        ? _options.audioCodec
        : AudioCodec.aac;
    _options = _options.copyWith(container: container, audioCodec: audio);
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

  /// 当前编码下的编码器卡片。
  List<(VideoEncoder, EncoderStatus)> get encoderChoices => [
    for (final e in VideoEncoders.forCodec(_options.videoCodec))
      (e, transcoder.status(e.id)),
  ];

  // —— 文件 ————————————————————————————————————————————————

  static String? rejection(List<String> paths) {
    final unknown = paths
        .where((p) => !MediaKinds.isVideo(p))
        .map(extensionOf)
        .toSet();
    if (unknown.isEmpty) return null;
    final audio = paths.where(MediaKinds.isAudio).length;
    if (audio == paths.where((p) => !MediaKinds.isVideo(p)).length) {
      return '已忽略 $audio 个音频文件，转码页只收视频';
    }
    return '已忽略不认识的格式：${unknown.where((e) => e.isNotEmpty).join('、')}';
  }

  Future<void> add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(MediaKinds.isVideo).where(known.add).toList();
    if (fresh.isEmpty) return;
    _files.addAll([for (final p in fresh) StagedVideo(path: p)]);
    _notify();
    // 首次加文件时顺带检测编码器，结果出来之前卡片显示检测中。
    unawaited(transcoder.ensureProbed());
    await Future.wait(fresh.map(_probe));
  }

  Future<void> _probe(String path) async {
    final size = await _fileSize(path);
    StagedVideo result;
    try {
      final probe = await transcoder.probe(path);
      result = StagedVideo(path: path, sizeBytes: size, probe: probe, probing: false);
    } on ActionableException catch (e) {
      result = StagedVideo(path: path, sizeBytes: size, error: e.message, probing: false);
    } catch (e) {
      result = StagedVideo(path: path, sizeBytes: size, error: '$e', probing: false);
    }
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return;
    _files[i] = result;
    _notify();
  }

  Future<void> browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '视频', extensions: MediaKinds.video.toList()),
      ],
    );
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  void handleDrop(List<String> paths) {
    _dropError = rejection(paths);
    _notify();
    add(paths);
  }

  void remove(StagedVideo file) {
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

  StagedVideoState stateOf(StagedVideo file) {
    if (file.probing) return StagedVideoState.probing;
    final probe = file.probe;
    if (probe == null) return StagedVideoState.broken;
    return probe.incompatibility(_options) == null
        ? StagedVideoState.ready
        : StagedVideoState.incompatible;
  }

  /// 行里第二行小字：目录，或者为什么会被跳过。
  String? problemOf(StagedVideo file) => switch (stateOf(file)) {
    StagedVideoState.broken => 'ffprobe 读不出音视频流，将跳过',
    StagedVideoState.incompatible =>
      '${file.probe!.incompatibility(_options)}，将跳过；改为转码即可',
    _ => null,
  };

  /// 会入队的文件：读完且兼容的，以及还在读的（跑起来准备阶段会再核对一次）。
  List<StagedVideo> get enqueueable => _files.where((f) {
    final s = stateOf(f);
    return s == StagedVideoState.ready || s == StagedVideoState.probing;
  }).toList();

  int get probingCount =>
      _files.where((f) => stateOf(f) == StagedVideoState.probing).length;

  int get skippedCount => _files.where((f) {
    final s = stateOf(f);
    return s == StagedVideoState.broken || s == StagedVideoState.incompatible;
  }).length;

  Duration get totalDuration => _files.fold(
    Duration.zero,
    (sum, f) => sum + (f.probe?.duration ?? Duration.zero),
  );

  // —— 校验 ————————————————————————————————————————————————

  /// 挡住开始的原因。null 表示可以开始（前提是有文件）。
  String? get blocker {
    if (transcoder.ffmpegProblem != null) {
      final hint = transcoder.ffmpegHint;
      return hint == null ? '找不到 FFmpeg' : '找不到 FFmpeg。$hint';
    }
    final problem = _options.problem;
    if (problem != null) return problem;
    final encoder = _options.encoder;
    if (!_options.remux &&
        _options.videoCodec != VideoCodec.copy &&
        encoder != null) {
      final status = transcoder.status(encoder.id);
      if (status.state == EncoderState.notCompiled ||
          status.state == EncoderState.failed) {
        return '${encoder.id} 在这台电脑上不可用，换一个编码器';
      }
    }
    return null;
  }

  bool get canStart => enqueueable.isNotEmpty && blocker == null;

  /// 「HEVC · VideoToolbox → MP4」。
  String get target {
    if (_options.remux) return '仅重混流 → ${_options.container.label}';
    final video = switch (_options.videoCodec) {
      VideoCodec.copy => '复制视频',
      final c => '${c.label} · ${_options.encoder?.backend.label ?? '—'}',
    };
    return '$video → ${_options.container.label}';
  }

  String get summary {
    if (_files.isEmpty) return '用 FFmpeg 把视频转成其他编码，或不转码直接换容器';
    final n = enqueueable.length;
    final total = totalDuration;
    return [
      '${_files.length} 个视频',
      if (total > Duration.zero) '共 ${Srt.formatDuration(total)}',
      target,
      '将创建 $n 个转码任务',
    ].join(' · ');
  }

  String get applyNote {
    final where = _options.outputLocation == OutputLocation.custom &&
            (_options.outputDir?.isNotEmpty ?? false)
        ? '输出写到指定目录'
        : '输出写到源文件旁';
    return '参数统一应用到每个文件；$where，文件名加 .${_options.resolvedSuffix} 后缀，不覆盖原文件';
  }

  ({String text, IconData icon, bool error}) get footer {
    if (_files.isEmpty) {
      return (text: '先添加视频', icon: Symbols.add_circle, error: false);
    }
    final block = blocker;
    if (block != null) return (text: block, icon: Symbols.error, error: true);
    final n = enqueueable.length;
    if (n == 0) {
      return (
        text: '选中的文件都无法按当前参数转码，换参数或换文件再试',
        icon: Symbols.error,
        error: true,
      );
    }
    final extras = [
      if (probingCount > 0) '$probingCount 个文件仍在读取，可先开始',
      if (skippedCount > 0) '$skippedCount 个文件不兼容，将跳过',
    ];
    final lead = n == 1
        ? '将创建 1 个转码任务，加入队列后在任务页查看进度'
        : '将创建 $n 个转码任务，按列表顺序排队';
    return (text: [lead, ...extras].join('；'), icon: Symbols.info, error: false);
  }

  /// 产物名示例：`interview.hevc.mp4`。
  String outputNameFor(String input) {
    final stem = stemOf(baseName(input));
    return '$stem.${_options.resolvedSuffix}.${_options.container.extension}';
  }

  String get advancedSummary => [
    _options.outputLocation.label,
    '后缀 .${_options.resolvedSuffix}',
    if (_options.faststart) '快速启动',
    if (_options.extraArgs.trim().isNotEmpty) '有额外参数',
  ].join(' · ');

  /// 命令预览：用列表里第一个文件，没有文件时用示例名。
  String get commandPreview {
    final input = _files.firstOrNull?.fileName ?? 'input.mkv';
    return TranscodeCommand.display(
      TranscodeCommand.build(
        options: _options,
        input: input,
        output: outputNameFor(input),
        audioEncoder: transcoder.audioEncoder(_options.effectiveAudio),
      ),
    );
  }

  /// 打包交出去并记为「上次参数」。不能开始时返回 null。
  ({List<String> paths, TranscodeOptions options})? submit() {
    if (!canStart) return null;
    settings.lastTranscodeOptions = _options;
    return (paths: enqueueable.map((f) => f.path).toList(), options: _options);
  }

  /// 给「拖错了门」的场景用：把一批路径直接放进来。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }
}
