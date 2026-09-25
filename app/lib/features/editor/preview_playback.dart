import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/cue.dart';
import '../../domain/media_kinds.dart';
import '../../domain/paths.dart';

/// 播放器要跟着走的字幕表：有哪些条、选中了哪一条。`EditorController`
/// 实现它；抽成接口是因为 controller 持有播放器（经 `EditorMedia`），
/// 这里再反过来 import controller 就成环了。
abstract interface class PlaybackCues implements Listenable {
  SubtitleDocument get document;

  /// 当前选中条在完整文档里的下标。
  int get selected;

  Cue? get current;

  void select(int indexInDocument);
}

/// 检视面板的预览播放：把播放器与编辑器的选中条绑在一起。
///
/// - 选中条变了（点表格、J/K、翻译跳转）→ 播放头跳到那一条的开始，
///   正在播放的话继续播。
/// - 播放中播放头进入另一条 → 选中那一条，表格跟着走。
///
/// 两个方向会互相触发，用 [_syncing] 挡住回声。播放器本身只在这里创建，
/// 没有音视频的会话不会碰 media_kit。
class PreviewPlayback extends ChangeNotifier {
  PreviewPlayback({required this.cues, required this.mediaPath})
    : player = Player(),
      isAudio = MediaKinds.isAudio(mediaPath),
      _selected = cues.selected {
    video = VideoController(player);
    cues.addListener(_onEditorChanged);
    _subs = [
      player.stream.position.listen(_onPosition),
      player.stream.duration.listen((d) {
        duration = d;
        // 文件刚加载完才能定位；在这之前的跳转先记着。
        if (d > Duration.zero && _pendingSeekMs != null) {
          final ms = _pendingSeekMs!;
          _pendingSeekMs = null;
          seekTo(ms);
        }
        notifyListeners();
      }),
      player.stream.playing.listen((p) {
        playing = p;
        notifyListeners();
      }),
      player.stream.width.listen((w) {
        hasVideo = (w ?? 0) > 0;
        notifyListeners();
      }),
      player.stream.error.listen((message) {
        error = message;
        notifyListeners();
      }),
    ];
  }

  final PlaybackCues cues;
  final String mediaPath;
  final Player player;
  late final VideoController video;

  /// 按扩展名判断的纯音频；画面区画一个音频图标而不是黑屏。
  final bool isAudio;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  bool hasVideo = false;

  /// 播放器报的最近一条错误，比如文件打不开；没有则为 null。
  String? error;

  late List<StreamSubscription<Object?>> _subs;
  int _selected;
  bool _syncing = false;
  int? _pendingSeekMs;
  bool _disposed = false;

  String get fileName => baseName(mediaPath);

  bool get loaded => duration > Duration.zero;

  /// 播放头所在的那一条；停在字幕之间的空白时为 null。
  Cue? get cueAtPlayhead {
    final index = cueIndexAt(
      cues.document.cues,
      position.inMilliseconds,
      preferred: cues.selected,
    );
    return index == null ? null : cues.document.cues[index];
  }

  /// 打开文件，不自动播放，播放头停在当前选中条的开始。
  Future<void> open() async {
    _pendingSeekMs = cues.current?.startMs ?? 0;
    await player.open(Media(mediaPath), play: false);
  }

  Future<void> toggle() => playing ? player.pause() : player.play();

  Future<void> pause() async {
    if (playing) await player.pause();
  }

  Future<void> seekTo(int ms) async {
    if (!loaded) {
      _pendingSeekMs = ms;
      return;
    }
    final clamped = ms.clamp(0, duration.inMilliseconds);
    position = Duration(milliseconds: clamped);
    notifyListeners();
    await player.seek(position);
  }

  /// 相对当前位置跳转，用于 ←/→。
  Future<void> nudge(Duration delta) =>
      seekTo((position + delta).inMilliseconds);

  void _onEditorChanged() {
    if (_disposed || cues.selected == _selected) return;
    _selected = cues.selected;
    if (_syncing) return;
    final cue = cues.current;
    if (cue != null) seekTo(cue.startMs);
  }

  void _onPosition(Duration p) {
    if (_disposed) return;
    position = p;
    if (playing) {
      final index = cueIndexAt(
        cues.document.cues,
        p.inMilliseconds,
        preferred: cues.selected,
      );
      if (index != null && index != cues.selected) {
        _syncing = true;
        try {
          cues.select(index);
        } finally {
          _syncing = false;
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cues.removeListener(_onEditorChanged);
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
