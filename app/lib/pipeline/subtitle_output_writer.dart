import 'dart:io';

import '../domain/language.dart';
import '../domain/line_wrap.dart';
import '../domain/output_naming.dart';
import '../domain/paths.dart';
import '../domain/srt.dart';
import '../domain/task.dart';
import '../domain/task_options.dart';
import '../services/provider_api.dart';

/// 把内存中的字幕文档写成用户选择的产物格式。
abstract final class SubtitleOutputWriter {
  static Future<List<String>> write(SubtitleTask task) async {
    final options = task.options;
    final format = options.format;
    if (!format.implemented) {
      throw ProviderException(
        '${format.label} 格式尚未实施',
        hint: 'ASS 要带一整套样式配置，留到第二期。先导出 SRT。',
      );
    }

    final dir = options.outputDirFor(task.sourcePath);
    await Directory(dir).create(recursive: true);

    final stem = stemOf(task.fileName);
    final written = <String>[];

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

    Future<void> write(String tag, SrtField field) async {
      final content = switch (format) {
        SubtitleFormat.srt => Srt.serialize(
          task.document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.vtt => Srt.serializeVtt(
          task.document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.txt => Srt.serializePlain(
          task.document.cues,
          field: field,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.ass => '',
      };
      if (content.trim().isEmpty) return;

      final path = '$dir/$stem.$tag.${format.extension}';
      await File(path).writeAsString(content);
      written.add(path);
    }

    // 纯翻译任务的「原文」就是用户选的那个字幕文件，再写一份只是重复；
    // 转写任务则必须写出原文，那是识别的产物。
    if (task.kind != TaskKind.translate) {
      await write(languageTag(task.sourceLanguage), SrtField.source);
    }
    if (task.kind.needsTranslation) {
      final layout = options.resolvedBilingual;
      await write(
        layout.isBilingual
            // 双语产物带上两种语言，跟单语那份区分得开，也说明了里面有什么。
            ? '${languageTag(task.sourceLanguage)}-${languageTag(task.targetLanguage)}'
            : languageTag(task.targetLanguage),
        layout.field,
      );
    }
    return written;
  }
}
