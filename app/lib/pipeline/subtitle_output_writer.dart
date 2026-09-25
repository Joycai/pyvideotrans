import 'dart:io';

import '../domain/language.dart';
import '../domain/line_wrap.dart';
import '../domain/output_naming.dart';
import '../domain/paths.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_control.dart';
import '../domain/task_options.dart';
import '../services/file_stamps.dart';

/// 把内存中的字幕文档写成用户选择的产物格式。
///
/// 完成阶段与编辑器的「保存」都走这里，所以两边写出的文件同名同路径。
abstract final class SubtitleOutputWriter {
  /// 这个任务的产物会写到哪些路径。内容为空的那一路写的时候会略过，
  /// 这里不管 —— 只是给界面列出「保存会写哪些文件」用的，不值得为此序列化整份文档。
  static List<String> targets(SubtitleTask task, {String? dir}) => [
    for (final (path, _) in _plan(task, dir ?? _dirOf(task))) path,
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
    for (final (path, field) in _plan(task, target)) {
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

  static List<(String, SrtField)> _plan(SubtitleTask task, String dir) {
    final stem = stemOf(task.fileName);
    final ext = task.options.format.extension;
    return [
      // 纯翻译任务的「原文」就是用户选的那个字幕文件，再写一份只是重复；
      // 转写任务则必须写出原文，那是识别的产物。
      if (task.kind != TaskKind.translate)
        (
          '$dir/$stem.${languageTag(task.sourceLanguage)}.$ext',
          SrtField.source,
        ),
      if (task.kind.needsTranslation)
        switch (task.options.resolvedBilingual) {
          final layout => (
            layout.isBilingual
                // 双语产物带上两种语言，跟单语那份区分得开，也说明了里面有什么。
                ? '$dir/$stem.${languageTag(task.sourceLanguage)}-'
                      '${languageTag(task.targetLanguage)}.$ext'
                : '$dir/$stem.${languageTag(task.targetLanguage)}.$ext',
            layout.field,
          ),
        },
    ];
  }
}
