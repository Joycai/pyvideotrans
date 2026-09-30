import 'asr_transport.dart';

/// 模型的一项可调参数。值只有三种类型：bool、double、String（选项）。
///
/// 形状照 `domain/transcode/encoder_params.dart`：目录里登记「有哪些参数」，
/// 设置页照目录渲染控件，服务实现照目录读值。加一个参数 = 目录加一行 +
/// 服务实现读一次，不用改存储与界面。
sealed class ModelParam {
  const ModelParam({required this.key, required this.label, this.hint});

  /// 存档里的键，也是请求体里的字段名。
  final String key;
  final String label;
  final String? hint;

  /// 用户没动过时的取值。null 表示「不发送这个字段」。
  Object? get defaultValue;

  /// 把存档或界面里来的值收拾成合法值；类型不对的回落到默认。
  Object? sanitize(Object? raw);

  /// [raw] 的类型对不对得上这一项。对不上的存值应当整个丢掉（回到「没动过」），
  /// 而不是收拾成默认值留着 —— 那样它会被当成用户亲手设的。
  bool accepts(Object? raw);
}

final class BoolModelParam extends ModelParam {
  const BoolModelParam({
    required super.key,
    required super.label,
    required this.defaultBool,
    super.hint,
  });

  final bool defaultBool;

  @override
  Object get defaultValue => defaultBool;

  @override
  Object sanitize(Object? raw) => raw is bool ? raw : defaultBool;

  @override
  bool accepts(Object? raw) => raw is bool;
}

final class NumberModelParam extends ModelParam {
  const NumberModelParam({
    required super.key,
    required super.label,
    required this.min,
    required this.max,
    required this.defaultNumber,
    this.step = 0.1,
    this.fractionDigits = 1,
    this.optional = false,
    super.hint,
  }) : assert(optional || defaultNumber != null, '不可省的参数必须有默认值');

  final double min;
  final double max;

  /// null 只在 [optional] 时允许：默认就不发送。
  final double? defaultNumber;
  final double step;

  /// 保留几位小数。与 [step] 对应（0.1 → 1）。
  final int fractionDigits;

  /// 可以「不发送」：有的模型根本不接受这个字段（推理模型的 temperature），
  /// 有的接口不带时由服务端自己决定。
  final bool optional;

  @override
  Object? get defaultValue => defaultNumber;

  @override
  Object? sanitize(Object? raw) {
    if (!accepts(raw)) return defaultNumber;
    if (raw == null) return null;
    // 经一次定点格式化：0.1 的整数倍在二进制里不精确，3 × 0.1 会变成
    // 0.30000000000000004 并原样写进请求体。
    final rounded = double.parse(
      (raw as num).toDouble().clamp(min, max).toStringAsFixed(fractionDigits),
    );
    // 四舍五入可能越过不在步长上的边界，再夹一次；-0.0 写进 JSON 是「-0.0」。
    final clamped = rounded.clamp(min, max);
    return clamped == 0 ? 0.0 : clamped;
  }

  @override
  bool accepts(Object? raw) =>
      raw == null ? optional : raw is num && !raw.isNaN;
}

final class ChoiceModelParam extends ModelParam {
  const ChoiceModelParam({
    required super.key,
    required super.label,
    required this.options,
    required this.defaultOption,
    super.hint,
  });

  /// (值, 界面文案)。值原样进请求体。
  final List<(String, String)> options;
  final String defaultOption;

  @override
  Object get defaultValue => defaultOption;

  @override
  Object sanitize(Object? raw) => accepts(raw) ? raw! : defaultOption;

  @override
  bool accepts(Object? raw) => options.any((o) => o.$1 == raw);
}

/// 一个模型的参数取值。
///
/// 只存用户改过的项：没存的项取目录里的默认值，所以没动过设置的人发出的
/// 请求与加这个功能之前完全一样。存了 null 表示用户明确选了「不发送」——
/// 它和「没存」是两回事，所以这里是 `Object?` 而不是把键删掉。
final class ModelOptions {
  const ModelOptions([this._values = const {}]);

  static const none = ModelOptions();

  final Map<String, Object?> _values;

  bool get isEmpty => _values.isEmpty;

  /// 用户有没有动过这一项。
  bool has(String key) => _values.containsKey(key);

  /// 这一项现在的值：动过的取存的（收拾成合法值），没动过的取默认。
  Object? resolve(ModelParam param) => _values.containsKey(param.key)
      ? param.sanitize(_values[param.key])
      : param.defaultValue;

  bool flag(BoolModelParam param) => resolve(param)! as bool;

  /// null 表示不发送。
  double? number(NumberModelParam param) => resolve(param) as double?;

  String choice(ChoiceModelParam param) => resolve(param)! as String;

  /// [value] 传 null 表示「不发送」。
  ModelOptions set(String key, Object? value) =>
      ModelOptions({..._values, key: value});

  /// 回到目录默认值。
  ModelOptions reset(String key) => ModelOptions({
    for (final e in _values.entries)
      if (e.key != key) e.key: e.value,
  });

  /// 丢掉目录里没有的键和类型对不上的值，其余收拾成合法值。
  ///
  /// 模型的接入方式改了之后，上一种接入方式的参数不该跟着留下。收拾过的
  /// 值一定能写成 JSON（没有 NaN、无穷），并且与写盘再读回的那份相等。
  ModelOptions sanitize(List<ModelParam> catalog) => ModelOptions({
    for (final p in catalog)
      if (_values.containsKey(p.key) && p.accepts(_values[p.key]))
        p.key: p.sanitize(_values[p.key]),
  });

  Map<String, Object?> toJson() => Map.of(_values);

  /// 读存档。只认 JSON 里能出现的标量，其余的键丢掉，绝不抛。
  factory ModelOptions.fromJson(Object? raw) {
    if (raw is! Map) return none;
    return ModelOptions({
      for (final e in raw.entries)
        if (e.key is String &&
            (e.value == null ||
                e.value is bool ||
                e.value is num ||
                e.value is String))
          e.key as String: e.value,
    });
  }

  @override
  bool operator ==(Object other) {
    if (other is! ModelOptions || other._values.length != _values.length) {
      return false;
    }
    for (final e in _values.entries) {
      if (!other._values.containsKey(e.key) || other._values[e.key] != e.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'ModelOptions($_values)';
}

/// 参数目录。第一版只登记服务实现已经在发、或接口文档写明的几项；
/// 默认值就是以前写死在代码里的值。
abstract final class ModelParams {
  /// OpenAI 转写接口的采样温度。以前不发，所以默认仍是不发送。
  static const asrTemperature = NumberModelParam(
    key: 'temperature',
    label: 'temperature',
    hint: 'OpenAI 转写接口的采样温度，0–1，步长 0.1。默认不发送，由服务端决定。',
    min: 0,
    max: 1,
    defaultNumber: null,
    optional: true,
  );

  /// 百炼 Qwen3-ASR 同步接口的逆文本规范化。以前写死为开。
  static const enableItn = BoolModelParam(
    key: 'enable_itn',
    label: '逆文本规范化',
    hint: '把「二零二六年」写成「2026年」。关闭后数字与日期保留口语写法。',
    defaultBool: true,
  );

  /// 对话接口的采样温度。以前写死 0.3。
  static const chatTemperature = NumberModelParam(
    key: 'temperature',
    label: 'temperature',
    hint: '采样温度，0–2，步长 0.1。推理模型不接受这个参数时勾选「不发送」。',
    min: 0,
    max: 2,
    defaultNumber: 0.3,
    optional: true,
  );

  /// 识别模型的参数，由接入方式与报文族决定。
  static List<ModelParam> asr(
    AsrTransport transport,
    DashScopeDialect? dialect,
  ) => switch (transport) {
    AsrTransport.openaiTranscription => const [asrTemperature],
    AsrTransport.dashscopeSync =>
      dialect == DashScopeDialect.qwen3Asr ? const [enableItn] : const [],
    AsrTransport.dashscopeFileTrans => const [],
  };

  /// 翻译（对话）模型的参数。
  static const chat = <ModelParam>[chatTemperature];
}
