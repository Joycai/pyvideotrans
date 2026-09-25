import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../services/provider_api.dart';
import '../../services/readiness.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import '../shared/provider_fields.dart';
import 'section_outline.dart';
import 'settings_section.dart';

/// 识别 / 翻译两种服务分区。
enum ProviderKind { asr, mt }

/// 一个服务分区（设计稿 C-ProviderSection）：选服务 + 地址 / 模型 / 密钥，
/// 识别多一行「识别提示」，翻译多「每批条数」与「翻译要求」。
///
/// 未配置时三处联动提醒：目录项红点（由页面画）、标题标签「未配置」、
/// 分区内一条 errorContainer 横幅说明后果；缺的那个输入框 2px error 描边。
class ProviderSection extends StatelessWidget {
  const ProviderSection({
    super.key,
    required this.kind,
    required this.settings,
    required this.onChanged,
    required this.keyVisible,
    required this.onToggleKeyVisible,
    this.stacked = false,
    this.saved = false,
  });

  final ProviderKind kind;
  final AppSettings settings;

  /// 任一字段写入后调用。[typed] 表示来自键入（页面会等停止输入再显示「已保存」）。
  final void Function({bool typed}) onChanged;

  final bool keyVisible;
  final VoidCallback onToggleKeyVisible;
  final bool stacked;
  final bool saved;

  bool get _isMt => kind == ProviderKind.mt;

  List<ProviderInfo> get _infos => _isMt ? Registry.translation : Registry.asr;

  String get _selectedId =>
      _isMt ? settings.translationProviderId : settings.asrProviderId;

  Readiness _check(String id) => _isMt
      ? ProviderReadiness.translation(id, settings)
      : ProviderReadiness.asr(id, settings);

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final info =
        _infos.where((i) => i.id == _selectedId).firstOrNull ?? _infos.first;
    final config = settings.configFor(info.id);
    final readiness = _check(info.id);
    final configured = settings.isConfigured(info);
    final endpoint = settings.endpointFor(info);
    final keyMissing = info.needsApiKey && endpoint.apiKey.isEmpty;

    final tag = !info.implemented
        ? const StatusTag(label: '第一期未实施', tone: TagTone.muted)
        : configured
        ? const StatusTag(
            label: '已配置',
            icon: Symbols.check_circle,
            tone: TagTone.success,
          )
        : const StatusTag(
            label: '未配置',
            icon: Symbols.error,
            tone: TagTone.error,
          );

    return SettingsSection(
      section: _isMt ? SettingsSectionKey.mt : SettingsSectionKey.asr,
      note: _isMt
          ? '字幕翻译。走 OpenAI 兼容的对话接口，本机服务与在线服务共用同一条链路。'
          : '音视频转字幕。改动立即生效，下一个任务开始时采用新配置。',
      tag: tag,
      saved: saved,
      children: [
        if (info.implemented && !configured)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s3),
            child: _WarningBanner(
              title: _isMt ? '翻译服务未配置完整，翻译任务无法启动' : '识别服务未配置完整，转写任务无法启动',
              body:
                  '${readiness.message}。填好后'
                  '${_isMt ? '「开始翻译」' : '「开始转写」'}'
                  '会自动恢复可用，已排队的任务不会丢失。',
            ),
          ),
        SettingsRow(
          label: '服务',
          note: _infos
              .where((i) => i.implemented)
              .map((i) => i.name)
              .join(' · '),
          stacked: stacked,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppDropdown<String>(
                value: info.id,
                groups: providerGroups(_infos, _check),
                leading: Icon(
                  info.runsLocally ? Symbols.computer : Symbols.cloud,
                  size: 18,
                  weight: 400,
                  color: cs.onSurfaceVariant,
                ),
                onChanged: (id) {
                  if (_isMt) {
                    settings.translationProviderId = id;
                  } else {
                    settings.asrProviderId = id;
                  }
                  onChanged();
                },
              ),
            ),
          ),
        ),
        SettingsRow(
          label: '服务地址',
          note: '填到 /v1 为止',
          stacked: stacked,
          child: SettingsTextField(
            key: ValueKey('${info.id}-url'),
            value: config.baseUrl ?? info.defaultBaseUrl ?? '',
            hint: 'https://…/v1',
            mono: true,
            error: info.implemented && endpoint.baseUrl.isEmpty,
            onChanged: (v) {
              settings.setConfig(info.id, config.copyWith(baseUrl: v));
              onChanged(typed: true);
            },
          ),
        ),
        SettingsRow(
          label: '模型',
          note: info.models.isEmpty
              ? '填写模型名；多个用逗号分隔，第一个为默认，新建时可选'
              : '多个用逗号分隔，第一个为默认，新建时可选。'
                    '常用：${info.models.join(' / ')}',
          stacked: stacked,
          child: SettingsTextField(
            key: ValueKey('${info.id}-model'),
            value: config.model ?? info.defaultModel ?? '',
            hint: '模型名',
            mono: true,
            error: info.implemented && endpoint.model.isEmpty,
            onChanged: (v) {
              settings.setConfig(info.id, config.copyWith(model: v));
              onChanged(typed: true);
            },
          ),
        ),
        if (info.needsApiKey)
          SettingsRow(
            label: 'API 密钥',
            stacked: stacked,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _KeyField(
                    key: ValueKey('${info.id}-key'),
                    value: config.apiKey ?? '',
                    visible: keyVisible,
                    missing: keyMissing,
                    onToggle: onToggleKeyVisible,
                    onChanged: (v) {
                      settings.setConfig(info.id, config.copyWith(apiKey: v));
                      onChanged(typed: true);
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.s1 + 2),
                InlineNote(
                  icon: keyMissing ? Symbols.priority_high : Symbols.info,
                  color: keyMissing ? cs.error : null,
                  text: keyMissing
                      ? '必填。目前以明文存在本机配置文件，请勿共享该文件。'
                      : '目前以明文存在本机配置文件，请勿共享该文件。',
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.s2 + 2, bottom: 2),
            child: InlineNote(text: '本机服务不需要密钥，已隐藏密钥一行。确认服务已在该地址监听即可。'),
          ),
        if (_isMt)
          SettingsRow(
            label: '每批条数',
            note: '一次请求送入的字幕条数，越大越省 token，越小越稳',
            stacked: stacked,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _BatchSlider(
                  value: settings.translationBatchSize,
                  onChanged: (v) {
                    settings.translationBatchSize = v;
                    onChanged();
                  },
                ),
              ),
            ),
          ),
        SettingsRow(
          label: _isMt ? '翻译要求' : '识别提示',
          note: _isMt ? '术语表、语气、人称。会作为系统提示随每批发送。' : '专有名词、人名、术语。帮助识别模型选对同音词。',
          stacked: stacked,
          child: MultilineField(
            key: ValueKey('${kind.name}-prompt'),
            value: _isMt ? settings.translationGuidance : settings.asrPrompt,
            minHeight: 76,
            hint: _isMt
                ? '例：保留英文专有名词原文；人称用「你」；口语化，短句优先。'
                : '例：术语：缓存穿透、布隆过滤器。人名：陈嘉行。',
            onChanged: (v) {
              if (_isMt) {
                settings.translationGuidance = v;
              } else {
                settings.asrPrompt = v;
              }
              onChanged(typed: true);
            },
          ),
        ),
      ],
    );
  }
}

/// 未配置横幅：errorContainer 底、error 图标、标题 + 一句后果与恢复条件。
/// 不弹窗、不抢焦点。
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3 + 2,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.error,
            size: 20,
            weight: 400,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.s2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.texts.titleSmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
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

/// 密钥输入：默认掩码，眼睛图标只切显示、不改存储；显示态用等宽字体便于逐字符核对。
/// 空着时描边换 2px error。
class _KeyField extends StatelessWidget {
  const _KeyField({
    super.key,
    required this.value,
    required this.visible,
    required this.missing,
    required this.onToggle,
    required this.onChanged,
  });

  final String value;
  final bool visible;
  final bool missing;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SingleLineField(
    value: value,
    hint: '未填写',
    obscure: !visible,
    style: visible
        ? AppTextStyles.timecode.copyWith(color: context.colors.onSurface)
        : null,
    error: missing,
    padding: const EdgeInsets.only(left: AppSpacing.s3, right: AppSpacing.s1),
    trailing: IconActionButton(
      icon: visible ? Symbols.visibility_off : Symbols.visibility,
      tooltip: visible ? '隐藏密钥' : '显示密钥',
      size: 28,
      iconSize: 18,
      onPressed: onToggle,
    ),
    onChanged: onChanged,
  );
}

/// 每批条数滑杆：4px 轨、primary 填充、20px 白色手柄；右侧当前值 + 「条 / 批」，
/// 下方标出 1 与 50 两端。
class _BatchSlider extends StatelessWidget {
  const _BatchSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  // 刻度按设计稿只到 50：设的是默认值，常用区间拉得开些好拖。个别任务要更大
  // 的批量，在建任务页里填（上限 TaskOptions.batchSizeRange）。
  static const min = 1;
  static const max = 50;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final muted = context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.surfaceContainerHighest,
                    thumbColor: cs.surfaceContainerLowest,
                    overlayColor: cs.primary.withValues(
                      alpha: AppStateLayer.focus,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    thumbShape: _ThumbShape(
                      fill: cs.surfaceContainerLowest,
                      border: cs.outlineVariant,
                      shadow: e.controlShadow,
                    ),
                    trackShape: const _FlatTrackShape(),
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    value: value.clamp(min, max).toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: max - min,
                    onChanged: (v) => onChanged(v.round()),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3 + 2),
              SizedBox(
                width: 26,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Timecode('$value'),
                ),
              ),
              const SizedBox(width: AppSpacing.s1 + 2),
              Text('条 / 批', style: muted),
            ],
          ),
        ),
        Padding(
          // 右侧留出数值与单位的宽度，让 1 / 50 对齐轨道两端。
          padding: const EdgeInsets.only(right: 66),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Timecode('$min', color: cs.onSurfaceVariant, fontSize: 12),
              Timecode('$max', color: cs.onSurfaceVariant, fontSize: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// 轨道贴满控件宽度、不留 M3 默认的左右内缩。
class _FlatTrackShape extends RoundedRectSliderTrackShape {
  const _FlatTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 4;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }
}

class _ThumbShape extends SliderComponentShape {
  const _ThumbShape({
    required this.fill,
    required this.border,
    required this.shadow,
  });

  final Color fill;
  final Color border;
  final List<BoxShadow> shadow;

  static const _radius = 10.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    for (final s in shadow) {
      canvas.drawCircle(
        center + s.offset,
        _radius + s.spreadRadius,
        Paint()
          ..color = s.color
          ..maskFilter = s.blurRadius == 0
              ? null
              : MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
    canvas.drawCircle(center, _radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      _radius - 0.5,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
}
