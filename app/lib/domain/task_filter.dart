import 'task.dart';

/// 任务列表的状态分组。任务页的筛选 chip 与状态栏的「后台任务」数都按它算，
/// 两处各写一份的话，迟早有一边改了另一边没跟上，数字就对不上。
enum TaskFilter {
  all('全部'),

  /// 排队中也算进行中：用户关心的是「还没结束的」，不是此刻占着 GPU 的那一个。
  running('进行中'),

  /// 取消也算失败：两者都停在半路、保留了已完成阶段的结果，都等用户决定续跑。
  failed('失败'),
  done('已完成');

  const TaskFilter(this.label);

  final String label;

  /// 已暂停（上次退出时还没跑完）只出现在「全部」里。
  bool matches(SubtitleTask task) => switch (this) {
    all => true,
    running =>
      task.status == TaskStatus.running || task.status == TaskStatus.queued,
    failed =>
      task.status == TaskStatus.failed || task.status == TaskStatus.cancelled,
    done => task.status == TaskStatus.done,
  };
}
