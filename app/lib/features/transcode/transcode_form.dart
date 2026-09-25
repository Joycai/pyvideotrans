import 'dart:async';

import 'package:file_selector/file_selector.dart';

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
import '../../services/file_io.dart';
import '../../services/transcoder.dart';
import '../shared/footer_message.dart';
import '../shared/new_task_form.dart';

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
class StagedVideo extends StagedPath {
  const StagedVideo({
    required super.path,
    this.sizeBytes = 0,
    this.probe,
    this.error,
    this.probing = true,
  });

  final int sizeBytes;
  final MediaProbe? probe;

  /// 读不出来时的原因。
  final String? error;
  final bool probing;

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
class TranscodeFormController
    extends NewTaskFormBase<TranscodeOptions, StagedVideo> {
  TranscodeFormController({
    required super.settings,
    required this.transcoder,
    TranscodeOptions? initial,
    Future<int> Function(String path)? fileSize,
    super.pickDirectory,
  }) : _fileSize = fileSize ?? fileLength,
       super(initial: initial ?? defaults) {
    transcoder.addListener(notifyIfAlive);
  }

  final Transcoder transcoder;

  /// 读文件大小。截图测试里换成假的：真 IO 在测试的假时钟里不会完成。
  final Future<int> Function(String path) _fileSize;

  /// 默认参数：H.264 · x264 · CRF 23 · AAC 160k · MP4。
  static TranscodeOptions get defaults => TranscodeOptions(
    encoderParams: VideoEncoders.defaultFor(VideoCodec.h264)!.defaults,
  );

  /// 各编码器上次的参数值。
  final _memory = <String, Map<String, Object>>{};

  @override
  void dispose() {
    transcoder.removeListener(notifyIfAlive);
    super.dispose();
  }

  @override
  TranscodeOptions get defaultOptions => defaults;

  @override
  TranscodeOptions? get lastUsedOptions => settings.lastTranscodeOptions;

  @override
  String? outputDirOf(TranscodeOptions o) => o.outputDir;

  @override
  TranscodeOptions withOutput(
    TranscodeOptions o,
    OutputLocation location, {
    String? dir,
  }) => dir == null
      ? o.copyWith(outputLocation: location)
      : o.copyWith(outputLocation: location, outputDir: dir);

  @override
  XTypeGroup get browseTypes =>
      XTypeGroup(label: '视频', extensions: MediaKinds.video.toList());

  // —— 参数 ————————————————————————————————————————————————

  /// 恢复默认，连同各编码器记住的参数一起忘掉。
  @override
  void reset() {
    _memory.clear();
    super.reset();
  }

  void _remember() {
    if (options.encoder != null) {
      _memory[options.encoderId] = options.resolvedParams;
    }
  }

  /// 换编码。优先挑一个可用的编码器：当前编码器属于这种编码就留着，
  /// 否则取目录里第一个可用的（通常是 CPU），参数取它上次的值。
  void setVideoCodec(VideoCodec codec) {
    if (codec == options.videoCodec) return;
    _remember();
    final candidates = VideoEncoders.forCodec(codec);
    final next =
        candidates.where((e) => transcoder.status(e.id).usable).firstOrNull ??
        candidates.firstOrNull;
    options = options.copyWith(
      videoCodec: codec,
      encoderId: next?.id ?? '',
      encoderParams: next == null ? const {} : (_memory[next.id] ?? next.defaults),
    );
    notifyIfAlive();
  }

  void selectEncoder(String id) {
    final encoder = VideoEncoders.byId(id);
    if (encoder == null || id == options.encoderId) return;
    _remember();
    options = options.copyWith(
      videoCodec: encoder.codec,
      encoderId: id,
      encoderParams: _memory[id] ?? encoder.defaults,
    );
    notifyIfAlive();
  }

  /// 改当前编码器的一项参数。数字框每次按键都会调，传 `notify: false`。
  void setParam(String key, Object value, {bool notify = true}) {
    final encoder = options.encoder;
    if (encoder == null) return;
    final next = {...options.resolvedParams, key: value};
    options = options.copyWith(encoderParams: encoder.sanitize(next));
    if (notify) notifyIfAlive();
  }

  /// 换容器。新容器装不下当前音频编码（MOV 不收 Opus）时改成 AAC ——
  /// 与设计稿一致：不留一个必然被拦下的选择让用户回头去找。
  void setContainer(OutputContainer container) {
    if (container == options.container) return;
    final audio = container.acceptsAudio(options.audioCodec)
        ? options.audioCodec
        : AudioCodec.aac;
    options = options.copyWith(container: container, audioCodec: audio);
    notifyIfAlive();
  }

  /// 检测这台机器上哪些编码器能用；已经测过就不再测。
  Future<void> probeEncoders() => transcoder.ensureProbed();

  /// 「重新检测」：换了 ffmpeg 或装了驱动之后再测一遍。
  Future<void> recheckEncoders() => transcoder.refresh();

  bool get probingEncoders => transcoder.isProbing;

  /// 当前编码下的编码器卡片。
  List<(VideoEncoder, EncoderStatus)> get encoderChoices => [
    for (final e in VideoEncoders.forCodec(options.videoCodec))
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

  @override
  Future<void> add(List<String> paths) async {
    final fresh = stageNew(
      paths.where(MediaKinds.isVideo),
      (p) => StagedVideo(path: p),
    );
    if (fresh.isEmpty) return;
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
    replaceStaged(result);
  }

  @override
  void handleDrop(List<String> paths) {
    dropError = rejection(paths);
    notifyIfAlive();
    add(paths);
  }

  StagedVideoState stateOf(StagedVideo file) {
    if (file.probing) return StagedVideoState.probing;
    final probe = file.probe;
    if (probe == null) return StagedVideoState.broken;
    return probe.incompatibility(options) == null
        ? StagedVideoState.ready
        : StagedVideoState.incompatible;
  }

  /// 行里第二行小字：目录，或者为什么会被跳过。
  String? problemOf(StagedVideo file) => switch (stateOf(file)) {
    StagedVideoState.broken => 'ffprobe 读不出音视频流，将跳过',
    StagedVideoState.incompatible =>
      '${file.probe!.incompatibility(options)}，将跳过；改为转码即可',
    _ => null,
  };

  /// 会入队的文件：读完且兼容的，以及还在读的（跑起来准备阶段会再核对一次）。
  List<StagedVideo> get enqueueable => stagedFiles.where((f) {
    final s = stateOf(f);
    return s == StagedVideoState.ready || s == StagedVideoState.probing;
  }).toList();

  int get probingCount =>
      stagedFiles.where((f) => stateOf(f) == StagedVideoState.probing).length;

  int get skippedCount => stagedFiles.where((f) {
    final s = stateOf(f);
    return s == StagedVideoState.broken || s == StagedVideoState.incompatible;
  }).length;

  Duration get totalDuration => stagedFiles.fold(
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
    final problem = options.problem;
    if (problem != null) return problem;
    final encoder = options.encoder;
    if (!options.remux &&
        options.videoCodec != VideoCodec.copy &&
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
    if (options.remux) return '仅重混流 → ${options.container.label}';
    final video = switch (options.videoCodec) {
      VideoCodec.copy => '复制视频',
      final c => '${c.label} · ${options.encoder?.backend.label ?? '—'}',
    };
    return '$video → ${options.container.label}';
  }

  String get summary {
    if (stagedFiles.isEmpty) return '用 FFmpeg 把视频转成其他编码，或不转码直接换容器';
    final n = enqueueable.length;
    final total = totalDuration;
    return [
      '${stagedFiles.length} 个视频',
      if (total > Duration.zero) '共 ${Srt.formatDuration(total)}',
      target,
      '将创建 $n 个转码任务',
    ].join(' · ');
  }

  String get applyNote {
    final where = options.outputLocation == OutputLocation.custom &&
            (options.outputDir?.isNotEmpty ?? false)
        ? '输出写到指定目录'
        : '输出写到源文件旁';
    return '参数统一应用到每个文件；$where，文件名加 .${options.resolvedSuffix} 后缀，不覆盖原文件';
  }

  FooterMessage get footer {
    if (stagedFiles.isEmpty) {
      return (text: '先添加视频', tone: FooterTone.add);
    }
    final block = blocker;
    if (block != null) return (text: block, tone: FooterTone.error);
    final n = enqueueable.length;
    if (n == 0) {
      return (
        text: '选中的文件都无法按当前参数转码，换参数或换文件再试',
        tone: FooterTone.error,
      );
    }
    final extras = [
      if (probingCount > 0) '$probingCount 个文件仍在读取，可先开始',
      if (skippedCount > 0) '$skippedCount 个文件不兼容，将跳过',
    ];
    return queuedFooter(n, '转码', extras);
  }

  /// 产物名示例：`interview.hevc.mp4`。
  String outputNameFor(String input) {
    final stem = stemOf(baseName(input));
    return '$stem.${options.resolvedSuffix}.${options.container.extension}';
  }

  String get advancedSummary => [
    options.outputLocation.label,
    '后缀 .${options.resolvedSuffix}',
    if (options.faststart) '快速启动',
    if (options.extraArgs.trim().isNotEmpty) '有额外参数',
  ].join(' · ');

  /// 命令预览：用列表里第一个文件，没有文件时用示例名。
  String get commandPreview {
    final input = stagedFiles.firstOrNull?.fileName ?? 'input.mkv';
    return TranscodeCommand.display(
      TranscodeCommand.build(
        options: options,
        input: input,
        output: outputNameFor(input),
        audioEncoder: transcoder.audioEncoder(options.effectiveAudio),
      ),
    );
  }

  /// 打包交出去并记为「上次参数」。不能开始时返回 null。
  ({List<String> paths, TranscodeOptions options})? submit() {
    if (!canStart) return null;
    settings.lastTranscodeOptions = options;
    return (paths: enqueueable.map((f) => f.path).toList(), options: options);
  }
}
