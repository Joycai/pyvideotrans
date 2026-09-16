
/// 转码方式。
enum TranscodeMode {
  transcode('转码'),

  /// 不重新编码，原样把音视频流复制进新容器。
  remux('仅重混流');

  const TranscodeMode(this.label);

  final String label;
}

/// 输出容器。
enum OutputContainer {
  mp4('MP4', 'mp4'),
  mov('MOV', 'mov');

  const OutputContainer(this.label, this.extension);

  final String label;
  final String extension;

  /// 能不能装下这种**编码出来的**视频。MOV 装不下 AV1（ffmpeg 的 mov 封装器不收）。
  bool acceptsVideo(VideoCodec codec) => switch (codec) {
    VideoCodec.av1 => this == mp4,
    _ => true,
  };

  /// Opus 只有 MP4 收。
  bool acceptsAudio(AudioCodec codec) => switch (codec) {
    AudioCodec.opus => this == mp4,
    _ => true,
  };

  /// 原样复制时，源文件里的这路视频（ffprobe 的 codec_name）能不能放进来。
  ///
  /// 用黑名单不用白名单：白名单漏掉一个冷门但合法的编码，就会把能跑的文件
  /// 错判成跳过；黑名单漏判的，任务会失败并带上 ffmpeg 的原话，损失小得多。
  /// 名单经本机 ffmpeg 实测。
  ///
  /// 两种容器的名单不一样：MOV 收 WMV2、FLAC 却不收，MP4 反过来。
  /// VC-1 在 MP4 里有标准的 `vc-1` 标签，可以复制；WMV3（WMV9 Main）不行。
  bool acceptsVideoCopy(String codecName) => !switch (this) {
    mp4 => const {
      'wmv1', 'wmv2', 'wmv3', 'flv1', 'vp6', 'vp6f', 'vp6a',
      'rv10', 'rv20', 'rv30', 'rv40', 'msmpeg4v1', 'msmpeg4v2', 'msmpeg4v3',
      'theora', 'cinepak',
    },
    mov => const {
      'av1', 'vp8', 'vp9', 'vc1', 'wmv3', 'flv1', 'vp6', 'vp6f', 'vp6a',
      'rv10', 'rv20', 'rv30', 'rv40', 'theora',
    },
  }.contains(codecName);

  /// 原样复制时，源文件里的这路音频能不能放进来。
  bool acceptsAudioCopy(String codecName) => !switch (this) {
    mp4 => const {
      'vorbis', 'wmav1', 'wmav2', 'wmapro', 'wmalossless', 'wmavoice',
      'cook', 'ra_144', 'ra_288', 'sipr', 'atrac3', 'nellymoser',
    },
    mov => const {
      'vorbis', 'opus', 'flac', 'wmav1', 'wmav2', 'wmapro', 'wmalossless',
      'wmavoice', 'cook', 'ra_144', 'ra_288', 'sipr', 'atrac3', 'truehd',
    },
  }.contains(codecName);

  static OutputContainer byName(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? mp4;
}

/// 视频编码。
enum VideoCodec {
  h264('H.264', 'AVC · x264'),
  hevc('HEVC', 'H.265 · x265'),
  av1('AV1', 'AOMedia Video 1'),

  /// 视频流原样复制，只转音频或只换容器。
  copy('复制', '不重新编码');

  const VideoCodec(this.label, this.description);

  final String label;
  final String description;

  /// 产物文件名里的默认后缀段。
  String get suffix => switch (this) {
    VideoCodec.copy => 'copy',
    _ => name,
  };

  static VideoCodec byName(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? h264;
}

/// 音频编码。
enum AudioCodec {
  aac('AAC', 'aac'),
  mp3('MP3', 'libmp3lame'),

  /// 只有 MP4 收。不提供 Vorbis（OGG 音频）：MP4 / MOV 都装不下它。
  opus('Opus', 'libopus'),
  copy('复制', 'copy');

  const AudioCodec(this.label, this.encoder);

  final String label;

  /// 首选的 ffmpeg 编码器名。
  final String encoder;

  /// 首选编码器没编进来时的替补，以及它需要的额外参数（原生 opus 编码器
  /// 标记为实验性）。
  (String, List<String>)? get fallback => switch (this) {
    AudioCodec.opus => ('opus', ['-strict', '-2']),
    _ => null,
  };

  static AudioCodec byName(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? aac;
}
