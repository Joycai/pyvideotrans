/// 跨平台路径字符串的小工具。
///
/// 纯字符串操作，不碰 IO —— 同一套规则被流水线（产物落盘）、编辑器（导出与
/// 写回）与界面（显示所在目录）共用；各写一份迟早会在某一处走形。
/// Windows 的路径分隔符是反斜杠，所以两种都认。
library;

/// 最后一段：`/a/b/demo.zh.srt` → `demo.zh.srt`。
String baseName(String path) => path.split(RegExp(r'[/\\]')).last;

/// 去掉最后一段。与 `File(path).parent.path` 一致：根目录回到 `/`，
/// 没有分隔符的相对路径回到 `.`。
String dirName(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  if (i < 0) return '.';
  if (i == 0) return path.substring(0, 1);
  // Windows 盘符根目录：`C:\\file` 的父目录是 `C:\\`，不是 `C:`。
  if (i == 2 && path.length > 2 && path[1] == ':') {
    return path.substring(0, 3);
  }
  return path.substring(0, i);
}

/// 去掉扩展名：`demo.zh.srt` → `demo.zh`。
String stemOf(String name) => name.replaceAll(RegExp(r'\.[^.]*$'), '');

/// 小写扩展名，没有扩展名时返回空串（默认值由调用方决定）。
String extensionOf(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// 分隔符统一成 `/`，只用来比较两条路径是否指向同一处：同一个目录，有的地方
/// 按平台分隔符拼、有的用 `/` 拼，Windows 上字面上就对不上。
String sameSeparators(String path) => path.replaceAll('\\', '/');
