import 'task_options.dart';

/// 转码：FFmpeg 的图形外壳。
///
/// 这里只有数据与规则 —— 编码器目录、每个编码器自己的参数表、容器兼容性、
/// 以及把这些拼成一条 ffmpeg 命令。跑进程、测编码器可不可用在 services 里。
///
/// 为什么参数表按编码器定义而不是做一套通用的「质量 / 速度」：同样是 H.264，
/// x264 用 CRF 与 preset（ultrafast…veryslow），NVENC 用 CQ 与 p1…p7，
/// QSV 用 ICQ，AMF 用 CQP，VideoToolbox 只有 -q:v。硬抽象成一套就只能取交集，
/// 各家真正有用的开关全被藏掉；映射表还会悄悄改变用户以为自己选了的东西。

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

  /// 能不能装下这种**编码出来的**视频。VC-1 本来就没有编码器，这里不管。
  /// MOV 装不下 AV1（ffmpeg 的 mov 封装器不收）。
  bool acceptsVideo(VideoCodec codec) => switch (codec) {
    VideoCodec.av1 => this == mp4,
    _ => true,
  };

  /// Vorbis 两种容器都装不下；Opus 只有 MP4 收。
  bool acceptsAudio(AudioCodec codec) => switch (codec) {
    AudioCodec.vorbis => false,
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

  /// FFmpeg 没有 VC-1 编码器，只能解码。列出来是为了说清楚为什么选不了，
  /// 以及 VC-1 源文件该怎么办（复制 / 仅重混流）。
  vc1('VC-1', 'SMPTE 421M'),

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

  /// Ogg 家族里能放进 MP4 的那个。
  opus('Opus', 'libopus'),

  /// 即 OGG 音频。MP4 / MOV 都装不下，界面上灰显并说明。
  vorbis('Vorbis', 'libvorbis'),
  copy('复制', 'copy');

  const AudioCodec(this.label, this.encoder);

  final String label;

  /// 首选的 ffmpeg 编码器名。
  final String encoder;

  /// 首选编码器没编进来时的替补，以及它需要的额外参数。
  /// Homebrew 的 ffmpeg 就没带 libvorbis，只有标记为实验性的原生 vorbis。
  (String, List<String>)? get fallback => switch (this) {
    AudioCodec.opus => ('opus', ['-strict', '-2']),
    AudioCodec.vorbis => ('vorbis', ['-strict', '-2']),
    _ => null,
  };

  static AudioCodec byName(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? aac;
}

/// 编码器由谁来跑。
enum EncoderBackend {
  cpu('CPU', '软件编码'),
  videotoolbox('VideoToolbox', 'Apple'),
  nvenc('NVENC', 'NVIDIA'),
  qsv('QSV', 'Intel'),
  amf('AMF', 'AMD');

  const EncoderBackend(this.label, this.vendor);

  final String label;
  final String vendor;

  bool get isHardware => this != cpu;
}

// ═══════════════════════════════════════════════════════════════════════
// 参数表
// ═══════════════════════════════════════════════════════════════════════

/// 编码器的一项参数。值只有三种类型：String（选项）、int、bool。
sealed class EncoderParam {
  const EncoderParam({
    required this.key,
    required this.label,
    this.hint,
    this.visibleWhen,
  });

  final String key;
  final String label;
  final String? hint;

  /// 只在另一项取某些值时出现：码率控制选 CRF 时只显示 CRF，选码率时只显示码率。
  final ({String key, Set<String> values})? visibleWhen;

  Object get defaultValue;

  /// 把存档或界面里来的值收拾成合法值；类型不对或越界的回落到默认。
  Object sanitize(Object? raw);

  bool isVisible(Map<String, Object> values) {
    final when = visibleWhen;
    return when == null || when.values.contains(values[when.key]);
  }
}

class ChoiceParam extends EncoderParam {
  const ChoiceParam({
    required super.key,
    required super.label,
    required this.options,
    required this.defaultOption,
    this.segmented = false,
    super.hint,
    super.visibleWhen,
  });

  /// (值, 界面文案)。值原样进命令行。
  final List<(String, String)> options;
  final String defaultOption;

  /// 选项少且短时用分段控件，否则用下拉。
  final bool segmented;

  @override
  Object get defaultValue => defaultOption;

  @override
  Object sanitize(Object? raw) =>
      options.any((o) => o.$1 == raw) ? raw! : defaultOption;

  String labelOf(Object? value) =>
      options.where((o) => o.$1 == value).firstOrNull?.$2 ?? '$value';
}

class IntParam extends EncoderParam {
  const IntParam({
    required super.key,
    required super.label,
    required this.min,
    required this.max,
    required this.defaultInt,
    this.unit,
    super.hint,
    super.visibleWhen,
  });

  final int min;
  final int max;
  final int defaultInt;

  /// 数值框后面的单位，如「kbps」。
  final String? unit;

  @override
  Object get defaultValue => defaultInt;

  @override
  Object sanitize(Object? raw) =>
      raw is int ? raw.clamp(min, max) : defaultInt;
}

class BoolParam extends EncoderParam {
  const BoolParam({
    required super.key,
    required super.label,
    this.defaultBool = false,
    super.hint,
    super.visibleWhen,
  });

  final bool defaultBool;

  @override
  Object get defaultValue => defaultBool;

  @override
  Object sanitize(Object? raw) => raw is bool ? raw : defaultBool;
}

/// 一个编码器产出的命令行片段：放在 `-i` 前面的（硬件解码）与后面的。
typedef EncoderArgs = ({List<String> input, List<String> output});

/// 编码器目录里的一项。
class VideoEncoder {
  const VideoEncoder({
    required this.id,
    required this.codec,
    required this.backend,
    required this.params,
    required this.build,
    this.note,
  });

  /// ffmpeg 里的编码器名：`libx264`、`hevc_nvenc`。
  final String id;
  final VideoCodec codec;
  final EncoderBackend backend;
  final List<EncoderParam> params;

  /// 参数值 → 命令行。拿到的值已经过 [sanitize]。
  final EncoderArgs Function(Map<String, Object> values) build;

  /// 卡片上的补充说明，例如「需要 RTX 40 系列及以上」。
  final String? note;

  /// 「x265 · CPU」「NVENC · NVIDIA」。
  String get title => backend == EncoderBackend.cpu
      ? '${_cpuNames[id] ?? id} · CPU'
      : '${backend.label} · ${backend.vendor}';

  static const _cpuNames = {
    'libx264': 'x264',
    'libx265': 'x265',
    'libsvtav1': 'SVT-AV1',
    'libaom-av1': 'libaom',
  };

  Map<String, Object> get defaults => {
    for (final p in params) p.key: p.defaultValue,
  };

  /// 补齐缺项、收拾非法值、丢掉不认识的键。
  Map<String, Object> sanitize(Map<String, Object?>? raw) => {
    for (final p in params) p.key: p.sanitize(raw?[p.key]),
  };

  EncoderParam? param(String key) =>
      params.where((p) => p.key == key).firstOrNull;
}

// —— 各家共用的参数片段 ————————————————————————————————————————

const _qualityHint = '数值越小画质越高、文件越大。';

IntParam _bitrate({required Set<String> when, int def = 6000}) => IntParam(
  key: 'bitrate',
  label: '码率',
  min: 100,
  max: 200000,
  defaultInt: def,
  unit: 'kbps',
  visibleWhen: (key: 'rc', values: when),
);

ChoiceParam _profile(VideoCodec codec, {bool baseline = true}) => ChoiceParam(
  key: 'profile',
  label: 'Profile',
  defaultOption: 'auto',
  options: switch (codec) {
    VideoCodec.hevc => const [('auto', '自动'), ('main', 'main'), ('main10', 'main10')],
    _ => [
      ('auto', '自动'),
      if (baseline) ('baseline', 'baseline'),
      ('main', 'main'),
      ('high', 'high'),
    ],
  },
);

BoolParam _hwdec(String label, {bool def = false}) => BoolParam(
  key: 'hwdec',
  label: label,
  defaultBool: def,
  hint: '解码也交给硬件。个别源文件硬件解不了时关掉它再试。',
);

List<String> _profileArgs(Map<String, Object> v) =>
    v['profile'] == 'auto' || v['profile'] == null
    ? const []
    : ['-profile:v', '${v['profile']}'];

/// H.264 一律压成 8 位 4:2:0：10 位或 4:2:2 的 H.264 几乎没有播放器认，
/// 硬件编码器更是直接拒收。
List<String> _pixFmt(VideoCodec codec, Map<String, Object> v, {String h264 = 'yuv420p'}) =>
    switch (codec) {
      VideoCodec.h264 => ['-pix_fmt', h264],
      VideoCodec.hevc when v['profile'] == 'main10' => ['-pix_fmt', 'p010le'],
      _ => const [],
    };

/// Apple 设备只认 hvc1 标签的 HEVC；ffmpeg 默认写 hev1。
List<String> _tag(VideoCodec codec) =>
    codec == VideoCodec.hevc ? const ['-tag:v', 'hvc1'] : const [];

// —— CPU ———————————————————————————————————————————————————————

const _x26xPresets = [
  ('ultrafast', 'ultrafast'),
  ('superfast', 'superfast'),
  ('veryfast', 'veryfast'),
  ('faster', 'faster'),
  ('fast', 'fast'),
  ('medium', 'medium'),
  ('slow', 'slow'),
  ('slower', 'slower'),
  ('veryslow', 'veryslow'),
];

VideoEncoder _x26x(VideoCodec codec) {
  final x265 = codec == VideoCodec.hevc;
  return VideoEncoder(
    id: x265 ? 'libx265' : 'libx264',
    codec: codec,
    backend: EncoderBackend.cpu,
    params: [
      const ChoiceParam(
        key: 'rc',
        label: '码率控制',
        segmented: true,
        defaultOption: 'crf',
        options: [('crf', 'CRF 恒定质量'), ('abr', '平均码率')],
      ),
      IntParam(
        key: 'crf',
        label: 'CRF',
        min: 0,
        max: 51,
        defaultInt: x265 ? 28 : 23,
        hint: '$_qualityHint${x265 ? '22' : '18'} 左右肉眼无损。',
        visibleWhen: (key: 'rc', values: const {'crf'}),
      ),
      _bitrate(when: const {'abr'}),
      const ChoiceParam(
        key: 'preset',
        label: '预设',
        defaultOption: 'medium',
        options: _x26xPresets,
        hint: '越慢压缩率越高，画质相同时文件更小。',
      ),
      ChoiceParam(
        key: 'tune',
        label: '调优',
        defaultOption: 'none',
        options: [
          ('none', '不指定'),
          if (!x265) ('film', 'film'),
          ('animation', 'animation'),
          ('grain', 'grain'),
          if (!x265) ('stillimage', 'stillimage'),
          ('fastdecode', 'fastdecode'),
          ('zerolatency', 'zerolatency'),
        ],
      ),
      _profile(codec),
    ],
    build: (v) => (
      input: const [],
      output: [
        '-c:v', x265 ? 'libx265' : 'libx264',
        '-preset', '${v['preset']}',
        if (v['tune'] != 'none') ...['-tune', '${v['tune']}'],
        ..._profileArgs(v),
        if (v['rc'] == 'crf') ...['-crf', '${v['crf']}']
        else ...['-b:v', '${v['bitrate']}k'],
        ..._pixFmt(codec, v),
        ..._tag(codec),
        // x265 默认往 stderr 刷一大段编码统计，把真正的报错淹掉。
        if (x265) ...['-x265-params', 'log-level=error'],
      ],
    ),
  );
}

final _svtAv1 = VideoEncoder(
  id: 'libsvtav1',
  codec: VideoCodec.av1,
  backend: EncoderBackend.cpu,
  params: [
    const ChoiceParam(
      key: 'rc',
      label: '码率控制',
      segmented: true,
      defaultOption: 'crf',
      options: [('crf', 'CRF 恒定质量'), ('abr', '平均码率')],
    ),
    const IntParam(
      key: 'crf',
      label: 'CRF',
      min: 0,
      max: 63,
      defaultInt: 35,
      hint: _qualityHint,
      visibleWhen: (key: 'rc', values: {'crf'}),
    ),
    _bitrate(when: const {'abr'}, def: 4000),
    const IntParam(
      key: 'preset',
      label: '预设',
      min: 0,
      max: 13,
      defaultInt: 8,
      hint: '0 最慢、压缩最好，13 最快。',
    ),
    const IntParam(
      key: 'filmGrain',
      label: '胶片颗粒',
      min: 0,
      max: 50,
      defaultInt: 0,
      hint: '合成颗粒去噪后再加回，适合老电影。0 为关闭。',
    ),
  ],
  build: (v) => (
    input: const [],
    output: [
      '-c:v', 'libsvtav1',
      '-preset', '${v['preset']}',
      if (v['rc'] == 'crf') ...['-crf', '${v['crf']}']
      else ...['-b:v', '${v['bitrate']}k'],
      if ((v['filmGrain'] as int) > 0) ...[
        '-svtav1-params', 'film-grain=${v['filmGrain']}',
      ],
    ],
  ),
);

final _aomAv1 = VideoEncoder(
  id: 'libaom-av1',
  codec: VideoCodec.av1,
  backend: EncoderBackend.cpu,
  params: [
    const IntParam(
      key: 'crf',
      label: 'CRF',
      min: 0,
      max: 63,
      defaultInt: 30,
      hint: _qualityHint,
    ),
    const IntParam(
      key: 'cpuUsed',
      label: '速度 cpu-used',
      min: 0,
      max: 8,
      defaultInt: 6,
      hint: '0 最慢最好，8 最快。libaom 很慢，没有 SVT-AV1 时才用它。',
    ),
  ],
  build: (v) => (
    input: const [],
    output: [
      '-c:v', 'libaom-av1',
      '-crf', '${v['crf']}',
      '-b:v', '0',
      '-cpu-used', '${v['cpuUsed']}',
      '-row-mt', '1',
    ],
  ),
);

// —— VideoToolbox ————————————————————————————————————————————————

VideoEncoder _videotoolbox(VideoCodec codec) => VideoEncoder(
  id: '${codec.name}_videotoolbox',
  codec: codec,
  backend: EncoderBackend.videotoolbox,
  params: [
    const ChoiceParam(
      key: 'rc',
      label: '码率控制',
      segmented: true,
      defaultOption: 'quality',
      options: [('quality', '恒定质量'), ('abr', '平均码率'), ('cbr', '固定码率')],
    ),
    const IntParam(
      key: 'quality',
      label: '质量',
      min: 1,
      max: 100,
      defaultInt: 65,
      hint: '数值越大画质越高。恒定质量只有 Apple 芯片支持，Intel Mac 请用码率。',
      visibleWhen: (key: 'rc', values: {'quality'}),
    ),
    _bitrate(when: const {'abr', 'cbr'}),
    _profile(codec),
    const BoolParam(
      key: 'prioSpeed',
      label: '优先速度',
      hint: '牺牲一点压缩率换编码速度。',
    ),
    const BoolParam(
      key: 'allowSw',
      label: '允许回退到软件编码',
      hint: '硬件忙或不支持当前分辨率时，由系统改用软件编码，不报错。',
    ),
    _hwdec('硬件解码', def: true),
  ],
  build: (v) => (
    input: v['hwdec'] == true ? const ['-hwaccel', 'videotoolbox'] : const [],
    output: [
      '-c:v', '${codec.name}_videotoolbox',
      if (v['rc'] == 'quality') ...['-q:v', '${v['quality']}']
      else ...['-b:v', '${v['bitrate']}k'],
      if (v['rc'] == 'cbr') ...['-constant_bit_rate', '1'],
      ..._profileArgs(v),
      if (v['prioSpeed'] == true) ...['-prio_speed', '1'],
      if (v['allowSw'] == true) ...['-allow_sw', '1'],
      ..._pixFmt(codec, v),
      ..._tag(codec),
    ],
  ),
);

// —— NVENC ———————————————————————————————————————————————————————

VideoEncoder _nvenc(VideoCodec codec) => VideoEncoder(
  id: '${codec.name}_nvenc',
  codec: codec,
  backend: EncoderBackend.nvenc,
  note: codec == VideoCodec.av1 ? '需要 RTX 40 系列及以上' : null,
  params: [
    const ChoiceParam(
      key: 'preset',
      label: '预设',
      segmented: true,
      defaultOption: 'p4',
      options: [
        ('p1', 'p1'), ('p2', 'p2'), ('p3', 'p3'), ('p4', 'p4'),
        ('p5', 'p5'), ('p6', 'p6'), ('p7', 'p7'),
      ],
      hint: 'p1 最快，p7 画质最好。',
    ),
    const ChoiceParam(
      key: 'tune',
      label: '调优',
      defaultOption: 'hq',
      options: [
        ('hq', 'hq 高画质'),
        ('ll', 'll 低延迟'),
        ('ull', 'ull 超低延迟'),
        ('lossless', 'lossless 无损'),
      ],
    ),
    const ChoiceParam(
      key: 'rc',
      label: '码率控制',
      segmented: true,
      defaultOption: 'cq',
      options: [('cq', 'CQ 恒定质量'), ('vbr', 'VBR'), ('cbr', 'CBR')],
    ),
    const IntParam(
      key: 'cq',
      label: 'CQ',
      min: 0,
      max: 51,
      defaultInt: 23,
      hint: _qualityHint,
      visibleWhen: (key: 'rc', values: {'cq'}),
    ),
    _bitrate(when: const {'vbr', 'cbr'}),
    const IntParam(
      key: 'maxrate',
      label: '最大码率',
      min: 0,
      max: 400000,
      defaultInt: 0,
      unit: 'kbps',
      hint: '0 为不限制。',
      visibleWhen: (key: 'rc', values: {'vbr'}),
    ),
    const ChoiceParam(
      key: 'multipass',
      label: '多遍编码',
      defaultOption: 'disabled',
      options: [
        ('disabled', '关闭'),
        ('qres', '四分之一分辨率'),
        ('fullres', '全分辨率'),
      ],
    ),
    const IntParam(
      key: 'lookahead',
      label: '前瞻帧数',
      min: 0,
      max: 32,
      defaultInt: 0,
      hint: '0 为关闭。开启后码率分配更合理，占用更多显存。',
    ),
    const BoolParam(key: 'spatialAq', label: '空间自适应量化 AQ'),
    if (codec != VideoCodec.av1) _profile(codec),
    _hwdec('CUDA 硬件解码'),
  ],
  build: (v) => (
    input: v['hwdec'] == true ? const ['-hwaccel', 'cuda'] : const [],
    output: [
      '-c:v', '${codec.name}_nvenc',
      '-preset', '${v['preset']}',
      '-tune', '${v['tune']}',
      ...switch (v['rc']) {
        'cq' => ['-rc', 'vbr', '-cq', '${v['cq']}', '-b:v', '0'],
        'cbr' => ['-rc', 'cbr', '-b:v', '${v['bitrate']}k'],
        _ => [
          '-rc', 'vbr', '-b:v', '${v['bitrate']}k',
          if ((v['maxrate'] as int) > 0) ...['-maxrate', '${v['maxrate']}k'],
        ],
      },
      if (v['multipass'] != 'disabled') ...['-multipass', '${v['multipass']}'],
      if ((v['lookahead'] as int) > 0) ...['-rc-lookahead', '${v['lookahead']}'],
      if (v['spatialAq'] == true) ...['-spatial-aq', '1'],
      ..._profileArgs(v),
      ..._pixFmt(codec, v),
      ..._tag(codec),
    ],
  ),
);

// —— QSV —————————————————————————————————————————————————————————

VideoEncoder _qsv(VideoCodec codec) => VideoEncoder(
  id: '${codec.name}_qsv',
  codec: codec,
  backend: EncoderBackend.qsv,
  note: codec == VideoCodec.av1 ? '需要 Arc 独显或 Core Ultra 核显' : null,
  params: [
    const ChoiceParam(
      key: 'preset',
      label: '预设',
      defaultOption: 'medium',
      options: [
        ('veryfast', 'veryfast'),
        ('faster', 'faster'),
        ('fast', 'fast'),
        ('medium', 'medium'),
        ('slow', 'slow'),
        ('slower', 'slower'),
        ('veryslow', 'veryslow'),
      ],
    ),
    const ChoiceParam(
      key: 'rc',
      label: '码率控制',
      segmented: true,
      defaultOption: 'icq',
      options: [('icq', 'ICQ 恒定质量'), ('vbr', 'VBR'), ('cbr', 'CBR')],
    ),
    const IntParam(
      key: 'quality',
      label: 'ICQ',
      min: 1,
      max: 51,
      defaultInt: 23,
      hint: _qualityHint,
      visibleWhen: (key: 'rc', values: {'icq'}),
    ),
    _bitrate(when: const {'vbr', 'cbr'}),
    if (codec == VideoCodec.h264)
      const BoolParam(
        key: 'lookAhead',
        label: '前瞻 Look-ahead',
        hint: '码率分配更合理，速度稍慢。',
      ),
    if (codec != VideoCodec.av1) _profile(codec),
    _hwdec('QSV 硬件解码'),
  ],
  build: (v) => (
    input: v['hwdec'] == true ? const ['-hwaccel', 'qsv'] : const [],
    output: [
      '-c:v', '${codec.name}_qsv',
      '-preset', '${v['preset']}',
      ...switch (v['rc']) {
        'icq' => ['-global_quality', '${v['quality']}'],
        'cbr' => [
          '-b:v', '${v['bitrate']}k',
          '-maxrate', '${v['bitrate']}k',
        ],
        _ => ['-b:v', '${v['bitrate']}k'],
      },
      if (v['lookAhead'] == true) ...['-look_ahead', '1'],
      ..._profileArgs(v),
      ..._pixFmt(codec, v, h264: 'nv12'),
      ..._tag(codec),
    ],
  ),
);

// —— AMF —————————————————————————————————————————————————————————

VideoEncoder _amf(VideoCodec codec) => VideoEncoder(
  id: '${codec.name}_amf',
  codec: codec,
  backend: EncoderBackend.amf,
  note: codec == VideoCodec.av1 ? '需要 RX 7000 系列及以上' : null,
  params: [
    const ChoiceParam(
      key: 'quality',
      label: '质量档',
      segmented: true,
      defaultOption: 'balanced',
      options: [('speed', '速度'), ('balanced', '均衡'), ('quality', '质量')],
    ),
    const ChoiceParam(
      key: 'rc',
      label: '码率控制',
      segmented: true,
      defaultOption: 'cqp',
      options: [('cqp', 'CQP 固定量化'), ('vbr_peak', 'VBR 峰值'), ('cbr', 'CBR')],
    ),
    const IntParam(
      key: 'qp',
      label: 'QP',
      min: 0,
      max: 51,
      defaultInt: 23,
      hint: '$_qualityHint I 帧与 P 帧用同一个值。',
      visibleWhen: (key: 'rc', values: {'cqp'}),
    ),
    _bitrate(when: const {'vbr_peak', 'cbr'}),
    const BoolParam(
      key: 'preanalysis',
      label: '预分析',
      hint: '编码前先分析画面复杂度，码率分配更合理。',
    ),
    if (codec == VideoCodec.h264)
      const ChoiceParam(
        key: 'profile',
        label: 'Profile',
        defaultOption: 'auto',
        options: [('auto', '自动'), ('main', 'main'), ('high', 'high')],
      ),
    _hwdec('D3D11 硬件解码'),
  ],
  build: (v) => (
    input: v['hwdec'] == true ? const ['-hwaccel', 'd3d11va'] : const [],
    output: [
      '-c:v', '${codec.name}_amf',
      '-quality', '${v['quality']}',
      ...switch (v['rc']) {
        'cqp' => [
          '-rc', 'cqp',
          '-qp_i', '${v['qp']}',
          '-qp_p', '${v['qp']}',
          if (codec == VideoCodec.h264) ...['-qp_b', '${v['qp']}'],
        ],
        final rc => ['-rc', '$rc', '-b:v', '${v['bitrate']}k'],
      },
      if (v['preanalysis'] == true) ...['-preanalysis', '1'],
      ..._profileArgs(v),
      ..._pixFmt(codec, v, h264: 'nv12'),
      ..._tag(codec),
    ],
  ),
);

/// 编码器目录。每种编码内的顺序就是界面上卡片的顺序：CPU 在前，
/// 然后 VideoToolbox、NVENC、QSV、AMF。
abstract final class VideoEncoders {
  static final List<VideoEncoder> all = [
    _x26x(VideoCodec.h264),
    _videotoolbox(VideoCodec.h264),
    _nvenc(VideoCodec.h264),
    _qsv(VideoCodec.h264),
    _amf(VideoCodec.h264),
    _x26x(VideoCodec.hevc),
    _videotoolbox(VideoCodec.hevc),
    _nvenc(VideoCodec.hevc),
    _qsv(VideoCodec.hevc),
    _amf(VideoCodec.hevc),
    _svtAv1,
    _aomAv1,
    _nvenc(VideoCodec.av1),
    _qsv(VideoCodec.av1),
    _amf(VideoCodec.av1),
  ];

  static List<VideoEncoder> forCodec(VideoCodec codec) =>
      all.where((e) => e.codec == codec).toList();

  static VideoEncoder? byId(String? id) =>
      all.where((e) => e.id == id).firstOrNull;

  /// 某种编码的默认编码器：目录里的第一个（CPU）。
  static VideoEncoder? defaultFor(VideoCodec codec) =>
      forCodec(codec).firstOrNull;
}

// ═══════════════════════════════════════════════════════════════════════
// 任务参数
// ═══════════════════════════════════════════════════════════════════════

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

  static ResolutionLimit byName(Object? name) =>
      values.where((r) => r.name == name).firstOrNull ?? keep;
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
    final codec = VideoCodec.byName(json['videoCodec']);
    var encoder = VideoEncoders.byId(pick<String>('encoderId'));
    if (encoder != null && encoder.codec != codec) encoder = null;
    // 编码器被换掉时存档里的参数是别家的，同名的键（crf）含义与范围也不同，全部作废。
    final rawParams = encoder == null
        ? null
        : pick<Map>('encoderParams')?.cast<String, Object?>();
    encoder ??= VideoEncoders.defaultFor(codec);
    final location = OutputLocation.values
            .where((l) => l.name == json['outputLocation'])
            .firstOrNull ??
        OutputLocation.besideSource;
    final dir = pick<String>('outputDir');
    return TranscodeOptions(
      mode: TranscodeMode.values
              .where((m) => m.name == json['mode'])
              .firstOrNull ??
          TranscodeMode.transcode,
      container: OutputContainer.byName(json['container']),
      videoCodec: codec,
      encoderId: encoder?.id ?? '',
      encoderParams: encoder?.sanitize(rawParams) ?? const {},
      resolution: ResolutionLimit.byName(json['resolution']),
      fps: switch (pick<int>('fps')) {
        final f? when frameRates.contains(f) => f,
        _ => null,
      },
      audioCodec: AudioCodec.byName(json['audioCodec']),
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
    if (videoCodec == VideoCodec.vc1) {
      return 'FFmpeg 没有 VC-1 编码器，VC-1 源文件请用「复制」或「仅重混流」';
    }
    if (videoCodec != VideoCodec.copy) {
      if (encoder == null) return '没有选择编码器';
      if (!container.acceptsVideo(videoCodec)) {
        return '${container.label} 装不下 ${videoCodec.label} 视频，换成 MP4';
      }
    }
    if (!container.acceptsAudio(audioCodec)) {
      return audioCodec == AudioCodec.vorbis
          ? 'MP4 与 MOV 都装不下 Vorbis（OGG 音频），换成 Opus 或 AAC'
          : '${container.label} 装不下 ${audioCodec.label} 音频，换成 MP4 或 AAC';
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 源文件信息
// ═══════════════════════════════════════════════════════════════════════

class VideoStreamInfo {
  const VideoStreamInfo({
    required this.codec,
    this.width,
    this.height,
    this.fps,
    this.pixFmt,
  });

  final String codec;
  final int? width;
  final int? height;
  final double? fps;
  final String? pixFmt;

  /// 「3840×2160 · 60p」。
  String get shape => [
    if (width != null && height != null) '$width×$height',
    if (fps != null) '${fps! % 1 == 0 ? fps!.toInt() : fps!.toStringAsFixed(2)}p',
  ].join(' · ');
}

class AudioStreamInfo {
  const AudioStreamInfo({required this.codec, this.channels});

  final String codec;
  final int? channels;
}

/// ffprobe 读出的流信息。附图（封面）不算视频流。
class MediaProbe {
  const MediaProbe({
    this.duration,
    this.video = const [],
    this.audio = const [],
    this.subtitleCount = 0,
  });

  final Duration? duration;
  final List<VideoStreamInfo> video;
  final List<AudioStreamInfo> audio;
  final int subtitleCount;

  bool get isEmpty => video.isEmpty && audio.isEmpty;

  /// 解析 `ffprobe -show_streams -show_format -of json` 的输出。
  factory MediaProbe.fromJson(Map<String, Object?> json) {
    final streams = (json['streams'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => s.cast<String, Object?>());
    final video = <VideoStreamInfo>[];
    final audio = <AudioStreamInfo>[];
    var subs = 0;
    for (final s in streams) {
      final codec = s['codec_name'] as String? ?? 'unknown';
      final disposition = s['disposition'];
      final attachedPic =
          disposition is Map && disposition['attached_pic'] == 1;
      switch (s['codec_type']) {
        case 'video' when !attachedPic:
          video.add(
            VideoStreamInfo(
              codec: codec,
              width: s['width'] as int?,
              height: s['height'] as int?,
              fps: _rate(s['avg_frame_rate']) ?? _rate(s['r_frame_rate']),
              pixFmt: s['pix_fmt'] as String?,
            ),
          );
        case 'audio':
          audio.add(
            AudioStreamInfo(codec: codec, channels: s['channels'] as int?),
          );
        case 'subtitle':
          subs++;
      }
    }
    final seconds = double.tryParse(
      '${(json['format'] as Map?)?['duration'] ?? ''}',
    );
    return MediaProbe(
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      video: video,
      audio: audio,
      subtitleCount: subs,
    );
  }

  /// 「30000/1001」→ 29.97；「0/0」→ null。
  static double? _rate(Object? raw) {
    final parts = '$raw'.split('/');
    if (parts.length != 2) return double.tryParse('$raw');
    final n = double.tryParse(parts[0]);
    final d = double.tryParse(parts[1]);
    if (n == null || d == null || d == 0 || n == 0) return null;
    return (n / d * 100).round() / 100;
  }

  /// 按 [options] 转进 [container] 时哪路流放不进去。null 表示都能放。
  String? incompatibility(TranscodeOptions options) {
    final container = options.container;
    if (options.effectiveVideo == VideoCodec.copy) {
      for (final v in video) {
        if (!container.acceptsVideoCopy(v.codec)) {
          return '${codecLabel(v.codec)} 视频不能直接放进 ${container.label}';
        }
      }
    }
    if (options.effectiveAudio == AudioCodec.copy) {
      for (final a in audio) {
        if (!container.acceptsAudioCopy(a.codec)) {
          return '${codecLabel(a.codec)} 音频不能直接放进 ${container.label}';
        }
      }
    }
    return null;
  }

  /// ffprobe 的编码名 → 界面上的写法。
  static String codecLabel(String codec) => switch (codec) {
    'h264' => 'H.264',
    'hevc' => 'HEVC',
    'av1' => 'AV1',
    'vc1' => 'VC-1',
    'vp9' => 'VP9',
    'vp8' => 'VP8',
    'mpeg4' => 'MPEG-4',
    'mpeg2video' => 'MPEG-2',
    'prores' => 'ProRes',
    'wmv3' => 'WMV3',
    'wmv2' => 'WMV2',
    'aac' => 'AAC',
    'mp3' => 'MP3',
    'opus' => 'Opus',
    'vorbis' => 'Vorbis',
    'flac' => 'FLAC',
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'dts' => 'DTS',
    'truehd' => 'TrueHD',
    'alac' => 'ALAC',
    final c when c.startsWith('wma') => 'WMA',
    final c when c.startsWith('pcm_') => 'PCM',
    final c => c.toUpperCase(),
  };
}

/// 挂在转码任务上的状态：参数、准备阶段读出的源信息、定下来的产物路径与命令。
class TranscodeJob {
  TranscodeJob({
    required this.options,
    this.sourceVideo,
    this.sourceAudio,
    this.outputPath,
    this.command,
    this.outputBytes,
  });

  final TranscodeOptions options;

  /// 「HEVC」「3840×2160 · 60p」这类摘要，准备阶段填。
  String? sourceVideo;
  String? sourceAudio;

  /// 准备阶段定下。续跑沿用同一个路径，不会越跑越多 `-2`、`-3`。
  String? outputPath;

  /// 实际执行的命令（给人看的形式），详情面板里可复制。
  String? command;

  /// 完成后的产物大小。
  int? outputBytes;

  /// 「HEVC → MP4」：源视频编码 → 目标。
  String get direction {
    final target = options.remux
        ? options.container.label
        : options.effectiveVideo == VideoCodec.copy
        ? options.container.label
        : '${options.videoCodec.label} · ${options.container.label}';
    return '${sourceVideo ?? '视频'} → $target';
  }

  /// 用的是哪个编码器；复制视频时为 null。
  VideoEncoder? get encoder =>
      options.effectiveVideo == VideoCodec.copy ? null : options.encoder;

  Map<String, Object?> toJson() => {
    'options': options.toJson(),
    'sourceVideo': sourceVideo,
    'sourceAudio': sourceAudio,
    'outputPath': outputPath,
    'command': command,
    'outputBytes': outputBytes,
  };

  factory TranscodeJob.fromJson(Map<String, Object?> json) => TranscodeJob(
    options: TranscodeOptions.fromJson(
      (json['options'] as Map? ?? const {}).cast<String, Object?>(),
    ),
    sourceVideo: json['sourceVideo'] as String?,
    sourceAudio: json['sourceAudio'] as String?,
    outputPath: json['outputPath'] as String?,
    command: json['command'] as String?,
    outputBytes: json['outputBytes'] as int?,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 命令
// ═══════════════════════════════════════════════════════════════════════

abstract final class TranscodeCommand {
  /// 拼出 ffmpeg 的参数（不含可执行文件本身）。
  ///
  /// [audioEncoder] 是实际可用的音频编码器名与它要的额外参数；null 时用
  /// [AudioCodec.encoder]。[progress] 为 true 时加上机器可读的进度输出，
  /// 界面上的命令预览不带它 —— 用户复制去终端跑，要的是正常输出。
  static List<String> build({
    required TranscodeOptions options,
    required String input,
    required String output,
    (String, List<String>)? audioEncoder,
    bool progress = false,
  }) {
    final video = options.effectiveVideo;
    final audio = options.effectiveAudio;
    final encoder = video == VideoCodec.copy ? null : options.encoder;
    final encoderArgs = encoder?.build(encoder.sanitize(options.encoderParams));

    final filters = [
      if (encoder != null && options.resolution.height != null)
        "scale=w=-2:h='min(${options.resolution.height},ih)'",
      if (encoder != null && options.fps != null) 'fps=${options.fps}',
    ];

    final audioArgs = switch (audio) {
      AudioCodec.copy => const ['-c:a', 'copy'],
      _ => [
        '-c:a', audioEncoder?.$1 ?? audio.encoder,
        ...?audioEncoder?.$2,
        '-b:a', '${options.audioBitrate}k',
        if (options.audioChannels != null) ...['-ac', '${options.audioChannels}'],
      ],
    };

    return [
      '-hide_banner',
      '-nostdin',
      '-y',
      if (progress) ...['-v', 'error', '-progress', 'pipe:1', '-nostats'],
      ...?encoderArgs?.input,
      '-i', input,
      // 大写 V：视频流里排除封面附图，封面按视频转码会出错或凭空多一路。
      '-map', '0:V?',
      '-map', '0:a?',
      '-map_metadata', '0',
      '-map_chapters', '0',
      if (encoderArgs == null) ...['-c:v', 'copy'] else ...encoderArgs.output,
      if (filters.isNotEmpty) ...['-vf', filters.join(',')],
      ...audioArgs,
      if (options.faststart) ...['-movflags', '+faststart'],
      ...splitArgs(options.extraArgs),
      '-f', options.container.extension,
      output,
    ];
  }

  /// 把用户写的额外参数按空白切开，支持单双引号包住带空格的值。
  static List<String> splitArgs(String raw) {
    final out = <String>[];
    final buf = StringBuffer();
    String? quote;
    var hasToken = false;
    for (final ch in raw.split('')) {
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
        hasToken = true;
      } else if (ch.trim().isEmpty) {
        if (hasToken) out.add(buf.toString());
        buf.clear();
        hasToken = false;
      } else {
        buf.write(ch);
        hasToken = true;
      }
    }
    if (hasToken) out.add(buf.toString());
    return out;
  }

  /// 给人看的命令行：带空格或特殊字符的参数加引号。
  static String display(List<String> args, {String executable = 'ffmpeg'}) =>
      [executable, ...args.map(_quote)].join(' ');

  static String _quote(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'''^[\w@%+=:,./-]+$''').hasMatch(arg)) return arg;
    return "'${arg.replaceAll("'", r"'\''")}'";
  }

  /// 产物路径：`目录/原文件名.后缀.mp4`。[exists] 判断文件是否已存在，
  /// 已存在或与源文件同路径时加序号，不覆盖任何已有文件。
  static String outputPath({
    required String input,
    required TranscodeOptions options,
    required bool Function(String path) exists,
  }) {
    final sep = input.contains('\\') && !input.contains('/') ? '\\' : '/';
    final cut = input.lastIndexOf(RegExp(r'[/\\]'));
    final sourceDir = cut < 0 ? '.' : input.substring(0, cut);
    final name = cut < 0 ? input : input.substring(cut + 1);
    final stem = name.replaceAll(RegExp(r'\.[^.]*$'), '');
    final dir = options.outputLocation == OutputLocation.custom &&
            (options.outputDir?.trim().isNotEmpty ?? false)
        ? options.outputDir!.trim().replaceAll(RegExp(r'[/\\]+$'), '')
        : sourceDir;
    final base = '$dir$sep$stem.${options.resolvedSuffix}';
    final ext = options.container.extension;
    var candidate = '$base.$ext';
    for (var n = 2; candidate == input || exists(candidate); n++) {
      candidate = '$base-$n.$ext';
    }
    return candidate;
  }
}

/// ffmpeg `-progress` 输出的一个区块。
class TranscodeProgress {
  const TranscodeProgress({
    this.position = Duration.zero,
    this.frame,
    this.speed,
    this.done = false,
  });

  final Duration position;
  final int? frame;

  /// 相对实时的倍速：2.4 表示 1 秒处理 2.4 秒素材。
  final double? speed;

  /// 收到 `progress=end`。
  final bool done;

  /// 从一个区块的 `key=value` 行里取出进度。
  static TranscodeProgress parse(Map<String, String> block) {
    // out_time_us 是微秒；老版本的 out_time_ms 名字写着毫秒，实际也是微秒。
    final us = int.tryParse(block['out_time_us'] ?? block['out_time_ms'] ?? '');
    final speed = double.tryParse(
      (block['speed'] ?? '').trim().replaceAll('x', ''),
    );
    return TranscodeProgress(
      position: us == null || us < 0
          ? Duration.zero
          : Duration(microseconds: us),
      frame: int.tryParse(block['frame'] ?? ''),
      speed: speed,
      done: block['progress'] == 'end',
    );
  }
}
