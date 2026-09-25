extension EnumTryByName<T extends Enum> on Iterable<T> {
  /// 按枚举名查找，认不出来（包括不是字符串）返回 null。
  ///
  /// SDK 的 `values.byName` 找不到就抛 —— 只适合名字出自同一个枚举的地方。
  /// 存档与偏好里的名字可能是旧版本写的、被手改过的，读它们一律用这个，
  /// 在调用处用 `??` 写明回落值。
  T? tryByName(Object? name) {
    for (final value in this) {
      if (value.name == name) return value;
    }
    return null;
  }
}
