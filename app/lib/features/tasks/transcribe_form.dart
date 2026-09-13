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
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import 'provider_fields.dart';

/// 表单确认后交出来的东西：一批文件 + 一份参数。
class NewTranscribeResult {
  const NewTranscribeResult({required this.paths, required this.options});

  final List<String> paths;
  final TaskOptions options;
}

/// 文件列表里一行的探测状态。
enum StagedFileState {
  /// 正在读时长与大小。不阻断提交 —— 时长只是辅助信息，任务跑起来会再探一遍。
  probing,
  ready,

  /// 文件不存在或读不出来。不入队，也不计入总数。
  unreadable,
}

/// 加进「新建转写」列表里的一个文件。
class StagedFile {
  const StagedFile({required this.path, this.info, required this.state});

  final String path;
  final MediaFileInfo? info;
  final StagedFileState state;

  String get fileName => path.split(RegExp(r'[/\\]')).last;

  /// 所在目录，用于列表副信息。
  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }

  bool get isVideo => const {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    'flv',
    'wmv',
  }.contains(MediaKinds.extensionOf(path));

  bool get willEnqueue => state != StagedFileState.unreadable;
}

/// 「新建转写」的表单状态：文件列表、参数、校验与提交。
///
/// 对话框与导航栏的「新建转写」页共用这一份 —— 两处的字段、校验文案与就绪
/// 判断必须逐字相同，各写一份必然走形。它不碰任务队列：`submit` 只把文件与
/// 参数打包交出去，入队由调用方完成，进度归任务页。
class TranscribeFormController extends ChangeNotifier {
  TranscribeFormController({
    required this.settings,
    Media? media,
    TaskOptions? initial,
  }) : media = media ?? Media(),
       _options = initial ?? settings.defaultTaskOptions();

  final AppSettings settings;
  final Media media;

  TaskOptions _options;
  TaskOptions get options => _options;

  final _files = <StagedFile>[];
  List<StagedFile> get files => List.unmodifiable(_files);

  /// 拖进来的东西不是音视频时的说明。落下即清掉上一次的。
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
    final last = settings.lastTranscribeOptions;
    if (last == null) return false;
    _options = last;
    _notify();
    return true;
  }

  bool get hasLastUsed => settings.lastTranscribeOptions != null;

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

  /// 这批路径里不是音视频的那些该怎么跟用户解释。全都收下时返回 null。
  static String? rejection(List<String> paths) {
    final rejected = paths.where((p) => !MediaKinds.isMedia(p)).toList();
    if (rejected.isEmpty) return null;
    final subtitles = rejected.where(MediaKinds.isSubtitle).length;
    if (subtitles == rejected.length) {
      return '已忽略 $subtitles 个字幕文件，字幕请用「新建翻译」';
    }
    return '不认识的格式：'
        '${rejected.map(MediaKinds.extensionOf).where((e) => e.isNotEmpty).toSet().join('、')}';
  }

  /// 加一批路径。非音视频与已在列表里的跳过；先以「探测中」入列，探完再更新，
  /// 用户不必等 ffprobe 跑完才看到文件出现。
  Future<void> add(List<String> paths) async {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(MediaKinds.isMedia).where(known.add).toList();
    if (fresh.isEmpty) return;
    _files.addAll([
      for (final p in fresh)
        StagedFile(path: p, state: StagedFileState.probing),
    ]);
    _notify();
    await Future.wait(fresh.map(_probe));
  }

  Future<void> _probe(String path) async {
    final MediaFileInfo info;
    try {
      info = await media.probeFile(path);
    } catch (_) {
      // A single unreadable path must not leave the row stuck in "probing"
      // or reject the whole batch.
      final fallback = MediaFileInfo(path: path, sizeBytes: 0, exists: false);
      _setProbeResult(path, fallback);
      return;
    }
    _setProbeResult(path, info);
  }

  void _setProbeResult(String path, MediaFileInfo info) {
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return; // 探测期间被移除了。
    _files[i] = StagedFile(
      path: path,
      info: info,
      state: info.exists ? StagedFileState.ready : StagedFileState.unreadable,
    );
    _notify();
  }

  Future<void> browse() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '音视频', extensions: MediaKinds.media.toList()),
      ],
    );
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  /// 落下一批路径：记下被拒的说明，收下其余。
  void handleDrop(List<String> paths) {
    _dropError = rejection(paths);
    _notify();
    add(paths);
  }

  /// 预填的一批里可能混着字幕（任务页把整把拖放原样转过来），说清楚它们去哪儿了。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }

  void remove(StagedFile file) {
    _files.removeWhere((f) => f.path == file.path);
    _notify();
  }

  void clear() {
    _files.clear();
    _dropError = null;
    _notify();
  }

  void clearDropError() {
    if (_dropError == null) return;
    _dropError = null;
    _notify();
  }

  /// 会入队的文件（读不出来的不算）。
  List<StagedFile> get enqueueable =>
      _files.where((f) => f.willEnqueue).toList();

  int get probingCount =>
      _files.where((f) => f.state == StagedFileState.probing).length;

  int get unreadableCount =>
      _files.where((f) => f.state == StagedFileState.unreadable).length;

  /// 已探明的总时长。仍在探测的文件不计。
  Duration get totalDuration => _files.fold(
    Duration.zero,
    (sum, f) => sum + (f.info?.duration ?? Duration.zero),
  );

  // —— 校验 ————————————————————————————————————————————————

  Readiness get asrReadiness => ProviderReadiness.asr(
    _options.asrProviderId,
    settings,
    language: _options.sourceLanguage,
    model: _options.asrModel,
    diarize: _options.diarize,
  );

  Readiness get translationReadiness => ProviderReadiness.translation(
    _options.translationProviderId,
    settings,
    model: _options.translationModel,
  );

  List<Readiness> get _checks => [
    asrReadiness,
    if (_options.translate) translationReadiness,
  ];

  bool get canStart =>
      enqueueable.isNotEmpty && !_checks.any((r) => r.isBlocked);

  String get kindLabel => _options.translate ? '转写并翻译' : '转写';

  /// 底部那一行。阻断用 error 色并禁用按钮，提示用中性色但照常可以开始。
  ({String text, IconData icon, bool error}) get footer {
    if (_dropError != null) {
      return (text: _dropError!, icon: Symbols.error, error: true);
    }
    final n = enqueueable.length;
    if (n == 0) {
      return (
        text: unreadableCount > 0 ? '列表里的文件都读不出来，移除或替换后再开始' : '先选择音视频文件',
        icon: unreadableCount > 0 ? Symbols.error : Symbols.add_circle,
        error: unreadableCount > 0,
      );
    }
    for (final r in _checks) {
      if (r.isBlocked) {
        return (
          text: [r.message, r.hint].nonNulls.join('，'),
          icon: Symbols.error,
          error: true,
        );
      }
    }
    for (final r in _checks) {
      if (r.level == ReadinessLevel.advisory) {
        return (text: r.message, icon: Symbols.info, error: false);
      }
    }
    final probing = probingCount > 0 ? '；$probingCount 个文件仍在探测，可先开始' : '';
    return (
      text: n == 1
          ? '将创建 1 个$kindLabel任务，加入队列后在任务页查看进度$probing'
          : '将创建 $n 个$kindLabel任务，按列表顺序排队$probing',
      icon: Symbols.info,
      error: false,
    );
  }

  /// 高级区折叠时标题旁那行摘要。
  String get advancedSummary => [
    if (_options.asrPrompt.trim().isNotEmpty) '识别提示词已填' else '识别提示词',
    '每行 ${_options.cjkLineLength} / ${_options.latinLineLength}',
    '输出 ${_options.format.extension.toUpperCase()}',
    _options.outputLocation.label,
  ].join(' · ');

  /// 页面参数面板只有 400 宽，用更短的一版：格式 · 位置 · 每行字数[ · 提示词已填]。
  String get compactAdvancedSummary => [
    _options.format.extension.toUpperCase(),
    _options.outputLocation.label,
    '每行 ${_options.cjkLineLength} / ${_options.latinLineLength} 字',
    if (_options.asrPrompt.trim().isNotEmpty) '识别提示词已填',
  ].join(' · ');

  /// 打包交出去，并把这份参数记为「上次参数」。不能开始时返回 null。
  /// 不清空列表 —— 对话框随即关闭，页面则自己决定清空的时机。
  NewTranscribeResult? submit() {
    if (!canStart) return null;
    settings.lastTranscribeOptions = _options;
    return NewTranscribeResult(
      paths: enqueueable.map((f) => f.path).toList(),
      options: _options,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 三段表单。对话框与页面各自决定怎么摆，段内长什么样在这里定。
//
// 两种外形：对话框里每段是一张卡片（FormSection），页面的参数面板里三段
// 平铺、用 1px 分隔线隔开（flat）。字段、文案、校验完全相同。
// ═══════════════════════════════════════════════════════════════════════

String serviceLabel(ProviderInfo? info, String? model, AppSettings settings) {
  if (info == null) return '—';
  final chosen = resolvedModel(info, model, settings);
  return chosen.isEmpty ? info.name : '${info.name} · $chosen';
}

/// 「识别」段：语音语言、识别服务、模型、就绪状态行。
class TranscribeRecognizeSection extends StatelessWidget {
  const TranscribeRecognizeSection({
    super.key,
    required this.form,
    this.onOpenSettings,
    this.flat = false,
  });

  final TranscribeFormController form;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  /// 平铺（页面）还是卡片（对话框）。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final info = Registry.asrInfo(o.asrProviderId);
    final readiness = form.asrReadiness;
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final language = LabeledField(
      label: '语音语言',
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
    );
    final service = LabeledField(
      label: '识别服务',
      child: AppDropdown<String>(
        value: o.asrProviderId,
        error: readiness.isBlocked,
        display: serviceLabel(info, o.asrModel, form.settings),
        groups: providerGroups(
          Registry.asr,
          (id) => ProviderReadiness.asr(id, form.settings),
        ),
        // 换服务就把模型清掉，否则会把上一家的模型名发给下一家。
        // 新服务不支持说话人分离就把开关一并关掉，别留一个看不见的 true。
        onChanged: (id) => form.update(
          (o) => o.copyWith(
            asrProviderId: id,
            asrModel: null,
            diarize:
                o.diarize &&
                (Registry.asrInfo(id)?.supportsDiarization ?? false),
          ),
        ),
      ),
    );
    final model = modelField(
      info: info,
      model: o.asrModel,
      settings: form.settings,
      onChanged: (m) => form.update((o) => o.copyWith(asrModel: m)),
    );
    final status = ReadinessLine(
      readiness: readiness,
      needsApiKey: info?.needsApiKey ?? true,
      onOpenSettings: onOpenSettings,
    );
    // 只有支持的服务才有这个开关；不支持的连灰掉的都不给，免得用户去找原因。
    final diarize = info != null && info.supportsDiarization
        ? _DiarizeToggle(form: form)
        : null;

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
            '识别',
            style: context.texts.titleSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          twoColumn(language, service, gap: gap),
          model,
          ?diarize,
          status,
        ],
      );
    }

    return FormSection(
      title: '识别',
      children: [
        twoColumn(language, service),
        const SizedBox(height: AppSpacing.s3),
        twoColumn(
          model,
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
        if (diarize != null) ...[
          const SizedBox(height: AppSpacing.s3),
          diarize,
        ],
        const SizedBox(height: AppSpacing.s2),
        status,
      ],
    );
  }
}

/// 说话人分离开关：开关 + 一句说明。样子照「转写完成后继续翻译」那一行。
class _DiarizeToggle extends StatelessWidget {
  const _DiarizeToggle({required this.form});

  final TranscribeFormController form;

  @override
  Widget build(BuildContext context) {
    final on = form.options.diarize;
    final cs = context.colors;
    return Tappable(
      onTap: () => form.update((o) => o.copyWith(diarize: !on)),
      child: Row(
        children: [
          AppSwitch(
            value: on,
            onChanged: (v) => form.update((o) => o.copyWith(diarize: v)),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('说话人分离', style: context.texts.titleSmall),
                const SizedBox(height: 1),
                Text(
                  on
                      ? '按说话人切开字幕并标上「说话人1：」；多人会议、访谈适用。'
                            '带 -filetrans 的模型整段处理，编号全程一致；qwen3-asr-flash 不支持。'
                      : '区分多位说话人，给每条字幕标上说话人编号',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「翻译」段：开关 + 展开后的目标语言、服务、模型、每批条数、术语与风格。
class TranscribeTranslateSection extends StatelessWidget {
  const TranscribeTranslateSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranscribeFormController form;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final on = o.translate;
    final info = Registry.translationInfo(o.translationProviderId);
    final gap = flat ? AppSpacing.s3 : AppSpacing.s4;

    final toggle = Tappable(
      onTap: () => form.update((o) => o.copyWith(translate: !on)),
      child: Row(
        children: [
          AppSwitch(
            value: on,
            onChanged: (v) => form.update((o) => o.copyWith(translate: v)),
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
    );
    final target = LabeledField(
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
    );
    final service = LabeledField(
      label: '翻译服务',
      child: AppDropdown<String>(
        value: o.translationProviderId,
        error: form.translationReadiness.isBlocked,
        groups: providerGroups(
          Registry.translation,
          (id) => ProviderReadiness.translation(
            id,
            form.settings,
            model: id == o.translationProviderId ? o.translationModel : null,
          ),
        ),
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
      '条数越大越省接口调用，出错时重试的范围也越大',
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
      label: '术语与风格（可选）',
      child: MultilineField(
        value: o.translationGuidance,
        hint: '保持人名与产品名不译：Flutter、SenseVoice。口语化，句子尽量短。',
        onChanged: (v) => form.update(
          (o) => o.copyWith(translationGuidance: v),
          notify: false,
        ),
      ),
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          toggle,
          if (on) ...[
            twoColumn(target, service, gap: gap),
            twoColumn(
              model,
              LabeledField(label: '每批条数', child: batch),
              gap: gap,
            ),
            batchHint,
            guidance,
          ],
        ],
      );
    }

    return FormSection(
      gap: 14,
      children: [
        toggle,
        if (on) ...[
          Container(height: 1, color: cs.outlineVariant),
          twoColumn(target, service),
          twoColumn(
            model,
            LabeledField(
              label: '每批条数',
              child: Row(
                children: [
                  batch,
                  const SizedBox(width: AppSpacing.s2 + 2),
                  Expanded(child: batchHint),
                ],
              ),
            ),
          ),
          guidance,
        ],
      ],
    );
  }
}

/// 「高级」段：可折叠；识别提示词、每行字数、输出格式与位置。
class TranscribeAdvancedSection extends StatelessWidget {
  const TranscribeAdvancedSection({
    super.key,
    required this.form,
    this.flat = false,
  });

  final TranscribeFormController form;
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
                flat ? form.compactAdvancedSummary : form.advancedSummary,
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
    final prompt = LabeledField(
      label: '识别提示词（可选）',
      child: MultilineField(
        value: o.asrPrompt,
        minHeight: 56,
        hint: '列出专有名词，帮助识别固定写法。例：SenseVoice、字幕组、whisper-large-v3',
        onChanged: (v) =>
            form.update((o) => o.copyWith(asrPrompt: v), notify: false),
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
    final format = LabeledField(
      label: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedToggle<SubtitleFormat>(
            value: o.format,
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
            'ASS 需要一整套字幕样式配置，留到第二期。',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (flat) {
      return flatSection(
        context,
        gap: 14,
        children: [
          header,
          if (open) ...[
            prompt,
            lengths,
            format,
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
          prompt,
          lengths,
          format,
          LabeledField(
            label: '输出位置',
            child: Row(
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
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: GestureDetector(
                    onTap: form.pickOutputDir,
                    child: Text(
                      o.outputLocation == OutputLocation.custom
                          ? (o.outputDir ?? '点此选择目录…')
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
}

/// 页面版的「输出位置」：两个单选 + 命名规则说明。
/// 面板只有 400 宽，分段开关加路径挤不下，竖排的单选把路径放在自己那行。
class _OutputLocationRadios extends StatelessWidget {
  const _OutputLocationRadios({required this.form});

  final TranscribeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final custom = o.outputLocation == OutputLocation.custom;
    final sample =
        form.enqueueable.firstOrNull?.fileName ?? 'interview_ep12.mp4';
    final stem = sample.contains('.')
        ? sample.substring(0, sample.lastIndexOf('.'))
        : sample;
    final mono = kTimecodeStyle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: cs.onSurfaceVariant,
    );
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
              TextSpan(
                text: '$sample → $stem.${o.format.extension}',
                style: mono,
              ),
              const TextSpan(text: '，同名文件会被覆盖'),
            ],
          ),
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 页脚那行校验文案：图标 + 文字，阻断用 error 色。
class TranscribeFooterLine extends StatelessWidget {
  const TranscribeFooterLine({super.key, required this.form, this.line});

  final TranscribeFormController form;

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

/// 「开始转写」。页面上带数量，对话框不带 —— 对话框的文件区就在按钮上方。
class TranscribeStartButton extends StatelessWidget {
  const TranscribeStartButton({
    super.key,
    required this.form,
    required this.onStart,
    this.withCount = false,
  });

  final TranscribeFormController form;
  final VoidCallback onStart;
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final n = form.enqueueable.length;
    return PrimaryButton(
      label: withCount ? '开始转写 · $n' : '开始转写',
      icon: Symbols.mic,
      onPressed: form.canStart ? onStart : null,
    );
  }
}
