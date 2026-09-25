import 'dart:io';

import '../domain/file_stamp.dart';

/// 读 [path] 当前的大小与修改时间；文件不存在时返回 [FileStamp.missing]。
Future<FileStamp> stampOf(String path) async {
  final stat = await File(path).stat();
  if (stat.type == FileSystemEntityType.notFound) return FileStamp.missing;
  return FileStamp(
    size: stat.size,
    modifiedMs: stat.modified.millisecondsSinceEpoch,
  );
}

/// 先写临时文件再改名：写到一半出错，原文件还是完整的。
Future<void> writeFileAtomically(String path, String content) =>
    writeFilesAtomically({path: content});

/// 一次写好几份文件（原文 + 译文），要么全写成，要么都不留。
///
/// 先把每份都写成临时文件，全部写成才逐个改名。写临时文件这一步最容易
/// 出错（磁盘满、没权限），出错时删掉临时文件，目标一份都没动过 ——
/// 否则另存为会留下「原文写成、译文没有」的半套字幕。
/// 改名阶段再出错（极少见）时，把这次新建出来的文件删掉；原本就存在、
/// 已经被换成新内容的保持新内容，它们各自都是完整的。
Future<void> writeFilesAtomically(Map<String, String> contents) async {
  final staged = <String, File>{};
  try {
    for (final MapEntry(key: path, value: content) in contents.entries) {
      final tmp = File('$path.tmp');
      staged[path] = tmp;
      await tmp.writeAsString(content, flush: true);
    }
  } catch (_) {
    await Future.wait(staged.values.map(_deleteQuietly));
    rethrow;
  }

  final created = <String>[];
  try {
    for (final MapEntry(key: path, value: tmp) in staged.entries) {
      final existed = await File(path).exists();
      await tmp.rename(path);
      if (!existed) created.add(path);
    }
  } catch (_) {
    await Future.wait([
      ...staged.values.map(_deleteQuietly),
      ...created.map((p) => _deleteQuietly(File(p))),
    ]);
    rethrow;
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // 清理失败不掩盖真正的写入错误。
  }
}
