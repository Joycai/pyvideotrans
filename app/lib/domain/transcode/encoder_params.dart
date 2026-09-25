import 'codecs.dart';

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

final class ChoiceParam extends EncoderParam {
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

final class IntParam extends EncoderParam {
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

final class BoolParam extends EncoderParam {
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
