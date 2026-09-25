/// 建任务页底部那行校验文案的性质。
///
/// 表单只说这行话是什么性质，图标与颜色由 [TaskFooterLine] 决定 —— 表单是
/// 界面状态的持有者，不该认识图标。
enum FooterTone {
  /// 还没加文件，提示去添加。
  add,
  info,

  /// 一切就绪（折叠摘要里用）。
  ok,
  warning,

  /// 拖入的东西被拒收：说明原因，但不阻断已有的列表。
  rejected,

  /// 阻断：禁用「开始」。
  error,
}

/// 页脚那行校验文案。
typedef FooterMessage = ({String text, FooterTone tone});

extension FooterMessageBlocking on FooterMessage {
  /// 阻断提交，文字用 error 色。
  bool get error => tone == FooterTone.error;
}
