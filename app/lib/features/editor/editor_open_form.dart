import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../domain/cue.dart';
import '../../domain/language.dart';
import '../../domain/media_kinds.dart';
import '../../domain/srt.dart';
import '../../domain/subtitle_pairing.dart';
import '../../domain/task_options.dart';
import 'editor_session.dart';

/// 入口页上的两个位置。
enum OpenSlot { source, translation }

/// 入口页「本地字幕」一栏的状态：两个位置放了什么、语言、配对方式、
/// 说话人标签开关，以及据此算出的配对预览。
///
/// 放在页面之外，是为了切去任务页再回来，挑好的文件还在；也方便测试。
class EditorOpenForm extends ChangeNotifier {
  EditorOpenForm({required this.defaults});

  /// 语言与翻译参数的默认值，来自设置。
  TaskOptions Function() defaults;

  LocalSubtitleFile? _source;
  LocalSubtitleFile? _translation;
  final Map<OpenSlot, String> _errors = {};
  final Map<OpenSlot, Language> _languages = {};
  PairingMode? _mode;
  bool _readSpeakerLabels = true;
  PairingResult? _pairing;
  bool _disposed = false;

  /// 编辑器能读的字幕格式。ASS / SSA 带样式，第一期不做。
  static const extensions = ['srt', 'vtt'];

  LocalSubtitleFile? get source => _source;
  LocalSubtitleFile? get translation => _translation;
  LocalSubtitleFile? file(OpenSlot slot) =>
      slot == OpenSlot.source ? _source : _translation;
  String? error(OpenSlot slot) => _errors[slot];

  bool get hasAny => _source != null || _translation != null;

  bool get readSpeakerLabels => _readSpeakerLabels;

  /// 用户选的方式；没选时是配对结果里自动定下的方式。
  PairingMode? get mode => _pairing?.mode ?? _mode;

  PairingResult? get pairing => _pairing;

  /// 原文里识别出的行首标签；没有时为空列表。
  List<String> get speakerLabels => _source?.speakerLabels?.labels ?? const [];

  Language language(OpenSlot slot) {
    final chosen = _languages[slot];
    if (chosen != null) return chosen;
    final guessed = file(slot)?.language;
    if (guessed != null) return guessed;
    final d = defaults();
    return slot == OpenSlot.source ? d.sourceLanguage : d.targetLanguage;
  }

  /// 语言是从文件名或文字猜出来的（界面上写「· 自动识别」）。
  bool languageGuessed(OpenSlot slot) =>
      _languages[slot] == null && file(slot)?.language != null;

  bool get canOpen => _source != null && (_pairing?.plausible ?? true);

  /// 打开后的条数。
  int get cueCount => _pairing?.cues.length ?? _source?.cues.length ?? 0;

  int get fileCount =>
      (_source == null ? 0 : 1) + (_translation == null ? 0 : 1);

  /// 页脚一句话。
  ({String text, bool error, bool empty}) get footer {
    if (_source == null) {
      return (text: '先添加原文字幕', error: false, empty: true);
    }
    if (!canOpen) {
      return (text: '时间轴基本对不上，先切到「按序号」再打开', error: true, empty: false);
    }
    return (
      text: '将打开 ${_grouped(cueCount)} 条；⌘S 保存会写回这 $fileCount 个文件',
      error: false,
      empty: false,
    );
  }

  /// 配对块底部的说明。
  String? get pairingNote {
    final p = _pairing;
    if (p == null) return null;
    if (p.mode == PairingMode.byIndex && p.misalignedFrom == null) {
      return '两份逐条对应，共 ${_grouped(p.paired)} 条';
    }
    if (p.mode == PairingMode.byTime &&
        p.misalignedFrom != null &&
        p.plausible) {
      final differ = p.sourceCount != p.translationCount;
      return '${differ ? '两份条数不同，' : ''}按序号配对会从第 ${p.misalignedFrom} 条开始错位';
    }
    return null;
  }

  /// 读一个文件放进 [slot]。读不了时位置保持原样，记下错误。
  Future<void> load(OpenSlot slot, String path) async {
    try {
      setFile(slot, await LocalSubtitleFile.load(path));
      return;
    } on FormatException catch (e) {
      _errors[slot] = '${_fileName(path)}：${e.message}';
    } on FileSystemException {
      _errors[slot] = '${_fileName(path)}：读不了这个文件，确认是 UTF-8 编码的 SRT / VTT';
    }
    _recompute();
  }

  /// 直接放一份已经读好的文件。
  void setFile(OpenSlot slot, LocalSubtitleFile file) {
    _errors.remove(slot);
    _languages.remove(slot);
    if (slot == OpenSlot.source) {
      _source = file;
    } else {
      _translation = file;
    }
    _recompute();
  }

  Future<void> browse(OpenSlot slot) async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '字幕', extensions: extensions),
      ],
    );
    if (picked != null) await load(slot, picked.path);
  }

  /// 拖入一批路径。拖到某个位置上就放进那个位置；拖到面板空白处时按
  /// 文件名里的语言段分配，分不出来就放进原文位置。
  Future<void> handleDrop(List<String> paths, {OpenSlot? slot}) async {
    final subs = paths.where(isOpenable).toList();
    if (subs.isEmpty) return;
    if (slot != null) return load(slot, subs.first);

    if (subs.length >= 2) {
      final (src, dst) = _assign(subs[0], subs[1]);
      await load(OpenSlot.source, src);
      if (dst != null) await load(OpenSlot.translation, dst);
      return;
    }
    final target = _source == null || _translation != null
        ? OpenSlot.source
        : OpenSlot.translation;
    await load(target, subs.first);
  }

  static bool isOpenable(String path) =>
      extensions.contains(MediaKinds.extensionOf(path));

  /// 两个文件怎么分：语言段不同时，和设置里目标语言一致的那份当译文；
  /// 分不出来就只放第一个进原文。
  (String, String?) _assign(String a, String b) {
    final la = Languages.fromFileName(a);
    final lb = Languages.fromFileName(b);
    if (la == null || lb == null || la.code == lb.code) return (a, null);
    final target = defaults().targetLanguage.code;
    return la.code == target ? (b, a) : (a, b);
  }

  void remove(OpenSlot slot) {
    if (slot == OpenSlot.source) {
      _source = null;
    } else {
      _translation = null;
    }
    _errors.remove(slot);
    _languages.remove(slot);
    _recompute();
  }

  void swap() {
    if (_source == null || _translation == null) return;
    final previousSource = _source;
    _source = _translation;
    _translation = previousSource;
    final src = _languages.remove(OpenSlot.source);
    final dst = _languages.remove(OpenSlot.translation);
    if (dst != null) _languages[OpenSlot.source] = dst;
    if (src != null) _languages[OpenSlot.translation] = src;
    _recompute();
  }

  void clear() {
    _source = null;
    _translation = null;
    _errors.clear();
    _languages.clear();
    _mode = null;
    _recompute();
  }

  void setMode(PairingMode mode) {
    _mode = mode;
    _recompute();
  }

  void setLanguage(OpenSlot slot, Language language) {
    _languages[slot] = language;
    _recompute();
  }

  void setReadSpeakerLabels(bool on) {
    _readSpeakerLabels = on;
    _recompute();
  }

  /// 用读好的文件预填（来源浮层里的「替换…」「重新配对…」）。
  Future<void> seed({
    required String sourcePath,
    String? translationPath,
  }) async {
    clear();
    await load(OpenSlot.source, sourcePath);
    if (translationPath != null) {
      await load(OpenSlot.translation, translationPath);
    }
  }

  /// 按当前选择建会话。[restored] 是上次保存的附加状态。
  FileSession build({SubtitleDocument? restored}) => FileSession.open(
    source: _source!,
    translation: _translation,
    defaults: defaults(),
    sourceLanguage: language(OpenSlot.source),
    targetLanguage: language(OpenSlot.translation),
    mode: _mode,
    readSpeakerLabels: _readSpeakerLabels,
    restored: restored,
  );

  /// 「00:00:01 – 00:48:12」。
  static String span(LocalSubtitleFile file) {
    final start = file.cues.first.startMs;
    final end = file.cues.fold<int>(0, (m, c) => c.endMs > m ? c.endMs : m);
    String hms(int ms) => Srt.formatTimecode(ms).substring(0, 8);
    return '${hms(start)} – ${hms(end)}';
  }

  void _recompute() {
    final src = _source;
    final dst = _translation;
    if (src == null || dst == null) {
      _pairing = null;
    } else {
      List<Cue> cuesOf(LocalSubtitleFile f) =>
          _readSpeakerLabels ? (f.speakerLabels?.cues ?? f.cues) : f.cues;
      _pairing = SubtitlePairing.pair(
        cuesOf(src),
        cuesOf(dst),
        mode: _mode,
        cjk: language(OpenSlot.translation).cjk,
      );
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;
}

String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
