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
Future<void> writeFileAtomically(String path, String content) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(path);
}
