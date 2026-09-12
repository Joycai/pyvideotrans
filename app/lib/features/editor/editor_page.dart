import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../domain/srt.dart';
import '../../services/provider_api.dart';
import 'cue_table.dart';
import 'editor_controller.dart';
import 'inspector.dart';

/// 编辑器页：字幕表 + 检视面板。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.controller});

  final EditorController controller;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  final _focus = FocusNode();

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    // 进页面就接管键盘，J/K 不用先点一下列表才生效。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// provider 的报错本来就带 hint，直接原样展示给用户。
  String _describe(Object error) => error is ProviderException
      ? [error.message, if (error.hint != null) error.hint!].join(' · ')
      : '$error';

  Future<void> retranslate(int index) async {
    try {
      await controller.retranslate(index);
    } catch (e) {
      _report(_describe(e));
    }
  }

  Future<void> translateMissing() async {
    try {
      final n = await controller.translateMissing();
      _report(n == 0 ? '没有未翻译的条目' : '已翻译 $n 条');
    } catch (e) {
      _report(_describe(e));
    }
  }

  Future<void> export() async {
    try {
      final written = await controller.export({
        SrtField.source,
        if (controller.document.untranslatedCount <
            controller.document.cues.length)
          SrtField.translation,
      });
      _report(
        written.isEmpty ? '没有可导出的内容' : '已导出 ${written.length} 个文件到源文件目录',
      );
    } catch (e) {
      _report('导出失败：${_describe(e)}');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 输入框获得焦点时不抢 J/K，否则打不了字。
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != _focus && primary.context != null) {
      final isTextField =
          primary.context!.widget.runtimeType.toString().contains('EditableText');
      if (isTextField) return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.arrowDown:
        controller.step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyK:
      case LogicalKeyboardKey.arrowUp:
        controller.step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        controller.toggleReviewed();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyZ
          when HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed:
        controller.undo();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: CueTable(controller: controller)),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: 440,
            child: Inspector(
              controller: controller,
              onRetranslate: retranslate,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏右侧：视图切换 + 翻译未译 + 导出。
class EditorPageActions extends StatelessWidget {
  const EditorPageActions({
    super.key,
    required this.controller,
    required this.onTranslateMissing,
    required this.onExport,
  });

  final EditorController controller;
  final VoidCallback onTranslateMissing;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final missing = controller.document.untranslatedCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedToggle<CueView>(
          value: controller.view,
          onChanged: controller.setView,
          segments: const [
            (value: CueView.source, label: '原文'),
            (value: CueView.translation, label: '译文'),
            (value: CueView.both, label: '双语'),
          ],
        ),
        const SizedBox(width: AppSpacing.s3),
        ControlButton(
          label: missing == 0 ? '全部已翻译' : '翻译未译 $missing 条',
          icon: Symbols.translate,
          onPressed: missing == 0 ? null : onTranslateMissing,
        ),
        const SizedBox(width: AppSpacing.s3),
        PrimaryButton(
          label: '导出',
          icon: Symbols.download,
          onPressed: controller.document.cues.isEmpty ? null : onExport,
        ),
      ],
    );
  }
}

/// 顶栏标题右侧的「待校对 N」。
class EditorReviewBadge extends StatelessWidget {
  const EditorReviewBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = context.colors;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.flag,
            size: 16,
            weight: 400,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '待校对 $count',
            style: context.texts.labelMedium?.copyWith(
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
