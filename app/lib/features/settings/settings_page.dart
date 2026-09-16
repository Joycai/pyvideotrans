import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/language.dart';
import '../../domain/task_options.dart';
import '../../services/local/local_backend.dart';
import '../../services/media.dart';
import '../../services/registry.dart';
import '../../services/reveal.dart';
import '../../services/settings.dart';
import '../shell/page_chrome.dart';
import 'provider_section.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 顶栏内容。副标题点明「自动保存」，右侧是「恢复默认」。
/// 放在这里而不是 main.dart，截图测试才能用同一份。
PageChrome settingsChrome({required VoidCallback onReset}) => PageChrome(
  title: '设置',
  subtitle: '改动即时生效，自动保存；识别与翻译各自独立配置',
  actions: [
    QuietButton(label: '恢复默认', icon: Symbols.restart_alt, onPressed: onReset),
  ],
);

/// 设置页（设计稿 M-SettingsPage）。
///
/// 内容面板左侧是 208px 的分区目录，右侧内容列限宽 880 靠左，八个分区
/// 竖排、间距 32。没有「保存 / 取消」：改动即写入，只在改动的分区标题
/// 右侧闪一下「已保存」。
///
/// 两个响应式断点（按窗口宽度，与设计稿一致；这里换算成面板宽）：
/// - 窄于 1180：目录折叠成面板顶部 48px 的横向 Tab；
/// - 窄于 1000：表单行的标签堆到控件上方。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.media});

  final AppSettings settings;

  /// 「环境」分区要显示 ffmpeg 找没找到。由外面传进来而不是自己 new 一个：
  /// 截图测试得能塞一份固定的，否则截图会随测试机装没装 ffmpeg 而变。
  final Media media;

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

/// 外壳占掉的宽度：12 外边距 ×2 + 72 Rail + 12 间隙。
const _kShellWidth = 108.0;

/// 目录折叠成 Tab 的面板宽度阈值（窗口 1180）。
const _kTabsBelow = 1180 - _kShellWidth;

/// 标签堆叠的面板宽度阈值（窗口 1000）。
const _kStackBelow = 1000 - _kShellWidth;

/// 跳转后分区标题距内容区顶部的留白。
const _kScrollMargin = 16.0;

class SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _sectionKeys = {
    for (final k in SettingsSectionKey.values) k: GlobalKey(),
  };

  SettingsSectionKey _active = SettingsSectionKey.appearance;

  /// 点击目录后的平滑滚动期间不跟着滚动位置改高亮，否则目录会先跳到
  /// 中间几个分区再落到目标上。
  bool _jumping = false;
  Timer? _spyTimer;

  SettingsSectionKey? _saved;
  Timer? _savedTimer;
  Timer? _typingTimer;

  bool _asrKeyVisible = false;
  bool _mtKeyVisible = false;

  AppSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    s.addListener(_refresh);
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_refresh);
      widget.settings.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _spyTimer?.cancel();
    _savedTimer?.cancel();
    _typingTimer?.cancel();
    s.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 当前高亮的分区（测试用）。
  @visibleForTesting
  SettingsSectionKey get active => _active;

  // ── 已保存反馈 ────────────────────────────────────────────────────────

  /// 某分区写入成功。下拉、分段、滑杆松手即显示；键入的要等停止输入 600ms。
  void _touch(SettingsSectionKey key, {bool typed = false}) {
    _typingTimer?.cancel();
    if (typed) {
      _typingTimer = Timer(const Duration(milliseconds: 600), () {
        showSaved(key);
      });
    } else {
      showSaved(key);
    }
  }

  /// 在该分区标题右侧显示「已保存」，2 秒后淡出。
  @visibleForTesting
  void showSaved(SettingsSectionKey key) {
    if (!mounted) return;
    _savedTimer?.cancel();
    setState(() => _saved = key);
    _savedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = null);
    });
  }

  // ── 目录：跳转与滚动高亮 ─────────────────────────────────────────────

  /// 各分区标题相对内容区顶部的位置。
  Map<SettingsSectionKey, double> _sectionTops() {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return const {};
    final tops = <SettingsSectionKey, double>{};
    for (final entry in _sectionKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      tops[entry.key] = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    }
    return tops;
  }

  /// 点击目录：平滑滚到该分区，标题贴到内容区顶部下方 16px。
  void jumpTo(SettingsSectionKey key) {
    final top = _sectionTops()[key];
    setState(() => _active = key);
    if (top == null || !_scroll.hasClients) return;
    final target = (_scroll.offset + top - _kScrollMargin).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _jumping = true;
    _scroll
        .animateTo(target, duration: AppDuration.long, curve: kEasingEmphasized)
        .whenComplete(() => _jumping = false);
  }

  /// 滚动停下 100ms 后再更新高亮，快速滚动时目录不会乱跳。
  void _onScroll() {
    if (_jumping) return;
    _spyTimer?.cancel();
    _spyTimer = Timer(AppDuration.short, _spy);
  }

  /// 「距内容区顶部最近且已越过顶部的分区」为当前项；都没越过就是第一个。
  void _spy() {
    if (!mounted) return;
    final tops = _sectionTops();
    if (tops.isEmpty) return;
    var current = SettingsSectionKey.values.first;
    for (final key in SettingsSectionKey.values) {
      final top = tops[key];
      if (top != null && top <= _kScrollMargin + AppSpacing.s2) current = key;
    }
    if (current != _active) setState(() => _active = current);
  }

  // ── 恢复默认 ──────────────────────────────────────────────────────────

  /// 顶栏「恢复默认」：确认对话框二次确认，可以只重置当前分区，也可以全部。
  Future<void> confirmReset() async {
    final group = _groupOf(_active);
    final choice = await showDialog<_ResetChoice>(
      context: context,
      builder: (context) =>
          _ResetDialog(current: _active, hasGroup: group != null),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _ResetChoice.current:
        if (group != null) s.reset(group);
      case _ResetChoice.all:
        s.resetAll();
    }
    showSaved(_active);
  }

  static SettingsGroup? _groupOf(SettingsSectionKey key) => switch (key) {
    SettingsSectionKey.appearance => SettingsGroup.appearance,
    SettingsSectionKey.asr => SettingsGroup.asr,
    SettingsSectionKey.mt => SettingsGroup.translation,
    SettingsSectionKey.lang => SettingsGroup.language,
    SettingsSectionKey.defaults => SettingsGroup.defaults,
    SettingsSectionKey.output => SettingsGroup.output,
    // 「环境」里没有可恢复的设置项：ffmpeg 放在哪是机器的事实，不是偏好。
    SettingsSectionKey.environment => null,
    SettingsSectionKey.local => null,
  };

  // ── 布局 ──────────────────────────────────────────────────────────────

  Set<SettingsSectionKey> get _warnKeys {
    final asr = Registry.asrInfo(s.asrProviderId);
    final mt = Registry.translationInfo(s.translationProviderId);
    return {
      if (asr != null && asr.implemented && !s.isConfigured(asr))
        SettingsSectionKey.asr,
      if (mt != null && mt.implemented && !s.isConfigured(mt))
        SettingsSectionKey.mt,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ContentPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final tabs = w < _kTabsBelow;
          final stacked = w < _kStackBelow;
          final outline = SectionOutline(
            mode: tabs ? OutlineMode.tabs : OutlineMode.rail,
            active: _active,
            warn: _warnKeys,
            onSelect: jumpTo,
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tabs) outline,
              Expanded(child: _content(stacked)),
            ],
          );
          if (tabs) return content;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 208, child: outline),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _content(bool stacked) {
    final padding = stacked
        ? const EdgeInsets.fromLTRB(24, 20, 24, 32)
        : const EdgeInsets.fromLTRB(32, 24, 32, 40);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        key: _viewportKey,
        controller: _scroll,
        padding: padding,
        child: Align(
          alignment: Alignment.topLeft,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, section) in _sections(stacked).indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.s8),
                    section,
                  ],
                  const SizedBox(height: AppSpacing.s6),
                  const _Footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _anchor(SettingsSectionKey key, Widget child) =>
      KeyedSubtree(key: _sectionKeys[key], child: child);

  List<Widget> _sections(bool stacked) => [
    _anchor(SettingsSectionKey.appearance, _appearance(stacked)),
    _anchor(
      SettingsSectionKey.asr,
      ProviderSection(
        kind: ProviderKind.asr,
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.asr,
        keyVisible: _asrKeyVisible,
        onToggleKeyVisible: () =>
            setState(() => _asrKeyVisible = !_asrKeyVisible),
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.asr, typed: typed),
      ),
    ),
    _anchor(
      SettingsSectionKey.mt,
      ProviderSection(
        kind: ProviderKind.mt,
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.mt,
        keyVisible: _mtKeyVisible,
        onToggleKeyVisible: () =>
            setState(() => _mtKeyVisible = !_mtKeyVisible),
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.mt, typed: typed),
      ),
    ),
    _anchor(SettingsSectionKey.lang, _language(stacked)),
    _anchor(SettingsSectionKey.defaults, _defaults(stacked)),
    _anchor(SettingsSectionKey.output, _output(stacked)),
    _anchor(
      SettingsSectionKey.environment,
      _EnvironmentSection(media: widget.media, stacked: stacked),
    ),
    _anchor(SettingsSectionKey.local, const _LocalBackendSection()),
  ];

  Widget _appearance(bool stacked) => SettingsSection(
    section: SettingsSectionKey.appearance,
    saved: _saved == SettingsSectionKey.appearance,
    children: [
      SettingsRow(
        label: '主题',
        note: '跟随系统时随桌面的浅色 / 深色设置切换',
        stacked: stacked,
        child: Align(
          alignment: Alignment.centerLeft,
          child: PillSegments<String>(
            segments: const [
              (value: 'system', label: '跟随系统', icon: Symbols.brightness_auto),
              (value: 'light', label: '浅色', icon: Symbols.light_mode),
              (value: 'dark', label: '深色', icon: Symbols.dark_mode),
            ],
            value: s.themeMode,
            onChanged: (v) {
              s.themeMode = v;
              _touch(SettingsSectionKey.appearance);
            },
          ),
        ),
      ),
    ],
  );

  Widget _language(bool stacked) => SettingsSection(
    section: SettingsSectionKey.lang,
    note: '识别与翻译共用这一组语言设置，新建任务时可以临时改。',
    saved: _saved == SettingsSectionKey.lang,
    children: [
      SettingsRow(
        label: '源语言',
        note: '音频里说的语言。auto 让识别模型自己判断。',
        stacked: stacked,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AppDropdown<String>(
              value: Languages.resolve(s.sourceLanguage).code,
              groups: [
                DropdownGroup(
                  entries: [
                    for (final l in Languages.source)
                      DropdownEntry(
                        value: l.code,
                        label: l.isAuto ? '自动检测（auto）' : '${l.name}（${l.code}）',
                      ),
                  ],
                ),
              ],
              onChanged: (code) {
                s.sourceLanguage = code;
                _touch(SettingsSectionKey.lang);
              },
            ),
          ),
        ),
      ),
      SettingsRow(
        label: '目标语言',
        note: '用自然语言写，会原样交给翻译模型',
        stacked: stacked,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: SettingsTextField(
              value: s.targetLanguage,
              hint: '例如「英文」「日文」「简体中文」',
              onChanged: (v) {
                s.targetLanguage = v;
                _touch(SettingsSectionKey.lang, typed: true);
              },
            ),
          ),
        ),
      ),
    ],
  );

  Widget _defaults(bool stacked) {
    final cs = context.colors;
    Widget lineLength(String label, Widget field) => SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.texts.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          field,
        ],
      ),
    );

    return SettingsSection(
      section: SettingsSectionKey.defaults,
      note: '新建转写 / 翻译时的初始参数。对话框里改动只作用于当次任务。',
      saved: _saved == SettingsSectionKey.defaults,
      children: [
        SettingsRow(
          label: '输出格式',
          note: 'srt 兼容性最好；ass 保留样式',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AppDropdown<SubtitleFormat>(
                value: s.outputFormat,
                menuWidth: 240,
                groups: [
                  DropdownGroup(
                    entries: [
                      for (final f in SubtitleFormat.values)
                        DropdownEntry(
                          value: f,
                          label: f.extension,
                          enabled: f.implemented,
                          description: f.implemented
                              ? f.label
                              : '${f.label} · 第二期实施',
                        ),
                    ],
                  ),
                ],
                onChanged: (f) {
                  s.outputFormat = f;
                  _touch(SettingsSectionKey.defaults);
                },
              ),
            ),
          ),
        ),
        SettingsRow(
          label: '双语排版',
          note: '翻译任务里原文与译文的上下关系',
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillSegments<BilingualLayout>(
              segments: const [
                (value: BilingualLayout.targetOnly, label: '单语', icon: null),
                (value: BilingualLayout.targetAbove, label: '译文在上', icon: null),
                (value: BilingualLayout.targetBelow, label: '原文在上', icon: null),
              ],
              value: s.bilingual,
              onChanged: (v) {
                s.bilingual = v;
                _touch(SettingsSectionKey.defaults);
              },
            ),
          ),
        ),
        SettingsRow(
          label: '单行字数',
          note: '超过就断行。按文字类型分开设，中日韩按字数、拉丁按字符数。',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            children: [
              lineLength(
                '中日韩',
                NumberField(
                  key: ValueKey('cjk-${s.cjkLineLength}'),
                  value: s.cjkLineLength,
                  min: 4,
                  max: 60,
                  width: 132,
                  onChanged: (v) {
                    if (v == s.cjkLineLength) return;
                    s.cjkLineLength = v;
                    _touch(SettingsSectionKey.defaults, typed: true);
                  },
                ),
              ),
              lineLength(
                '拉丁',
                NumberField(
                  key: ValueKey('latin-${s.latinLineLength}'),
                  value: s.latinLineLength,
                  min: 8,
                  max: 120,
                  width: 132,
                  onChanged: (v) {
                    if (v == s.latinLineLength) return;
                    s.latinLineLength = v;
                    _touch(SettingsSectionKey.defaults, typed: true);
                  },
                ),
              ),
            ],
          ),
        ),
        SettingsRow(
          label: '字幕时长',
          note: '识别后断句：短于下限且紧跟上一条的并进去，长于上限的按标点拆开。',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            children: [
              lineLength(
                '最短（毫秒）',
                NumberField(
                  key: ValueKey('min-cue-${s.minCueMs}'),
                  value: s.minCueMs,
                  min: 0,
                  max: 3000,
                  width: 132,
                  onChanged: (v) {
                    if (v == s.minCueMs) return;
                    s.minCueMs = v;
                    _touch(SettingsSectionKey.defaults, typed: true);
                  },
                ),
              ),
              lineLength(
                '最长（秒）',
                NumberField(
                  key: ValueKey('max-cue-${s.maxCueMs}'),
                  value: s.maxCueMs ~/ 1000,
                  min: 2,
                  max: 60,
                  width: 132,
                  onChanged: (v) {
                    if (v * 1000 == s.maxCueMs) return;
                    s.maxCueMs = v * 1000;
                    _touch(SettingsSectionKey.defaults, typed: true);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _output(bool stacked) {
    final cs = context.colors;
    final dir = s.outputDir;
    return SettingsSection(
      section: SettingsSectionKey.output,
      saved: _saved == SettingsSectionKey.output,
      children: [
        SettingsRow(
          label: '输出目录',
          note: '清除后字幕写回源文件所在目录',
          stacked: stacked,
          child: Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 200,
                  // 路径框吃掉一行里按钮以外的全部宽度；换行时退到 200。
                  maxWidth: stacked
                      ? double.infinity
                      : 880 - 180 - 24 - 84 - 64 - 16,
                ),
                child: ControlSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.folder,
                        size: 18,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          dir ?? '源文件所在目录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kTimecodeStyle.copyWith(
                            color: dir == null
                                ? cs.onSurfaceVariant
                                : cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ControlButton(
                label: '选择…',
                onPressed: () async {
                  final picked = await getDirectoryPath();
                  if (picked == null || !mounted) return;
                  s.outputDir = picked;
                  _touch(SettingsSectionKey.output);
                },
              ),
              QuietButton(
                label: '清除',
                onPressed: dir == null
                    ? null
                    : () {
                        s.outputDir = null;
                        _touch(SettingsSectionKey.output);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 环境：ffmpeg 现在在哪，找不到时怎么补上。
///
/// 这里刻意不做成「填一个路径」的设置项。投放目录是固定的已知位置，用户只要
/// 点开它、把可执行文件拖进去就行 —— Windows 用户的卡点从来不是「填路径」，
/// 而是不知道该把文件放哪、也不会配环境变量。少一层心智负担，也省掉路径填错
/// 之后的一堆状态。
class _EnvironmentSection extends StatefulWidget {
  const _EnvironmentSection({required this.media, required this.stacked});

  final Media media;
  final bool stacked;

  @override
  State<_EnvironmentSection> createState() => _EnvironmentSectionState();
}

class _EnvironmentSectionState extends State<_EnvironmentSection> {
  late String? _path = widget.media.ffmpegOrNull;

  /// 用户刚把文件放进去，得让上次的查找结果作废再查一遍。
  void _recheck() {
    widget.media.reset();
    setState(() => _path = widget.media.ffmpegOrNull);
  }

  Future<void> _openDropIn() async {
    final dir = await Media.ensureDropInDir();
    if (dir == null) return;
    await Reveal.openDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final found = _path != null;
    return SettingsSection(
      section: SettingsSectionKey.environment,
      note:
          '抽音与转码都要用 FFmpeg。没有的话，点「打开目录」把 '
          '${Media.dropInNames.join(' 和 ')} 放进去即可，不用配环境变量。',
      children: [
        SettingsRow(
          label: 'FFmpeg',
          note: found ? '已找到' : '未找到',
          stacked: widget.stacked,
          child: Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 200,
                  // 与「输出目录」同一套算法：路径框吃掉按钮以外的宽度。
                  maxWidth: widget.stacked
                      ? double.infinity
                      : 880 - 180 - 24 - 96 - 88 - 16,
                ),
                child: ControlSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        found ? Symbols.check_circle : Symbols.error,
                        size: 18,
                        weight: 400,
                        color: found ? cs.primary : cs.error,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          _path ?? '未找到，放进目录后点重新检测',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kTimecodeStyle.copyWith(
                            color: found ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ControlButton(
                label: '打开目录',
                icon: Symbols.folder_open,
                onPressed: _openDropIn,
              ),
              QuietButton(
                label: '重新检测',
                icon: Symbols.refresh,
                onPressed: _recheck,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 本地模型服务：第一期未实施，用一张说明卡讲清楚「同一条链路」。
class _LocalBackendSection extends StatelessWidget {
  const _LocalBackendSection();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = context.texts.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return SettingsSection(
      section: SettingsSectionKey.local,
      tag: const StatusTag(label: '第一期未实施', tone: TagTone.muted),
      children: [
        Container(
          margin: const EdgeInsets.only(top: AppSpacing.s3),
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('本地后端与在线 API 走同一条链路', style: context.texts.titleSmall),
              const SizedBox(height: AppSpacing.s2 + 2),
              Text.rich(
                TextSpan(
                  style: muted,
                  children: [
                    const TextSpan(text: '后续版本会在本机启动一个 OpenAI 兼容服务，默认地址 '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Timecode(
                        Registry.asrInfo(LocalBackend.asrProviderId)
                                ?.defaultBaseUrl ??
                            'http://127.0.0.1:8765/v1',
                      ),
                    ),
                    const TextSpan(
                      text:
                          '。届时在上面两个「服务」下拉里直接选「本地模型服务」，'
                          '服务地址、模型、提示词这几行的含义完全一致，不需要另学一套设置。',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s2 + 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2 + 2,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.info,
                      size: 18,
                      weight: 400,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        '现在就想在本机跑翻译：到「翻译服务」里选 Ollama 或 LM Studio，填本机地址，不需要密钥。',
                        style: context.texts.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 页脚：一句话说明自动保存。
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.cloud_done,
            size: 16,
            weight: 400,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              '改动即时生效并自动保存，没有「保存 / 取消」。密钥与其他设置一起存在本机配置里。',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ResetChoice { current, all }

/// 「恢复默认」的二次确认。沿用 20px 圆角的玻璃浮层。
class _ResetDialog extends StatelessWidget {
  const _ResetDialog({required this.current, required this.hasGroup});

  final SettingsSectionKey current;

  /// 当前分区有没有可重置的东西（「本地服务」没有）。
  final bool hasGroup;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return AlertDialog(
      title: const Text('恢复默认设置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          '全部恢复会清掉所有服务的地址、模型与 API 密钥，并把语言、'
          '任务默认值、输出目录、主题都退回初始值。已排队的任务不受影响。',
          style: context.texts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      actions: [
        QuietButton(label: '取消', onPressed: () => Navigator.pop(context)),
        if (hasGroup)
          ControlButton(
            label: '仅「${current.title}」',
            onPressed: () => Navigator.pop(context, _ResetChoice.current),
          ),
        ControlButton(
          label: '全部恢复',
          onPressed: () => Navigator.pop(context, _ResetChoice.all),
        ),
      ],
    );
  }
}
