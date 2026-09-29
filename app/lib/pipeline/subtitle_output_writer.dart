import 'dart:io';

import '../domain/language.dart';
import '../domain/line_wrap.dart';
import '../domain/output_naming.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_control.dart';
import '../domain/task_options.dart';
import '../services/file_io.dart';
import '../services/provider_api.dart';

/// 把内存中的字幕文档写成用户选择的产物格式。
///
/// 完成阶段与编辑器的「保存」都走这里，所以两边写出的文件同名同路径。
abstract final class SubtitleOutputWriter {
  /// 这个任务的产物会写到哪些路径。内容为空的那一路写的时候会略过，
  /// 这里不管 —— 只是给界面列出「保存会写哪些文件」用的，不值得为此序列化整份文档。
  ///
  /// 还没写出过的那一路给的是首选名；真写的时候若那里已有别人的文件，会换成
  /// 带序号的名字，见 [write]。
  static List<String> targets(SubtitleTask task, {String? dir}) => [
    for (final (path, _) in _plan(task, dir)) path,
  ];

  /// 写出产物，返回写了哪些路径。
  ///
  /// 写到任务自己的输出目录（[dir] 为空）时，顺带记下每个文件写完后的
  /// 大小与修改时间；[dir] 指定别处时只是另存一份，不记。
  /// 「未写入的修改」由调用方清零：编辑器要扣掉写文件期间新来的改动。
  static Future<List<String>> write(SubtitleTask task, {String? dir}) async {
    final options = task.options;
    final format = options.format;
    if (!format.implemented) {
      throw ActionableException(
        '${format.label} 格式尚未实施',
        hint: 'ASS 要带一整套样式配置，留到第二期。先导出 SRT。',
      );
    }

    final target = dir ?? _dirOf(task);
    await Directory(target).create(recursive: true);
    final plan = dir == null ? await _avoidExisting(task) : _plan(task, dir);

    // 两路各按自己的语言折行：双语字幕的上下两行语种不同，用同一个上限
    // 必然有一边难看。
    String Function(String) wrapper(Language language) {
      final limit = language.cjk
          ? options.cjkLineLength
          : options.latinLineLength;
      return (text) => LineWrap.wrap(text, limit: limit, cjk: language.cjk);
    }

    final wrapSource = wrapper(task.sourceLanguage);
    final wrapTranslation = wrapper(task.targetLanguage);
    // 说话人标签跟着源语言走：中日韩「说话人1：」，其他「Speaker 1: 」；
    // 在编辑器里起过名字的写名字，关掉了标签就不写。
    final speakerLabel = task.document.speakerLabeler(task.sourceLanguage);
    // 写之前先记下这一刻的文档：写文件要等 IO，期间编辑器可能又改了。
    final cues = task.document.cues;

    final contents = <String, String>{};
    for (final (path, field) in plan) {
      final content = switch (format) {
        SubtitleFormat.srt => Srt.serialize(
          cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.vtt => Srt.serializeVtt(
          cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.txt => Srt.serializePlain(
          cues,
          field: field,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.ass => '',
      };
      if (content.trim().isEmpty) continue;
      contents[path] = content;
    }
    // 产物可能正被播放器读着：先写临时文件再改名，写到一半出错不留半截文件；
    // 原文、译文一起写，不会只写成一份。
    try {
      await writeFilesAtomically(contents);
    } catch (_) {
      // 改名阶段失败时，已经换成新内容的产物留着新内容；不重新记时间戳的话，
      // 下次保存会把应用自己刚写的当成「在别处被改过」。
      if (dir == null) {
        for (final path in contents.keys) {
          if (task.outputs.containsKey(path)) {
            task.outputs[path] = await stampOf(path);
          }
        }
      }
      rethrow;
    }
    final written = contents.keys.toList();

    if (dir == null) {
      task.outputs = {for (final path in written) path: await stampOf(path)};
      task.outputsWrittenAt = DateTime.now();
    }
    return written;
  }

  static String _dirOf(SubtitleTask task) =>
      task.options.outputDirFor(task.sourcePath);

  /// 每一路写到哪。写到任务自己的输出目录（[dir] 为空）时，已经写出过的
  /// 那一路沿用记下的路径（包括改命名规则之前的老名字、避让时带了序号的名字），
  /// 同一个任务的产物不会因为规则变了或重算一遍就换地方。
  static List<(String, SrtField)> _plan(SubtitleTask task, String? dir) {
    final options = task.options;
    final stem = OutputNaming.stemFor(task.kind, task.fileName, options);
    final base = dir ?? _dirOf(task);
    return [
      for (final field in OutputNaming.fields(task.kind, options))
        (
          (dir == null ? _recorded(task, field, base, stem) : null) ??
              '$base/${OutputNaming.fileName(stem, field, options)}',
          field,
        ),
    ];
  }

  /// [field] 这一路已经写出过的路径；没写出过为 null。
  static String? _recorded(
    SubtitleTask task,
    SrtField field,
    String dir,
    String stem,
  ) {
    final options = task.options;
    // 主干之后的部分：`.zh.srt`。
    final rest = OutputNaming.fileName(
      stem,
      field,
      options,
    ).substring(stem.length);
    final preferred = '$dir/$stem$rest';
    final legacy =
        '$dir/${OutputNaming.legacyFileName(task.fileName, field, options)}';
    final numbered = RegExp(
      '^${RegExp.escape('$dir/$stem.')}\\d+${RegExp.escape(rest)}\$',
    );
    for (final path in task.outputs.keys) {
      if (path == preferred || path == legacy || numbered.hasMatch(path)) {
        return path;
      }
    }
    return null;
  }

  /// 首次写出的那一路若已有文件，就是别人的（用户自己下的字幕、别的任务的
  /// 产物）：换成 `<主干>.2.<语言>.<扩展名>`、`.3.`… 直到没人占着，不盖掉它。
  /// 以前的产物名带着 `src`、`zh-en` 这类段几乎撞不上，按 Jellyfin 约定改名后
  /// `Film.srt`、`Film.zh.srt` 与用户已有的文件同名是常事。
  static Future<List<(String, SrtField)>> _avoidExisting(
    SubtitleTask task,
  ) async {
    final options = task.options;
    final stem = OutputNaming.stemFor(task.kind, task.fileName, options);
    final dir = _dirOf(task);
    final planned = _plan(task, null);
    final taken = {for (final (path, _) in planned) path};
    return [
      for (final (path, field) in planned)
        if (task.outputs.containsKey(path) || !await fileExists(path))
          (path, field)
        else
          (await _free(dir, stem, field, options, taken), field),
    ];
  }

  static Future<String> _free(
    String dir,
    String stem,
    SrtField field,
    TaskOptions options,
    Set<String> taken,
  ) async {
    for (var n = 2; ; n++) {
      final path =
          '$dir/${OutputNaming.fileName(stem, field, options, copy: n)}';
      if (taken.contains(path) || await fileExists(path)) continue;
      taken.add(path);
      return path;
    }
  }
}
