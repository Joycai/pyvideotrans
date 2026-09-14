import 'dart:io';

import '../../domain/cue.dart';
import '../../domain/language.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/subtitle_pairing.dart';
import '../../domain/task.dart';
import '../../domain/task_options.dart';

/// 编辑器打开的是什么：一个任务，或者本地的一两份字幕文件。
///
/// 两种会话共用同一张表格与检视面板，差别只在从哪儿来、存到哪儿去 ——
/// 任务的改动随任务一起自动写盘，本地文件由用户保存时写回原文件。
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

  /// 找预览用的音视频，依次取：[linked]（上次手动关联的，文件还在才算）、
  /// 任务的源文件（本身是媒体时）、字幕旁边去掉语言段后同名的音视频。
  /// 都没有时保持 null。
  Future<String?> locateMedia({String? linked}) async {
    if (linked != null && await File(linked).exists()) {
      return mediaPath = linked;
    }
    if (mediaPath != null && await File(mediaPath!).exists()) return mediaPath;
    return mediaPath = await findSiblingMedia(subtitlePath, exportStem);
  }
}

/// 在 [subtitlePath] 所在目录里找与之配套的音视频：主干等于 [stem]（语言段
/// 已去掉）或等于字幕自己去掉扩展名后的名字。视频优先于音频，同类里按名字排。
/// 目录读不了（不存在、无权限）时返回 null。
Future<String?> findSiblingMedia(String subtitlePath, String stem) async {
  final dir = File(subtitlePath).parent;
  final ownStem = _withoutExtension(_fileName(subtitlePath));
  final stems = {stem, ownStem};
  final candidates = <(int, String, String)>[];
  try {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = _fileName(entry.path);
      if (!MediaKinds.isMedia(name)) continue;
      if (!stems.contains(_withoutExtension(name))) continue;
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

/// 从任务打开。文档就是任务的文档，参数是任务入队时定下的那份。
class TaskSession extends EditorSession {
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
  String get exportDir => _outputDir(options, task.sourcePath);

  @override
  String get exportStem => _withoutExtension(task.fileName);

  @override
  String get subtitlePath => task.sourcePath;

  /// 转写任务的源文件就是音视频，不用找。
  @override
  Future<String?> locateMedia({String? linked}) async {
    if (linked != null && await File(linked).exists()) {
      return mediaPath = linked;
    }
    if (MediaKinds.isMedia(task.sourcePath) &&
        await File(task.sourcePath).exists()) {
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

  String get fileName => _fileName(path);

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
      parse(path, await File(path).readAsString());
}

/// 从本地字幕文件打开。
class FileSession extends EditorSession {
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

  final String sourcePath;

  /// 译文文件。只挂原文时为 null；在编辑器里翻译后第一次保存会补上。
  String? translationPath;

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
  String get exportDir => _outputDir(options, sourcePath);

  @override
  String get subtitlePath => sourcePath;

  /// `interview_ep12.zh.srt` → `interview_ep12`：语言段也去掉，导出时再按
  /// 实际语言加回来。
  @override
  String get exportStem {
    final stem = _withoutExtension(_fileName(sourcePath));
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
    final written = <String>[];
    await _write(
      sourcePath,
      SrtField.source,
      document.speakerLabeler(sourceLanguage),
    );
    written.add(sourcePath);

    if (!document.cues.any((c) => c.hasTranslation)) {
      translationPath = null;
      return written;
    }
    final target = translationPath ?? await _freshTranslationPath();
    await _write(
      target,
      SrtField.translation,
      labelTranslation ? document.speakerLabeler(targetLanguage) : null,
    );
    translationPath = target;
    written.add(target);
    return written;
  }

  Future<String> _freshTranslationPath() async {
    final dir = File(sourcePath).parent.path;
    final sep = Platform.pathSeparator;
    final tag = _langTag(targetLanguage);
    final ext = _extension(sourcePath);
    var path = '$dir$sep$exportStem.$tag.$ext';
    for (var n = 2; await File(path).exists(); n++) {
      path = '$dir$sep$exportStem-$n.$tag.$ext';
    }
    return path;
  }

  /// 先写临时文件再改名：写到一半出错，原文件还是完整的。
  Future<void> _write(
    String path,
    SrtField field,
    String Function(int)? speakerLabel,
  ) async {
    final content = _extension(path).toLowerCase() == 'vtt'
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
    final tmp = File('$path.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(path);
  }
}

String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

String _withoutExtension(String name) =>
    name.replaceAll(RegExp(r'\.[^.]*$'), '');

String _extension(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? 'srt' : name.substring(dot + 1);
}

/// 与任务产物一致：设置了输出目录就用它，否则与源文件同目录。
String _outputDir(TaskOptions options, String sourcePath) =>
    switch (options.outputLocation) {
      OutputLocation.custom when options.outputDir?.trim().isNotEmpty == true =>
        options.outputDir!.trim(),
      _ => File(sourcePath).parent.path,
    };

String _langTag(Language language) =>
    language.isAuto ? 'src' : language.code.replaceAll(RegExp(r'[^\w-]+'), '_');
