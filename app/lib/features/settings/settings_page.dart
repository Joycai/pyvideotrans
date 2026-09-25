import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../services/media.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import '../shared/page_chrome.dart';
import 'appearance_section.dart';
import 'defaults_section.dart';
import 'environment_section.dart';
import 'language_section.dart';
import 'local_backend_section.dart';
import 'output_section.dart';
import 'provider_section.dart';
import 'section_outline.dart';
import 'settings_footer.dart';
import 'settings_reset_dialog.dart';

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
    final choice = await showDialog<ResetChoice>(
      context: context,
      builder: (context) =>
          SettingsResetDialog(current: _active, hasGroup: group != null),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case ResetChoice.current:
        if (group != null) {
          s.reset(group, providerIds: _providerIds(group));
        }
      case ResetChoice.all:
        s.resetAll(
          asrProviderIds: Registry.asr.map((p) => p.id),
          translationProviderIds: Registry.translation.map((p) => p.id),
        );
    }
    showSaved(_active);
  }

  static Iterable<String> _providerIds(SettingsGroup group) => switch (group) {
    SettingsGroup.asr => Registry.asr.map((p) => p.id),
    SettingsGroup.translation => Registry.translation.map((p) => p.id),
    _ => const [],
  };

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
                  const SettingsFooter(),
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
    _anchor(SettingsSectionKey.appearance, AppearanceSection(
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.appearance,
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.appearance, typed: typed),
      )),
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
    _anchor(SettingsSectionKey.lang, LanguageSection(
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.lang,
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.lang, typed: typed),
      )),
    _anchor(SettingsSectionKey.defaults, DefaultsSection(
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.defaults,
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.defaults, typed: typed),
      )),
    _anchor(SettingsSectionKey.output, OutputSection(
        settings: s,
        stacked: stacked,
        saved: _saved == SettingsSectionKey.output,
        onChanged: ({bool typed = false}) =>
            _touch(SettingsSectionKey.output, typed: typed),
      )),
    _anchor(
      SettingsSectionKey.environment,
      EnvironmentSection(media: widget.media, stacked: stacked),
    ),
    _anchor(SettingsSectionKey.local, const LocalBackendSection()),
  ];

}
