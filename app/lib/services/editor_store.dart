import 'dart:convert';
import 'dart:io';

import '../domain/cue.dart';

/// 编辑器自己的存档，放在应用支持目录的 `editor/` 下：
///
/// - 本地会话的附加状态：已校对标记、置信度、说话人名单这些 SRT 装不下的
///   东西。同时记下文件的大小与修改时间，文件在别处被改过就作废，免得把旧
///   状态套到新内容上。
/// - 最近打开的会话。
class EditorStore {
  EditorStore(this.dir);

  final String dir;

  static const recentLimit = 10;

  File get _recentFile => File('$dir${Platform.pathSeparator}recent.json');

  File _stateFile(String sourcePath, String? translationPath) => File(
    '$dir${Platform.pathSeparator}'
    'files-${_key('$sourcePath\n${translationPath ?? ''}')}.json',
  );

  /// 保存本地会话的附加状态。须在字幕文件写完之后调用，记下的是写完后的
  /// 文件大小与修改时间。
  Future<void> saveFileState({
    required String sourcePath,
    String? translationPath,
    required SubtitleDocument document,
  }) async {
    await _writeJson(_stateFile(sourcePath, translationPath), {
      'version': 1,
      'sourcePath': sourcePath,
      'translationPath': translationPath,
      'files': {
        for (final path in [sourcePath, ?translationPath])
          path: await _stamp(path),
      },
      'document': document.toJson(),
    });
  }

  /// 读回附加状态。没存过、存档坏了、或文件在别处被改过时返回 null。
  Future<SubtitleDocument?> loadFileState(
    String sourcePath,
    String? translationPath,
  ) async {
    try {
      final json = jsonDecode(
        await _stateFile(sourcePath, translationPath).readAsString(),
      );
      if (json is! Map ||
          json['sourcePath'] != sourcePath ||
          json['translationPath'] != translationPath) {
        return null;
      }
      final files = (json['files'] as Map).cast<String, Object?>();
      for (final path in [sourcePath, ?translationPath]) {
        final saved = (files[path] as Map?)?.cast<String, Object?>();
        final now = await _stamp(path);
        if (saved == null ||
            saved['size'] != now['size'] ||
            saved['modifiedMs'] != now['modifiedMs']) {
          return null;
        }
      }
      return SubtitleDocument.fromJson(
        (json['document'] as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  /// 最近打开的会话，新的在前。读不了时返回空列表。
  Future<List<RecentSession>> loadRecents() async {
    try {
      final json = jsonDecode(await _recentFile.readAsString());
      if (json is! List) return const [];
      return [for (final raw in json) ?RecentSession.fromJson(raw)];
    } on Object {
      return const [];
    }
  }

  /// 记一次打开：同一个会话挪到最前面，超过 [recentLimit] 条的丢掉。
  Future<List<RecentSession>> touchRecent(RecentSession entry) async {
    final next = [
      entry,
      for (final r in await loadRecents())
        if (!r.sameSessionAs(entry)) r,
    ].take(recentLimit).toList();
    await _writeJson(_recentFile, [for (final r in next) r.toJson()]);
    return next;
  }

  Future<Map<String, Object?>> _stamp(String path) async {
    final stat = await File(path).stat();
    return {
      'size': stat.type == FileSystemEntityType.notFound ? -1 : stat.size,
      'modifiedMs': stat.modified.millisecondsSinceEpoch,
    };
  }

  /// 先写临时文件再改名，与 TaskStore 一样。
  Future<void> _writeJson(File target, Object json) async {
    await Directory(dir).create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(target.path);
  }

  /// 路径做文件名用的短哈希（FNV-1a 32 位）。撞了也只是覆盖掉另一份附加
  /// 状态，读回时还会核对路径。
  static String _key(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// 「最近打开」里的一项。任务会话记任务 id，本地会话记两个文件路径。
class RecentSession {
  const RecentSession({
    required this.title,
    required this.openedAt,
    required this.cueCount,
    this.speakerCount = 0,
    this.taskId,
    this.sourcePath,
    this.translationPath,
  });

  final String title;
  final DateTime openedAt;
  final int cueCount;
  final int speakerCount;
  final String? taskId;
  final String? sourcePath;
  final String? translationPath;

  bool get isTask => taskId != null;

  bool sameSessionAs(RecentSession other) => isTask
      ? taskId == other.taskId
      : !other.isTask &&
            sourcePath == other.sourcePath &&
            translationPath == other.translationPath;

  Map<String, Object?> toJson() => {
    'title': title,
    'openedAt': openedAt.toIso8601String(),
    'cueCount': cueCount,
    if (speakerCount > 0) 'speakerCount': speakerCount,
    if (taskId != null) 'taskId': taskId,
    if (sourcePath != null) 'sourcePath': sourcePath,
    if (translationPath != null) 'translationPath': translationPath,
  };

  /// 缺关键字段的记录返回 null，由调用方跳过。
  static RecentSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final openedAt = DateTime.tryParse(raw['openedAt'] as String? ?? '');
    final taskId = raw['taskId'];
    final sourcePath = raw['sourcePath'];
    if (title is! String || openedAt == null) return null;
    if (taskId is! String && sourcePath is! String) return null;
    return RecentSession(
      title: title,
      openedAt: openedAt,
      cueCount: raw['cueCount'] as int? ?? 0,
      speakerCount: raw['speakerCount'] as int? ?? 0,
      taskId: taskId as String?,
      sourcePath: sourcePath as String?,
      translationPath: raw['translationPath'] as String?,
    );
  }
}
