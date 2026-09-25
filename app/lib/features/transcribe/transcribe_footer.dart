import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/widgets/buttons.dart';
import 'transcribe_form.dart';

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
