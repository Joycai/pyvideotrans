import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/shortcuts/app_shortcut.dart';
import '../../core/shortcuts/shortcut_action.dart';
import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/providers/asr_transport.dart';
import '../../domain/providers/model_params.dart';
import '../../domain/providers/model_spec.dart';
import 'settings_section.dart';


/// 一家服务的模型列表编辑器（设计稿 C-ModelList），识别与翻译共用。
///
/// 模型以前是一串逗号分隔的文本：写错一个字符要等任务跑起来才知道，
/// 「这个模型怎么接」也没地方写。这里每个模型是一行声明，名字在添加的
/// 那一刻校验，接入方式与模型族由用户选定，参数展开就能调。
///
/// 列表本身由外面给，这里只管界面状态：展开的是哪一行、添加行里打了
/// 什么。**改动只在确认时回调**（点添加、点常用、数字框失焦），不逐键
/// 回调 —— 建任务表单按「模型还等于设置里的默认」判断要不要跟着设置走，
/// 逐键写设置会在打字途中把用户选的模型带走。
class ModelListEditor extends StatefulWidget {
  const ModelListEditor({
    super.key,
    required this.models,
    required this.presets,
    required this.nameHint,
    required this.validate,
    required this.onAdd,
    required this.onAddPreset,
    required this.onSetDefault,
    required this.onRemove,
    required this.onOptionChanged,
    this.transports = const [],
    this.suggest,
  });

  /// 用户配的模型，第一个是默认。
  final List<ModelSpec> models;

  /// 这家服务的常用模型；为空表示没有常用列表，只能自己填。
  final List<ModelSpec> presets;

  /// 添加行的占位文字。
  final String nameHint;

  /// 校验一个要添加的名字（已去首尾空白、非空）：合法返回 null，否则返回
  /// 一句可以直接显示的原因。
  final String? Function(String name) validate;

  /// 这家服务的模型可以怎么接。多于一种时，模型行显示声明标签，添加行
  /// 多出「接入方式」「模型族」两组分段；只有一种（或翻译服务，为空）时
  /// 界面上不出现任何接入方式的东西。
  final List<AsrTransport> transports;

  /// 按名字给出接入方式与模型族的建议，用来预填添加行的两组分段。
  final AsrModelSpec Function(String name)? suggest;

  /// 添加一个模型。[transport] 与 [dialect] 只在多接入方式的服务下给。
  final void Function(
    String name,
    AsrTransport? transport,
    DashScopeDialect? dialect,
  )
  onAdd;

  final ValueChanged<ModelSpec> onAddPreset;

  // 下面三个回调交出的是那一行的模型，不是下标：同一帧里前一次改动
  // 已经挪动了行的话，下标指的就不是用户点的那一行了。
  final ValueChanged<ModelSpec> onSetDefault;
  final ValueChanged<ModelSpec> onRemove;

  /// 改某一行的一项参数。[value] 为 null 表示「不发送」。
  final void Function(ModelSpec model, String key, Object? value)
  onOptionChanged;

  @override
  State<ModelListEditor> createState() => _ModelListEditorState();
}

class _ModelListEditorState extends State<ModelListEditor> {
  String? _expanded;

  @override
  void didUpdateWidget(ModelListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.models.any((m) => m.name == _expanded)) _expanded = null;
  }

  Future<void> _remove(ModelSpec model) async {
    final remaining = widget.models.where((m) => m.name != model.name).toList();
    final note = remaining.isEmpty
        ? (widget.presets.isEmpty ? '移除后需要添加模型才能使用此服务。' : '移除最后一项后，将恢复使用内置模型列表。')
        : widget.models.first.name == model.name
            ? '默认模型将改为 ${remaining.first.name}。' : '已入队的任务不受影响。';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => GlassDialog(
      title: '移除模型', message: model.name, note: note,
      actions: [
        ControlButton(label: '取消', onPressed: () => Navigator.pop(ctx, false)),
        ControlButton(label: '移除', onPressed: () => Navigator.pop(ctx, true)),
      ],
    ));
    if (confirmed == true && mounted) widget.onRemove(model);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('模型', style: context.texts.titleSmall),
          Text('管理新建任务可选的模型及默认参数。', style: context.texts.bodySmall),
        ])),
        ControlButton(
        label: '添加模型', icon: Symbols.add,
        onPressed: () => showDialog<void>(context: context,
          builder: (_) => _AddModelDialog(editor: widget)),
      )]),
      const SizedBox(height: AppSpacing.s2),
      ContentPanel(child: Material(color: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.models.isEmpty) _EmptyNote(hasPresets: widget.presets.isNotEmpty),
        for (final (i, model) in widget.models.indexed)
          _ModelRow(
            key: ValueKey(model.name), model: model, isDefault: i == 0,
            showDeclaration: widget.transports.length > 1,
            open: _expanded == model.name,
            onToggle: () => setState(() => _expanded = _expanded == model.name ? null : model.name),
            onSetDefault: i == 0 ? null : () => widget.onSetDefault(model),
            onRemove: () => _remove(model),
            onOptionChanged: (key, value) => widget.onOptionChanged(model, key, value),
          ),
      ]))),
    ],
  );
}

class _AddModelDialog extends StatefulWidget {
  const _AddModelDialog({required this.editor});
  final ModelListEditor editor;
  @override
  State<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<_AddModelDialog> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  late AsrTransport? _transport = widget.editor.transports.firstOrNull;
  DashScopeDialect _dialect = DashScopeDialect.qwen3Asr;

  /// 用户手动点过分段。点过之后不再按名字预填 —— 名字只是建议，
  /// 用户改过的选择不能被下一次键入冲掉。
  bool _touched = false;

  static const _clear = AppShortcut(LogicalKeyboardKey.escape);

  bool get _multi => widget.editor.transports.length > 1;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_refresh);
    _prefill('');
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  String get _trimmed => _name.text.trim();

  /// 添加行的错误。空着不算错，只是不能添加。
  String? get _error => _trimmed.isEmpty ? null : widget.editor.validate(_trimmed);

  void _prefill(String name) {
    final suggest = widget.editor.suggest;
    if (!_multi || _touched || suggest == null) return;
    final spec = suggest(name);
    _transport = spec.transport;
    _dialect = spec.dialect ?? _dialect;
  }

  void _onNameChanged(String _) => setState(() => _prefill(_trimmed));

  void _resetAddRow() {
    _name.clear();
    _touched = false;
    _prefill('');
  }

  void _submit() {
    final name = _trimmed;
    if (name.isEmpty || widget.editor.validate(name) != null) return;
    final preset = widget.editor.presets.where((m) => m.name == name).firstOrNull;
    if (preset != null && !_touched) {
      widget.editor.onAddPreset(preset);
      Navigator.pop(context);
      return;
    }
    final transport = _multi ? _transport : null;
    widget.editor.onAdd(
      name,
      transport,
      transport != null && transport.needsDialect ? _dialect : null,
    );
    Navigator.pop(context);
  }

  String _declarationLabel(AsrTransport transport) =>
      [transport.label, if (transport.needsDialect) _dialect.label].join(' · ');


  late bool _custom = widget.editor.presets.isEmpty;
  String _query = '';
  ModelSpec? _selected;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: SizedBox(width: 680, child: GlassPanel(strong: true, expand: false,
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Material(color: Colors.transparent, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('添加模型', style: context.texts.titleLarge),
          const SizedBox(height: AppSpacing.s3),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('内置模型'), selected: !_custom,
              onSelected: widget.editor.presets.isEmpty ? null : (_) => setState(() => _custom = false)),
            ChoiceChip(label: const Text('自定义模型'), selected: _custom,
              onSelected: (_) => setState(() => _custom = true)),
          ]),
          if (_custom) _addRow(context) else ...[
            TextField(decoration: const InputDecoration(hintText: '搜索名称或模型 ID'),
              onChanged: (v) => setState(() { _query = v.toLowerCase(); _selected = null; })),
            const SizedBox(height: AppSpacing.s2),
            if (!widget.editor.presets.any((m) => '${_modelTitle(m)} ${m.name}'.toLowerCase().contains(_query)))
              const Padding(padding: EdgeInsets.all(12), child: Text('未找到内置模型，可切换到自定义模型。')),
            for (final model in widget.editor.presets.where((m) =>
                '${_modelTitle(m)} ${m.name}'.toLowerCase().contains(_query)))
              ListTile(
                isThreeLine: true,
                title: Text(_modelTitle(model)),
                subtitle: Text('${model.name}\n${_modelSummary(model)}'),
                selected: _selected == model,
                trailing: widget.editor.models.any((m) => m.name == model.name)
                    ? const Text('已添加') : const Icon(Symbols.add),
                onTap: widget.editor.models.any((m) => m.name == model.name)
                    ? null : () => setState(() => _selected = model),
              ),
            Align(alignment: Alignment.centerRight, child: ControlButton(
              label: '添加所选模型', onPressed: _selected == null ? null : () {
                widget.editor.onAddPreset(_selected!);
                Navigator.pop(context);
              },
            )),
          ],
          Align(alignment: Alignment.centerRight, child: QuietButton(
            label: '取消', onPressed: () => Navigator.pop(context))),
        ],
      ))),
    )),
  );

  Widget _addRow(BuildContext context) {
    final cs = context.colors;
    final error = _error;
    final transport = _transport;
    final field = Shortcuts(
      shortcuts: {_clear.activator(): const _ClearIntent()},
      child: Actions(
        actions: {
          // 框里没东西时不拦 Esc：让它继续往外传，该关对话框的关对话框。
          _ClearIntent: ShortcutAction<_ClearIntent>(
            (_) => setState(_resetAddRow),
            enabled: (_) => _name.text.isNotEmpty,
          ),
        },
        child: ControlSurface(
          focused: _nameFocus.hasFocus,
          error: error != null,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          child: TextField(
            controller: _name,
            focusNode: _nameFocus,
            style: AppTextStyles.timecode.copyWith(color: cs.onSurface),
            decoration: bareInputDecoration(context, hint: widget.editor.nameHint),
            onChanged: _onNameChanged,
            // 给了 onEditingComplete，回车就不会让输入框失焦。
            onEditingComplete: _submit,
          ),
        ),
      ),
    );
    final add = ControlButton(
      label: '添加',
      icon: Symbols.add,
      onPressed: _trimmed.isEmpty || error != null ? null : _submit,
    );

    // 分段是按名字猜的时候说一声，免得用户以为那是定好的。
    final prefilled =
        error == null && !_touched && _trimmed.isNotEmpty && _multi;
    final hint = prefilled && transport != null
        ? '已按名字预填「${_declarationLabel(transport)}」，不对可以改'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_multi || transport == null)
            Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: AppSpacing.s2),
                add,
              ],
            )
          else ...[
            field,
            ExpansionTile(title: const Text('高级接入配置'), initiallyExpanded: true,
              children: [
                LabeledField(label: '接入方式', child: AppDropdown<AsrTransport>(
                  value: transport,
                  groups: [DropdownGroup(entries: [for (final t in widget.editor.transports)
                    DropdownEntry(value: t, label: t.label)])],
                  onChanged: (v) => setState(() { _transport = v; _touched = true; }),
                )),
                if (transport.needsDialect) LabeledField(label: '模型族', child: AppDropdown<DashScopeDialect>(
                  value: _dialect,
                  groups: [DropdownGroup(entries: [for (final d in DashScopeDialect.values)
                    DropdownEntry(value: d, label: d.label)])],
                  onChanged: (v) => setState(() { _dialect = v; _touched = true; }),
                )),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: add),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            InlineNote(
              icon: Symbols.priority_high,
              color: cs.error,
              text: error,
            ),
          ] else if (hint != null) ...[
            const SizedBox(height: 6),
            InlineNote(text: hint),
          ],
        ],
      ),
    );
  }
}

class _ClearIntent extends Intent {
  const _ClearIntent();
}

/// 列表为空时的一行说明。有常用列表的服务空着也能用（新建任务时从常用里
/// 选）；没有的（自定义接口）必须至少填一个，按出错的样子提醒。
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.hasPresets});

  final bool hasPresets;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = hasPresets ? cs.onSurfaceVariant : cs.error;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            hasPresets ? Symbols.info : Symbols.priority_high,
            size: 16,
            weight: 400,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasPresets ? '未添加模型，新建任务时使用常用列表' : '至少添加一个模型',
              style: context.texts.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个模型：名字、声明标签、能力、「默认」标记、行尾操作；展开后下面是
/// 参数面板。
class _ModelRow extends StatefulWidget {
  const _ModelRow({
    super.key,
    required this.model,
    required this.isDefault,
    required this.showDeclaration,
    required this.open,
    required this.onToggle,
    required this.onSetDefault,
    required this.onRemove,
    required this.onOptionChanged,
  });

  final ModelSpec model;
  final bool isDefault;

  /// 显示接入方式与模型族两个标签（只在多接入方式的服务下）。
  final bool showDeclaration;
  final bool open;
  final VoidCallback onToggle;

  /// 第一行已经是默认，为 null。
  final VoidCallback? onSetDefault;
  final VoidCallback onRemove;
  final void Function(String key, Object? value) onOptionChanged;

  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final model = widget.model;
    final asr = model is AsrModelSpec ? model : null;
    final head = Padding(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8, runSpacing: 8, children: [
          Text(_modelTitle(model), style: context.texts.titleSmall),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.isDefault) const _DefaultMark(),
            const SizedBox(width: 8),
            ControlButton(label: widget.open ? '收起' : '配置', dense: true, onPressed: widget.onToggle),
            PopupMenuButton<String>(tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'default') widget.onSetDefault?.call();
                if (value == 'remove') widget.onRemove();
                if (value == 'copy') Clipboard.setData(ClipboardData(text: model.name));
              },
              itemBuilder: (_) => [
                if (widget.onSetDefault != null) const PopupMenuItem(value: 'default', child: Text('设为默认')),
                const PopupMenuItem(value: 'copy', child: Text('复制模型 ID')),
                const PopupMenuItem(value: 'remove', child: Text('移除模型')),
              ],
            ),
          ]),
        ]),
        const SizedBox(height: 4),
        SelectableText(model.name, style: AppTextStyles.timecode.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(_modelSummary(model), style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (widget.open && asr != null)
          ExpansionTile(title: const Text('接入信息'), children: [
            ListTile(title: Text(asr.transport.label), subtitle: Text(_transportNote(asr.transport))),
            if (asr.dialect != null) ListTile(title: Text(asr.dialect!.label)),
          ]),
      ]),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          AnimatedSize(
            duration: AppDuration.medium,
            curve: AppEasing.standard,
            alignment: Alignment.topCenter,
            child: widget.open
                ? _ParamPanel(model: model, onChanged: widget.onOptionChanged)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static String _transportNote(AsrTransport transport) => switch (transport) {
    AsrTransport.dashscopeMessage => '通过流式连接发送文件音频，返回句级时间戳',
    AsrTransport.openaiTranscription => 'OpenAI 转写接口：整文件上传，分段时间戳',
    AsrTransport.dashscopeSync => '同步接口：本地按静音切片后逐段识别，时间码来自切片边界',
    AsrTransport.dashscopeFileTrans => '录音文件转写：整文件上传后异步转写，句级时间戳',
  };
}

class _DefaultMark extends StatelessWidget {
  const _DefaultMark();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Tooltip(
      message: '列表第一个是默认模型',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            '默认',
            style: context.texts.labelSmall?.copyWith(
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个模型的参数面板：照参数目录逐项出控件。加一个参数只要目录加一行，
/// 这里不用改。
class _ParamPanel extends StatelessWidget {
  const _ParamPanel({required this.model, required this.onChanged});

  final ModelSpec model;
  final void Function(String key, Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final params = model.params;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        38,
        AppSpacing.s3,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final param in params) ...[
            switch (param) {
              BoolModelParam() => _BoolParam(
                param: param,
                value: model.options.flag(param),
                onChanged: (v) => onChanged(param.key, v),
              ),
              NumberModelParam() => _NumberParam(
                param: param,
                value: model.options.number(param),
                onChanged: (v) => onChanged(param.key, v),
              ),
              ChoiceModelParam() => _ParamRow(
                param: param,
                control: PillSegments<String>(
                  value: model.options.choice(param),
                  segments: [
                    for (final (value, label) in param.options)
                      (value: value, label: label, icon: null),
                  ],
                  onChanged: (v) => onChanged(param.key, v),
                ),
              ),
            },
            const SizedBox(height: AppSpacing.s3),
          ],
          InlineNote(
            text: params.isEmpty ? '该模型没有可调参数' : '参数随任务入队时定下，改动只影响之后新建的任务。',
          ),
        ],
      ),
    );
  }
}

/// 参数的标签与说明。
class _ParamLabel extends StatelessWidget {
  const _ParamLabel({required this.param});

  final ModelParam param;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(param.label, style: context.texts.titleSmall),
      if (param.hint case final hint?) ...[
        const SizedBox(height: 1),
        Text(
          hint,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

/// 左边标签与说明、右边控件的一行。
class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.param, required this.control});

  final ModelParam param;
  final Widget control;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _ParamLabel(param: param)),
      const SizedBox(width: AppSpacing.s4),
      control,
    ],
  );
}

class _BoolParam extends StatelessWidget {
  const _BoolParam({
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final BoolModelParam param;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        AppSwitch(value: value, onChanged: onChanged),
        const SizedBox(width: AppSpacing.s3),
        Expanded(child: _ParamLabel(param: param)),
      ],
    ),
  );
}

class _NumberParam extends StatelessWidget {
  const _NumberParam({
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final NumberModelParam param;

  /// null = 不发送。
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final value = this.value;
    final off = value == null;
    return _ParamRow(
      param: param,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DecimalField(param: param, value: value, onCommit: onChanged),
          if (param.optional) ...[
            const SizedBox(width: AppSpacing.s3),
            Tappable(
              // 取消「不发送」要有个数可填：目录有默认值就用它，没有
              // （默认就是不发送的那种）从下限起。
              onTap: () =>
                  onChanged(off ? param.defaultNumber ?? param.min : null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: off ? cs.primary : null,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: off
                          ? null
                          : Border.all(color: cs.outline, width: 2),
                    ),
                    child: off
                        ? Icon(
                            Symbols.check,
                            size: 14,
                            weight: 400,
                            color: cs.onPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text('不发送', style: context.texts.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 小数输入框。失焦或回车时才把值交出去：打到一半的「0.」不是一个数，
/// 越界的值也要等打完才知道该夹到哪。
class _DecimalField extends StatefulWidget {
  const _DecimalField({
    required this.param,
    required this.value,
    required this.onCommit,
  });

  final NumberModelParam param;

  /// null = 不发送，框置灰显示「—」。
  final double? value;
  final ValueChanged<double?> onCommit;

  @override
  State<_DecimalField> createState() => _DecimalFieldState();
}

class _DecimalFieldState extends State<_DecimalField> {
  late final _controller = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(double? value) =>
      value == null ? '' : value.toStringAsFixed(widget.param.fractionDigits);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_DecimalField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
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
    if (!_focus.hasFocus) _commit();
    setState(() {});
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text);
    // 打的不是数（空的、只有一个点）就回到原来的值。
    final next = parsed == null
        ? widget.value
        : widget.param.sanitize(parsed) as double?;
    _controller.text = _format(next);
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final digits = widget.param.fractionDigits;
    if (widget.value == null) {
      return ControlSurface(
        width: 88,
        enabled: false,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        child: Text(
          '—',
          style: AppTextStyles.timecode.copyWith(
            color: cs.onSurface.withValues(
              alpha: AppStateLayer.disabledContent,
            ),
          ),
        ),
      );
    }
    return ControlSurface(
      width: 88,
      focused: _focus.hasFocus,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(digits == 0 ? r'^\d*' : '^\\d*\\.?\\d{0,$digits}'),
          ),
        ],
        style: AppTextStyles.timecode.copyWith(color: cs.onSurface),
        decoration: bareInputDecoration(context),
        onEditingComplete: _commit,
      ),
    );
  }
}

// 展示名称只做精确映射，不参与运行时协议选择。
String _modelTitle(ModelSpec model) => const {
  'qwen-audio-3.1-asr-flash-filetrans': 'Qwen Audio 3.1 · 整文件转写',
  'qwen-audio-3.1-asr-flash-message': 'Qwen Audio 3.1 · 流式文件转写',
  'qwen-audio-3.0-asr-flash': 'Qwen Audio 3.0 · 逐段识别',
  'qwen-audio-3.0-asr-flash-filetrans': 'Qwen Audio 3.0 · 整文件转写',
  'qwen3-asr-flash': 'Qwen3 ASR · 逐段识别',
  'qwen3-asr-flash-filetrans': 'Qwen3 ASR · 整文件转写',
}[model.name] ?? model.name;

String _modelSummary(ModelSpec model) {
  if (model is! AsrModelSpec) return '字幕翻译';
  return [model.transport.label,
    if (model.capabilities.contextPrompt) '上下文提示',
    if (model.transport == AsrTransport.dashscopeMessage ||
        model.transport == AsrTransport.dashscopeFileTrans && model.dialect == DashScopeDialect.qwenAudio3) '即时热词',
    if (model.capabilities.diarization) '说话人分离',
    if (model.languages != null) '语种：${model.languages!.join('、')}',
  ].join(' · ');
}
