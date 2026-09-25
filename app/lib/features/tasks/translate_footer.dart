import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/widgets/buttons.dart';
import 'translate_form.dart';

/// 「开始翻译」。页面上带数量，对话框不带 —— 对话框的文件区就在按钮上方。
class TranslateStartButton extends StatelessWidget {
  const TranslateStartButton({
    super.key,
    required this.form,
    required this.onStart,
    this.withCount = false,
  });

  final TranslateFormController form;
  final VoidCallback onStart;
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final n = form.enqueueable.length;
    return PrimaryButton(
      label: withCount ? '开始翻译 · $n' : '开始翻译',
      icon: Symbols.translate,
      onPressed: form.canStart ? onStart : null,
    );
  }
}
