import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/cue.dart';
import '../../domain/file_stamp.dart';
import '../../domain/language.dart';
import '../../domain/line_wrap.dart';
import '../../domain/output_naming.dart';
import '../../domain/srt.dart';
import '../../domain/task_options.dart';
import '../../services/editor_store.dart';
import '../../services/file_io.dart';
import '../../services/provider_api.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';
import 'editor_session.dart';

/// 原文 / 译文 / 双语。
enum CueView { source, translation, both }

/// 列表过滤。
enum CueFilter {
  all('全部'),
  review('待校对'),
  untranslated('未翻译'),
  unpaired('未配对'),

  /// 与上次写进字幕文件的版本不一样的条目。
  edited('本次修改');

  const CueFilter(this.label);

  final String label;
}

/// 字幕文件与编辑器里的文档对得上吗。顶栏 chip、保存按钮、状态栏都按它显示。
enum SyncState {
  /// 字幕文件就是编辑器里这一版。
  synced,

  /// 有修改还没写进字幕文件。
  dirty,

  /// 正在写。
  writing,

  /// 刚写完，停留 2 秒后回到 [synced]。
  written,

  /// 上次写入失败；继续编辑也保持，直到下一次写成功。
  failed,

  /// 保存前发现字幕文件在别处被改过，等用户决定。
  conflict,

  /// 任务没跑完，还没写过产物。
  noOutput,
}

/// 保存前发现字幕文件在外部被改过。界面接住它，问用户覆盖还是另存。
class WriteConflict implements Exception {
  const WriteConflict(this.changes);

  final List<FileChange> changes;

  @override
  String toString() => '${changes.map((c) => c.path).join('、')} 在别处被改过';
}

/// 另存为 / 导出的目标不能用（原目录、有同名文件）。不算写入失败，
/// 同步状态不变，界面直接把原因告诉用户。
class TargetRejected implements Exception {
  const TargetRejected(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 名单上的一位说话人，带上界面要显示的统计。
class SpeakerSummary {
  const SpeakerSummary({
    required this.id,
    required this.name,
    required this.named,
    required this.cueCount,
    required this.durationMs,
  });

  final int id;

  /// 显示名：起过名字的用名字，否则「说话人N」。
  final String name;

  /// 用户（或导入的标签）起过名字。
  final bool named;

  final int cueCount;
  final int durationMs;
}

/// 编辑器的状态与操作。文档是不可变的，每次改动换一份新的 —— 撤销栈因此
/// 只需要存快照，不用记反向操作。
///
/// 保存分两层：编辑进度每次改动都自动存（任务会话由上层随任务 JSON 写盘，
/// 本地会话在这里攒 300ms 写草稿）；字幕文件只在 [save] 时写。
class EditorController extends ChangeNotifier {
  /// [saved] 是上次写进字幕文件的版本。不给时：没有未写入修改的会话就是
  /// 打开时的文档；有的话（任务重开）就不知道了，「撤销到上次写入」不可用。
  ///
  /// [recoveredAt] 不为空表示本地会话接着上次没写回文件的编辑进度打开，
  /// 界面据此显示恢复横幅。
  EditorController({
    required this.session,
    required this.settings,
    this.store,
    SubtitleDocument? saved,
    this.recoveredAt,
    DateTime Function()? clock,
    Listenable? follow,
    this.translator,
  }) : _saved = saved ?? (session.pendingEdits == 0 ? session.document : null),
       _clock = clock ?? DateTime.now,
       _follow = follow {
    _baseline = _saved ?? session.document;
    _seen = session.document;
    _wasLocked = locked;
    _phase = session.phase;
    if (recoveredAt != null) recoveredEdits = session.pendingEdits;
    follow?.addListener(_sourceChanged);
  }

  final EditorSession session;
  final AppSettings settings;

  /// 本地会话的附加状态与编辑进度写在这里；为空就不写。
  final EditorStore? store;

  final DateTime Function() _clock;

  /// 测试用：替换按设置建出来的翻译服务。
  @visibleForTesting
  final TranslationProvider Function()? translator;

  /// 文档可能在编辑器以外被改的来源（任务队列）；它一通知就看看文档换没换。
  final Listenable? _follow;

  /// 编辑器最后一次看到的文档，用来分辨文档是不是被别处换掉了。
  late SubtitleDocument _seen;
  late bool _wasLocked;
  Object? _phase;

  /// 本地会话打开时恢复了上次没写回文件的修改：草稿存下的时间。
  final DateTime? recoveredAt;

  /// 恢复的草稿之后，字幕文件又被别的程序改过。横幅要说明，保存时会问。
  bool recoveredOverChanged = false;

  /// 本地会话另存为后挂到了新文件上；上层据此更新「最近打开」。
  VoidCallback? onRemount;

  bool _disposed = false;

  /// 恢复了几处修改。横幅关掉后归零。
  int recoveredEdits = 0;

  CueView view = CueView.both;
  CueFilter filter = CueFilter.all;
  String search = '';

  /// 说话人筛选，可多选。空集表示不按说话人筛；集合里的 null 表示「无说话人」。
  Set<int?> speakerFilter = {};

  /// 当前选中条在**完整文档**里的下标。
  int selected = 0;

  /// 正在重新翻译的条目下标，用来在界面上禁用按钮。
  final Set<int> translating = {};

  final List<SubtitleDocument> _undo = [];
  static const _undoLimit = 50;

  /// 上次写进字幕文件的文档。文档不可变，比较引用就知道有没有改过。
  /// 不知道时为 null（见构造函数）。
  SubtitleDocument? _saved;

  /// 「本次修改」的比较基准：上次写入的版本，不知道就用打开时的。
  late SubtitleDocument _baseline;
  Set<String>? _baselineKeys;

  /// 连续编辑同一条同一字段时合并成一次修改：检视面板每敲一个字都会
  /// 提交一次，不合并的话「N 处修改」按字数涨、撤销也按字退。
  static const _coalesceWindow = Duration(seconds: 1);
  String? _coalesceKey;
  DateTime? _coalesceAt;

  bool _writing = false;
  String? _failure;
  List<FileChange> _conflicts = const [];
  List<String>? _justWritten;
  Timer? _writtenTimer;

  Timer? _draftTimer;
  bool _draftDirty = false;

  /// 编辑进度最后一次变化的时间；打开后没改过为 null。
  DateTime? progressAt;

  SubtitleDocument get document => session.document;

  /// 任务排队或运行中：流水线随时会整份换掉文档，编辑器这时的修改要么
  /// 被下一批译文盖掉，要么把流水线的结果盖掉，所以只看不改。
  bool get locked => session.busy;

  bool get canUndo => !locked && _undo.isNotEmpty;

  /// 还没写进字幕文件的修改数。
  int get unsavedEdits {
    if (identical(document, _saved)) return 0;
    final n = session.pendingEdits;
    // 撤销越过了上次写入的版本：文档与文件不一样了，至少算一处。
    return n < 1 ? (_saved == null ? 0 : 1) : n;
  }

  /// 能「撤销到上次写入」：知道上次写的是哪一版，且现在不一样。
  bool get canRevertToWritten =>
      !locked && _saved != null && unsavedEdits > 0;

  SyncState get sync {
    if (_writing) return SyncState.writing;
    if (_failure != null) return SyncState.failed;
    if (_conflicts.isNotEmpty) return SyncState.conflict;
    if (_justWritten != null) return SyncState.written;
    if (!session.hasOutputs) return SyncState.noOutput;
    return unsavedEdits > 0 ? SyncState.dirty : SyncState.synced;
  }

  /// 现在按「保存」有没有事可做：有修改、没生成过产物、上次失败或冲突了。
  /// 任务还在跑时不写：完成阶段会按最终的文档写出产物。
  bool get canWrite => !locked && switch (sync) {
    SyncState.dirty ||
    SyncState.noOutput ||
    SyncState.failed ||
    SyncState.conflict => true,
    SyncState.synced || SyncState.writing || SyncState.written => false,
  };

  /// 上次写入失败的原因。
  String? get failure => _failure;

  /// 保存前发现在外部被改过的文件。
  List<FileChange> get conflicts => _conflicts;

  /// 刚写完的文件（停留 2 秒）。
  List<String> get justWritten => _justWritten ?? const [];

  /// 这一条与上次写入的版本不一样。
  bool isEdited(Cue cue) => !_keys.contains(_cueKey(cue));

  Set<String> get _keys =>
      _baselineKeys ??= {for (final c in _baseline.cues) _cueKey(c)};

  /// 比较内容而不是对象：拆分合并会给后面每一条重新编号，按对象比就全成了
  /// 「改过」。
  static String _cueKey(Cue c) =>
      '${c.startMs}|${c.endMs}|${c.speaker}|${c.reviewed}|'
      '${c.source}|${c.translation}';

  void dismissRecovery() {
    recoveredEdits = 0;
    notifyListeners();
  }

  /// 文档里有没有任何译文。只挂了原文的会话没有，这时「未翻译」不算一种
  /// 状态，列表按有没有校对来显示。
  bool get hasTranslations => document.cues.any((c) => c.hasTranslation);

  /// 还没有译文、且有原文可翻的条数：「翻译未译 N 条」。
  int get missingTranslationCount => document.cues
      .where((c) => !c.hasTranslation && c.source.trim().isNotEmpty)
      .length;

  /// 界面上显示的状态。见 [displayStateOf]。
  CueState displayState(Cue cue) =>
      displayStateOf(cue, translated: hasTranslations);

  List<Cue> get visibleCues {
    final needle = search.trim().toLowerCase();
    final translated = hasTranslations;
    return document.cues.where((cue) {
      final state = displayStateOf(cue, translated: translated);
      final passesFilter = switch (filter) {
        CueFilter.all => true,
        CueFilter.review => state == CueState.review,
        CueFilter.untranslated => state == CueState.untranslated,
        CueFilter.unpaired => state == CueState.unpaired,
        CueFilter.edited => isEdited(cue),
      };
      if (!passesFilter) return false;
      if (speakerFilter.isNotEmpty && !speakerFilter.contains(cue.speaker)) {
        return false;
      }
      if (needle.isEmpty) return true;
      return cue.source.toLowerCase().contains(needle) ||
          (cue.translation ?? '').toLowerCase().contains(needle);
    }).toList();
  }

  Cue? get current => selected >= 0 && selected < document.cues.length
      ? document.cues[selected]
      : null;

  int countOf(CueFilter f) {
    if (f == CueFilter.all) return document.cues.length;
    if (f == CueFilter.edited) return document.cues.where(isEdited).length;
    final translated = hasTranslations;
    final want = switch (f) {
      CueFilter.review => CueState.review,
      CueFilter.untranslated => CueState.untranslated,
      _ => CueState.unpaired,
    };
    return document.cues
        .where((c) => displayStateOf(c, translated: translated) == want)
        .length;
  }

  /// 说话人名单，按编号排。
  List<SpeakerSummary> get speakers {
    final counts = <int, int>{};
    final durations = <int, int>{};
    for (final cue in document.cues) {
      final s = cue.speaker;
      if (s == null) continue;
      counts[s] = (counts[s] ?? 0) + 1;
      durations[s] = (durations[s] ?? 0) + cue.durationMs;
    }
    return [
      for (final id in document.speakerIds)
        SpeakerSummary(
          id: id,
          name: document.speakerName(id),
          named: document.speakers.containsKey(id),
          cueCount: counts[id] ?? 0,
          durationMs: durations[id] ?? 0,
        ),
    ];
  }

  /// 当前条所在的同一人连续段有几条，给「连续 N 条」用。
  int get currentRunLength {
    if (current == null) return 0;
    final run = document.speakerRun(selected);
    return run.end - run.start + 1;
  }

  void setView(CueView v) {
    view = v;
    notifyListeners();
  }

  void setFilter(CueFilter f) {
    filter = f;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void setSpeakerFilter(Set<int?> speakers) {
    speakerFilter = {...speakers};
    notifyListeners();
  }

  void toggleSpeakerFilter(int? speaker) {
    final next = {...speakerFilter};
    if (!next.remove(speaker)) next.add(speaker);
    speakerFilter = next;
    notifyListeners();
  }

  void select(int indexInDocument) {
    selected = document.cues.isEmpty
        ? 0
        : indexInDocument.clamp(0, document.cues.length - 1);
    notifyListeners();
  }

  /// J/K 在**当前可见列表**里移动，而不是整份文档 —— 过滤成「待校对」后
  /// 按 J 应该跳到下一条待校对，不是下一行。
  void step(int delta) {
    final visible = visibleCues;
    if (visible.isEmpty) return;
    final currentCue = current;
    var position = currentCue == null
        ? -1
        : visible.indexWhere((c) => c.index == currentCue.index);
    position = (position + delta).clamp(0, visible.length - 1);
    final target = visible[position];
    selected = document.cues.indexWhere((c) => c.index == target.index);
    notifyListeners();
  }

  void _push() {
    _undo.add(document);
    session.pendingEdits++;
    session.recordEdit();
    _coalesceKey = null;
    if (_undo.length > _undoLimit) _undo.removeAt(0);
  }

  /// 文档换了之后：记下编辑进度、排一次草稿写盘、通知界面。
  ///
  /// 「刚写入」让位给新的修改，否则写完 2 秒内再改、再按 ⌘S 会被当成
  /// 没事可做。写入失败的红色保留到下一次写成。
  void _changed() {
    _seen = document;
    progressAt = _clock();
    _justWritten = null;
    _writtenTimer?.cancel();
    _draftDirty = true;
    _scheduleDraft();
    notifyListeners();
  }

  /// 改文档的操作都走这里：先存快照再换新文档。没变化就什么都不做，
  /// 免得撤销栈里堆一份一模一样的快照。
  void _commit(SubtitleDocument next) {
    if (locked || identical(next, document)) return;
    _push();
    session.document = next;
    _changed();
  }

  /// 文字编辑：同一条同一字段 1 秒内的连续改动并进上一次提交。
  void _commitText(SubtitleDocument next, String key) {
    if (locked || identical(next, document)) return;
    final now = _clock();
    final last = _coalesceAt;
    if (_coalesceKey == key &&
        last != null &&
        now.difference(last) < _coalesceWindow &&
        _undo.isNotEmpty) {
      session.document = next;
      _coalesceAt = now;
      _changed();
      return;
    }
    _commit(next);
    _coalesceKey = key;
    _coalesceAt = now;
  }

  void undo() {
    if (!canUndo) return;
    session.document = _undo.removeLast();
    if (session.pendingEdits > 0) session.pendingEdits--;
    _coalesceKey = null;
    selected = document.cues.isEmpty
        ? 0
        : selected.clamp(0, document.cues.length - 1);
    _changed();
  }

  /// 「撤销到上次写入」：换回上次写进字幕文件的版本。本身也能撤销。
  void revertToWritten() {
    final saved = _saved;
    if (locked || saved == null || identical(saved, document)) return;
    _commit(saved);
    session.pendingEdits = 0;
    notifyListeners();
  }

  void _replaceCurrent(Cue cue) => _commit(document.replaceAt(selected, cue));

  void editSource(String text) {
    final cue = current;
    if (cue == null || cue.source == text) return;
    _commitText(
      document.replaceAt(selected, cue.copyWith(source: text)),
      '$selected:source',
    );
  }

  void editTranslation(String text) {
    final cue = current;
    if (cue == null || cue.translation == text) return;
    _commitText(
      document.replaceAt(selected, cue.copyWith(translation: text)),
      '$selected:translation',
    );
  }

  void editStart(int ms) {
    final cue = current;
    if (cue == null) return;
    // 起点不能越过终点，否则时间码会倒置。
    _replaceCurrent(cue.copyWith(startMs: ms.clamp(0, cue.endMs - 1)));
  }

  void editEnd(int ms) {
    final cue = current;
    if (cue == null) return;
    _replaceCurrent(
      cue.copyWith(endMs: ms < cue.startMs + 1 ? cue.startMs + 1 : ms),
    );
  }

  void toggleReviewed() {
    final cue = current;
    if (cue == null) return;
    _replaceCurrent(cue.copyWith(reviewed: !cue.reviewed));
  }

  /// 在原文的中点拆成两条。
  void split() {
    final cue = current;
    if (cue == null || cue.source.length < 2) return;
    _commit(document.splitAt(selected, cue.source.length ~/ 2));
  }

  void mergeWithNext() {
    if (selected >= document.cues.length - 1) return;
    _commit(document.mergeWithNext(selected, cjk: _isCjk));
  }

  /// 并入上一条 —— 未配对的译文行最常用。
  void mergeWithPrevious() {
    if (selected <= 0 || selected >= document.cues.length) return;
    selected--;
    mergeWithNext();
  }

  bool get _isCjk => session.sourceLanguage.cjk;

  /// 改名。名字清空回到「说话人N」。
  void renameSpeaker(int id, String name) =>
      _commit(document.renameSpeaker(id, name));

  /// 把 [from] 的字幕全部并到 [into] 名下；筛选里的 [from] 也跟着换成 [into]。
  void mergeSpeaker(int from, int into) {
    if (from == into) return;
    if (speakerFilter.contains(from)) {
      speakerFilter = {
        for (final s in speakerFilter) s == from ? into : s,
      };
    }
    _commit(document.mergeSpeaker(from, into));
  }

  /// 新增一位说话人，返回编号。名字为空时记成「说话人N」，否则一位没有
  /// 字幕也没有名字的说话人在名单里无从存在。
  int addSpeaker(String name) {
    final id = document.nextSpeakerId;
    final trimmed = name.trim();
    _commit(
      document.renameSpeaker(
        id,
        trimmed.isEmpty ? document.speakerName(id) : trimmed,
      ),
    );
    return id;
  }

  /// 把当前条改给 [speaker]（null 为清除）。[run] 为真时改的是当前条所在的
  /// 同一人连续段 —— 识别在换人处切歪时往往一连错好几条。
  void assignSpeaker(int? speaker, {bool run = false}) {
    if (current == null) return;
    final range = run
        ? document.speakerRun(selected)
        : (start: selected, end: selected);
    final positions = [
      for (var i = range.start; i <= range.end; i++)
        if (document.cues[i].speaker != speaker) i,
    ];
    if (positions.isEmpty) return;
    _commit(document.assignSpeaker(positions, speaker));
  }

  /// 导出时是否写说话人标签。
  void setSpeakerLabels(bool on) {
    if (document.speakerLabels == on) return;
    _commit(document.copyWith(speakerLabels: on));
  }

  /// 卸载译文：清空文档里的译文、删掉未配对行。可以撤销；译文文件本身不动。
  void unmountTranslation() {
    if (session is! FileSession) return;
    if (!document.cues.any((c) => c.hasTranslation)) return;
    _commit(document.withoutTranslations());
    selected = document.cues.isEmpty
        ? 0
        : selected.clamp(0, document.cues.length - 1);
  }

  /// 把文档写进字幕文件，返回写了哪些路径。
  ///
  /// 写之前先看文件在上次读 / 写之后有没有被别的程序改过，改过就抛
  /// [WriteConflict] 交给界面去问；[overwrite] 为真时不看，直接覆盖。
  Future<List<String>> save({bool overwrite = false}) async {
    if (_writing || locked) return const [];
    if (!overwrite) {
      final changes = await session.externalChanges();
      if (changes.isNotEmpty) {
        _conflicts = changes;
        notifyListeners();
        throw WriteConflict(changes);
      }
    }
    return _write(session.write);
  }

  /// 另存到 [dir]。本地会话写完就挂在新文件上；任务会话只是另存一份，
  /// 产物与同步状态不变。目标不能用时抛 [TargetRejected]。
  Future<List<String>> saveAs(String dir) async {
    if (locked) throw const TargetRejected('任务还在运行，完成后再另存');
    final s = session;
    if (await s.checkWriteTo(dir) case final reason?) {
      throw TargetRejected(reason);
    }
    if (s is! FileSession) {
      final written = await s.writeTo(dir);
      _showWritten(written);
      notifyListeners();
      return written;
    }
    final (oldSource, oldTranslation) = (s.sourcePath, s.translationPath);
    final written = await _write(() => s.writeTo(dir));
    // 旧文件那份草稿里的修改已经写到新文件了，留着下次打开旧文件会误报。
    await store?.forgetFileState(oldSource, oldTranslation);
    onRemount?.call();
    return written;
  }

  Future<List<String>> _write(Future<List<String>> Function() write) async {
    final saving = document;
    final pendingBefore = session.pendingEdits;
    _writing = true;
    _failure = null;
    // 写完会连同附加状态一起存，排着的草稿不用再写；写文件期间新来的改动
    // 会重新标记。写失败时再把草稿补上。
    final draftPending = _draftDirty;
    _draftDirty = false;
    _draftTimer?.cancel();
    notifyListeners();
    try {
      final written = await write();
      _saved = saving;
      _baseline = saving;
      _baselineKeys = null;
      _coalesceKey = null;
      _conflicts = const [];
      // 写文件要等 IO，期间又改了的留到下一次写入。
      session.pendingEdits = identical(document, saving)
          ? 0
          : math.max(1, session.pendingEdits - pendingBefore);
      _writing = false;
      recoveredOverChanged = false;
      await _saveFileState();
      if (identical(document, saving)) _showWritten(written);
      return written;
    } catch (e) {
      _failure = _describeFailure(e);
      if (draftPending) {
        _draftDirty = true;
        _scheduleDraft();
      }
      rethrow;
    } finally {
      _writing = false;
      // 写到一半切走了会话：控制器已经 dispose，不能再通知。
      if (!_disposed) notifyListeners();
    }
  }

  void _showWritten(List<String> written) {
    if (_disposed) return;
    _justWritten = written;
    _writtenTimer?.cancel();
    _writtenTimer = Timer(const Duration(seconds: 2), () {
      _justWritten = null;
      notifyListeners();
    });
  }

  static String _describeFailure(Object e) {
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      // EACCES / EPERM（POSIX）与 ERROR_ACCESS_DENIED（Windows）。
      if (code == 13 || code == 1 || code == 5) return '目录没有写权限';
      if (code == 28 || code == 112) return '磁盘空间不足';
      return e.message;
    }
    if (e is ProviderException) return e.message;
    return '$e';
  }

  void _scheduleDraft() {
    if (session is! FileSession || store == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), flushDraft);
  }

  /// 把还没写盘的编辑进度写掉。退出应用、切换会话前调。
  Future<void> flushDraft() async {
    _draftTimer?.cancel();
    _draftTimer = null;
    if (!_draftDirty) return;
    _draftDirty = false;
    await _saveFileState();
  }

  /// 扔掉这对文件存下的附加状态与草稿，之后也不再写。按文件重新打开前调。
  Future<void> forgetDraft() async {
    _draftTimer?.cancel();
    _draftDirty = false;
    final s = session;
    if (s is FileSession) {
      await store?.forgetFileState(s.sourcePath, s.translationPath);
    }
  }

  /// 本地会话的附加状态：上次写入的版本 + 还没写回的编辑进度。
  Future<void> _saveFileState() async {
    final s = session;
    final store = this.store;
    if (s is! FileSession || store == null) return;
    final pending = unsavedEdits;
    await store.saveFileState(
      sourcePath: s.sourcePath,
      translationPath: s.translationPath,
      document: _saved ?? document,
      draft: pending == 0 ? null : document,
      pendingEdits: pending,
      stamps: s.trackedStamps,
    );
  }

  /// 任务队列通知了：流水线可能换掉了文档，或任务开跑 / 跑完了。
  ///
  /// 文档被换掉时撤销栈里全是旧文档的快照，留着的话一撤销就把流水线的
  /// 结果换回去，所以清掉；「本次修改」改以新文档为基准。
  void _sourceChanged() {
    if (_disposed) return;
    final wasLocked = _wasLocked;
    final phase = _phase;
    _wasLocked = locked;
    _phase = session.phase;
    if (identical(document, _seen)) {
      if (wasLocked != locked && session.justFinished) {
        // 跑完了：完成阶段已按这份文档写出产物、清零了未写入数。
        _saved = document;
        _baseline = document;
        _baselineKeys = null;
      }
      // 阶段变了（排队 → 识别 → 翻译）也要刷新只读横幅上的说明。
      if (wasLocked != locked || phase != _phase) notifyListeners();
      return;
    }
    _seen = document;
    _undo.clear();
    _coalesceKey = null;
    _saved = session.pendingEdits == 0 ? document : null;
    _baseline = document;
    _baselineKeys = null;
    selected = document.cues.isEmpty
        ? 0
        : selected.clamp(0, document.cues.length - 1);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _follow?.removeListener(_sourceChanged);
    _writtenTimer?.cancel();
    // 关掉前把编辑进度写掉；写盘是异步的，不必等。
    if (_draftDirty) unawaited(flushDraft().catchError((Object _) {}));
    _draftTimer?.cancel();
    super.dispose();
  }

  TranslationProvider _translationProvider() {
    if (translator case final build?) return build();
    final options = session.options;
    return Registry.buildTranslation(
      options.translationProviderId,
      settings,
      model: options.translationModel,
      guidance: options.translationGuidance,
    );
  }

  /// 重新翻译某一条。失败时把错误抛给调用方去弹 SnackBar。
  Future<void> retranslate(int indexInDocument) async {
    if (locked) return;
    final cue = document.cues[indexInDocument];
    translating.add(indexInDocument);
    notifyListeners();
    try {
      final result = await _translationProvider().translateBatch(
        lines: [cue.source],
        sourceLanguage: session.sourceLanguage.name,
        targetLanguage: session.targetLanguage.name,
        token: CancellationToken(),
      );
      if (result.length != 1) {
        throw const ProviderException(
          '译文与原文条数对不上',
          hint: '模型没有返回恰好一条译文，请稍后重试。',
        );
      }
      // 等译文期间文档被流水线换掉了：下标已经对不上，这条译文不要了。
      if (indexInDocument >= document.cues.length ||
          !identical(document.cues[indexInDocument], cue)) {
        return;
      }
      _commit(
        document.replaceAt(
          indexInDocument,
          cue.copyWith(translation: result.single, reviewed: false),
        ),
      );
    } finally {
      translating.remove(indexInDocument);
      notifyListeners();
    }
  }

  /// 翻译所有还没有译文的条目。返回翻了多少条。
  ///
  /// 未配对行没有原文，不送去翻译；识别跳过留下的空原文同理。
  Future<int> translateMissing() async {
    if (locked) return 0;
    final pending = [
      for (final (i, c) in document.cues.indexed)
        if (!c.hasTranslation && c.source.trim().isNotEmpty) i,
    ];
    if (pending.isEmpty) return 0;

    final provider = _translationProvider();
    final token = CancellationToken();
    final batchSize = session.options.translationBatchSize;
    var done = 0;
    var pushed = false;

    for (var start = 0; start < pending.length; start += batchSize) {
      final slice = [
        for (final i in pending.sublist(
          start,
          (start + batchSize).clamp(0, pending.length),
        ))
          if (i < document.cues.length) i,
      ];
      final sources = [for (final i in slice) document.cues[i].source];
      final result = await provider.translateBatch(
        lines: sources,
        sourceLanguage: session.sourceLanguage.name,
        targetLanguage: session.targetLanguage.name,
        token: token,
      );
      // 翻到一半任务被续跑了：文档归流水线，再写回去会盖掉它的结果。
      if (locked || _disposed) return done;
      if (result.length != slice.length) {
        throw ProviderException(
          '译文与原文条数对不上',
          detail: '期望 ${slice.length} 条，实际收到 ${result.length} 条',
          hint: '模型合并或丢弃了字幕行，请减小批量后重试。',
        );
      }
      // 等译文期间文档可能又变了（用户接着改、拆分合并、流水线续跑过又停了）：
      // 译文写到**现在**的文档上，只填原文没变、还没有译文的那几条，
      // 别的条目一律不碰 —— 不能拿开始时的快照整份盖回去。
      final cues = [...document.cues];
      var filled = 0;
      for (final (j, i) in slice.indexed) {
        if (i >= cues.length) continue;
        final cue = cues[i];
        if (cue.source != sources[j] || cue.hasTranslation) continue;
        cues[i] = cue.copyWith(translation: result[j]);
        filled++;
      }
      if (filled == 0) continue;
      if (!pushed) {
        _push();
        pushed = true;
      }
      session.document = document.copyWith(cues: cues);
      done += filled;
      _changed();
    }
    return done;
  }

  /// 导出到 [dir]（默认源文件所在目录或设置里指定的输出目录）。返回写出
  /// 的路径。导出是另存一份，不改变同步状态。
  Future<List<String>> export(Set<SrtField> fields, {String? dir}) async {
    // 与另存为一致：跑到一半的文档导出去也没用。
    if (locked) throw const TargetRejected('任务还在运行，完成后再导出');
    final options = session.options;
    if (!options.format.implemented) {
      throw const ProviderException(
        '当前字幕格式尚未实施',
        hint: '先在任务参数中选择 SRT、WebVTT 或纯文本。',
      );
    }
    dir ??= session.exportDir;
    final stem = session.exportStem;
    String pathOf(SrtField field) {
      final suffix = switch (field) {
        SrtField.source => languageTag(session.sourceLanguage),
        SrtField.translation => languageTag(session.targetLanguage),
        SrtField.bilingualTargetAbove || SrtField.bilingualTargetBelow =>
          '${languageTag(session.sourceLanguage)}-'
              '${languageTag(session.targetLanguage)}',
      };
      // 用平台分隔符：要与 targetPaths 比对，Windows 上混用 / 与 \ 会比不上。
      return '$dir${Platform.pathSeparator}$stem.$suffix.'
          '${options.format.extension}';
    }

    // 导出是另存一份。落到字幕文件自己身上就成了绕过冲突检查的「保存」，
    // 而同步状态还以为文件没更新 —— 让用户改用保存。
    final own = session.targetPaths.toSet();
    if (fields.map(pathOf).any(own.contains)) {
      throw const TargetRejected(
        '这个目录里就是字幕文件本身，想更新它们请用「保存」（⌘S）；导出请换一个目录',
      );
    }
    await Directory(dir).create(recursive: true);

    String Function(String) wrap(Language language) {
      final limit = language.cjk
          ? options.cjkLineLength
          : options.latinLineLength;
      return (text) => LineWrap.wrap(text, limit: limit, cjk: language.cjk);
    }

    final wrapSource = wrap(session.sourceLanguage);
    final wrapTranslation = wrap(session.targetLanguage);
    final speakerLabel = document.speakerLabeler(session.sourceLanguage);

    final contents = <String, String>{};
    for (final field in fields) {
      final content = switch (options.format) {
        SubtitleFormat.srt => Srt.serialize(
          document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.vtt => Srt.serializeVtt(
          document.cues,
          field: field,
          wrapSource: wrapSource,
          wrapTranslation: wrapTranslation,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.txt => Srt.serializePlain(
          document.cues,
          field: field,
          speakerLabel: speakerLabel,
        ),
        SubtitleFormat.ass => '',
      };
      if (content.trim().isEmpty) continue;
      contents[pathOf(field)] = content;
    }
    // 几份一起写，失败时不留半套。
    await writeFilesAtomically(contents);
    return contents.keys.toList();
  }
}
