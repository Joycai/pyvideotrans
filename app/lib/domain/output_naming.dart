import 'language.dart';
import 'srt.dart';
import 'task_kind.dart';
import 'task_options.dart';

/// 产物文件名里的语言标签：`demo.zh.srt`。
///
/// 用语言代码而不是中文名 —— 中文名带不进跨平台安全的文件名。
/// 「自动检测」没有代码可写，用 `src` 代替。
String languageTag(Language language) => language.isAuto
    ? 'src'
    : language.code.replaceAll(RegExp(r'[^\w-]+'), '_');

/// 产物命名规则。流水线写产物、编辑器导出、任务详情与建任务页的文件名示例
/// 都从这里取 —— 各写一份的话，界面上说的文件名迟早与实际写出的对不上。
abstract final class OutputNaming {
  /// 一个任务写出哪几路：纯翻译任务的「原文」就是用户选的那个字幕文件，
  /// 再写一份只是重复；转写任务则必须写出原文，那是识别的产物。
  static List<SrtField> fields(TaskKind kind, TaskOptions options) => [
    if (kind != TaskKind.translate) SrtField.source,
    if (kind.needsTranslation) options.resolvedBilingual.field,
  ];

  /// 一路产物名里的语言段。双语产物带上两种语言，跟单语那份区分得开，
  /// 也说明了里面有什么。
  static String langTag(SrtField field, Language source, Language target) =>
      switch (field) {
        SrtField.source => languageTag(source),
        SrtField.translation => languageTag(target),
        SrtField.bilingualTargetAbove || SrtField.bilingualTargetBelow =>
          '${languageTag(source)}-${languageTag(target)}',
      };

  /// `interview_ep12` + 译文 → `interview_ep12.en.srt`。
  static String fileName(String stem, SrtField field, TaskOptions options) =>
      '$stem.${langTag(field, options.sourceLanguage, options.targetLanguage)}'
      '.${options.format.extension}';
}
