import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/cue.dart';
import '../../domain/srt.dart';
import '../../domain/task.dart';
import '../../services/provider_api.dart';
import '../../services/registry.dart';
import '../../services/settings.dart';

/// 原文 / 译文 / 双语。
enum CueView { source, translation, both }

/// 列表过滤。
enum CueFilter {
  all('全部'),
  review('待校对'),
  untranslated('未翻译');

  const CueFilter(this.label);

  final String label;
}

/// 编辑器的状态与操作。文档是不可变的，每次改动换一份新的 —— 撤销栈因此
/// 只需要存快照，不用记反向操作。
class EditorController extends ChangeNotifier {
  EditorController({required this.task, required this.settings});

  final SubtitleTask task;
  final AppSettings settings;

  CueView view = CueView.both;
  CueFilter filter = CueFilter.all;
  String search = '';

  /// 当前选中条在**完整文档**里的下标。
  int selected = 0;

  /// 正在重新翻译的条目下标，用来在界面上禁用按钮。
  final Set<int> translating = {};

  final List<SubtitleDocument> _undo = [];
  static const _undoLimit = 50;

  SubtitleDocument get document => task.document;

  bool get canUndo => _undo.isNotEmpty;

  List<Cue> get visibleCues {
    final needle = search.trim().toLowerCase();
    return document.cues.where((cue) {
      final passesFilter = switch (filter) {
        CueFilter.all => true,
        CueFilter.review => cue.state == CueState.review,
        CueFilter.untranslated => cue.state == CueState.untranslated,
      };
      if (!passesFilter) return false;
      if (needle.isEmpty) return true;
      return cue.source.toLowerCase().contains(needle) ||
          (cue.translation ?? '').toLowerCase().contains(needle);
    }).toList();
  }

  Cue? get current =>
      selected >= 0 && selected < document.cues.length
      ? document.cues[selected]
      : null;

  int countOf(CueFilter f) => switch (f) {
    CueFilter.all => document.cues.length,
    CueFilter.review => document.reviewCount,
    CueFilter.untranslated => document.untranslatedCount,
  };

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

  void select(int indexInDocument) {
    selected = indexInDocument;
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
    if (_undo.length > _undoLimit) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    task.document = _undo.removeLast();
    selected = selected.clamp(0, document.cues.length - 1);
    notifyListeners();
  }

  void _replaceCurrent(Cue cue) {
    _push();
    task.document = document.replaceAt(selected, cue);
    notifyListeners();
  }

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
    _replaceCurrent(cue.copyWith(endMs: ms < cue.startMs + 1 ? cue.startMs + 1 : ms));
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
    _push();
    task.document = document.splitAt(selected, cue.source.length ~/ 2);
    notifyListeners();
  }

  void mergeWithNext() {
    if (selected >= document.cues.length - 1) return;
    _push();
    task.document = document.mergeWithNext(selected, cjk: _isCjk);
    notifyListeners();
  }

  bool get _isCjk => const [
    'zh',
    'ja',
    'ko',
    '中',
    '日',
    '韩',
    '粤',
  ].any(task.sourceLanguage.toLowerCase().startsWith);

  /// 重新翻译某一条。失败时把错误抛给调用方去弹 SnackBar。
  Future<void> retranslate(int indexInDocument) async {
    final cue = document.cues[indexInDocument];
    translating.add(indexInDocument);
    notifyListeners();
    try {
      final provider = Registry.buildTranslation(
        task.translationProviderId,
        settings,
      );
      final result = await provider.translateBatch(
        lines: [cue.source],
        sourceLanguage: task.sourceLanguage,
        targetLanguage: task.targetLanguage,
        token: CancellationToken(),
      );
      _push();
      task.document = document.replaceAt(
        indexInDocument,
        cue.copyWith(translation: result.single, reviewed: false),
      );
    } finally {
      translating.remove(indexInDocument);
      notifyListeners();
    }
  }

  /// 翻译所有还没有译文的条目。返回翻了多少条。
  Future<int> translateMissing() async {
    final pending = [
      for (final (i, c) in document.cues.indexed)
        if (!c.hasTranslation) i,
    ];
    if (pending.isEmpty) return 0;

    final provider = Registry.buildTranslation(
      task.translationProviderId,
      settings,
    );
    final token = CancellationToken();
    final batchSize = settings.translationBatchSize;
    final cues = [...document.cues];
    _push();

    for (var start = 0; start < pending.length; start += batchSize) {
      final slice = pending.sublist(
        start,
        (start + batchSize).clamp(0, pending.length),
      );
      final result = await provider.translateBatch(
        lines: [for (final i in slice) cues[i].source],
        sourceLanguage: task.sourceLanguage,
        targetLanguage: task.targetLanguage,
        token: token,
      );
      for (final (j, i) in slice.indexed) {
        cues[i] = cues[i].copyWith(translation: result[j]);
      }
      task.document = document.copyWith(cues: cues);
      notifyListeners();
    }
    return pending.length;
  }

  /// 导出到源文件所在目录（或设置里指定的输出目录）。返回写出的路径。
  Future<List<String>> export(Set<SrtField> fields) async {
    final dir = settings.outputDir ?? File(task.sourcePath).parent.path;
    final stem = task.fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
    final written = <String>[];

    for (final field in fields) {
      final content = Srt.serialize(document.cues, field: field);
      if (content.trim().isEmpty) continue;
      final suffix = switch (field) {
        SrtField.source => _tag(task.sourceLanguage),
        SrtField.translation => _tag(task.targetLanguage),
        SrtField.bilingual => '双语',
      };
      final path = '$dir/$stem.$suffix.srt';
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
