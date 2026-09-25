/// 一个文件在某一刻的大小与修改时间。用来判断文件在我们上次读 / 写之后
/// 有没有被别的程序改过 —— 比对内容太贵，大小加修改时间足够可靠。
class FileStamp {
  const FileStamp({required this.size, required this.modifiedMs});

  /// 文件不存在时的记号。
  static const missing = FileStamp(size: -1, modifiedMs: 0);

  final int size;
  final int modifiedMs;

  bool get exists => size >= 0;

  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(modifiedMs);

  Map<String, Object?> toJson() => {'size': size, 'modifiedMs': modifiedMs};

  static FileStamp? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = raw['size'];
    final modified = raw['modifiedMs'];
    if (size is! int || modified is! int) return null;
    return FileStamp(size: size, modifiedMs: modified);
  }

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      other.size == size &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(size, modifiedMs);
}
