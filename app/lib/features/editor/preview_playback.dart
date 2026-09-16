import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/cue.dart';
import '../../domain/media_kinds.dart';
import '../../domain/paths.dart';
import 'editor_controller.dart';

/// 检视面板的预览播放：把播放器与编辑器的选中条绑在一起。
///
/// - 选中条变了（点表格、J/K、翻译跳转）→ 播放头跳到那一条的开始，
///   正在播放的话继续播。
/// - 播放中播放头进入另一条 → 选中那一条，表格跟着走。
///
/// 两个方向会互相触发，用 [_syncing] 挡住回声。播放器本身只在这里创建，
/// 没有音视频的会话不会碰 media_kit。
class PreviewPlayback extends ChangeNotifier {
  PreviewPlayback({required this.controller, required this.mediaPath})
    : player = Player(),
      isAudio = MediaKinds.isAudio(mediaPath),
      _selected = controller.selected {
    video = VideoController(player);
    controller.addListener(_onEditorChanged);
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

  final EditorController controller;
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
      controller.document.cues,
      position.inMilliseconds,
      preferred: controller.selected,
    );
    return index == null ? null : controller.document.cues[index];
  }

  /// 打开文件，不自动播放，播放头停在当前选中条的开始。
  Future<void> open() async {
    _pendingSeekMs = controller.current?.startMs ?? 0;
    await player.open(Media(mediaPath), play: false);
  }

  Future<void> toggle() => playing ? player.pause() : player.play();

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
    if (_disposed || controller.selected == _selected) return;
    _selected = controller.selected;
    if (_syncing) return;
    final cue = controller.current;
    if (cue != null) seekTo(cue.startMs);
  }

  void _onPosition(Duration p) {
    if (_disposed) return;
    position = p;
    if (playing) {
      final index = cueIndexAt(
        controller.document.cues,
        p.inMilliseconds,
        preferred: controller.selected,
      );
      if (index != null && index != controller.selected) {
        _syncing = true;
        try {
          controller.select(index);
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
    controller.removeListener(_onEditorChanged);
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// [ms] 落在哪一条字幕里（含开始、不含结束）。几条重叠时优先 [preferred]，
/// 这样播放头在重叠段里不会来回跳；都不含时返回 null。
int? cueIndexAt(List<Cue> cues, int ms, {int? preferred}) {
  bool contains(Cue c) => ms >= c.startMs && ms < c.endMs;
  if (preferred != null &&
      preferred >= 0 &&
      preferred < cues.length &&
      contains(cues[preferred])) {
    return preferred;
  }
  final index = cues.indexWhere(contains);
  return index < 0 ? null : index;
}
