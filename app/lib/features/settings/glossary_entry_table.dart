import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../domain/glossary.dart';

/// 一份词表的条目表（设计稿 C-GlossarySection 右侧）：原文、译文两列，
/// 逐格编辑，表尾常驻一行用来新增，多行文本粘贴进来按行解析。
///
/// 表里可以有写到一半的行（原文空着、原文与前面重复）。这类行只留在界面上，
/// 标红说明原因，**不进 [onChanged]** —— 交出去的永远是一份收拾干净的条目，
/// 与存盘后读回来的那份相等。
class GlossaryEntryTable extends StatefulWidget {
  const GlossaryEntryTable({
    super.key,
    required this.entries,
    required this.onChanged,
  });

  final List<GlossaryEntry> entries;

  /// 只回传有效条目（原文非空、不重复），已去掉多余空白。
  final ValueChanged<List<GlossaryEntry>> onChanged;

  @override
  State<GlossaryEntryTable> createState() => _GlossaryEntryTableState();
}

/// 一行正在编辑的内容。
class _Draft {
  _Draft([GlossaryEntry entry = const GlossaryEntry(term: '')])
    : term = TextEditingController(text: entry.term),
      translation = TextEditingController(text: entry.translation);

  final TextEditingController term;
  final TextEditingController translation;
  final termFocus = FocusNode();
  final translationFocus = FocusNode();

  GlossaryEntry get entry =>
      GlossaryEntry(term: term.text, translation: translation.text);

  /// 去掉多余空白之后的原文，判断空与重复都看它。
  String get cleanTerm => entry.normalized().term;

  void dispose() {
    term.dispose();
    translation.dispose();
    termFocus.dispose();
    translationFocus.dispose();
  }
}

class _GlossaryEntryTableState extends State<GlossaryEntryTable> {
  /// 表体最多显示这么多行，再多就在表里滚。表头与新增行不跟着滚：
  /// 几百条的词表里，新增行不该被推到几屏之外。
  static const _visibleRows = 12;
  static const _rowHeight = 36.0;

  late List<_Draft> _rows = [for (final e in widget.entries) _Draft(e)];

  /// 表尾的新增行。回车或点加号才进表。
  final _fresh = _Draft();

  /// 上一次交出去的条目。外面传进来的与它不同，说明词表被别处改了
  /// （而不是自己那次改动绕了一圈回来），这时才按外面的重建各行。
  ///
  /// 在 [initState] 里赋值，不写成字段的初始化式：`late` 字段第一次被读
  /// 时才求值，那可能已经是 [didUpdateWidget] 里了，读到的是新的 widget，
  /// 外面的第一次改动就会被当成自己的回声吞掉。
  late List<GlossaryEntry> _emitted;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _emitted = widget.entries;
  }

  @override
  void didUpdateWidget(GlossaryEntryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(widget.entries, _emitted)) return;
    for (final row in _rows) {
      row.dispose();
    }
    _rows = [for (final e in widget.entries) _Draft(e)];
    _emitted = widget.entries;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _fresh.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _emit() {
    final cleaned = GlossaryText.clean([for (final row in _rows) row.entry]);
    setState(() {});
    if (listEquals(cleaned, _emitted)) return;
    _emitted = cleaned;
    widget.onChanged(cleaned);
  }

  void _remove(_Draft row) {
    _rows.remove(row);
    _emit();
    // 等这一帧用完它的控制器再销毁。
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  void _append(Iterable<GlossaryEntry> entries) {
    _rows.addAll(entries.map(_Draft.new));
    _emit();
    _scrollToEnd();
  }

  /// 滚到表尾，让刚加的那几条看得见。
  ///
  /// 列表只量过看得见的那些行，总高度是估的，而且行数变了之后要等下一次
  /// 布局才更新：跳过去发现还没到底，就再跳一次。
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.offset == end) return;
      _scroll.jumpTo(end);
      _scrollToEnd();
    });
  }

  /// 把新增行里的内容加进表。原文空着时不加。
  void _addFresh() {
    if (_fresh.cleanTerm.isEmpty) return;
    final entry = _fresh.entry;
    _fresh.term.clear();
    _fresh.translation.clear();
    _append([entry]);
    // 连着录入是常事：焦点回到新增行的原文格。
    _fresh.termFocus.requestFocus();
  }

  /// 粘贴进来的多行文本：逐行解析后追加在末尾，已经有的原文跳过。
  void _pasteLines(String text) {
    final known = {for (final row in _rows) row.cleanTerm};
    _append(GlossaryText.parse(text).where((e) => !known.contains(e.term)));
  }

  /// 每一行的错误：原文空着，或与前面某行重复。
  List<String?> _errors() {
    final firstAt = <String, int>{};
    final errors = <String?>[];
    for (final (i, row) in _rows.indexed) {
      final term = row.cleanTerm;
      final first = firstAt[term];
      if (term.isEmpty) {
        errors.add('原文为空，这一条不会保存');
      } else if (first != null) {
        errors.add('「$term」已在第 ${first + 1} 行，重复的原文只保留第一条');
      } else {
        firstAt[term] = i;
        errors.add(null);
      }
    }
    return errors;
  }

  /// 回车：跳到下一行的同一列，最后一行跳到新增行。
  void _focusBelow(int index, {required bool translation}) {
    final next = index + 1 < _rows.length ? _rows[index + 1] : _fresh;
    (translation ? next.translationFocus : next.termFocus).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final errors = _errors();
    final line = BorderSide(color: cs.outlineVariant);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _PasteLines(
        onLines: _pasteLines,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(bottom: line),
              ),
              child: DefaultTextStyle.merge(
                style: context.texts.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                child: const Row(
                  children: [
                    Expanded(child: _HeaderCell('原文')),
                    Expanded(child: _HeaderCell('译文（可空）')),
                    SizedBox(width: 36),
                  ],
                ),
              ),
            ),
            if (_rows.isEmpty)
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(bottom: line)),
                child: Text(
                  '还没有条目。在下面一行输入，或把多行文本直接粘贴进来。',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _visibleRows * (_rowHeight + 1),
                ),
                // 按需建行：几百条的词表不该每敲一个字重建几百个输入框。
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    return _EntryRow(
                      key: ObjectKey(row),
                      draft: row,
                      error: errors[i],
                      onChanged: _emit,
                      onRemove: () => _remove(row),
                      onSubmit: (translation) =>
                          _focusBelow(i, translation: translation),
                    );
                  },
                ),
              ),
            _FreshRow(draft: _fresh, onAdd: _addFresh),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
    child: Text(label),
  );
}

/// 一条已有的条目：两个格子 + 行尾删除。出错的行下面多一句原因。
class _EntryRow extends StatefulWidget {
  const _EntryRow({
    super.key,
    required this.draft,
    required this.error,
    required this.onChanged,
    required this.onRemove,
    required this.onSubmit,
  });

  final _Draft draft;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// 在某一格里按了回车；参数是「是不是译文那一格」。
  final ValueChanged<bool> onSubmit;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final draft = widget.draft;
    final error = widget.error;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _hovered ? cs.onSurface.withValues(alpha: 0.06) : null,
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        // 给行底那条线让出 1px，别让它压在格子上。
        child: Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Cell(
                      controller: draft.term,
                      focusNode: draft.termFocus,
                      hint: '原文',
                      error: error != null,
                      onChanged: widget.onChanged,
                      onSubmit: () => widget.onSubmit(false),
                    ),
                  ),
                  Expanded(
                    child: _Cell(
                      controller: draft.translation,
                      focusNode: draft.translationFocus,
                      hint: '留空则保留原文写法',
                      idleHint: '—',
                      divider: true,
                      onChanged: widget.onChanged,
                      onSubmit: () => widget.onSubmit(true),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Center(
                      // 出错的行删除按钮常显：它不会被保存，多半是要删掉的。
                      child: AnimatedOpacity(
                        opacity: _hovered || error != null ? 1 : 0,
                        duration: AppDuration.short,
                        // 不进 Tab 顺序：Tab 是在格子之间走的。
                        child: ExcludeFocus(
                          child: IconActionButton(
                            icon: Symbols.close,
                            tooltip: '删除这一条',
                            size: 28,
                            iconSize: 18,
                            onPressed: widget.onRemove,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.s3, 2, 12, 6),
                  child: InlineNote(
                    icon: Symbols.priority_high,
                    color: cs.error,
                    text: error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表尾常驻的新增行。
class _FreshRow extends StatelessWidget {
  const _FreshRow({required this.draft, required this.onAdd});

  final _Draft draft;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Cell(
          controller: draft.term,
          focusNode: draft.termFocus,
          hint: '原文',
          onSubmit: onAdd,
        ),
      ),
      Expanded(
        child: _Cell(
          controller: draft.translation,
          focusNode: draft.translationFocus,
          hint: '译文，留空则保留原文写法',
          divider: true,
          onSubmit: onAdd,
        ),
      ),
      SizedBox(
        width: 36,
        child: Center(
          child: ExcludeFocus(
            child: IconActionButton(
              icon: Symbols.add,
              tooltip: '添加这一条（Enter）',
              size: 28,
              iconSize: 18,
              color: context.colors.primary,
              onPressed: onAdd,
            ),
          ),
        ),
      ),
    ],
  );
}

/// 表里的一格：没有自己的描边，聚焦时 2px primary 内描边，出错时换成 error。
class _Cell extends StatefulWidget {
  const _Cell({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmit,
    this.idleHint,
    this.onChanged,
    this.divider = false,
    this.error = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// 聚焦时的占位。
  final String hint;

  /// 没聚焦时的占位；不给就与 [hint] 相同。
  final String? idleHint;
  final VoidCallback? onChanged;
  final VoidCallback onSubmit;

  /// 左边画一条竖线，把它与前一格隔开。
  final bool divider;
  final bool error;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_Cell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_refresh);
    widget.focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final focused = widget.focusNode.hasFocus;
    // 在这里取：右键菜单建在浮层里，它的 context 上面找不到表格。
    final lines = _PasteLines.of(context);
    final ring = widget.error
        ? cs.error
        : focused
        ? cs.primary
        : null;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      alignment: Alignment.centerLeft,
      // 内描边画在前景上，不挤占内容的位置。前景装饰任何时候都给一个
      // （哪怕是空的）：有与没有之间切换会让 Container 多包 / 少包一层，
      // 输入框跟着重建，刚拿到的焦点与输入法连接就断了。
      foregroundDecoration: BoxDecoration(
        border: ring != null
            ? Border.all(color: ring, width: 2)
            : widget.divider
            ? Border(left: BorderSide(color: cs.outlineVariant))
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: context.texts.bodyMedium,
        decoration: bareInputDecoration(
          context,
          hint: focused ? widget.hint : widget.idleHint ?? widget.hint,
        ),
        onChanged: widget.onChanged == null ? null : (_) => widget.onChanged!(),
        // 给了 onEditingComplete，回车就不会让这一格失焦后停在原地。
        onEditingComplete: widget.onSubmit,
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.buttonItems(
              anchors: state.contextMenuAnchors,
              buttonItems: [
                for (final item in state.contextMenuButtonItems)
                  // 右键菜单里的「粘贴」不经过快捷键那条路，单独接上。
                  item.type == ContextMenuButtonType.paste
                      ? item.copyWith(
                          onPressed: () {
                            ContextMenuController.removeAny();
                            void plain() =>
                                state.pasteText(SelectionChangedCause.toolbar);
                            lines == null ? plain() : lines.paste(plain);
                          },
                        )
                      : item,
              ],
            ),
      ),
    );
  }
}

/// 拦住表里各个格子的粘贴：剪贴板里是多行文本时整块交给 [onLines]，
/// 不写进当前格；单行照常粘贴。
///
/// 输入框是单行的，多行文本照常粘进去换行会被吃掉，几十条词挤成一格。
class _PasteLines extends StatefulWidget {
  const _PasteLines({required this.onLines, required this.child});

  final ValueChanged<String> onLines;
  final Widget child;

  static _PasteLinesState? of(BuildContext context) =>
      context.findAncestorStateOfType<_PasteLinesState>();

  @override
  State<_PasteLines> createState() => _PasteLinesState();
}

class _PasteLinesState extends State<_PasteLines> {
  static final _newline = RegExp(r'[\r\n]');

  /// 读剪贴板：多行交给表格，否则走 [fallback]（输入框自己的粘贴）。
  Future<void> paste(VoidCallback? fallback) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    // 末尾带一个换行的单行（从表格里复制一格常见）不算多行。
    if (_newline.hasMatch(text.trim())) {
      widget.onLines(text);
    } else {
      fallback?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {PasteTextIntent: _PasteAction(paste)},
    child: widget.child,
  );
}

/// 盖过输入框自带的粘贴动作。输入框的动作是可覆盖的：快捷键先找到它，
/// 它再往上找到这里，[callingAction] 就是它自己，单行时交回去照常粘贴。
///
/// 没有用 `ShortcutAction`：要交回去就得拿到 [callingAction]，那是
/// [Action] 自己的成员，回调里拿不到。它也不用守「组字时让出按键」那条：
/// 粘贴不是输入法要用的键，组字时多行文本照样该按行进表。
class _PasteAction extends Action<PasteTextIntent> {
  _PasteAction(this.paste);

  final Future<void> Function(VoidCallback? fallback) paste;

  @override
  Object? invoke(PasteTextIntent intent) {
    // 读剪贴板是异步的，回来时 callingAction 已经清掉了，先留一份。
    final original = callingAction;
    paste(original == null ? null : () => original.invoke(intent));
    return null;
  }
}
