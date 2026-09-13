import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/cue.dart';
import '../../domain/language.dart';
import '../../domain/line_wrap.dart';
import '../../domain/srt.dart';
import '../../domain/task_options.dart';
import '../../services/editor_store.dart';
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
  unpaired('未配对');

  const CueFilter(this.label);

  final String label;
}

/// 界面上显示的状态。整份文档都没有译文时（只挂了原文），「未翻译」没有
/// 意义，按置信度与校对标记显示成「待校对」或「已校对」。
CueState displayStateOf(Cue cue, {required bool translated}) {
  final state = cue.state;
  if (translated || state != CueState.untranslated) return state;
  final low = cue.confidence != null && cue.confidence! < Cue.lowConfidence;
  return low && !cue.reviewed ? CueState.review : CueState.ok;
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
class EditorController extends ChangeNotifier {
  EditorController({required this.session, required this.settings, this.store})
    : _saved = session.document;

  final EditorSession session;
  final AppSettings settings;

  /// 本地会话保存时顺带写附加状态；为空就不写。
  final EditorStore? store;

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

  /// 上次保存时的文档。文档不可变，比较引用就知道有没有改过。
  SubtitleDocument _saved;
  int _editsSinceSave = 0;

  SubtitleDocument get document => session.document;

  bool get canUndo => _undo.isNotEmpty;

  /// 本地会话里还没保存的修改数。任务会话随任务自动写盘，恒为 0。
  int get unsavedEdits {
    if (session is! FileSession || identical(document, _saved)) return 0;
    return _editsSinceSave < 1 ? 1 : _editsSinceSave;
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
    _editsSinceSave++;
    if (_undo.length > _undoLimit) _undo.removeAt(0);
  }

  /// 改文档的操作都走这里：先存快照再换新文档。没变化就什么都不做，
  /// 免得撤销栈里堆一份一模一样的快照。
  void _commit(SubtitleDocument next) {
    if (identical(next, document)) return;
    _push();
    session.document = next;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    session.document = _undo.removeLast();
    if (_editsSinceSave > 0) _editsSinceSave--;
    selected = document.cues.isEmpty
        ? 0
        : selected.clamp(0, document.cues.length - 1);
    notifyListeners();
  }

  void _replaceCurrent(Cue cue) => _commit(document.replaceAt(selected, cue));

  void editSource(String text) {
    final cue = current;
    if (cue == null || cue.source == text) return;
    _replaceCurrent(cue.copyWith(source: text));
  }

  void editTranslation(String text) {
    final cue = current;
    if (cue == null || cue.translation == text) return;
    _replaceCurrent(cue.copyWith(translation: text));
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

  /// 保存本地会话，返回写了哪些文件。任务会话自动保存，这里什么都不做。
  Future<List<String>> save() async {
    final s = session;
    if (s is! FileSession) return const [];
    final saving = document;
    final written = await s.save();
    _saved = saving;
    _editsSinceSave = 0;
    await store?.saveFileState(
      sourcePath: s.sourcePath,
      translationPath: s.translationPath,
      document: saving,
    );
    notifyListeners();
    return written;
  }

  TranslationProvider _translationProvider() {
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
    final pending = [
      for (final (i, c) in document.cues.indexed)
        if (!c.hasTranslation && c.source.trim().isNotEmpty) i,
    ];
    if (pending.isEmpty) return 0;

    final provider = _translationProvider();
    final token = CancellationToken();
    final batchSize = session.options.translationBatchSize;
    final cues = [...document.cues];
    _push();

    for (var start = 0; start < pending.length; start += batchSize) {
      final slice = pending.sublist(
        start,
        (start + batchSize).clamp(0, pending.length),
      );
      final result = await provider.translateBatch(
        lines: [for (final i in slice) cues[i].source],
        sourceLanguage: session.sourceLanguage.name,
        targetLanguage: session.targetLanguage.name,
        token: token,
      );
      if (result.length != slice.length) {
        throw ProviderException(
          '译文与原文条数对不上',
          detail: '期望 ${slice.length} 条，实际收到 ${result.length} 条',
          hint: '模型合并或丢弃了字幕行，请减小批量后重试。',
        );
      }
      for (final (j, i) in slice.indexed) {
        cues[i] = cues[i].copyWith(translation: result[j]);
      }
      session.document = document.copyWith(cues: cues);
      notifyListeners();
    }
    return pending.length;
  }

  /// 导出到源文件所在目录（或设置里指定的输出目录）。返回写出的路径。
  Future<List<String>> export(Set<SrtField> fields) async {
    final options = session.options;
    if (!options.format.implemented) {
      throw const ProviderException(
        '当前字幕格式尚未实施',
        hint: '先在任务参数中选择 SRT、WebVTT 或纯文本。',
      );
    }
    final dir = session.exportDir;
    await Directory(dir).create(recursive: true);
    final stem = session.exportStem;
    final written = <String>[];

    String Function(String) wrap(Language language) {
      final limit = language.cjk
          ? options.cjkLineLength
          : options.latinLineLength;
      return (text) => LineWrap.wrap(text, limit: limit, cjk: language.cjk);
    }

    final wrapSource = wrap(session.sourceLanguage);
    final wrapTranslation = wrap(session.targetLanguage);
    final speakerLabel = document.speakerLabeler(session.sourceLanguage);

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
      final suffix = switch (field) {
        SrtField.source => _tag(session.sourceLanguage.code),
        SrtField.translation => _tag(session.targetLanguage.code),
        SrtField.bilingualTargetAbove || SrtField.bilingualTargetBelow =>
          '${_tag(session.sourceLanguage.code)}-'
              '${_tag(session.targetLanguage.code)}',
      };
      final path = '$dir/$stem.$suffix.${options.format.extension}';
      await File(path).writeAsString(content);
      written.add(path);
    }
    return written;
  }

  static String _tag(String language) {
    final trimmed = language.trim();
    if (trimmed.isEmpty || trimmed == 'auto') return 'src';
    return trimmed.replaceAll(RegExp(r'[\\/\s]+'), '_');
  }
}
