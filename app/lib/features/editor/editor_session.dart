import '../../domain/cue.dart';
import '../../domain/file_stamp.dart';
import '../../domain/language.dart';
import '../../domain/media_kinds.dart';
import '../../domain/output_naming.dart';
import '../../domain/paths.dart';
import '../../domain/srt.dart';
import '../../domain/subtitle_pairing.dart';
import '../../domain/task.dart';
import '../../domain/task_options.dart';
import '../../pipeline/subtitle_output_writer.dart';
import '../../services/file_io.dart';

/// 编辑器打开的是什么：一个任务，或者本地的一两份字幕文件。
///
/// 两种会话共用同一张表格与检视面板，也共用同一套保存规则：
/// **编辑进度自动存，字幕文件手动写**。编辑进度（任务 JSON / 本地会话的
/// 草稿）每次改动都存；字幕文件只在用户保存时写 —— 任务写产物，本地会话
/// 写回挂载的文件。两者之间差多少处修改记在 [pendingEdits]。
sealed class EditorSession {
  SubtitleDocument get document;
  set document(SubtitleDocument value);

  /// 翻译、换行、导出用的参数。
  TaskOptions get options;

  Language get sourceLanguage => options.sourceLanguage;
  Language get targetLanguage => options.targetLanguage;

  /// 顶栏上显示的名字。
  String get title;

  /// 导出目录。
  String get exportDir;

  /// 导出文件名的主干，不含语言段与扩展名。
  String get exportStem;

  /// 检视面板预览用的音视频文件；没有就只预览字幕样式。
  ///
  /// 打开会话时由 [locateMedia] 找一次，之后用户也可以手动关联。
  String? mediaPath;

  /// 字幕所在的路径：手动关联的音视频按它记，也在它旁边找同名文件。
  String get subtitlePath;

  /// 还没写进字幕文件的修改数。随编辑进度一起存，重启后还在。
  int get pendingEdits;
  set pendingEdits(int value);

  /// 记一次编辑。任务会话另记累计数，续跑前用来提醒修改会被覆盖。
  void recordEdit() {}

  /// 保存会写哪些文件。
  List<String> get targetPaths;

  /// 字幕文件是否已经有了：失败或取消的任务还没写过产物。
  bool get hasOutputs => true;

  /// 文档正被编辑器以外的地方改着（任务排队或运行中），编辑器只能看。
  bool get busy => false;

  /// 进行到哪一步；变了编辑器就刷新只读说明。
  Object? get phase => null;

  /// 刚跑完且产物已按当前文档写出：解锁时据此认定字幕文件已同步。
  bool get justFinished => false;

  /// 字幕文件上次写入（或读入）的时间；不知道时为 null。
  DateTime? get writtenAt;

  /// 写字幕文件，返回写了哪些路径。调用前先看 [externalChanges]。
  Future<List<String>> write();

  /// 另存到 [dir]，返回写了哪些路径。先用 [checkWriteTo] 查过。
  Future<List<String>> writeTo(String dir);

  /// 另存为的目标能不能用；不能用时返回给用户看的原因。
  ///
  /// 另存为是为了两边都留，所以不许写回原来的目录，也不许盖掉目标目录
  /// 里已有的同名文件 —— 尤其是冲突对话框里点「另存为」、在默认打开的
  /// 原目录直接确认的时候。
  Future<String?> checkWriteTo(String dir) async {
    if (dir == dirName(targetPaths.firstOrNull ?? exportDir)) {
      return '选的是字幕文件原来的目录，请换一个';
    }
    for (final path in writeToPaths(dir)) {
      if (await fileExists(path)) return '${baseName(path)} 已存在，请换一个目录';
    }
    return null;
  }

  /// 另存到 [dir] 时会写哪些路径。
  List<String> writeToPaths(String dir);

  /// 上次读 / 写之后被别的程序改过的字幕文件。只看这次会写的文件
  /// （卸载了的译文不写，也就不用问）；已经删掉的不算 —— 直接写回去
  /// 不会盖掉任何东西。
  Future<List<FileChange>> externalChanges() async {
    final targets = targetPaths.toSet();
    return [
      for (final MapEntry(key: path, value: before) in trackedStamps.entries)
        if (targets.contains(path))
          if (await stampOf(path) case final now
              when now.exists && now != before)
            (path: path, before: before, now: now),
    ];
  }

  /// 记着的字幕文件时间戳：上次读 / 写完那一刻的。
  Map<String, FileStamp> get trackedStamps;

  /// 找预览用的音视频，依次取：[linked]（上次手动关联的，文件还在才算）、
  /// 任务的源文件（本身是媒体时）、字幕旁边去掉语言段后同名的音视频。
  /// 都没有时保持 null。
  Future<String?> locateMedia({String? linked}) async {
    if (linked != null && await fileExists(linked)) {
      return mediaPath = linked;
    }
    if (mediaPath != null && await fileExists(mediaPath!)) return mediaPath;
    return mediaPath = await findSiblingMedia(subtitlePath, exportStem);
  }
}

/// 从任务打开。文档就是任务的文档，参数是任务入队时定下的那份。
/// 字幕文件是任务的产物，与完成阶段同名同路径。
final class TaskSession extends EditorSession {
  TaskSession(this.task);

  final SubtitleTask task;

  @override
  SubtitleDocument get document => task.document;

  @override
  set document(SubtitleDocument value) => task.document = value;

  @override
  TaskOptions get options => task.options;

  @override
  String get title => task.fileName;

  @override
  String get exportDir => options.outputDirFor(task.sourcePath);

  @override
  String get exportStem => stemOf(task.fileName);

  @override
  String get subtitlePath => task.sourcePath;

  @override
  int get pendingEdits => task.unsyncedEdits;

  @override
  set pendingEdits(int value) => task.unsyncedEdits = value;

  @override
  void recordEdit() => task.editorEdits++;

  @override
  List<String> get targetPaths => SubtitleOutputWriter.targets(task);

  @override
  bool get hasOutputs =>
      task.outputs.isNotEmpty || task.status == TaskStatus.done;

  /// 排队的也算：一轮到它，流水线就从续跑阶段起重写文档。
  @override
  bool get busy =>
      task.status == TaskStatus.running || task.status == TaskStatus.queued;

  @override
  Object? get phase => (task.status, task.stage);

  /// 取消、失败也会解锁，但那时产物没按这份文档写过。
  @override
  bool get justFinished =>
      task.status == TaskStatus.done && task.unsyncedEdits == 0;

  @override
  DateTime? get writtenAt => task.outputsWrittenAt;

  @override
  Map<String, FileStamp> get trackedStamps => task.outputs;

  @override
  Future<List<String>> write() => SubtitleOutputWriter.write(task);

  @override
  Future<List<String>> writeTo(String dir) =>
      SubtitleOutputWriter.write(task, dir: dir);

  @override
  List<String> writeToPaths(String dir) =>
      SubtitleOutputWriter.targets(task, dir: dir);

  /// 转写任务的源文件就是音视频，不用找。
  @override
  Future<String?> locateMedia({String? linked}) async {
    if (linked != null && await fileExists(linked)) {
      return mediaPath = linked;
    }
    if (MediaKinds.isMedia(task.sourcePath) &&
        await fileExists(task.sourcePath)) {
      return mediaPath = task.sourcePath;
    }
    return super.locateMedia();
  }
}

/// 读进来、还没配对的一份本地字幕。
class LocalSubtitleFile {
  const LocalSubtitleFile({
    required this.path,
    required this.cues,
    this.speakerLabels,
    this.language,
  });

  final String path;

  /// 按文件原样解析出的字幕，说话人标签还在文本里。
  final List<Cue> cues;

  /// 行首说话人标签的识别结果；没有标签时为 null。
  final SpeakerLabelDetection? speakerLabels;

  /// 从文件名或文字猜出的语言；猜不出为 null。
  final Language? language;

  String get fileName => baseName(path);

  /// 解析一份字幕文本。解析不出任何字幕时抛 [FormatException]。
  static LocalSubtitleFile parse(String path, String text) {
    final cues = Srt.parse(text);
    if (cues.isEmpty) {
      throw const FormatException('解析不出字幕内容');
    }
    // 猜语言只看前 200 条，够用了，长字幕不必整份扫一遍。
    final sample = cues.take(200).map((c) => c.source).join('\n');
    return LocalSubtitleFile(
      path: path,
      cues: cues,
      speakerLabels: Srt.detectSpeakerLabels(cues),
      language: Languages.fromFileName(path) ?? Languages.guessFromText(sample),
    );
  }

  /// 按 UTF-8 读文件。编码不对或解析不出字幕时抛异常，由界面提示「换一个」。
  static Future<LocalSubtitleFile> load(String path) async =>
      parse(path, await readText(path));
}

/// 从本地字幕文件打开。
final class FileSession extends EditorSession {
  FileSession({
    required this.sourcePath,
    this.translationPath,
    required this.options,
    required this.document,
    this.pairing,
    this.labelTranslation = false,
  });

  /// 用读进来的文件建一个会话。
  ///
  /// 语言没指定时依次取：文件名或文字猜出的、设置里的默认值。翻译服务等
  /// 其余参数都来自 [defaults]，也就是设置 —— 本地字幕没有任务参数可用。
  ///
  /// [restored] 是上次保存时另存的文档（带已校对标记与说话人名单）；
  /// 给了就直接用它，不再重新配对。
  factory FileSession.open({
    required LocalSubtitleFile source,
    LocalSubtitleFile? translation,
    required TaskOptions defaults,
    Language? sourceLanguage,
    Language? targetLanguage,
    PairingMode? mode,
    bool readSpeakerLabels = true,
    SubtitleDocument? restored,
  }) {
    final src = sourceLanguage ?? source.language ?? defaults.sourceLanguage;
    final dst =
        targetLanguage ?? translation?.language ?? defaults.targetLanguage;
    final options = defaults.copyWith(sourceLanguage: src, targetLanguage: dst);
    final sourceLabels = readSpeakerLabels ? source.speakerLabels : null;
    // 译文里的标签只去掉、保存时再写回，不拿来当说话人：说话人以原文为准。
    final translationLabels = readSpeakerLabels
        ? translation?.speakerLabels
        : null;

    if (restored != null) {
      return FileSession(
        sourcePath: source.path,
        translationPath: translation?.path,
        options: options,
        document: restored,
        labelTranslation: translationLabels != null,
      );
    }

    final sourceCues = sourceLabels?.cues ?? source.cues;
    final translationCues = translationLabels?.cues ?? translation?.cues;
    final pairing = translationCues == null
        ? null
        : SubtitlePairing.pair(
            sourceCues,
            translationCues,
            mode: mode,
            cjk: dst.cjk,
          );
    return FileSession(
      sourcePath: source.path,
      translationPath: translation?.path,
      options: options,
      pairing: pairing,
      labelTranslation: translationLabels != null,
      document: SubtitleDocument(
        cues: pairing?.cues ?? sourceCues,
        sourceLanguage: src.code,
        targetLanguage: dst.code,
        speakers: sourceLabels?.speakers ?? const {},
      ),
    );
  }

  /// 原文文件。「另存为」之后换成新路径。
  String sourcePath;

  /// 译文文件。只挂原文时为 null；在编辑器里翻译后第一次保存会补上。
  String? translationPath;

  @override
  int pendingEdits = 0;

  /// 挂载的文件上次读 / 写完时的大小与修改时间。打开时由 [captureStamps] 记，
  /// 每次保存后更新。
  @override
  final Map<String, FileStamp> trackedStamps = {};

  /// 记下挂载文件当前的时间戳。打开会话后调一次。
  Future<void> captureStamps() async {
    trackedStamps
      ..clear()
      ..addAll({
        for (final path in [sourcePath, ?translationPath])
          path: await stampOf(path),
      });
  }

  @override
  TaskOptions options;

  @override
  SubtitleDocument document;

  /// 打开时的配对结果；只挂原文或从存档恢复时为 null。
  final PairingResult? pairing;

  /// 译文文件原本就带说话人标签，保存时写回去。
  final bool labelTranslation;

  /// 当前真正挂着的译文文件：路径还在、文档里也还有译文。
  /// 「卸载译文」只清文档（可以撤销），路径留到保存时才去掉。
  String? get mountedTranslationPath =>
      translationPath != null && document.cues.any((c) => c.hasTranslation)
      ? translationPath
      : null;

  @override
  String get title => exportStem;

  @override
  String get exportDir => options.outputDirFor(sourcePath);

  @override
  String get subtitlePath => sourcePath;

  @override
  List<String> get targetPaths => [sourcePath, ?mountedTranslationPath];

  @override
  DateTime? get writtenAt => trackedStamps[sourcePath]?.modified;

  @override
  Future<List<String>> write() => save();

  /// 另存到 [dir]：写出后编辑器就挂在新文件上。写失败时仍挂在原来的
  /// 文件上 —— 否则之后的草稿、重试都会跟着一个写不进去的目录走。
  @override
  Future<List<String>> writeTo(String dir) async {
    final (oldSource, oldTranslation) = (sourcePath, translationPath);
    final stamps = {...trackedStamps};
    final paths = writeToPaths(dir);
    sourcePath = paths.first;
    translationPath = mountedTranslationPath == null ? null : paths.last;
    try {
      return await save();
    } catch (_) {
      sourcePath = oldSource;
      translationPath = oldTranslation;
      trackedStamps
        ..clear()
        ..addAll(stamps);
      rethrow;
    }
  }

  @override
  List<String> writeToPaths(String dir) {
    final sep = pathSeparator;
    return [
      '$dir$sep${baseName(sourcePath)}',
      if (mountedTranslationPath case final t?) '$dir$sep${baseName(t)}',
    ];
  }

  /// `interview_ep12.zh.srt` → `interview_ep12`：语言段也去掉，导出时再按
  /// 实际语言加回来。
  @override
  String get exportStem {
    final stem = stemOf(baseName(sourcePath));
    final dot = stem.lastIndexOf('.');
    if (dot > 0 && Languages.fromTag(stem.substring(dot + 1)) != null) {
      return stem.substring(0, dot);
    }
    return stem;
  }

  /// 写回挂载的文件，返回写了哪些路径。
  ///
  /// - 原文写回原文文件，说话人标签按文档设置写回行首。
  /// - 有译文时写译文文件。只挂了原文、在编辑器里翻译过的，译文写到原文
  ///   旁边的 `<主干>.<目标语言>.<扩展名>`，同名文件已存在就换个名字，
  ///   绝不覆盖一份没挂载过的文件。
  /// - 译文被卸载（文档里没有译文了）时不动译文文件，只是不再挂着它。
  /// - 已校对标记、置信度 SRT 装不下，由 EditorStore 另存。
  /// - VTT 按 VTT 写回，但样式块、注释这类字幕以外的内容不保留。
  Future<List<String>> save() async {
    final contents = {
      sourcePath: _content(
        sourcePath,
        SrtField.source,
        document.speakerLabeler(sourceLanguage),
      ),
    };
    final translated = document.cues.any((c) => c.hasTranslation);
    final target = !translated
        ? null
        : translationPath ?? await _freshTranslationPath();
    if (target != null) {
      contents[target] = _content(
        target,
        SrtField.translation,
        labelTranslation ? document.speakerLabeler(targetLanguage) : null,
      );
    }
    // 原文、译文一起写：另存为时写成一半就失败，不能留下只有原文的半套。
    try {
      await writeFilesAtomically(contents);
    } catch (_) {
      // 改名阶段失败时，已换成新内容的文件留着新内容：重新记时间戳，
      // 否则下次保存会把自己刚写的当成外部修改。另存为失败由 writeTo 回滚。
      await captureStamps();
      rethrow;
    }
    translationPath = target;
    await captureStamps();
    return contents.keys.toList();
  }

  Future<String> _freshTranslationPath() async {
    final dir = dirName(sourcePath);
    final sep = pathSeparator;
    final tag = languageTag(targetLanguage);
    final sourceExt = extensionOf(sourcePath);
    final ext = sourceExt.isEmpty ? 'srt' : sourceExt;
    var path = '$dir$sep$exportStem.$tag.$ext';
    for (var n = 2; await fileExists(path); n++) {
      path = '$dir$sep$exportStem-$n.$tag.$ext';
    }
    return path;
  }

  String _content(
    String path,
    SrtField field,
    String Function(int)? speakerLabel,
  ) {
    final ext = extensionOf(path);
    return (ext.isEmpty ? 'srt' : ext) == 'vtt'
        ? Srt.serializeVtt(
            document.cues,
            field: field,
            speakerLabel: speakerLabel,
          )
        : Srt.serialize(
            document.cues,
            field: field,
            speakerLabel: speakerLabel,
          );
  }
}
