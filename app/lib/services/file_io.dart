import 'dart:io';

import '../domain/file_stamp.dart';
import '../domain/media_kinds.dart';
import '../domain/paths.dart';

// 界面层要按读写失败的种类给提示，但不该为此直接依赖 dart:io ——
// 文件系统只在 services 里碰。
export 'dart:io' show FileSystemException;

/// 当前平台的路径分隔符。拼出的路径要与别处按平台拼的比对，不能写死 `/`。
String get pathSeparator => Platform.pathSeparator;

Future<bool> fileExists(String path) => File(path).exists();

/// 文件字节数；读不了（不存在、无权限）时为 0。
Future<int> fileLength(String path) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return 0;
  }
}

/// 按 UTF-8 读整份文本。编码不对时抛 [FileSystemException]。
Future<String> readText(String path) => File(path).readAsString();

Future<void> ensureDir(String path) async {
  await Directory(path).create(recursive: true);
}

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

/// 在 [subtitlePath] 所在目录里找与之配套的音视频：主干等于 [stem]（语言段
/// 已去掉）或等于字幕自己去掉扩展名后的名字。视频优先于音频，同类里按名字排。
/// 目录读不了（不存在、无权限）时返回 null。
Future<String?> findSiblingMedia(String subtitlePath, String stem) async {
  final dir = File(subtitlePath).parent;
  final ownStem = stemOf(baseName(subtitlePath));
  final stems = {stem, ownStem};
  final candidates = <(int, String, String)>[];
  try {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = baseName(entry.path);
      if (!MediaKinds.isMedia(name)) continue;
      if (!stems.contains(stemOf(name))) continue;
      final rank = MediaKinds.isAudio(name) ? 1 : 0;
      candidates.add((rank, name.toLowerCase(), entry.path));
    }
  } on FileSystemException {
    return null;
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  return candidates.first.$3;
}
