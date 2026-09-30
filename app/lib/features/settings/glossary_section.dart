import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/shortcuts/shortcut_action.dart';
import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/text_focus.dart';
import '../../domain/glossary.dart';
import '../../services/settings.dart';
import 'glossary_entry_table.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 「词表」分区（设计稿 C-GlossarySection）：左边是词表列表，右边是选中
/// 那份的条目表。
///
/// 专有名词以前只能写进「识别提示」「翻译要求」两段自由文本里，识别与
/// 翻译各写一遍，也没法按节目、按客户分开。词表是独立的一份数据：建任务
/// 时勾选要用的几份，入队那一刻展开成条目随任务冻结。
///
/// 它是用户数据，不是设置：「恢复默认」不动它。
class GlossarySection extends StatefulWidget {
  const GlossarySection({
    super.key,
    required this.settings,
    required this.onChanged,
    this.stacked = false,
    this.saved = false,
  });

  final AppSettings settings;

  /// 任一改动写入后调用。[typed] 表示来自键入。
  final void Function({bool typed}) onChanged;

  /// 窄窗口：词表列表从左侧一列变成上方一行可换行的筹码。
  final bool stacked;
  final bool saved;

  @override
  State<GlossarySection> createState() => _GlossarySectionState();
}

class _GlossarySectionState extends State<GlossarySection> {
  /// 正在看的那份。它被删掉（或还没选过）时落到列表第一份。
  String? _selectedId;

  /// 正在给选中的那份改名。
  bool _renaming = false;

  AppSettings get _settings => widget.settings;

  Glossary? get _current {
    final all = _settings.glossaries;
    return all.where((g) => g.id == _selectedId).firstOrNull ?? all.firstOrNull;
  }

  void _select(String id) => setState(() {
    _selectedId = id;
    _renaming = false;
  });

  /// 新建后直接进入改名：默认的「词表 N」多半不是用户想要的名字。
  void _create() {
    final glossary = _settings.addGlossary();
    setState(() {
      _selectedId = glossary.id;
      _renaming = true;
    });
    widget.onChanged();
  }

  /// 名字合法返回 null，否则返回一句原因。
  String? _nameError(Glossary glossary, String raw) {
    final name = raw.trim();
    if (name.isEmpty) return '名字不能为空';
    final taken = _settings.glossaries.any(
      (g) => g.id != glossary.id && g.name == name,
    );
    return taken ? '已经有一份叫「$name」的词表' : null;
  }

  /// 改一份词表：读设置里现在的那份，改完存回去。
  ///
  /// 不用 build 时拿到的那份算：改名失焦提交与紧跟着的一次点击可能落在
  /// 同一帧里，后一次拿旧的那份改，前一次的改动就被盖掉了。
  void _update(
    String id,
    Glossary Function(Glossary current) change, {
    bool typed = false,
  }) {
    final current = _settings.glossaries.where((g) => g.id == id).firstOrNull;
    if (current == null) return;
    _settings.setGlossary(change(current));
    widget.onChanged(typed: typed);
  }

  void _rename(Glossary glossary, String raw) {
    setState(() => _renaming = false);
    final name = raw.trim();
    if (name == glossary.name) return;
    _update(glossary.id, (g) => g.copyWith(name: name));
  }

  Future<void> _confirmRemove(Glossary glossary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: '删除「${glossary.name}」？',
        message: '里面的 ${glossary.entries.length} 条会一起删掉；已入队的任务不受影响。',
        leading: DialogTextAction(
          label: '删除',
          color: context.colors.error,
          onTap: () => Navigator.of(context).pop(true),
        ),
        actions: [
          ControlButton(
            label: '取消',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _settings.removeGlossary(glossary.id);
    setState(() {
      _selectedId = null;
      _renaming = false;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final glossaries = _settings.glossaries;
    final current = _current;
    return SettingsSection(
      section: SettingsSectionKey.glossary,
      note:
          '专有名词、人名、术语。识别与翻译共用，新建任务时勾选要用的几份；'
          '已入队的任务用的是入队那一刻的内容。',
      saved: widget.saved,
      children: [
        const SizedBox(height: AppSpacing.s3),
        if (current == null)
          _EmptyState(onCreate: _create)
        else if (widget.stacked) ...[
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final glossary in glossaries)
                FilterChipButton(
                  label: glossary.name,
                  count: glossary.entries.length,
                  selected: glossary.id == current.id,
                  onTap: () => _select(glossary.id),
                ),
              QuietButton(
                label: '新建',
                icon: Symbols.add,
                height: 32,
                onPressed: _create,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          _detail(current),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: _GlossaryList(
                  glossaries: glossaries,
                  selectedId: current.id,
                  onSelect: _select,
                  onCreate: _create,
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(child: _detail(current)),
            ],
          ),
      ],
    );
  }

  /// 选中那份词表：名字与操作一行，下面是条目表与说明。
  Widget _detail(Glossary glossary) {
    final cs = context.colors;
    final count = glossary.entries.length;
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    void toggleDefault() => _update(
      glossary.id,
      (g) => g.copyWith(enabledByDefault: !g.enabledByDefault),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          // 两组之间撑开；放不下时「默认启用」折到名字下一行。
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s1,
            children: [
              if (_renaming)
                _RenameField(
                  // 换一份词表改名时重建，输入框才会拿到另一份的名字。
                  key: ValueKey('rename-${glossary.id}'),
                  initial: glossary.name,
                  validate: (name) => _nameError(glossary, name),
                  onCommit: (name) => _rename(glossary, name),
                  onCancel: () => setState(() => _renaming = false),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        glossary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    IconActionButton(
                      icon: Symbols.edit,
                      tooltip: '重命名',
                      size: 28,
                      iconSize: 18,
                      onPressed: () => setState(() => _renaming = true),
                    ),
                    IconActionButton(
                      icon: Symbols.delete,
                      tooltip: '删除这份词表',
                      size: 28,
                      iconSize: 18,
                      onPressed: () => _confirmRemove(glossary),
                    ),
                  ],
                ),
              Tappable(
                onTap: toggleDefault,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('新建任务时默认启用', style: context.texts.bodyMedium),
                    const SizedBox(width: 10),
                    AppSwitch(
                      value: glossary.enabledByDefault,
                      onChanged: (_) => toggleDefault(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlossaryEntryTable(
          // 换一份词表时重建：写到一半没存的行不带到另一份里去。
          key: ValueKey(glossary.id),
          entries: glossary.entries,
          onChanged: (entries) => _update(
            glossary.id,
            (g) => g.copyWith(entries: entries),
            typed: true,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '多行粘贴会按「原文=译文」「原文→译文」「原文<Tab>译文」逐行解析，'
          '只有原文也可以。${count > 0 ? '共 $count 条。' : ''}',
          style: muted,
        ),
        const SizedBox(height: 2),
        // 有的识别模型只读提示词末尾的一小段（Whisper 约 224 个 token），
        // 各家上限不一，也没法在本地数 token，所以只提醒、不截断。
        Text(
          '识别时原文会拼进提示词。识别用的词不宜过多：有的模型只读提示词'
          '末尾的一小段，排在前面的会被忽略。',
          style: muted,
        ),
      ],
    );
  }
}

/// 还没有任何词表：说明它怎么用，给一个新建按钮。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return CustomPaint(
      painter: DashedBorder(color: cs.outline, radius: AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.dictionary,
              size: 32,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text('还没有词表', style: context.texts.titleSmall),
            const SizedBox(height: AppSpacing.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                '识别时，原文列会拼进上下文提示，帮模型选对同音词与专名写法。'
                '翻译时，有译文的按「原文 → 译文」交给模型，'
                '没写译文的要求保留原文写法。',
                textAlign: TextAlign.center,
                style: muted,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '词表可以有多份，新建任务时勾选要用的几份。',
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: AppSpacing.s4),
            ControlButton(
              label: '新建词表',
              icon: Symbols.add,
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}

/// 左侧的词表列表：名字、条数、默认启用的圆点。
class _GlossaryList extends StatelessWidget {
  const _GlossaryList({
    required this.glossaries,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
  });

  final List<Glossary> glossaries;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = cs.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.only(left: AppSpacing.s3, right: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${glossaries.length} 份词表',
                        style: context.texts.labelMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                    IconActionButton(
                      icon: Symbols.add,
                      tooltip: '新建词表',
                      size: 28,
                      iconSize: 18,
                      onPressed: onCreate,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, glossary) in glossaries.indexed) ...[
                      if (i > 0) const SizedBox(height: 2),
                      _GlossaryListItem(
                        glossary: glossary,
                        selected: glossary.id == selectedId,
                        onTap: () => onSelect(glossary.id),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              StatusDot(cs.primary, size: 6),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '新建任务时默认启用',
                  style: context.texts.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlossaryListItem extends StatelessWidget {
  const _GlossaryListItem({
    required this.glossary,
    required this.selected,
    required this.onTap,
  });

  final Glossary glossary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(8);
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
        focusColor: cs.onSurface.withValues(alpha: AppStateLayer.focus),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    glossary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (selected
                                ? context.texts.titleSmall
                                : context.texts.bodyMedium)
                            ?.copyWith(color: fg),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Timecode(
                  '${glossary.entries.length}',
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
                const SizedBox(width: AppSpacing.s2),
                // 没启用的留着空位，条数那一列才对得齐。
                if (glossary.enabledByDefault)
                  Tooltip(
                    message: '新建任务时默认启用',
                    waitDuration: const Duration(milliseconds: 400),
                    child: StatusDot(cs.primary, size: 6),
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 改名输入框：回车或失焦提交，Esc 放弃。名字不合法时描红并说明原因，
/// 回车不提交；这时失焦等于放弃。
class _RenameField extends StatefulWidget {
  const _RenameField({
    super.key,
    required this.initial,
    required this.validate,
    required this.onCommit,
    required this.onCancel,
  });

  final String initial;
  final String? Function(String name) validate;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();

  /// 已经提交或放弃。之后输入框被拆掉时还会失一次焦，不能再提交一遍。
  bool _done = false;

  static const _cancel = AppShortcut(LogicalKeyboardKey.escape);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // 切去别的应用时焦点也会被拿走，回来再还上：那不算离开这个框。
    if (_focus.hasFocus || appInBackground()) {
      setState(() {});
      return;
    }
    if (widget.validate(_controller.text) == null) {
      _finish(commit: true);
    } else {
      _finish(commit: false);
    }
  }

  void _finish({required bool commit}) {
    if (_done) return;
    _done = true;
    commit ? widget.onCommit(_controller.text) : widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final error = widget.validate(_controller.text);
    return Shortcuts(
      shortcuts: {_cancel.activator(): const _CancelIntent()},
      child: Actions(
        actions: {
          _CancelIntent: ShortcutAction<_CancelIntent>(
            (_) => _finish(commit: false),
          ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ControlSurface(
              width: 240,
              focused: _focus.hasFocus,
              error: error != null,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                style: context.texts.titleSmall,
                decoration: bareInputDecoration(context, hint: '词表名'),
                onChanged: (_) => setState(() {}),
                onEditingComplete: () {
                  if (error == null) _finish(commit: true);
                },
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.s1),
              InlineNote(
                icon: Symbols.priority_high,
                color: cs.error,
                text: error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
