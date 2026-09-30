import 'dart:convert';
import 'dart:io';

import '../domain/task.dart';
import '../domain/task_options.dart';
import 'file_io.dart';

/// 任务的持久化：每个任务一份 JSON，放在应用支持目录的 `tasks/` 下。
///
/// 一个任务一个文件而不是整个队列一个文件：进度回调很频繁，只重写变了的
/// 那一个任务；某一份存档坏了也只丢那一个任务。
class TaskStore {
  TaskStore(this.dir);

  final String dir;

  File _file(String id) => File('$dir${Platform.pathSeparator}$id.json');

  /// 原子写：写到一半进程被杀，旧存档还在，不会留下半截 JSON。
  Future<void> save(SubtitleTask task) async {
    await Directory(dir).create(recursive: true);
    await writeFileAtomically(_file(task.id).path, jsonEncode(task.toJson()));
  }

  Future<void> delete(String id) async {
    try {
      await _file(id).delete();
    } on FileSystemException {
      // 没存过或已经删了，都算删掉了。
    }
  }

  /// 读回全部任务，新的在前。读不了的存档跳过，不让一份坏文件拖垮启动。
  ///
  /// 旧版本写的存档（任务参数里没有模型声明）读回来之后交给 [onMigrated]，
  /// 由调用方写回：不写回的话，下次启动又会按那时的设置重新补一遍，
  /// 同一个任务两次启动之间可能换了模型。
  Future<List<SubtitleTask>> loadAll({
    required TaskOptions fallbackOptions,
    DefaultModels? defaultModels,
    void Function(SubtitleTask task)? onMigrated,
  }) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return [];
    final tasks = <SubtitleTask>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is! Map) continue;
        final task = SubtitleTask.fromJson(
          json.cast<String, Object?>(),
          fallbackOptions: fallbackOptions,
          defaultModels: defaultModels,
        );
        tasks.add(task);
        final options = json['options'];
        if (options is! Map ||
            TaskOptions.isLegacyJson(options.cast<String, Object?>())) {
          onMigrated?.call(task);
        }
      } on Object {
        continue;
      }
    }
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }
}
