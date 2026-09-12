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

/// 对话框确认后交出来的东西：一批文件 + 一份参数。
class NewTranscribeResult {
  const NewTranscribeResult({required this.paths, required this.options});

  final List<String> paths;
  final TaskOptions options;
}

/// 「新建转写」对话框。
///
/// 只负责收集参数，**不跑任务也不显示进度** —— 点「开始转写」立即入队并关闭，
/// 进度归任务页。原 Python 实现把识别过程跑在同一个窗口里，于是那个窗口既是
/// 表单又是控制台，两件事互相挡着。
Future<NewTranscribeResult?> showNewTranscribeDialog(
  BuildContext context, {
  required AppSettings settings,
  List<String> initialPaths = const [],
  Media? media,
  VoidCallback? onOpenSettings,
}) => showDialog<NewTranscribeResult>(
  context: context,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
  builder: (_) => NewTranscribeDialog(
    settings: settings,
    initialPaths: initialPaths,
    media: media,
    onOpenSettings: onOpenSettings,
  ),
);

class NewTranscribeDialog extends StatefulWidget {
  const NewTranscribeDialog({
    super.key,
    required this.settings,
    this.initialPaths = const [],
    this.media,
    this.onOpenSettings,
  });

  final AppSettings settings;
  final List<String> initialPaths;
  final Media? media;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  @override
  State<NewTranscribeDialog> createState() => NewTranscribeDialogState();
}

class NewTranscribeDialogState extends State<NewTranscribeDialog> {
  late final Media _media = widget.media ?? Media();
  late TaskOptions _options = widget.settings.defaultTaskOptions();

  final _files = <MediaFileInfo>[];
  bool _advOpen = false;
  bool _dragging = false;

  /// 拖进来的东西不是音视频时的说明。落下即清掉上一次的。
  String? _dropError;

  @override
  void initState() {
    super.initState();
    if (widget.initialPaths.isEmpty) return;
    // 预填的一批里可能混着字幕（任务页把整把拖放原样转过来），说清楚它们去哪儿了。
    _dropError = _rejection(widget.initialPaths);
    _add(widget.initialPaths);
  }

  /// 这批路径里不是音视频的那些该怎么跟用户解释。全都收下时返回 null。
  static String? _rejection(List<String> paths) {
    final rejected = paths.where((p) => !MediaKinds.isMedia(p)).toList();
    if (rejected.isEmpty) return null;
    final subtitles = rejected.where(MediaKinds.isSubtitle).length;
    if (subtitles == rejected.length) {
      return '已忽略 $subtitles 个字幕文件，字幕请用「新建翻译」';
    }
    return '不认识的格式：'
        '${rejected.map(MediaKinds.extensionOf).where((e) => e.isNotEmpty).toSet().join('、')}';
  }

  Future<void> _add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths
        .where(MediaKinds.isMedia)
        .where(known.add)
        .toList();
    final probed = await Future.wait(fresh.map(_media.probeFile));
    if (!mounted) return;
    setState(() => _files.addAll(probed));
  }

  Future<void> _browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList()),
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
    setState(() {
      _dragging = false;
      _dropError = _rejection(paths);
    });
    _add(paths);
  }

  // —— 校验 ————————————————————————————————————————————————

  Readiness get _asrReadiness => ProviderReadiness.asr(
    _options.asrProviderId,
    widget.settings,
    language: _options.sourceLanguage,
    model: _options.asrModel,
  );

  Readiness get _translationReadiness => ProviderReadiness.translation(
    _options.translationProviderId,
    widget.settings,
  );

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get _footer {
    if (_dropError != null) {
      return (text: _dropError!, icon: Symbols.error, error: true);
    }
    if (_files.isEmpty) {
      return (text: '先选择音视频文件', icon: Symbols.add_circle, error: false);
    }
    for (final r in [_asrReadiness, if (_options.translate) _translationReadiness]) {
      if (r.isBlocked) {
        return (
          text: [r.message, r.hint].nonNulls.join('，'),
          icon: Symbols.error,
          error: true,
        );
      }
    }
    for (final r in [_asrReadiness, if (_options.translate) _translationReadiness]) {
      if (r.level == ReadinessLevel.advisory) {
        return (text: r.message, icon: Symbols.info, error: false);
      }
    }
    final kind = _options.translate ? '转写并翻译' : '转写';
    return (
      text: _files.length == 1
          ? '将创建 1 个$kind任务，加入队列后在任务页查看进度'
          : '将创建 ${_files.length} 个$kind任务，按列表顺序排队',
      icon: Symbols.info,
      error: false,
    );
  }

  bool get _canStart =>
      _files.isNotEmpty &&
      !_asrReadiness.isBlocked &&
      (!_options.translate || !_translationReadiness.isBlocked);

  void _start() {
    if (!_canStart) return;
    Navigator.of(context).pop(
      NewTranscribeResult(
        paths: _files.map((f) => f.path).toList(),
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
                              _recognizeSection(),
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
              Text('新建转写', style: context.texts.titleLarge),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '从音视频生成字幕，可接着翻译',
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
          color: _dragging ? cs.primary.withValues(alpha: 0.06) : null,
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
              Symbols.upload_file,
              size: 32,
              weight: 400,
              color: _dragging ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              _dragging ? '松开以添加文件' : '把音视频文件拖到这里',
              style: context.texts.titleSmall,
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              'mp4 · mov · mkv · mp3 · m4a · wav，可一次选多个',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            QuietButton(label: '选择文件…', height: 32, onPressed: _browse),
          ],
        ),
      ),
    );
  }

  Widget _fileList() {
    final cs = context.colors;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final file in _files) _FileRow(
            file: file,
            onRemove: () => setState(() => _files.remove(file)),
          ),
          const SizedBox(height: AppSpacing.s1),
          Container(height: 1, color: cs.outlineVariant),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                QuietButton(
                  label: '添加文件…',
                  icon: Symbols.add,
                  height: 28,
                  onPressed: _browse,
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Text(
                    _files.length > 1
                        ? '共 ${_files.length} 个文件，以下参数统一应用到每个文件'
                        : '再拖入文件可继续添加',
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // —— 识别 ——————————————————————————————————————————————

  Widget _recognizeSection() {
    final info = Registry.asrInfo(_options.asrProviderId);
    final readiness = _asrReadiness;
    return FormSection(
      title: '识别',
      children: [
        _twoColumn(
          LabeledField(
            label: '语音语言',
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
          LabeledField(
            label: '识别服务',
            child: AppDropdown<String>(
              value: _options.asrProviderId,
              error: readiness.isBlocked,
              display: _serviceLabel(info, _options.asrModel),
              groups: providerGroups(
                Registry.asr,
                (id) => ProviderReadiness.asr(id, widget.settings),
              ),
              onChanged: (id) => setState(() {
                // 换服务就把模型清掉，否则会把上一家的模型名发给下一家。
                _options = _options.copyWith(asrProviderId: id, asrModel: null);
              }),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        _twoColumn(
          modelField(
            info: info,
            model: _options.asrModel,
            settings: widget.settings,
            onChanged: (m) =>
                setState(() => _options = _options.copyWith(asrModel: m)),
          ),
          info != null && !info.implemented
              ? Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                    child: Text(
                      '模型随识别服务变化，自定义接口可自行填写模型名',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSpacing.s2),
        _statusLine(readiness),
      ],
    );
  }

  Widget _statusLine(Readiness readiness) {
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
                ? (Registry.asrInfo(_options.asrProviderId)?.needsApiKey ??
                          true)
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

  // —— 翻译 ——————————————————————————————————————————————

  Widget _translateSection() {
    final cs = context.colors;
    final on = _options.translate;
    final info = Registry.translationInfo(_options.translationProviderId);
    return FormSection(
      gap: 14,
      children: [
        Tappable(
          onTap: () => setState(
            () => _options = _options.copyWith(translate: !on),
          ),
          child: Row(
            children: [
              AppSwitch(
                value: on,
                onChanged: (v) =>
                    setState(() => _options = _options.copyWith(translate: v)),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('转写完成后继续翻译', style: context.texts.titleSmall),
                    const SizedBox(height: 1),
                    Text(
                      on
                          ? '任务类型为「转写并翻译」，翻译失败时原文字幕仍会保留'
                          : '关闭时任务类型为「转写」，之后也能在任务页单独发起翻译',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (on) ...[
          Container(height: 1, color: cs.outlineVariant),
          _twoColumn(
            LabeledField(
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
            LabeledField(
              label: '翻译服务',
              child: AppDropdown<String>(
                value: _options.translationProviderId,
                error: _translationReadiness.isBlocked,
                groups: providerGroups(
                  Registry.translation,
                  (id) => ProviderReadiness.translation(id, widget.settings),
                ),
                onChanged: (id) => setState(() {
                  _options = _options.copyWith(
                    translationProviderId: id,
                    translationModel: null,
                  );
                }),
              ),
            ),
          ),
          _twoColumn(
            modelField(
              info: info,
              model: _options.translationModel,
              settings: widget.settings,
              onChanged: (m) => setState(
                () => _options = _options.copyWith(translationModel: m),
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
                      () => _options = _options.copyWith(
                        translationBatchSize: v,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2 + 2),
                  Expanded(
                    child: Text(
                      '条数越大越省接口调用，出错时重试的范围也越大',
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          LabeledField(
            label: '术语与风格（可选）',
            child: MultilineField(
              value: _options.translationGuidance,
              hint: '保持人名与产品名不译：Flutter、SenseVoice。口语化，句子尽量短。',
              onChanged: (v) =>
                  _options = _options.copyWith(translationGuidance: v),
            ),
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
                  _advOpen ? Symbols.expand_more : Symbols.chevron_right,
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
            ],
          ),
        ),
        if (_advOpen) ...[
          Container(height: 1, color: cs.outlineVariant),
          LabeledField(
            label: '识别提示词（可选）',
            child: MultilineField(
              value: _options.asrPrompt,
              minHeight: 56,
              hint: '列出专有名词，帮助识别固定写法。例：SenseVoice、字幕组、whisper-large-v3',
              onChanged: (v) => _options = _options.copyWith(asrPrompt: v),
            ),
          ),
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
                  'ASS 需要一整套字幕样式配置，留到第二期。',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          LabeledField(
            label: '输出位置',
            child: Row(
              children: [
                SegmentedToggle<OutputLocation>(
                  value: _options.outputLocation,
                  onChanged: (v) {
                    setState(
                      () => _options = _options.copyWith(outputLocation: v),
                    );
                    if (v == OutputLocation.custom &&
                        _options.outputDir == null) {
                      _pickOutputDir();
                    }
                  },
                  segments: [
                    for (final v in OutputLocation.values)
                      (value: v, label: v.label, enabled: true),
                  ],
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickOutputDir,
                    child: Text(
                      _options.outputLocation == OutputLocation.custom
                          ? (_options.outputDir ?? '点此选择目录…')
                          : '与源文件同一个文件夹',
                      style: kTimecodeStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String get _advancedSummary => [
    if (_options.asrPrompt.trim().isNotEmpty) '识别提示词已填' else '识别提示词',
    '每行 ${_options.cjkLineLength} / ${_options.latinLineLength}',
    '输出 ${_options.format.extension.toUpperCase()}',
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
            label: '开始转写',
            icon: Symbols.mic,
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

  String _serviceLabel(ProviderInfo? info, String? model) {
    if (info == null) return '—';
    final chosen = model ?? info.defaultModel ?? '';
    return chosen.isEmpty ? info.name : '${info.name} · $chosen';
  }

}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final MediaFileInfo file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.s3, right: AppSpacing.s2),
        child: Row(
          children: [
            Icon(
              MediaKinds.extensionOf(file.path) == 'mp4' ||
                      MediaKinds.extensionOf(file.path) == 'mov' ||
                      MediaKinds.extensionOf(file.path) == 'mkv'
                  ? Symbols.movie
                  : Symbols.audio_file,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: Text(
                file.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Text(
              file.duration == null ? '—' : Srt.formatDuration(file.duration!),
              style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            SizedBox(
              width: 64,
              child: Text(
                file.sizeLabel,
                textAlign: TextAlign.right,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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
