import '../enum_by_name.dart';
import '../task_options.dart';
import 'codecs.dart';
import 'encoder_catalog.dart';
import 'encoder_params.dart';

/// 输出分辨率：只缩小，不放大。
enum ResolutionLimit {
  keep('保持原样', null),
  p2160('2160p', 2160),
  p1440('1440p', 1440),
  p1080('1080p', 1080),
  p720('720p', 720),
  p480('480p', 480);

  const ResolutionLimit(this.label, this.height);

  final String label;
  final int? height;
}

/// 一个转码任务的全部参数。与 [TaskOptions] 同理：入队那一刻定死。
class TranscodeOptions {
  static const _unset = Object();

  const TranscodeOptions({
    this.mode = TranscodeMode.transcode,
    this.container = OutputContainer.mp4,
    this.videoCodec = VideoCodec.h264,
    this.encoderId = 'libx264',
    this.encoderParams = const {},
    this.resolution = ResolutionLimit.keep,
    this.fps,
    this.audioCodec = AudioCodec.aac,
    this.audioBitrate = 160,
    this.audioChannels,
    this.faststart = true,
    this.extraArgs = '',
    this.outputLocation = OutputLocation.besideSource,
    this.outputDir,
    this.suffix,
  });

  final TranscodeMode mode;
  final OutputContainer container;
  final VideoCodec videoCodec;

  /// 选中的编码器。[videoCodec] 为复制时无意义。
  final String encoderId;

  /// 当前编码器的参数值。缺项按编码器默认值补。
  final Map<String, Object> encoderParams;

  final ResolutionLimit resolution;

  /// 输出帧率；null 保持原样。
  final int? fps;

  final AudioCodec audioCodec;

  /// kbps。
  final int audioBitrate;

  /// 1 / 2；null 保持原样。
  final int? audioChannels;

  /// 把 moov 放到文件头，网页里可以边下边播。
  final bool faststart;

  /// 原样追加在输出文件前的参数。
  final String extraArgs;

  final OutputLocation outputLocation;
  final String? outputDir;

  /// 文件名后缀段；null 按编码自动取（`hevc`、`remux`）。
  final String? suffix;

  static const bitrates = [96, 128, 160, 192, 256, 320];
  static const frameRates = [60, 30, 25, 24];

  VideoEncoder? get encoder => VideoEncoders.byId(encoderId);

  bool get remux => mode == TranscodeMode.remux;

  /// 实际生效的视频编码：重混流时一律复制。
  VideoCodec get effectiveVideo => remux ? VideoCodec.copy : videoCodec;

  AudioCodec get effectiveAudio => remux ? AudioCodec.copy : audioCodec;

  /// 当前编码器的参数，补齐并收拾过。
  Map<String, Object> get resolvedParams =>
      encoder?.sanitize(encoderParams) ?? const {};

  String get resolvedSuffix {
    final s = suffix?.trim() ?? '';
    if (s.isNotEmpty) return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (remux) return 'remux';
    return effectiveVideo.suffix;
  }

  /// 换编码：编码器跟着换成该编码的默认编码器（参数用它的默认值），
  /// 除非当前编码器本来就属于这种编码。
  TranscodeOptions withVideoCodec(VideoCodec codec) {
    if (codec == videoCodec) return this;
    final keep = encoder?.codec == codec;
    final next = keep ? encoder : VideoEncoders.defaultFor(codec);
    return copyWith(
      videoCodec: codec,
      encoderId: next?.id ?? encoderId,
      encoderParams: keep ? encoderParams : (next?.defaults ?? const {}),
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'container': container.name,
    'videoCodec': videoCodec.name,
    'encoderId': encoderId,
    'encoderParams': encoderParams,
    'resolution': resolution.name,
    'fps': fps,
    'audioCodec': audioCodec.name,
    'audioBitrate': audioBitrate,
    'audioChannels': audioChannels,
    'faststart': faststart,
    'extraArgs': extraArgs,
    'outputLocation': outputLocation.name,
    'outputDir': outputDir,
    'suffix': suffix,
  };

  /// 缺项、类型不对、不认识的编码器都回落到默认，不因为一份旧存档抛异常。
  factory TranscodeOptions.fromJson(Map<String, Object?> json) {
    T? pick<T>(String key) => json[key] is T ? json[key] as T : null;
    final codec =
        VideoCodec.values.tryByName(json['videoCodec']) ?? VideoCodec.h264;
    var encoder = VideoEncoders.byId(pick<String>('encoderId'));
    if (encoder != null && encoder.codec != codec) encoder = null;
    // 编码器被换掉时存档里的参数是别家的，同名的键（crf）含义与范围也不同，全部作废。
    final rawParams = encoder == null
        ? null
        : pick<Map>('encoderParams')?.cast<String, Object?>();
    encoder ??= VideoEncoders.defaultFor(codec);
    final location =
        OutputLocation.values.tryByName(json['outputLocation']) ??
        OutputLocation.besideSource;
    final dir = pick<String>('outputDir');
    return TranscodeOptions(
      mode: TranscodeMode.values.tryByName(json['mode']) ??
          TranscodeMode.transcode,
      container:
          OutputContainer.values.tryByName(json['container']) ??
          OutputContainer.mp4,
      videoCodec: codec,
      encoderId: encoder?.id ?? '',
      encoderParams: encoder?.sanitize(rawParams) ?? const {},
      resolution:
          ResolutionLimit.values.tryByName(json['resolution']) ??
          ResolutionLimit.keep,
      fps: switch (pick<int>('fps')) {
        final f? when frameRates.contains(f) => f,
        _ => null,
      },
      audioCodec:
          AudioCodec.values.tryByName(json['audioCodec']) ?? AudioCodec.aac,
      audioBitrate: switch (pick<int>('audioBitrate')) {
        final b? when bitrates.contains(b) => b,
        _ => 160,
      },
      audioChannels: switch (pick<int>('audioChannels')) {
        final c? when c == 1 || c == 2 => c,
        _ => null,
      },
      faststart: pick<bool>('faststart') ?? true,
      extraArgs: pick<String>('extraArgs') ?? '',
      outputLocation: location == OutputLocation.custom && dir == null
          ? OutputLocation.besideSource
          : location,
      outputDir: dir,
      suffix: pick<String>('suffix'),
    );
  }

  TranscodeOptions copyWith({
    TranscodeMode? mode,
    OutputContainer? container,
    VideoCodec? videoCodec,
    String? encoderId,
    Map<String, Object>? encoderParams,
    ResolutionLimit? resolution,
    Object? fps = _unset,
    AudioCodec? audioCodec,
    int? audioBitrate,
    Object? audioChannels = _unset,
    bool? faststart,
    String? extraArgs,
    OutputLocation? outputLocation,
    Object? outputDir = _unset,
    Object? suffix = _unset,
  }) => TranscodeOptions(
    mode: mode ?? this.mode,
    container: container ?? this.container,
    videoCodec: videoCodec ?? this.videoCodec,
    encoderId: encoderId ?? this.encoderId,
    encoderParams: encoderParams ?? this.encoderParams,
    resolution: resolution ?? this.resolution,
    fps: identical(fps, _unset) ? this.fps : fps as int?,
    audioCodec: audioCodec ?? this.audioCodec,
    audioBitrate: audioBitrate ?? this.audioBitrate,
    audioChannels: identical(audioChannels, _unset)
        ? this.audioChannels
        : audioChannels as int?,
    faststart: faststart ?? this.faststart,
    extraArgs: extraArgs ?? this.extraArgs,
    outputLocation: outputLocation ?? this.outputLocation,
    outputDir: identical(outputDir, _unset)
        ? this.outputDir
        : outputDir as String?,
    suffix: identical(suffix, _unset) ? this.suffix : suffix as String?,
  );

  /// 这份参数本身有没有问题（与具体文件无关）。null 表示没问题。
  String? get problem {
    if (remux) return null;
    if (videoCodec != VideoCodec.copy) {
      if (encoder == null) return '没有选择编码器';
      if (!container.acceptsVideo(videoCodec)) {
        return '${container.label} 装不下 ${videoCodec.label} 视频，换成 MP4';
      }
    }
    if (!container.acceptsAudio(audioCodec)) {
      return '${container.label} 装不下 ${audioCodec.label} 音频，换成 MP4 或 AAC';
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 源文件信息
// ═══════════════════════════════════════════════════════════════════════
