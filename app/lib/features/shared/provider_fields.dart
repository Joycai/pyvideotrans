import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/text_focus.dart';
import '../../domain/providers/model_name.dart';
import '../../domain/providers/model_spec.dart';
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/settings.dart';

/// 跨页面共用的「选服务 / 填模型」零件。
///
/// 新建转写、新建翻译、转码页与设置页的服务下拉、模型字段、链接文字长得完全一样，
/// 各写一份必然会走形 —— 改了一边忘了另一边，用户就会看到两个本该相同的控件表现不一致。
/// 放在 features/shared/ 是因为它同时被 transcribe / translate / settings 几个 feature 用，
/// 不属于其中任何一个。整行可点、链接文字、单选行这类不带业务语义的零件在
/// core/widgets/form_layout.dart。

/// 服务下拉分两组：可用的在上，未实施的在下并说明原因。
///
/// 本机跑的服务标一个「本机」——「不花钱、不出网」是用户真正在意的区别。
List<DropdownGroup<String>> providerGroups(
  List<ProviderInfo> all,
  Readiness Function(String id) check,
) {
  DropdownEntry<String> entry(ProviderInfo info) {
    final readiness = check(info.id);
    return DropdownEntry(
      value: info.id,
      label: info.name,
      enabled: info.implemented,
      badge: info.runsLocally ? '本机' : null,
      badgeIcon: info.runsLocally ? Symbols.computer : null,
      description: info.implemented
          ? readiness.isBlocked
                ? readiness.message
                : (info.defaultBaseUrl ?? '').isEmpty
                ? '自行填写地址与模型名'
                : null
          : readiness.hint,
    );
  }

  final available = all.where((i) => i.implemented).map(entry).toList();
  final pending = all.where((i) => !i.implemented).map(entry).toList();
  return [
    DropdownGroup(title: pending.isEmpty ? null : '可用', entries: available),
    if (pending.isNotEmpty) DropdownGroup(title: '第二期未实施', entries: pending),
  ];
}

/// 模型选择。有候选的给下拉，没有候选的给输入框，不能换模型的灰掉并说明。
///
/// 候选是设置里这家服务的模型声明（[AppSettings.modelChoices]）；选中的是整份
/// 声明，不只是名字 —— 接入方式与参数跟着它一起进任务。
///
/// 只有一种接入方式的服务，下拉末尾有一项「其他模型…」：临时填一个名字，
/// 只用于这次任务。多接入方式的服务（百炼）不给 —— 光有名字不知道怎么接，
/// 得去设置里声明，菜单末尾给一句指路。
class ModelField<T extends ModelSpec> extends StatefulWidget {
  const ModelField({
    super.key,
    required this.info,
    required this.model,
    required this.settings,
    required this.onChanged,
    this.onOpenSettings,
  });

  /// 识别服务配识别模型、翻译服务配翻译模型：[info] 与 [T] 由调用方成对给。
  final ProviderInfo? info;
  final T model;
  final AppSettings settings;
  final ValueChanged<T> onChanged;

  /// 「在设置里添加」。为 null 时那句话是纯文字。
  final VoidCallback? onOpenSettings;

  @override
  State<ModelField<T>> createState() => _ModelFieldState<T>();
}

class _ModelFieldState<T extends ModelSpec> extends State<ModelField<T>> {
  /// 下拉里「其他模型…」那一项的值。模型名里不会有控制字符，撞不上。
  static const _other = '\u0000other';

  /// 正在手填一个列表外的模型。
  bool _typing = false;

  /// 手填时最近一次交出去的声明。外面的值与它不同，说明参数被别处换掉了
  /// （重置、上次参数、换服务），这时退出手填、按外面的来。
  T? _emitted;

  final _name = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 识别服务配识别模型、翻译服务配翻译模型。配错了要到用户点「其他
    // 模型…」才在强转上抛，这里先拦住。
    assert(
      widget.info == null || widget.info!.presets is List<T>,
      '${widget.info?.id} 的模型不是 $T',
    );
    _focus.addListener(_onFocusChanged);
    if (_candidates.isEmpty) _name.text = widget.model.name;
  }

  @override
  void didUpdateWidget(ModelField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external =
        oldWidget.info?.id != widget.info?.id || widget.model != _emitted;
    if (!external) return;
    _typing = false;
    _emitted = null;
    // 没有候选的服务一直是输入框：把外面的值同步进来。正在打字时不动，
    // 这时的变化是自己输入绕了一圈回来，覆盖回去会把光标甩到末尾。
    if (!_focus.hasFocus && _name.text.trim() != widget.model.name) {
      _name.text = _candidates.isEmpty ? widget.model.name : '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  List<T> get _candidates {
    final info = widget.info;
    if (info == null) return const [];
    // 按 T 取一遍：种类对不上的声明不会混进候选。
    return widget.settings.modelChoices(info).whereType<T>().toList();
  }

  /// 「还没选模型」的占位。手填的名字空着或不合法时交出它，就绪检查会
  /// 按「未选择模型」拦住，不让一个写坏的名字进任务。
  T get _unset => switch (widget.info!) {
    final AsrProviderInfo info => info.unsetModel as T,
    ChatProviderInfo() => ChatModelSpec.unset as T,
  };

  void _emit(T model) {
    _emitted = model;
    widget.onChanged(model);
  }

  /// 手填框里现在这个名字的错误；空着不算错。
  String? get _error {
    final name = ModelName.normalize(_name.text);
    return name.isEmpty ? null : ModelName.validate(name);
  }

  void _onTyped(String raw) {
    final name = ModelName.normalize(raw);
    final T next;
    if (name.isEmpty || ModelName.validate(name) != null) {
      next = _unset;
    } else {
      // 设置里有同名的就用那一份（带着用户调过的参数）。
      next =
          _candidates.where((m) => m.name == name).firstOrNull ??
          widget.info!.guess(name) as T;
    }
    setState(() {});
    _emit(next);
  }

  void _startTyping() {
    setState(() {
      _typing = true;
      _name.clear();
    });
    _emit(_unset);
    // 显式把焦点请过来，不靠 autofocus：建任务页与对话框的根节点一直
    // 占着焦点（SubmitShortcuts），同一作用域里后挂上的 autofocus 不生效。
    // 拿不到焦点的话，用户得再点一下才能打字，这时按 Esc 关掉的是整个
    // 对话框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _typing) _focus.requestFocus();
    });
  }

  /// 回到列表，选回这家服务的默认模型。
  void _backToList() {
    setState(() {
      _typing = false;
      _name.clear();
    });
    _emitted = null;
    widget.onChanged(widget.settings.defaultModel(widget.info!) as T);
  }

  void _onFocusChanged() {
    // 清空后离开：没有要填的了，回到列表。切去别的应用不算离开 ——
    // 多半是去复制模型名，回来还要接着填。
    final left = !_focus.hasFocus && !appInBackground();
    if (left && _typing && _name.text.trim().isEmpty) {
      _backToList();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    if (info == null || !info.implemented) {
      return LabeledField(
        label: '模型',
        enabled: false,
        child: AppDropdown<String>(
          value: '',
          enabled: false,
          display: '该服务暂不支持切换模型',
          groups: const [],
          onChanged: (_) {},
        ),
      );
    }
    final candidates = _candidates;
    // 没有候选可列（自定义接口、LM Studio），只能让用户自己写。
    if (candidates.isEmpty) return _typed(context, canGoBack: false);
    if (_typing) return _typed(context, canGoBack: true);

    final model = widget.model;
    final multi = info is AsrProviderInfo && info.multiTransport;
    // 「上次参数」或手填可能带来一个不在候选里的模型：照样列出来，排最前。
    final entries = [
      if (!candidates.any((m) => m.name == model.name)) model,
      ...candidates,
    ];
    return LabeledField(
      label: '模型',
      child: AppDropdown<String>(
        value: model.name,
        groups: [
          DropdownGroup(
            entries: [
              for (final m in entries)
                DropdownEntry(
                  value: m.name,
                  label: m.isUnset ? '未选择' : m.name,
                  badge: multi && m is AsrModelSpec ? m.transport.label : null,
                  description: _summary(m),
                ),
            ],
          ),
          if (!multi)
            const DropdownGroup(
              divided: true,
              entries: [
                DropdownEntry(
                  value: _other,
                  label: '其他模型…',
                  description: '手动填写模型名，只用于这次任务',
                ),
              ],
            ),
        ],
        footer: multi ? _settingsHint : null,
        onChanged: (name) => name == _other
            ? _startTyping()
            : widget.onChanged(entries.firstWhere((m) => m.name == name)),
      ),
    );
  }

  /// 菜单末尾那句「要用列表外的模型，在设置里添加」。
  Widget _settingsHint(BuildContext context, VoidCallback close) {
    final cs = context.colors;
    final style = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final open = widget.onOpenSettings;
    if (open == null) return Text('要用列表外的模型，在设置里添加', style: style);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('要用列表外的模型，', style: style),
        LinkText(
          label: '在设置里添加',
          color: cs.primary,
          onTap: () {
            close();
            open();
          },
        ),
      ],
    );
  }

  /// 手填的输入框。[canGoBack]：有列表可回（从「其他模型…」进来的）。
  Widget _typed(BuildContext context, {required bool canGoBack}) {
    final cs = context.colors;
    final error = _error;
    final example = widget.info!.presets.firstOrNull?.name ?? '';
    final field = TextField(
      controller: _name,
      focusNode: _focus,
      style: AppTextStyles.timecode.copyWith(color: cs.onSurface),
      decoration: bareInputDecoration(
        context,
        hint: canGoBack || example.isEmpty ? '填写模型名' : '填写模型名，例 $example',
      ),
      onChanged: _onTyped,
    );
    return LabeledField(
      label: '模型',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ControlSurface(
            focused: _focus.hasFocus,
            error: error != null,
            padding: EdgeInsets.only(
              left: AppSpacing.s3,
              right: canGoBack ? AppSpacing.s1 : AppSpacing.s3,
            ),
            child: Row(
              children: [
                Expanded(child: field),
                if (canGoBack)
                  IconActionButton(
                    icon: Symbols.close,
                    tooltip: '回到列表',
                    size: 28,
                    iconSize: 18,
                    onPressed: _backToList,
                  ),
              ],
            ),
          ),
          if (error != null || canGoBack) ...[
            const SizedBox(height: AppSpacing.s1 + 2),
            InlineNote(
              icon: error != null ? Symbols.priority_high : Symbols.info,
              color: error != null ? cs.error : null,
              text: error ?? '只用于这次任务，不会加进设置里的列表。清空后回到列表。',
            ),
          ],
        ],
      ),
    );
  }

  /// 下拉项第二行的能力摘要：「说话人分离 · 句级时间戳」。翻译模型没有。
  static String? _summary(ModelSpec model) {
    if (model is! AsrModelSpec || model.isUnset) return null;
    final caps = model.capabilities;
    return [
      if (caps.diarization) '说话人分离',
      if (caps.contextPrompt) '上下文提示',
      caps.timing,
    ].join(' · ');
  }
}

/// 服务就绪状态行：图标 + 一句话，阻断时 error 色并附「去设置」。
class ReadinessLine extends StatelessWidget {
  const ReadinessLine({
    super.key,
    required this.readiness,
    required this.needsApiKey,
    this.onOpenSettings,
  });

  final Readiness readiness;

  /// 就绪时用来区分「已配置密钥」与「无需密钥」两句。
  final bool needsApiKey;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
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
                ? needsApiKey
                      ? '已配置密钥，可直接开始'
                      : '无需密钥，可直接开始'
                : [
                    readiness.message,
                    if (!error) readiness.hint,
                  ].nonNulls.join('。'),
            style: context.texts.bodySmall?.copyWith(color: color),
          ),
        ),
        if (error && onOpenSettings != null) ...[
          const SizedBox(width: AppSpacing.s2),
          LinkText(label: '去设置', color: color, onTap: onOpenSettings!),
        ],
      ],
    );
  }
}

/// 服务下拉上显示的「服务 · 模型」。还没选模型时只有服务名。
String serviceLabel(ProviderInfo? info, ModelSpec model) {
  if (info == null) return '—';
  return model.isUnset ? info.name : '${info.name} · ${model.name}';
}
