import '../../services/readiness.dart';

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

/// 一切就绪时那句：「将创建 N 个…任务」，附注用分号接在后面。三个建任务
/// 表单的这句必须逐字相同。
FooterMessage queuedFooter(
  int count,
  String kindLabel, [
  List<String> notes = const [],
]) {
  final lead = count == 1
      ? '将创建 1 个$kindLabel任务，加入队列后在任务页查看进度'
      : '将创建 $count 个$kindLabel任务，按列表顺序排队';
  return (text: [lead, ...notes].join('；'), tone: FooterTone.info);
}

/// 就绪检查里第一条阻断，说明与提示连成一句。都不阻断时为 null。
FooterMessage? blockedFooter(Iterable<Readiness> checks) {
  for (final r in checks) {
    if (r.isBlocked) {
      return (
        text: [r.message, r.hint].nonNulls.join('，'),
        tone: FooterTone.error,
      );
    }
  }
  return null;
}

/// 就绪检查里第一条提醒：中性色，照常可以开始。没有时为 null。
FooterMessage? advisoryFooter(Iterable<Readiness> checks) {
  for (final r in checks) {
    if (r.level == ReadinessLevel.advisory) {
      return (text: r.message, tone: FooterTone.info);
    }
  }
  return null;
}
