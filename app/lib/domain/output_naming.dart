import 'language.dart';

/// 产物文件名里的语言标签：`demo.zh.srt`。
///
/// 用语言代码而不是中文名 —— 中文名带不进跨平台安全的文件名。
/// 「自动检测」没有代码可写，用 `src` 代替。
String languageTag(Language language) => language.isAuto
    ? 'src'
    : language.code.replaceAll(RegExp(r'[^\w-]+'), '_');
