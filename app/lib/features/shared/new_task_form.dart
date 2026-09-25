import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../domain/paths.dart';
import '../../domain/task_options.dart';
import '../../services/settings.dart';
import 'footer_message.dart';

/// 建任务页文件列表里的一行：各页的行在此之上加自己的探测结果。
abstract class StagedPath {
  const StagedPath({required this.path});

  final String path;

  String get fileName => baseName(path);

  /// 所在目录，用于列表副信息。
  String get directory {
    final cut = path.length - fileName.length;
    return cut <= 0 ? '' : path.substring(0, cut);
  }
}

/// 三个建任务表单（转写 / 翻译 / 转码）共有的状态：参数、文件列表、拖放说明、
/// 高级区开合、输出位置与「上次参数」。
///
/// 各表单的差别在收什么文件、怎么探测、怎么校验；这些留给子类。参数的类型
/// 不同（[TaskOptions] 与转码参数），改输出位置时由子类接上各自的 copyWith。
abstract class NewTaskFormBase<TOptions, TFile extends StagedPath>
    extends ChangeNotifier {
  NewTaskFormBase({
    required this.settings,
    required TOptions initial,
    Future<String?> Function()? pickDirectory,
  }) : _options = initial,
       _pickDirectory = pickDirectory ?? getDirectoryPath;

  final AppSettings settings;

  /// 选目录的对话框。测试里换成假的：平台插件在单元测试里没有实现。
  final Future<String?> Function() _pickDirectory;

  TOptions _options;
  TOptions get options => _options;
  @protected
  set options(TOptions value) => _options = value;

  final _files = <TFile>[];
  List<TFile> get files => List.unmodifiable(_files);

  /// 子类增删行用的可写列表。
  @protected
  List<TFile> get stagedFiles => _files;

  /// 拖进来的东西被拒收时的说明。落下即清掉上一次的。
  String? _dropError;
  String? get dropError => _dropError;
  @protected
  set dropError(String? value) => _dropError = value;

  bool _advancedOpen = false;
  bool get advancedOpen => _advancedOpen;
  set advancedOpen(bool v) {
    if (_advancedOpen == v) return;
    _advancedOpen = v;
    notifyIfAlive();
  }

  /// 探测与选目录都是异步的，回来时表单可能已经随页面销毁。
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @protected
  void notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  // —— 子类接上的差异 ——————————————————————————————————————————

  /// 「恢复默认」用的参数。
  @protected
  TOptions get defaultOptions;

  /// 最近一次成功提交的参数；没有存档时为 null。
  @protected
  TOptions? get lastUsedOptions;

  @protected
  String? outputDirOf(TOptions o);

  /// 换输出位置；[dir] 为 null 时不动目录。
  @protected
  TOptions withOutput(TOptions o, OutputLocation location, {String? dir});

  /// 「浏览…」对话框里可选的文件类型。
  @protected
  XTypeGroup get browseTypes;

  /// 加一批路径：不收的与已在列表里的跳过，其余入列并探测。
  Future<void> add(List<String> paths);

  /// 落下一批路径：记下被拒的说明，收下其余。
  void handleDrop(List<String> paths);

  // —— 参数 ————————————————————————————————————————————————

  /// 改一项参数。多行输入框每个字符都会调，传 `notify: false` 省掉重建。
  void update(TOptions Function(TOptions) change, {bool notify = true}) {
    _options = change(_options);
    if (notify) notifyIfAlive();
  }

  /// 恢复为默认值，不动文件列表。
  void reset() {
    _options = defaultOptions;
    notifyIfAlive();
  }

  /// 把最近一次成功提交的参数整份填回。没有存档时返回 false，界面据此禁用按钮。
  bool applyLastUsed() {
    final last = lastUsedOptions;
    if (last == null) return false;
    _options = last;
    notifyIfAlive();
    return true;
  }

  bool get hasLastUsed => lastUsedOptions != null;

  /// 切换输出位置。选「指定目录」而还没有目录时先弹选择框，选了才切过去 ——
  /// 取消的话留在原来的位置，不会停在「指定目录」却没有目录（那样实际会写到
  /// 源文件旁边，摘要却说指定目录）。
  void chooseOutputLocation(OutputLocation location) {
    if (location == OutputLocation.custom &&
        (outputDirOf(_options)?.trim().isEmpty ?? true)) {
      pickOutputDir();
      return;
    }
    update((o) => withOutput(o, location));
  }

  Future<void> pickOutputDir() async {
    final dir = await _pickDirectory();
    if (dir == null || _disposed) return;
    _options = withOutput(_options, OutputLocation.custom, dir: dir);
    notifyIfAlive();
  }

  // —— 文件 ————————————————————————————————————————————————

  /// 把 [paths] 里还不在列表中的以占位行（探测中）先入列，用户不必等探测
  /// 跑完才看到文件出现。返回新入列的路径，交给子类去探测。
  @protected
  List<String> stageNew(
    Iterable<String> paths,
    TFile Function(String path) placeholder,
  ) {
    final known = _files.map((f) => f.path).toSet();
    final fresh = paths.where(known.add).toList();
    if (fresh.isEmpty) return fresh;
    _files.addAll(fresh.map(placeholder));
    notifyIfAlive();
    return fresh;
  }

  /// 探测结果回来，换掉同一路径的占位行。探测期间被移除或表单已销毁时丢弃。
  @protected
  void replaceStaged(TFile next) {
    if (_disposed) return;
    final i = _files.indexWhere((f) => f.path == next.path);
    if (i < 0) return;
    _files[i] = next;
    notifyIfAlive();
  }

  Future<void> browse() async {
    final picked = await openFiles(acceptedTypeGroups: [browseTypes]);
    if (picked.isNotEmpty) await add(picked.map((f) => f.path).toList());
  }

  /// 预填一批路径（任务页把整把拖放原样转过来）。可能混着别的页收的文件，
  /// 走拖放那条路才能说清楚它们去哪儿了。
  void seed(List<String> paths) {
    if (paths.isEmpty) return;
    handleDrop(paths);
  }

  void remove(TFile file) {
    _files.removeWhere((f) => f.path == file.path);
    notifyIfAlive();
  }

  void clear() {
    _files.clear();
    _dropError = null;
    notifyIfAlive();
  }

  void clearDropError() {
    if (_dropError == null) return;
    _dropError = null;
    notifyIfAlive();
  }

  /// 被拒收的说明压过其他页脚文案。
  @protected
  FooterMessage? get dropErrorFooter =>
      _dropError == null ? null : (text: _dropError!, tone: FooterTone.error);
}

/// 参数是 [TaskOptions] 的建任务表单（转写与翻译）：默认值取自设置页。
abstract class TaskOptionsFormBase<TFile extends StagedPath>
    extends NewTaskFormBase<TaskOptions, TFile> {
  TaskOptionsFormBase({
    required super.settings,
    TaskOptions? initial,
    super.pickDirectory,
  }) : super(initial: initial ?? settings.defaultTaskOptions());

  @override
  TaskOptions get defaultOptions => settings.defaultTaskOptions();

  @override
  String? outputDirOf(TaskOptions o) => o.outputDir;

  @override
  TaskOptions withOutput(
    TaskOptions o,
    OutputLocation location, {
    String? dir,
  }) => dir == null
      ? o.copyWith(outputLocation: location)
      : o.copyWith(outputLocation: location, outputDir: dir);
}
