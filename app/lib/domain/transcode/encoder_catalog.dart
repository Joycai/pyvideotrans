import 'codecs.dart';
import 'encoder_params.dart';

/// 转码：FFmpeg 的图形外壳。
///
/// 这里只有数据与规则 —— 编码器目录、每个编码器自己的参数表、容器兼容性、
/// 以及把这些拼成一条 ffmpeg 命令。跑进程、测编码器可不可用在 services 里。
///
/// 为什么参数表按编码器定义而不是做一套通用的「质量 / 速度」：同样是 H.264，
/// x264 用 CRF 与 preset（ultrafast…veryslow），NVENC 用 CQ 与 p1…p7，
/// QSV 用 ICQ，AMF 用 CQP，VideoToolbox 只有 -q:v。硬抽象成一套就只能取交集，
/// 各家真正有用的开关全被藏掉；映射表还会悄悄改变用户以为自己选了的东西。

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

BoolParam _hwdec(String label, String flag, {bool def = false}) => BoolParam(
  key: 'hwdec',
  label: label,
  defaultBool: def,
  hint: '解码也交给硬件（-hwaccel $flag）。个别源文件硬件解不了时关掉它再试。',
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
    _hwdec('硬件解码', 'videotoolbox', def: true),
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
    _hwdec('CUDA 硬件解码', 'cuda'),
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
    _hwdec('QSV 硬件解码', 'qsv'),
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
    _hwdec('D3D11 硬件解码', 'd3d11va'),
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
