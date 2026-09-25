import '../../domain/task_options.dart';

/// 建任务的表单确认后交出来的东西：一批文件 + 一份共用的参数。
///
/// 「新建转写」「新建翻译」两个 feature 各自产出它，任务页和装配层只认它、
/// 不认具体的表单，于是任务页不必 import 那两个 feature。
///
/// [paths] 已经剔掉注定失败的文件（解析不出内容的字幕、探测失败的媒体）——
/// 那些留在界面上是为了让用户知道自己拖了什么，但不该变成必然失败的任务。
class EnqueueRequest {
  const EnqueueRequest({required this.paths, required this.options});

  final List<String> paths;
  final TaskOptions options;
}
