import 'language.dart';
import 'paths.dart';
import 'srt.dart';
import 'task_kind.dart';
import 'task_options.dart';

/// 产物文件名里的语言标签：`demo.zh.srt`。
///
/// 用语言代码而不是中文名 —— 中文名带不进跨平台安全的文件名。
/// 「自动检测」没有代码可写，调用方应当略过语言段，见 [OutputNaming.tags]。
String languageTag(Language language) =>
    language.code.replaceAll(RegExp(r'[^\w-]+'), '_');

/// 产物命名规则。流水线写产物、编辑器导出、任务详情与建任务页的文件名示例
/// 都从这里取 —— 各写一份的话，界面上说的文件名迟早与实际写出的对不上。
///
/// 格式按 Jellyfin 的外挂字幕约定：`<视频主干>[.<标题>].<语言>.<扩展名>`。
/// Jellyfin 从后往前逐段认：认得出的第一个语言码定语言，`default` / `forced`
/// 之类是标志，其余拼成字幕轨标题。Plex、Kodi 同样取扩展名前那一段作语言，
/// 所以语言码总放在最后。
abstract final class OutputNaming {
  /// 双语产物的标题段。语言段写译文语言：双语字幕就是给看译文的人准备的。
  /// 不写成 `zh-en` 之类的合成码 —— 那不是合法语言码，播放器认不出语言，
  /// 只会把它当标题。
  static const bilingualTitle = 'Bilingual';

  /// 一个任务写出哪几路：纯翻译任务的「原文」就是用户选的那个字幕文件，
  /// 再写一份只是重复；转写任务则必须写出原文，那是识别的产物。
  static List<SrtField> fields(TaskKind kind, TaskOptions options) => [
    if (kind != TaskKind.translate) SrtField.source,
    if (kind.needsTranslation) options.resolvedBilingual.field,
  ];

  /// 一路产物名里主干之后、扩展名之前的几段。
  ///
  /// 源语言是「自动检测」时原文不写语言段：写个占位词（以前是 `src`）会被
  /// Jellyfin 当成字幕标题，不如留给播放器当作未知语言。
  static List<String> tags(SrtField field, Language source, Language target) =>
      switch (field) {
        SrtField.source => [if (!source.isAuto) languageTag(source)],
        SrtField.translation => [languageTag(target)],
        SrtField.bilingualTargetAbove || SrtField.bilingualTargetBelow => [
          bilingualTitle,
          languageTag(target),
        ],
      };

  /// `interview_ep12` + 译文 → `interview_ep12.en.srt`。
  ///
  /// [copy] 是避让已有文件时的序号，单独成段放在主干后面（`ep12.2.en.srt`）：
  /// 拼进主干（`ep12-2`）的话，播放器按主干就配不上视频了；单独一段只会被
  /// 当成标题。
  static String fileName(
    String stem,
    SrtField field,
    TaskOptions options, {
    int? copy,
  }) => [
    stem,
    ?copy?.toString(),
    ...tags(field, options.sourceLanguage, options.targetLanguage),
    options.format.extension,
  ].join('.');

  /// 改成 Jellyfin 约定之前的产物名：主干照搬源文件，语言段是 `src`、`zh-en`
  /// 这类写法。只用来认出老任务已经写出的文件，接着写回原处 —— 不然升级后
  /// 一保存就换了名字，旧文件留在磁盘上，播放器里同一条字幕出现两遍。
  static String legacyFileName(
    String fileName,
    SrtField field,
    TaskOptions options,
  ) {
    String tag(Language l) => l.isAuto ? 'src' : languageTag(l);
    final source = tag(options.sourceLanguage);
    final target = tag(options.targetLanguage);
    final lang = switch (field) {
      SrtField.source => source,
      SrtField.translation => target,
      SrtField.bilingualTargetAbove ||
      SrtField.bilingualTargetBelow => '$source-$target',
    };
    return '${stemOf(fileName)}.$lang.${options.format.extension}';
  }

  /// 产物名的主干。
  ///
  /// 纯翻译任务的源文件本身就是字幕，常带语言段（`Film.en.srt`）：照搬会写出
  /// `Film.en.zh.srt`，Jellyfin 只认最后一个语言码，`en` 成了字幕标题。去掉
  /// 这一段，产物才与视频 `Film.mkv` 同主干。去掉后若与源文件同名（给
  /// `Film.zh.srt` 选了翻译成中文），宁可保留，也不能把源文件盖掉。
  static String stemFor(TaskKind kind, String fileName, TaskOptions options) {
    final stem = stemOf(fileName);
    if (kind != TaskKind.translate) return stem;
    // 只去掉与源语言对得上的那一段：`The.Big.It.srt` 的 `It` 形同意大利语，
    // 照单全收会削成 `The.Big`，反倒与视频 `The.Big.It.mkv` 不同主干了。
    final source = options.sourceLanguage;
    final tagged = Languages.fromTag(stem.substring(stem.lastIndexOf('.') + 1));
    if (!source.isAuto && tagged?.code != source.code) return stem;
    final stripped = subtitleStem(fileName);
    final own = fileName.toLowerCase();
    final clash = fields(
      kind,
      options,
    ).any((f) => OutputNaming.fileName(stripped, f, options).toLowerCase() == own);
    return clash ? stem : stripped;
  }

  /// 字幕文件名去掉扩展名与末尾的语言段：`interview_ep12.zh.srt` →
  /// `interview_ep12`。语言段只认语言表里的代码与常见别名 —— 按「两三个字母」
  /// 的形状判断的话，`The.Big.Cat.srt` 会被削成 `The.Big`。
  static String subtitleStem(String fileName) {
    final stem = stemOf(baseName(fileName));
    final dot = stem.lastIndexOf('.');
    if (dot > 0 && Languages.fromTag(stem.substring(dot + 1)) != null) {
      return stem.substring(0, dot);
    }
    return stem;
  }

  /// 字幕 [subtitle] 相对视频 [video] 多出来的那几段：`ep1.mp4` 配
  /// `ep1.zh.srt` 是 `[zh]`，配 `ep1.Bilingual.zh.srt` 是 `[Bilingual, zh]`，
  /// 同名的 `ep1.srt` 是空列表；不是它的字幕返回 null。
  ///
  /// 多出来的段限定成语言代码的样子（双语产物前面可以多一个标题段）：上次
  /// 合并旁挂的 `a.merged.srt` 不是 `a.mp4` 的字幕，配上去会把整份时间轴压到
  /// 第 1 段上。局限：三个字母的普通词（`old`）与 ISO 639-2 代码形状相同，
  /// 分不开，`ep1.old.srt` 仍会配给 `ep1.mp4`。
  static List<String>? sidecarTags(String video, String subtitle) {
    final stem = stemOf(baseName(video));
    final sub = stemOf(baseName(subtitle));
    if (sub == stem) return const [];
    if (!sub.startsWith('$stem.')) return null;
    final tags = sub.substring(stem.length + 1).split('.');
    final ok = switch (tags) {
      [final lang] => _languageShape.hasMatch(lang),
      [bilingualTitle, final lang] => _languageShape.hasMatch(lang),
      _ => false,
    };
    return ok ? tags : null;
  }

  static final _languageShape = RegExp(
    r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$',
  );
}
