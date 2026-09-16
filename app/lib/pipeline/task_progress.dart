/// 按已经完成条目的平均耗时外推剩余时间。
///
/// 字幕翻译按条目算，转码按已处理毫秒算；公式一致，不各写一份。
Duration? estimateRemaining(DateTime started, int done, int total) {
  if (done == 0) return null;
  final elapsed = DateTime.now().difference(started);
  final perItem = elapsed.inMilliseconds / done;
  return Duration(milliseconds: (perItem * (total - done)).round());
}
