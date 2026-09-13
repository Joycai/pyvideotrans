import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/language.dart';
import '../../domain/media_kinds.dart';
import '../../domain/task_options.dart';
import '../../services/media.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import 'provider_fields.dart';

/// 表单确认后交出来的东西：一批字幕文件 + 一份参数。
///
/// [paths] 已经剔掉解析不出内容的文件 —— 那些留在界面上是为了让用户知道
/// 自己拖了什么，但不该变成必然失败的任务。
class NewTranslateResult {
  const NewTranslateResult({required this.paths, required this.options});

  final List<String> paths;
  final TaskOptions options;
}

/// 字幕列表里一行的解析状态。
enum StagedSubtitleState {
  /// 正在读条数与时间跨度。不阻断提交 —— 任务跑起来会再解析一遍。
  parsing,
  ready,

  /// 一条都读不出来：空文件、编码坏、或根本不是字幕。不入队，也不计入总数。
  broken,
}

/// 加进「翻译」列表里的一个字幕文件。
class StagedSubtitle {
  const StagedSubtitle({required this.path, this.info, required this.state});

  final String path;
  final MediaFileInfo? info;
  final StagedSubtitleState state;

  String get fileName => path.split(RegExp(r'[/\\]')).last;

  /// 所在目录，用于列表副信息。
  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }

  /// 解析出的条数；未解析完或解析不出时为 null。
  int? get cueCount =>
      state == StagedSubtitleState.ready ? info?.cueCount : null;

  bool get willEnqueue => state == StagedSubtitleState.ready;
}

/// 「翻译」的表单状态：字幕列表、参数、校验与提交。
///
/// 对话框与导航栏的「翻译」页共用这一份 —— 两处的字段、校验文案与就绪判断
/// 必须逐字相同，各写一份必然走形。它不碰任务队列：`submit` 只把文件与参数
/// 打包交出去，入队由调用方完成，进度归任务页。
///
/// 与 [TranscribeFormController] 的差别就是翻译与转写的差别：输入是字幕，
/// 计量单位是条数而不是时长；拖进来的音视频不算错，记下来让用户一键改走
/// 「新建转写」；语言是一对，可以对换。
class TranslateFormController extends ChangeNotifier {
  TranslateFormController({
    required this.settings,
    Media? media,
    TaskOptions? initial,
  }) : media = media ?? Media(),
       _options = initial ?? settings.defaultTaskOptions();

  final AppSettings settings;
  final Media media;

  TaskOptions _options;
  TaskOptions get options => _options;

  final _files = <StagedSubtitle>[];
  List<StagedSubtitle> get files => List.unmodifiable(_files);

  /// 被忽略的音视频路径。留着是为了「改用新建转写」能把它们原样带过去。
  final _ignoredMedia = <String>[];
  List<String> get ignoredMedia => List.unmodifiable(_ignoredMedia);

  /// 拖进来的东西既不是字幕也不是音视频时的说明。落下即清掉上一次的。
  String? _dropError;
  String? get dropError => _dropError;

  bool _advancedOpen = false;
  bool get advancedOpen => _advancedOpen;
  set advancedOpen(bool v) {
    if (_advancedOpen == v) return;
    _advancedOpen = v;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // —— 参数 ————————————————————————————————————————————————

  /// 改一项参数。多行输入框每个字符都会调，传 `notify: false` 省掉重建。
  void update(TaskOptions Function(TaskOptions) change, {bool notify = true}) {
    _options = change(_options);
    if (notify) _notify();
  }

  /// 恢复为设置页的默认值，不动文件列表。
  void reset() {
    _options = settings.defaultTaskOptions();
    _notify();
  }

  /// 把最近一次成功提交的参数整份填回。没有存档时返回 false，界面据此禁用按钮。
  bool applyLastUsed() {
    final last = settings.lastTranslateOptions;
    if (last == null) return false;
    _options = last;
    _notify();
    return true;
  }

  bool get hasLastUsed => settings.lastTranslateOptions != null;

  /// 原文是「自动检测」时没有东西可以换到目标那边去。
  bool get canSwapLanguages => !_options.sourceLanguage.isAuto;

  /// 原文与目标对换。不能换时什么都不做。
  void swapLanguages() {
    if (!canSwapLanguages) return;
    _options = _options.copyWith(
      sourceLanguage: _options.targetLanguage,
      targetLanguage: _options.sourceLanguage,
    );
    _notify();
  }

  Future<void> pickOutputDir() async {
    final dir = await getDirectoryPath();
    if (dir == null || _disposed) return;
    _options = _options.copyWith(
      outputDir: dir,
      outputLocation: OutputLocation.custom,
    );
    _notify();
  }

  // —— 文件 ————————————————————————————————————————————————

  /// 这批路径里既不是字幕也不是音视频的那些该怎么跟用户解释。
  /// 音视频不算被拒 —— 它们另有去处（见 [ignoredNote]）。全都认识时返回 null。
  static String? rejection(List<String> paths) {
    final unknown = paths
        .where((p) => !MediaKinds.isSubtitle(p) && !MediaKinds.isMedia(p))
        .map(MediaKinds.extensionOf)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (unknown.isEmpty) return null;
    return '不认识的格式：${unknown.join('、')}';
  }

  /// 加一批路径。非字幕与已在列表里的跳过；先以「解析中」入列，解析完再更新，
  /// 用户不必等所有文件读完才看到它们出现。
  Future<void> add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(MediaKinds.isSubtitle).where(known.add).toList();
    if (fresh.isEmpty) return;
    _files.addAll([
      for (final p in fresh)
        StagedSubtitle(path: p, state: StagedSubtitleState.parsing),
    ]);
    _notify();
    await Future.wait(fresh.map(_parse));
  }

  Future<void> _parse(String path) async {
    final info = await media.probeFile(path);
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return; // 解析期间被移除了。
    final ok = info.exists && (info.cueCount ?? 0) > 0;
    _files[i] = StagedSubtitle(
      path: path,
      info: info,
      state: ok ? StagedSubtitleState.ready : StagedSubtitleState.broken,
    );
    _notify();
  }

  Future<void> browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '字幕', extensions: MediaKinds.subtitle.toList()),
      ],
    );
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  /// 落下一批路径：音视频记到「已忽略」，不认识的格式记一句说明，其余收下。
  void handleDrop(List<String> paths) {
    final known = _ignoredMedia.toSet();
    _ignoredMedia.addAll(paths.where(MediaKinds.isMedia).where(known.add));
    _dropError = rejection(paths);
    _notify();
    add(paths);
  }

  /// 预填的一批里可能混着音视频（任务页把整把拖放原样转过来），说清楚它们去哪儿了。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }

  void remove(StagedSubtitle file) {
    _files.removeWhere((f) => f.path == file.path);
    _notify();
  }

  void clear() {
    _files.clear();
    _ignoredMedia.clear();
    _dropError = null;
    _notify();
  }

  void clearDropError() {
    if (_dropError == null) return;
    _dropError = null;
    _notify();
  }

  /// 「改用新建转写」：交出被忽略的音视频并从这里清掉。调用方把它们带去转写。
  List<String> takeIgnoredMedia() {
    final media = List<String>.from(_ignoredMedia);
    _ignoredMedia.clear();
    _notify();
    return media;
  }

  /// 文件区顶部那条中性说明。没有忽略任何东西时为 null。
  String? get ignoredNote => _ignoredMedia.isEmpty
      ? null
      : '已忽略 ${_ignoredMedia.length} 个音视频文件，音视频请用「新建转写」';

  /// 会入队的文件（解析不出内容的不算）。
  List<StagedSubtitle> get enqueueable =>
      _files.where((f) => f.willEnqueue).toList();

  int get parsingCount =>
      _files.where((f) => f.state == StagedSubtitleState.parsing).length;

  int get brokenCount =>
      _files.where((f) => f.state == StagedSubtitleState.broken).length;

  /// 已解析出的总条数。仍在解析的文件不计。
  int get totalCues => _files.fold(0, (sum, f) => sum + (f.cueCount ?? 0));

  /// 已解析出的总时间跨度。
  Duration get totalDuration => _files.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  /// 按每批条数估算要调用几次翻译接口。用户调批次大小时这个数跟着变，
  /// 是「调大省调用」最直观的证据。
  int get batchCount => totalCues == 0
      ? 0
      : (totalCues + _options.translationBatchSize - 1) ~/
            _options.translationBatchSize;

  // —— 校验 ————————————————————————————————————————————————

  Readiness get readiness =>
      ProviderReadiness.translation(_options.translationProviderId, settings);

  bool get canStart => enqueueable.isNotEmpty && !readiness.isBlocked;

  String get direction =>
      '${_options.sourceLanguage.name} → ${_options.targetLanguage.name}';

  /// 顶栏副标题：有文件时汇总条数与方向，没有时说这页是干什么的。
  String get summary {
    final n = enqueueable.length;
    if (_files.isEmpty) return '把字幕文件翻译成目标语言';
    return '$n 个文件 · 共 ${grouped(totalCues)} 条 · $direction · '
        '将创建 $n 个翻译任务';
  }

  /// 文件表下面那句：参数怎么应用，以及这批要花几次调用。
  String get applyNote {
    final cost = totalCues == 0
        ? ''
        : '；共 ${grouped(totalCues)} 条，每批 ${_options.translationBatchSize} 条，'
              '约 $batchCount 次调用';
    return '参数统一应用到每个文件$cost；单个失败不影响其余';
  }

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get footer {
    if (_dropError != null) {
      return (text: _dropError!, icon: Symbols.error, error: true);
    }
    if (_files.isEmpty) {
      return (text: '先添加字幕文件', icon: Symbols.add_circle, error: false);
    }
    final r = readiness;
    if (r.isBlocked) {
      return (
        text: [r.message, r.hint].nonNulls.join('，'),
        icon: Symbols.error,
        error: true,
      );
    }
    final n = enqueueable.length;
    if (n == 0 && parsingCount == 0) {
      return (text: '选中的文件都解析不出字幕内容，换几个文件再试', icon: Symbols.error, error: true);
    }
    if (r.level == ReadinessLevel.advisory) {
      return (text: r.message, icon: Symbols.info, error: false);
    }
    final extras = [
      // 一个就绪的都没有时开头那句已经说了「仍在解析」，不再重复。
      if (n > 0 && parsingCount > 0) '$parsingCount 个文件仍在解析，可先开始',
      if (brokenCount > 0) '$brokenCount 个文件无法解析，将跳过',
    ];
    final lead = n == 0
        ? '文件仍在解析，解析完即可开始'
        : n == 1
        ? '将创建 1 个翻译任务，加入队列后在任务页查看进度'
        : '将创建 $n 个翻译任务，按列表顺序排队';
    return (
      text: [lead, ...extras].join('；'),
      icon: Symbols.info,
      error: false,
    );
  }

  /// 对话框的页脚：文件区就在按钮上方，不必再说「将创建几个任务」，
  /// 改为汇总条数与语言方向。拦住或没文件时与 [footer] 相同。
  ({String text, IconData icon, bool error}) get compactFooter {
    final foot = footer;
    final n = enqueueable.length;
    if (foot.error || n == 0) return foot;
    final extras = [
      if (parsingCount > 0) '$parsingCount 个文件仍在解析，可先开始',
      if (brokenCount > 0) '$brokenCount 个文件无法解析，将跳过',
    ];
    return (
      text: [
        '$n 个文件 · 共 ${grouped(totalCues)} 条 · $direction',
        ...extras,
      ].join('；'),
      icon: extras.isEmpty ? Symbols.check_circle : Symbols.warning,
      error: false,
    );
  }

  /// 产物名里的语言段。与 [TaskRunner] 的命名保持一致，双语带上两种语言，
  /// 原文为自动检测时写 src。
  String get langTag {
    String tag(Language l) => l.isAuto ? 'src' : l.code;
    return _options.resolvedBilingual.isBilingual
        ? '${tag(_options.sourceLanguage)}-${tag(_options.targetLanguage)}'
        : tag(_options.targetLanguage);
  }

  /// 「原文件名.en.srt」这样的产物名示例。
  String get outputNameExample => '原文件名.$langTag.${_options.format.extension}';

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    _options.resolvedBilingual.label,
    '${_options.cjkLineLength} / ${_options.latinLineLength} 字',
    _options.format.extension.toUpperCase(),
    _options.outputLocation.label,
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  NewTranslateResult? submit() {
    if (!canStart) return null;
    settings.lastTranslateOptions = _options;
    return NewTranslateResult(
      paths: enqueueable.map((f) => f.path).toList(),
      options: _options,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 两段表单。对话框与页面各自决定怎么摆，段内长什么样在这里定。
//
// 两种外形：对话框里每段是一张卡片（FormSection），页面的参数面板里两段
// 平铺、用 1px 分隔线隔开（flat）。字段、文案、校验完全相同。
// ═══════════════════════════════════════════════════════════════════════

/// 「翻译」段：语言对（可对换）、翻译服务、模型、每批条数、术语表、就绪状态行。
class TranslateLanguageSection extends StatelessWidget {
  const TranslateLanguageSection({
    super.key,
    required this.form,
    this.onOpenSettings,
    this.flat = false,
  });

  final TranslateFormController form;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字。
  final VoidCallback? onOpenSettings;

  /// 平铺（页面）还是卡片（对话框）。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final info = Registry.translationInfo(o.translationProviderId);
    final readiness = form.readiness;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    // 原文 ⇄ 目标放同一行，中间一个对换按钮：这是整段最该被一眼看懂的信息。
    final languages = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: '原文语言',
            child: AppDropdown<String>(
              value: o.sourceLanguage.code,
              groups: [
                DropdownGroup(
                  entries: [
                    for (final l in Languages.source)
                      DropdownEntry(value: l.code, label: l.name),
                  ],
                ),
              ],
              onChanged: (code) => form.update(
                (o) => o.copyWith(sourceLanguage: Languages.resolve(code)),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2 + 2),
        SwapLanguagesButton(form: form),
        const SizedBox(width: AppSpacing.s2 + 2),
        Expanded(
          child: LabeledField(
            label: '目标语言',
            child: AppDropdown<String>(
              value: o.targetLanguage.code,
              groups: [
                DropdownGroup(
                  entries: [
                    for (final l in Languages.target)
                      DropdownEntry(value: l.code, label: l.name),
                  ],
                ),
              ],
              onChanged: (code) => form.update(
                (o) => o.copyWith(targetLanguage: Languages.resolve(code)),
              ),
            ),
          ),
        ),
      ],
    );
    final service = LabeledField(
      label: '翻译服务',
      child: AppDropdown<String>(
        value: o.translationProviderId,
        error: readiness.isBlocked,
        groups: providerGroups(
          Registry.translation,
          (id) => ProviderReadiness.translation(id, form.settings),
        ),
        // 换服务就把模型清掉，否则会把上一家的模型名发给下一家。
        onChanged: (id) => form.update(
          (o) => o.copyWith(translationProviderId: id, translationModel: null),
        ),
      ),
    );
    final model = modelField(
      info: info,
      model: o.translationModel,
      settings: form.settings,
      onChanged: (m) => form.update((o) => o.copyWith(translationModel: m)),
    );
    final batchHint = Text(
      '一次送给模型的字幕条数。调大省 token，但更容易漏条或合并。范围 1–100。',
      style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
    );
    final batch = NumberField(
      value: o.translationBatchSize,
      min: 1,
      max: 100,
      width: flat ? double.infinity : 88,
      onChanged: (v) => form.update((o) => o.copyWith(translationBatchSize: v)),
    );
    final guidance = LabeledField(
      label: '术语表与风格（可选）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MultilineField(
            value: o.translationGuidance,
            hint: 'Ballistic Missile Defense=反导系统\n保持口语，不要书面化',
            onChanged: (v) => form.update(
              (o) => o.copyWith(translationGuidance: v),
              notify: false,
            ),
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            '术语一行一条，写成「原文=译文」；其余行当作风格要求。仅用于本次任务。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final status = ReadinessLine(
      readiness: readiness,
      needsApiKey: info?.needsApiKey ?? true,
      onOpenSettings: onOpenSettings,
    );

    if (flat) {
      return flatSection(
        context,
        divider: false,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s1,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        children: [
          Text(
            '翻译',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          languages,
          twoColumn(service, model, gap: gap),
          LabeledField(
            label: '每批条数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                batch,
                const SizedBox(height: AppSpacing.s1 + 2),
                batchHint,
              ],
            ),
          ),
          guidance,
          status,
        ],
      );
    }

    return FormSection(
      title: '翻译',
      gap: 14,
      children: [
        languages,
        twoColumn(service, model),
        LabeledField(
          label: '每批条数',
          child: Row(
            children: [
              batch,
              const SizedBox(width: AppSpacing.s3),
              Expanded(child: batchHint),
            ],
          ),
        ),
        guidance,
        status,
      ],
    );
  }
}

/// 原文 ⇄ 目标的对换按钮。原文为「自动检测」时禁用并说明原因。
class SwapLanguagesButton extends StatelessWidget {
  const SwapLanguagesButton({super.key, required this.form});

  final TranslateFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final enabled = form.canSwapLanguages;
    return Tooltip(
      message: enabled ? '对换原文与目标语言' : '原文为自动检测时不能对换',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? cs.outlineVariant
                  : cs.onSurface.withValues(
                      alpha: AppStateLayer.disabledContainer,
                    ),
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? form.swapLanguages : null,
            child: Ink(
              decoration: enabled
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: context.elevation.controlGradient,
                      ),
                      boxShadow: context.elevation.controlShadow,
                    )
                  : null,
              child: Icon(
                Symbols.swap_horiz,
                size: 20,
                weight: 400,
                color: enabled
                    ? cs.onSurface
                    : cs.onSurface.withValues(
                        alpha: AppStateLayer.disabledContent,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「高级」段：可折叠；输出格式、字幕排版（带预览）、每行字数、输出位置。
class TranslateAdvancedSection extends StatelessWidget {
  const TranslateAdvancedSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranslateFormController form;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final open = form.advancedOpen;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final header = Tappable(
      onTap: () => form.advancedOpen = !open,
      child: Row(
        children: [
          Icon(
            open ? Symbols.expand_more : Symbols.chevron_right,
            size: 18,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '高级',
            style: context.texts.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (!open)
            Flexible(
              child: Text(
                form.advancedSummary,
                textAlign: TextAlign.right,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    final format = LabeledField(
      label: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<SubtitleFormat>(
            value: o.format,
            fill: flat,
            onChanged: (f) => form.update((o) => o.copyWith(format: f)),
            segments: [
              for (final f in SubtitleFormat.values)
                (
                  value: f,
                  label: f.extension.toUpperCase(),
                  enabled: f.implemented,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            'ASS 需要一整套字幕样式配置，第二期提供。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final lengths = twoColumn(
      LabeledField(
        label: '每行最大字符数 · 中日韩',
        child: NumberField(
          value: o.cjkLineLength,
          min: 4,
          max: 60,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(cjkLineLength: v)),
        ),
      ),
      LabeledField(
        label: '每行最大字符数 · 其他语言',
        child: NumberField(
          value: o.latinLineLength,
          min: 8,
          max: 120,
          width: flat ? double.infinity : 88,
          onChanged: (v) => form.update((o) => o.copyWith(latinLineLength: v)),
        ),
      ),
      gap: gap,
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          header,
          if (open) ...[
            format,
            _LayoutField(form: form, fill: true),
            lengths,
            _OutputLocationRadios(form: form),
          ],
        ],
      );
    }

    return FormSection(
      gap: 14,
      children: [
        header,
        if (open) ...[
          Container(height: 1, color: cs.outlineVariant),
          format,
          _LayoutField(form: form, fill: false),
          lengths,
          _OutputLocationSegments(form: form),
        ],
      ],
    );
  }
}

/// 字幕排版 + 预览。纯文本没有「两行」的概念，这时整组灰掉并回落到「仅译文」。
class _LayoutField extends StatelessWidget {
  const _LayoutField({required this.form, required this.fill});

  final TranslateFormController form;

  /// 页面里撑满面板宽度；对话框里按内容宽。
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final plain = o.format == SubtitleFormat.txt;
    final layout = o.resolvedBilingual;
    return LabeledField(
      label: '字幕排版',
      enabled: !plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedToggle<BilingualLayout>(
            value: layout,
            fill: fill,
            onChanged: (v) => form.update((o) => o.copyWith(bilingual: v)),
            segments: [
              for (final v in BilingualLayout.values)
                (value: v, label: v.label, enabled: !plain),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          LayoutPreview(layout: layout),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            plain ? '纯文本不保留双语排版，已回落到「仅译文」' : '双语指同一条字幕里两行文字，不是两个文件。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 排版预览。纯展示，随选择实时变化 —— 让用户不用试跑就知道会得到什么。
/// 仅译文一行，双语两行按所选顺序。
class LayoutPreview extends StatelessWidget {
  const LayoutPreview({super.key, required this.layout});

  final BilingualLayout layout;

  static const target = '我们从第二章开始';
  static const source = "We'll start from chapter two";

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = kTimecodeStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    final body = kTimecodeStyle.copyWith(fontWeight: FontWeight.w400);
    final lines = switch (layout) {
      BilingualLayout.targetOnly => const [target],
      BilingualLayout.targetAbove => const [target, source],
      BilingualLayout.targetBelow => const [source, target],
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('12', style: muted),
          Text('00:01:23,450 --> 00:01:26,100', style: muted),
          for (final line in lines) Text(line, style: body),
        ],
      ),
    );
  }
}

/// 页面版的「输出位置」：两个单选 + 命名规则说明。面板只有 400 宽，
/// 分段开关加路径挤不下，竖排的单选把路径放在自己那行。
class _OutputLocationRadios extends StatelessWidget {
  const _OutputLocationRadios({required this.form});

  final TranslateFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final custom = o.outputLocation == OutputLocation.custom;
    final mono = kTimecodeStyle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    final small = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '输出位置',
          style: context.texts.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        RadioRow(
          selected: !custom,
          label: OutputLocation.besideSource.label,
          onTap: () => form.update(
            (o) => o.copyWith(outputLocation: OutputLocation.besideSource),
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        RadioRow(
          selected: custom,
          label: OutputLocation.custom.label,
          trailing: custom
              ? GestureDetector(
                  onTap: form.pickOutputDir,
                  child: Text(
                    o.outputDir ?? '点此选择目录…',
                    style: mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          onTap: () {
            form.update(
              (o) => o.copyWith(outputLocation: OutputLocation.custom),
            );
            if (form.options.outputDir == null) form.pickOutputDir();
          },
        ),
        const SizedBox(height: AppSpacing.s2),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '译文写成 '),
              TextSpan(text: form.outputNameExample, style: mono),
              const TextSpan(text: '，不覆盖原文件'),
            ],
          ),
          style: small,
        ),
        const SizedBox(height: AppSpacing.s1),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '双语时语言段写成 '),
              TextSpan(text: 'en-zh', style: mono),
              const TextSpan(text: '，原文为自动检测时写成 '),
              TextSpan(text: 'src', style: mono),
            ],
          ),
          style: small,
        ),
      ],
    );
  }
}

/// 对话框版的「输出位置」：分段开关，指定目录时给路径框与「选择…」。
class _OutputLocationSegments extends StatelessWidget {
  const _OutputLocationSegments({required this.form});

  final TranslateFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final custom = o.outputLocation == OutputLocation.custom;
    return LabeledField(
      label: '输出位置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<OutputLocation>(
            value: o.outputLocation,
            onChanged: (v) {
              form.update((o) => o.copyWith(outputLocation: v));
              if (v == OutputLocation.custom &&
                  form.options.outputDir == null) {
                form.pickOutputDir();
              }
            },
            segments: [
              for (final v in OutputLocation.values)
                (value: v, label: v.label, enabled: true),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          if (custom)
            Row(
              children: [
                Expanded(
                  child: ControlSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        o.outputDir ?? '点此选择目录…',
                        style: kTimecodeStyle.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2 + 2),
                ControlButton(label: '选择…', onPressed: form.pickOutputDir),
              ],
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '译文写成 '),
                  TextSpan(
                    text: form.outputNameExample,
                    style: kTimecodeStyle.copyWith(
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const TextSpan(text: '，不覆盖原文件。'),
                ],
              ),
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// 文件区顶部那条中性提示：忽略了几个音视频，右侧「改用新建转写」把它们带走。
/// 用 surface-container 而不是 error —— 拖错门不是错误。
class IgnoredMediaNote extends StatelessWidget {
  const IgnoredMediaNote({
    super.key,
    required this.text,
    this.onSwitchToTranscribe,
  });

  final String text;
  final VoidCallback? onSwitchToTranscribe;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.block,
            size: 18,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onSwitchToTranscribe != null) ...[
            const SizedBox(width: AppSpacing.s2),
            LinkText(
              label: '改用新建转写',
              color: cs.primary,
              onTap: onSwitchToTranscribe!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 页脚那行校验文案：图标 + 文字，阻断用 error 色。
class TranslateFooterLine extends StatelessWidget {
  const TranslateFooterLine({super.key, required this.form, this.line});

  final TranslateFormController form;

  /// 页面在拖放拒收时用中性色的说明顶替控制器里的 error 版本。
  final ({String text, IconData icon, bool error})? line;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final foot = line ?? form.footer;
    final color = foot.error ? cs.error : cs.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(foot.icon, size: 16, weight: 400, color: color),
        const SizedBox(width: AppSpacing.s1 + 2),
        Expanded(
          child: Text(
            foot.text,
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 「开始翻译」。页面上带数量，对话框不带 —— 对话框的文件区就在按钮上方。
class TranslateStartButton extends StatelessWidget {
  const TranslateStartButton({
    super.key,
    required this.form,
    required this.onStart,
    this.withCount = false,
  });

  final TranslateFormController form;
  final VoidCallback onStart;
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final n = form.enqueueable.length;
    return PrimaryButton(
      label: withCount ? '开始翻译 · $n' : '开始翻译',
      icon: Symbols.translate,
      onPressed: form.canStart ? onStart : null,
    );
  }
}
