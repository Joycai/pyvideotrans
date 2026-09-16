import 'dart:io';

/// 在系统文件管理器里定位一个文件。转码产物不是字幕，没有「打开编辑器」可言，
/// 用户下一步多半是去文件夹里拿它。
abstract final class Reveal {
  /// 按钮文案随平台叫法走。
  static String get label => Platform.isMacOS
      ? '在访达中显示'
      : Platform.isWindows
      ? '在资源管理器中显示'
      : '打开所在文件夹';

  /// 选中 [path]。文件已不存在时退而打开它原本所在的目录。
  static Future<void> show(String path) async {
    final file = File(path);
    final dir = file.parent.path;
    try {
      if (!file.existsSync()) {
        await _open(dir);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        // explorer 要求 /select, 与路径连成一个参数。
        await Process.run('explorer', ['/select,$path']);
      } else {
        await _open(dir);
      }
    } on ProcessException {
      // 没有可用的文件管理器（精简的 Linux 桌面），不值得为此报错。
    }
  }

  /// 打开一个目录本身（不选中里面的某个文件）。
  static Future<void> openDir(String dir) async {
    try {
      await _open(dir);
    } on ProcessException {
      // 同上：没有可用的文件管理器不值得报错。
    }
  }

  static Future<void> _open(String dir) => Process.run(
    Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'explorer'
        : 'xdg-open',
    [dir],
  );
}
