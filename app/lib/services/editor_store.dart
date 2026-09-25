import 'dart:convert';
import 'dart:io';

import '../domain/cue.dart';
import '../domain/file_stamp.dart';
import 'file_io.dart';

/// 编辑器自己的存档，放在应用支持目录的 `editor/` 下：
///
/// - 本地会话的附加状态：已校对标记、置信度、说话人名单这些 SRT 装不下的
///   东西，以及还没写回文件的编辑进度（草稿）。同时记下文件的大小与修改
///   时间，文件在别处被改过就作废，免得把旧状态套到新内容上。
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

  /// 保存本地会话的附加状态。
  ///
  /// - [document] 是上次写进字幕文件的版本（带已校对标记、说话人名单）。
  /// - [draft] 是还没写进文件的编辑进度，没有就不给；[pendingEdits] 是它
  ///   比 [document] 多出的修改数。
  /// - [stamps] 是字幕文件上次读 / 写时的大小与修改时间。不给就现读 ——
  ///   刚写完文件时这样调。
  Future<void> saveFileState({
    required String sourcePath,
    String? translationPath,
    required SubtitleDocument document,
    SubtitleDocument? draft,
    int pendingEdits = 0,
    Map<String, FileStamp>? stamps,
  }) async {
    await _writeJson(_stateFile(sourcePath, translationPath), {
      'version': 2,
      'sourcePath': sourcePath,
      'translationPath': translationPath,
      'files': {
        for (final path in [sourcePath, ?translationPath])
          path: (stamps?[path] ?? await stampOf(path)).toJson(),
      },
      'document': document.toJson(),
      if (draft != null) ...{
        'draft': draft.toJson(),
        'pendingEdits': pendingEdits,
        'draftAt': DateTime.now().toIso8601String(),
      },
    });
  }

  /// 删掉一对文件的附加状态。另存为之后，旧文件那份已经没用了。
  Future<void> forgetFileState(
    String sourcePath,
    String? translationPath,
  ) async {
    try {
      await _stateFile(sourcePath, translationPath).delete();
    } on FileSystemException {
      // 本来就没有，不用管。
    }
  }

  /// 读回附加状态（上次写进文件的版本）。文件在别处被改过时返回 null。
  Future<SubtitleDocument?> loadFileState(
    String sourcePath,
    String? translationPath,
  ) async {
    final state = await loadFileDraft(sourcePath, translationPath);
    return state == null || state.changedOutside ? null : state.saved;
  }

  /// 读回附加状态与编辑进度。没存过、存档坏了时返回 null。
  ///
  /// 文件在别处被改过时：只有附加状态的作废（旧的已校对标记套不上新内容）；
  /// 有没写回的编辑进度的照样返回并标上 [FileState.changedOutside] ——
  /// 离开时答应过用户「不写入也不会丢」，不能因为文件被 touch 了一下就
  /// 悄悄扔掉，由编辑器保存时走冲突询问。
  Future<FileState?> loadFileDraft(
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
      final stamps = <String, FileStamp>{};
      var changed = false;
      for (final path in [sourcePath, ?translationPath]) {
        final saved = FileStamp.tryFromJson(files[path]);
        if (saved == null) return null;
        if (saved != await stampOf(path)) changed = true;
        stamps[path] = saved;
      }
      final draft = json['draft'];
      if (changed && draft is! Map) return null;
      return FileState(
        stamps: stamps,
        changedOutside: changed,
        saved: SubtitleDocument.fromJson(
          (json['document'] as Map).cast<String, Object?>(),
        ),
        draft: draft is Map
            ? SubtitleDocument.fromJson(draft.cast<String, Object?>())
            : null,
        pendingEdits: json['pendingEdits'] as int? ?? 0,
        draftAt: DateTime.tryParse(json['draftAt'] as String? ?? ''),
      );
    } on Object {
      return null;
    }
  }

  File get _mediaFile => File('$dir${Platform.pathSeparator}media.json');

  /// 用户在编辑器里手动关联给某份字幕（或任务源文件）的音视频。
  /// 按字幕路径记，下次打开同一份字幕时优先用它。
  Future<void> saveMediaLink(String subtitlePath, String mediaPath) async {
    final links = await _loadMediaLinks();
    links[subtitlePath] = mediaPath;
    await _writeJson(_mediaFile, links);
  }

  /// 读回手动关联的音视频路径；没记过时为 null。文件是否还在由调用方核对。
  Future<String?> loadMediaLink(String subtitlePath) async =>
      (await _loadMediaLinks())[subtitlePath];

  Future<Map<String, String>> _loadMediaLinks() async {
    try {
      final json = jsonDecode(await _mediaFile.readAsString());
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is String) key: value,
      };
    } on Object {
      return {};
    }
  }

  /// 最近打开的会话，新的在前。读不了时返回空列表。
  Future<List<RecentSession>> loadRecents() async {
    try {
      final json = jsonDecode(await _recentFile.readAsString());
      if (json is! List) return const [];
      return [for (final raw in json) ?RecentSession.tryFromJson(raw)];
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

  /// 原子写，与 TaskStore 一样：写到一半出错，旧的那份还完整。
  Future<void> _writeJson(File target, Object json) async {
    await Directory(dir).create(recursive: true);
    await writeFileAtomically(target.path, jsonEncode(json));
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

/// 本地会话存下的附加状态。
class FileState {
  const FileState({
    this.stamps = const {},
    this.changedOutside = false,
    required this.saved,
    this.draft,
    this.pendingEdits = 0,
    this.draftAt,
  });

  /// 上次写进字幕文件的版本。
  final SubtitleDocument saved;

  /// 还没写进文件的编辑进度；没有为 null。
  final SubtitleDocument? draft;

  /// [draft] 比 [saved] 多出的修改数。
  final int pendingEdits;

  /// 编辑进度最后一次存下的时间。
  final DateTime? draftAt;

  /// 存下时字幕文件的时间戳。
  final Map<String, FileStamp> stamps;

  /// 存下之后字幕文件被别的程序改过（只在有草稿时才会返回这种状态）。
  final bool changedOutside;

  /// 打开时该显示的文档：有编辑进度用编辑进度。
  SubtitleDocument get current => draft ?? saved;
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
  static RecentSession? tryFromJson(Object? raw) {
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
