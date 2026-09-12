import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/language.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/task_options.dart';
import '../../services/media.dart';
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import 'provider_fields.dart';

/// 对话框确认后交出来的东西：一批字幕文件 + 一份参数。
///
/// [paths] 已经剔掉解析不出内容的文件 —— 那些留在界面上是为了让用户知道
/// 自己拖了什么，但不该变成必然失败的任务。
class NewTranslateResult {
  const NewTranslateResult({required this.paths, required this.options});

  final List<String> paths;
  final TaskOptions options;
}

/// 「新建翻译」对话框。
///
/// 与「新建转写」同构，少了「识别」那一段 —— 输入本来就是字幕，不需要识别；
/// 也没有「转写完成后继续翻译」开关，翻译是它的全部。确认后任务进同一个队列、
/// 同一条六阶段流水线，识别与断句两阶段标记为「已跳过」。
Future<NewTranslateResult?> showNewTranslateDialog(
  BuildContext context, {
  required AppSettings settings,
  List<String> initialPaths = const [],
  Media? media,
  VoidCallback? onOpenSettings,
  ValueChanged<List<String>>? onSwitchToTranscribe,
}) => showDialog<NewTranslateResult>(
  context: context,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
  builder: (_) => NewTranslateDialog(
    settings: settings,
    initialPaths: initialPaths,
    media: media,
    onOpenSettings: onOpenSettings,
    onSwitchToTranscribe: onSwitchToTranscribe,
  ),
);

class NewTranslateDialog extends StatefulWidget {
  const NewTranslateDialog({
    super.key,
    required this.settings,
    this.initialPaths = const [],
    this.media,
    this.onOpenSettings,
    this.onSwitchToTranscribe,
  });

  final AppSettings settings;
  final List<String> initialPaths;
  final Media? media;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  /// 用户把音视频一起拖了进来时的「改用新建转写」。收到的是被忽略的那几个路径。
  final ValueChanged<List<String>>? onSwitchToTranscribe;

  @override
  State<NewTranslateDialog> createState() => NewTranslateDialogState();
}

class NewTranslateDialogState extends State<NewTranslateDialog> {
  late final Media _media = widget.media ?? Media();
  late TaskOptions _options = widget.settings.defaultTaskOptions();

  final _files = <MediaFileInfo>[];

  /// 被忽略的音视频路径。留着是为了「改用新建转写」能把它们带过去。
  final _ignoredMedia = <String>[];

  bool _advOpen = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPaths.isEmpty) return;
    // 预填的一批里可能混着音视频（任务页把整把拖放原样转过来），
    // 这里就先记下来，好在文件区顶部说清楚它们被忽略了。
    _ignoredMedia.addAll(widget.initialPaths.where(MediaKinds.isMedia));
    _add(widget.initialPaths);
  }

  Future<void> _add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths
        .where(MediaKinds.isSubtitle)
        .where(known.add)
        .toList();
    if (fresh.isEmpty) return;
    // 入列即解析条数与时间跨度 —— 这是用户判断有没有拖错文件最快的信号。
    final probed = await Future.wait(fresh.map(_media.probeFile));
    if (!mounted) return;
    setState(() => _files.addAll(probed));
  }

  Future<void> _browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '字幕', extensions: MediaKinds.subtitle.toList()),
      ],
    );
    if (picked.isNotEmpty) await _add(picked.map((f) => f.path).toList());
  }

  Future<void> _pickOutputDir() async {
    final dir = await getDirectoryPath();
    if (dir == null || !mounted) return;
    setState(() {
      _options = _options.copyWith(
        outputDir: dir,
        outputLocation: OutputLocation.custom,
      );
    });
  }

  /// 落下一批路径。拖放本身要真实的平台事件才能触发，所以这里留个入口
  /// 给测试直接调用。
  @visibleForTesting
  void handleDrop(List<String> paths) {
    final known = _ignoredMedia.toSet();
    setState(() {
      _dragging = false;
      _ignoredMedia.addAll(paths.where(MediaKinds.isMedia).where(known.add));
    });
    _add(paths);
  }

  void _switchToTranscribe() {
    final media = List<String>.from(_ignoredMedia);
    Navigator.of(context).pop();
    widget.onSwitchToTranscribe?.call(media);
  }

  // —— 校验 ————————————————————————————————————————————————

  Readiness get _readiness => ProviderReadiness.translation(
    _options.translationProviderId,
    widget.settings,
  );

  /// 能真正入队的文件：解析得出条目的那些。
  List<MediaFileInfo> get _usable =>
      _files.where((f) => !f.isEmptySubtitle).toList();

  List<MediaFileInfo> get _broken =>
      _files.where((f) => f.isEmptySubtitle).toList();

  int get _totalCues =>
      _usable.fold(0, (sum, f) => sum + (f.cueCount ?? 0));

  /// 底部那一行。阻断用 error 色并禁用按钮，提醒用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get _footer {
    if (_files.isEmpty) {
      return (text: '先添加字幕文件', icon: Symbols.info, error: false);
    }
    final readiness = _readiness;
    if (readiness.isBlocked) {
      return (
        text: [readiness.message, readiness.hint].nonNulls.join('，'),
        icon: Symbols.error,
        error: true,
      );
    }
    if (_usable.isEmpty) {
      return (
        text: '选中的文件都解析不出字幕内容，换几个文件再试',
        icon: Symbols.error,
        error: true,
      );
    }

    final parts = [
      if (_ignoredMedia.isNotEmpty) '已忽略 ${_ignoredMedia.length} 个音视频文件',
      '${_usable.length} 个文件 · 共 ${grouped(_totalCues)} 条 · '
          '${_options.sourceLanguage.name} → ${_options.targetLanguage.name}',
      if (_broken.isNotEmpty) '${_broken.length} 个文件无法解析，将跳过',
    ];
    final clean = _ignoredMedia.isEmpty && _broken.isEmpty;
    return (
      text: parts.join('；'),
      icon: clean ? Symbols.check_circle : Symbols.warning,
      error: false,
    );
  }

  bool get _canStart => _usable.isNotEmpty && !_readiness.isBlocked;

  void _start() {
    if (!_canStart) return;
    Navigator.of(context).pop(
      NewTranslateResult(
        paths: _usable.map((f) => f.path).toList(),
        options: _options,
      ),
    );
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) _start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _start,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (d) =>
                handleDrop(d.files.map((f) => f.path).toList()),
            child: GlassPanel(
              strong: true,
              expand: false,
              radius: AppRadius.xl,
              shadow: context.elevation.shadow3,
              child: SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(cs),
                    // 内容区最高 640，再长就在对话框内部滚动 —— 标题与底部
                    // 那行校验必须始终看得见，否则用户不知道为什么不能开始。
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 640),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s6,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _fileArea(),
                              const SizedBox(height: AppSpacing.s4),
                              _translateSection(),
                              const SizedBox(height: AppSpacing.s4),
                              _advancedSection(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _footerBar(cs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s6,
      22,
      AppSpacing.s6,
      AppSpacing.s4,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新建翻译', style: context.texts.titleLarge),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '把字幕文件翻译成目标语言',
                style: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconActionButton(
          icon: Symbols.close,
          tooltip: '关闭（Esc）',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  // —— 文件区 ————————————————————————————————————————————

  Widget _fileArea() => _files.isEmpty ? _emptyDropZone() : _fileList();

  Widget _emptyDropZone() {
    final cs = context.colors;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: AnimatedContainer(
        duration: AppDuration.medium,
        curve: kEasingStandard,
        height: 136,
        decoration: BoxDecoration(
          color: _dragging ? cs.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: _dragging ? cs.primary : cs.outline,
            width: _dragging ? 2 : 1,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.subtitles,
              size: 32,
              weight: 400,
              color: _dragging ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              // 桌面拖放在进入窗口时只有位置、拿不到文件列表，所以不写数量。
              _dragging ? '松开以添加文件' : '把字幕文件拖到这里',
              style: context.texts.titleSmall?.copyWith(
                color: _dragging ? cs.primary : null,
              ),
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              _dragging
                  ? '非字幕文件会被忽略，音视频请用「新建转写」'
                  : '支持 SRT、VTT、ASS、SSA，可一次选多个',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (!_dragging) ...[
              const SizedBox(height: AppSpacing.s1 + 2),
              QuietButton(label: '选择文件…', height: 32, onPressed: _browse),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileList() {
    final cs = context.colors;
    final broken = _broken.length;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_ignoredMedia.isNotEmpty) _ignoredBanner(cs),
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      broken == 0
                          ? '已选 ${_files.length} 个文件'
                          : '已选 ${_files.length} 个文件，其中 $broken 个无法解析',
                      style: context.texts.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  QuietButton(
                    label: '添加文件…',
                    icon: Symbols.add,
                    height: 28,
                    onPressed: _browse,
                  ),
                ],
              ),
            ),
          ),
          for (final file in _files)
            _FileRow(
              file: file,
              onRemove: () => setState(() => _files.remove(file)),
            ),
        ],
      ),
    );
  }

  Widget _ignoredBanner(ColorScheme cs) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.s1),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s3,
      AppSpacing.s2,
      AppSpacing.s2 + 2,
      AppSpacing.s2,
    ),
    decoration: BoxDecoration(
      color: cs.tertiaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        Icon(
          Symbols.info,
          size: 18,
          weight: 400,
          color: cs.onTertiaryContainer,
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: Text(
            '已忽略 ${_ignoredMedia.length} 个音视频文件，音视频请用「新建转写」',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onTertiaryContainer,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        if (widget.onSwitchToTranscribe != null)
          LinkText(
            label: '改用新建转写',
            color: cs.onTertiaryContainer,
            onTap: _switchToTranscribe,
          ),
      ],
    ),
  );

  // —— 翻译 ——————————————————————————————————————————————

  Widget _translateSection() {
    final cs = context.colors;
    final info = Registry.translationInfo(_options.translationProviderId);
    final readiness = _readiness;
    return FormSection(
      title: '翻译',
      gap: 14,
      children: [
        // 原文 → 目标放同一行，中间一个箭头：这是整个对话框最该被一眼看懂的信息。
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: LabeledField(
                label: '原文语言',
                child: AppDropdown<String>(
                  value: _options.sourceLanguage.code,
                  groups: [
                    DropdownGroup(
                      entries: [
                        for (final l in Languages.source)
                          DropdownEntry(value: l.code, label: l.name),
                      ],
                    ),
                  ],
                  onChanged: (code) => setState(() {
                    _options = _options.copyWith(
                      sourceLanguage: Languages.resolve(code),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            SizedBox(
              height: 36,
              child: Icon(
                Symbols.arrow_forward,
                size: 20,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: LabeledField(
                label: '目标语言',
                child: AppDropdown<String>(
                  value: _options.targetLanguage.code,
                  groups: [
                    DropdownGroup(
                      entries: [
                        for (final l in Languages.target)
                          DropdownEntry(value: l.code, label: l.name),
                      ],
                    ),
                  ],
                  onChanged: (code) => setState(() {
                    _options = _options.copyWith(
                      targetLanguage: Languages.resolve(code),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
        _twoColumn(
          LabeledField(
            label: '翻译服务',
            child: AppDropdown<String>(
              value: _options.translationProviderId,
              error: readiness.isBlocked,
              groups: providerGroups(
                Registry.translation,
                (id) => ProviderReadiness.translation(id, widget.settings),
              ),
              onChanged: (id) => setState(() {
                // 换服务就把模型清掉，否则会把上一家的模型名发给下一家。
                _options = _options.copyWith(
                  translationProviderId: id,
                  translationModel: null,
                );
              }),
            ),
          ),
          modelField(
            info: info,
            model: _options.translationModel,
            settings: widget.settings,
            onChanged: (m) => setState(
              () => _options = _options.copyWith(translationModel: m),
            ),
          ),
        ),
        LabeledField(
          label: '每批条数',
          child: Row(
            children: [
              NumberField(
                value: _options.translationBatchSize,
                min: 1,
                max: 100,
                onChanged: (v) => setState(
                  () => _options = _options.copyWith(translationBatchSize: v),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  '一次送给模型的字幕条数。调大省 token，但模型更容易漏条或合并。范围 1–100。',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        LabeledField(
          label: '术语表与风格（可选）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MultilineField(
                value: _options.translationGuidance,
                hint: 'Ballistic Missile Defense=反导系统\n保持口语，不要书面化',
                onChanged: (v) =>
                    _options = _options.copyWith(translationGuidance: v),
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
        ),
        _statusLine(readiness, info),
      ],
    );
  }

  Widget _statusLine(Readiness readiness, ProviderInfo? info) {
    final cs = context.colors;
    final error = readiness.isBlocked;
    final color = error ? cs.error : cs.onSurfaceVariant;
    final icon = switch (readiness.level) {
      ReadinessLevel.ready => Symbols.check_circle,
      ReadinessLevel.advisory => Symbols.schedule,
      ReadinessLevel.blocked => Symbols.error,
    };
    return Row(
      children: [
        Icon(icon, size: 16, weight: 400, color: color),
        const SizedBox(width: AppSpacing.s1 + 2),
        Flexible(
          child: Text(
            readiness.isReady
                ? (info?.needsApiKey ?? true)
                      ? '已配置密钥，可直接开始'
                      : '无需密钥，可直接开始'
                : [readiness.message, if (!error) readiness.hint].nonNulls
                      .join('。'),
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
        if (error && widget.onOpenSettings != null) ...[
          const SizedBox(width: AppSpacing.s2),
          LinkText(
            label: '去设置',
            color: color,
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenSettings!();
            },
          ),
        ],
      ],
    );
  }

  // —— 高级 ——————————————————————————————————————————————

  Widget _advancedSection() {
    final cs = context.colors;
    return FormSection(
      gap: 14,
      children: [
        Tappable(
          onTap: () => setState(() => _advOpen = !_advOpen),
          child: Row(
            children: [
              Icon(
                Symbols.tune,
                size: 18,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s1 + 2),
              Text(
                '高级',
                style: context.texts.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (!_advOpen)
                Flexible(
                  child: Text(
                    _advancedSummary,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: AppSpacing.s2),
              Icon(
                _advOpen ? Symbols.expand_less : Symbols.expand_more,
                size: 20,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (_advOpen) ...[
          Container(height: 1, color: cs.outlineVariant),
          _layoutField(cs),
          _twoColumn(
            LabeledField(
              label: '每行最大字符数 · 中日韩',
              child: NumberField(
                value: _options.cjkLineLength,
                min: 4,
                max: 60,
                onChanged: (v) => setState(
                  () => _options = _options.copyWith(cjkLineLength: v),
                ),
              ),
            ),
            LabeledField(
              label: '每行最大字符数 · 其他语言',
              child: NumberField(
                value: _options.latinLineLength,
                min: 8,
                max: 120,
                onChanged: (v) => setState(
                  () => _options = _options.copyWith(latinLineLength: v),
                ),
              ),
            ),
          ),
          LabeledField(
            label: '输出格式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedToggle<SubtitleFormat>(
                  value: _options.format,
                  onChanged: (f) =>
                      setState(() => _options = _options.copyWith(format: f)),
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
          ),
          _outputLocationField(cs),
        ],
      ],
    );
  }

  /// 字幕排版。纯文本没有「两行」的概念，这时整组灰掉并回落到「仅译文」。
  Widget _layoutField(ColorScheme cs) {
    final plain = _options.format == SubtitleFormat.txt;
    final layout = _options.resolvedBilingual;
    return LabeledField(
      label: '字幕排版',
      enabled: !plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<BilingualLayout>(
            value: layout,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(bilingual: v)),
            segments: [
              for (final v in BilingualLayout.values)
                (value: v, label: v.label, enabled: !plain),
            ],
          ),
          const SizedBox(height: AppSpacing.s1 + 2),
          Text(
            plain
                ? '纯文本不保留双语排版，已回落到「仅译文」。'
                : '双语指同一条字幕里两行文字，不是两个文件。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (layout.isBilingual) ...[
            const SizedBox(height: AppSpacing.s1 + 2),
            _LayoutPreview(layout: layout),
          ],
        ],
      ),
    );
  }

  Widget _outputLocationField(ColorScheme cs) {
    final custom = _options.outputLocation == OutputLocation.custom;
    return LabeledField(
      label: '输出位置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<OutputLocation>(
            value: _options.outputLocation,
            onChanged: (v) {
              setState(() => _options = _options.copyWith(outputLocation: v));
              if (v == OutputLocation.custom && _options.outputDir == null) {
                _pickOutputDir();
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
                        _options.outputDir ?? '点此选择目录…',
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
                ControlButton(label: '选择…', onPressed: _pickOutputDir),
              ],
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '译文写成 '),
                  TextSpan(
                    text: '原文件名.${_langTag()}.${_options.format.extension}',
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

  /// 产物名里的语言段。与 [TaskRunner] 的命名保持一致，双语带上两种语言。
  String _langTag() {
    String tag(Language l) => l.isAuto ? 'src' : l.code;
    return _options.resolvedBilingual.isBilingual
        ? '${tag(_options.sourceLanguage)}-${tag(_options.targetLanguage)}'
        : tag(_options.targetLanguage);
  }

  String get _advancedSummary => [
    _options.resolvedBilingual.label,
    '${_options.cjkLineLength} / ${_options.latinLineLength} 字',
    _options.format.extension.toUpperCase(),
    _options.outputLocation.label,
  ].join(' · ');

  // —— 底栏 ——————————————————————————————————————————————

  Widget _footerBar(ColorScheme cs) {
    final foot = _footer;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s4),
      padding: const EdgeInsets.fromLTRB(AppSpacing.s6, 14, AppSpacing.s6, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            foot.icon,
            size: 16,
            weight: 400,
            color: foot.error ? cs.error : cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1 + 2),
          Expanded(
            child: Text(
              foot.text,
              style: context.texts.bodySmall?.copyWith(
                color: foot.error ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          ControlButton(
            label: '取消',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.s2),
          PrimaryButton(
            label: '开始翻译',
            icon: Symbols.translate,
            onPressed: _canStart ? _start : null,
          ),
        ],
      ),
    );
  }

  // —— 零件 ——————————————————————————————————————————————

  Widget _twoColumn(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: AppSpacing.s4),
      Expanded(child: right),
    ],
  );

}

/// 文件列表的一行：文件名 + 「条数 · 时间跨度 · 大小」。
///
/// 解析不出内容的文件留在列表里，用 error 色写明会被跳过 —— 直接不收下
/// 会让用户以为自己没拖进来，反复再拖一次。
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final MediaFileInfo file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final broken = file.isEmptySubtitle;
    final metaColor = broken ? cs.error : cs.onSurfaceVariant;
    final meta = broken
        ? '无法解析，将跳过'
        : [
            '${grouped(file.cueCount ?? 0)} 条',
            if (file.duration != null) Srt.formatDuration(file.duration!),
            file.sizeLabel,
          ].join(' · ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s3,
          6,
          AppSpacing.s2,
          6,
        ),
        child: Row(
          children: [
            Icon(
              broken ? Symbols.subtitles_off : Symbols.subtitles,
              size: 20,
              weight: 400,
              color: broken ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: metaColor),
                  ),
                ],
              ),
            ),
            IconActionButton(
              icon: Symbols.close,
              tooltip: '移除',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// 排版预览。纯展示，随选择实时变化 —— 让用户不用试跑就知道会得到什么。
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({required this.layout});

  final BilingualLayout layout;

  static const _target = '我们从第二章开始';
  static const _source = "We'll start from chapter two";

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final above = layout == BilingualLayout.targetAbove;
    final muted = kTimecodeStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
    final body = kTimecodeStyle.copyWith(fontWeight: FontWeight.w400);
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
          Text(above ? _target : _source, style: body),
          Text(above ? _source : _target, style: body),
        ],
      ),
    );
  }
}
