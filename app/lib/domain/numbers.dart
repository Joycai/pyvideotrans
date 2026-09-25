/// 千位分隔。字幕动辄上千条，`2416` 和 `2,416` 的可读性差得很远。
String grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 一个整数参数允许的取值范围（含两端）。
class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;

  int clamp(int value) => value.clamp(min, max);
}
