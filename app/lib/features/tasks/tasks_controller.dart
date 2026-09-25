import 'package:flutter/foundation.dart';

import '../../domain/media_kinds.dart';
import '../../domain/task.dart';
import '../../domain/task_filter.dart';
import '../../pipeline/task_queue.dart';

/// 拖进任务页的一把文件该交给哪个对话框。
enum DropRoute { none, transcribe, translate }

/// 任务页的筛选与选中。
///
/// 挂在根节点上，和各页的表单控制器一样：装配层按分区换页面、不保活，
/// 状态放在页面 State 里的话，去编辑器看一眼再回来，选中与筛选就全没了。
class TasksController extends ChangeNotifier {
  TasksController({required this.queue});

  final TaskQueue queue;

  TaskFilter _filter = TaskFilter.all;
  TaskFilter get filter => _filter;

  String? _selectedId;
  String? get selectedId => _selectedId;

  /// 当前筛选下可见的任务，顺序同队列（新的在前）。
  List<SubtitleTask> get visible => queue.tasks.where(_filter.matches).toList();

  Map<TaskFilter, int> get counts => {
    for (final f in TaskFilter.values) f: queue.countWhere(f.matches),
  };

  void setFilter(TaskFilter value) {
    if (value == _filter) return;
    _filter = value;
    notifyListeners();
  }

  /// 点同一行再点一次是收起详情面板。
  void toggleSelect(String id) {
    _selectedId = _selectedId == id ? null : id;
    notifyListeners();
  }

  /// 刚入队的任务在队列最前面，建完任务直接把它的详情亮出来。
  void selectNewest() {
    final newest = queue.tasks.firstOrNull;
    if (newest == null || newest.id == _selectedId) return;
    _selectedId = newest.id;
    notifyListeners();
  }

  /// 任务被删掉后别留着一个指向空处的选中。
  void forget(String id) {
    if (_selectedId != id) return;
    _selectedId = null;
    notifyListeners();
  }

  /// 拖进来的文件：音视频走「新建转写」，字幕走「新建翻译」。
  ///
  /// 两类混在一起时走文件多的那一边（一样多算字幕），整把原样转过去：
  /// 另一类由对话框自己列出并说明被忽略了。在这里就地丢掉的话，
  /// 用户只会觉得文件没拖进去。
  static DropRoute routeDrop(List<String> paths) {
    final subtitles = paths.where(MediaKinds.isSubtitle).length;
    final media = paths.where(MediaKinds.isMedia).length;
    if (subtitles == 0 && media == 0) return DropRoute.none;
    return subtitles >= media ? DropRoute.translate : DropRoute.transcribe;
  }
}
