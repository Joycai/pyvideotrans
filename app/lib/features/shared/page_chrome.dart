import 'package:flutter/material.dart';

/// 每个页面提供给顶栏的内容：标题、副标题、标题右侧的标签、右侧操作区。
class PageChrome {
  const PageChrome({
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final List<Widget> actions;
}
