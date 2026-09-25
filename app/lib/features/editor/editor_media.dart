import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/paths.dart';
import '../../services/editor_store.dart';
import 'editor_session.dart';
import 'preview_playback.dart';

/// 检视面板预览用的音视频：找哪个文件、手动关联、播放器。
///
/// 由 `EditorController` 持有、随它一起释放。编辑页只拿 [playback] 来画，
/// 不自己找文件、不自己开播放器 —— 页面每次切分区都会重建，放在页面上的话
/// 播放器切一次关一次、播放位置丢掉、找文件的读盘也重来一遍。
class EditorMedia extends ChangeNotifier {
  EditorMedia({
    required this.session,
    required PlaybackCues cues,
    this.store,
    PreviewPlayback? Function(String path)? openPlayer,
  }) : _openPlayer =
           openPlayer ??
           ((path) => PreviewPlayback(cues: cues, mediaPath: path));

  final EditorSession session;

  /// 手动关联记在这里；为空就不记也不读。
  final EditorStore? store;

  /// 建播放器。测试里换掉它，免得碰 media_kit 的原生库；返回 null 表示
  /// 只记路径不开播放器。
  final PreviewPlayback? Function(String path) _openPlayer;

  /// 播放器打开失败时的提示出口，由打开会话的一方接上。
  ValueChanged<String>? onError;

  String? _path;

  /// 正在预览的音视频；还没找到或没有时为 null，检视面板只预览字幕样式。
  String? get path => _path;

  PreviewPlayback? _playback;

  /// 检视面板的播放器；会话没有音视频时为 null。
  PreviewPlayback? get playback => _playback;

  Future<void>? _located;
  bool _disposed = false;

  /// 找会话配套的音视频，找到就开播放器。上次手动关联过的优先。
  ///
  /// 只找一次：再调用拿到的是同一个 Future。找不到或读不了就只预览字幕
  /// 样式，不报错。
  Future<void> locate() => _located ??= _locate();

  Future<void> _locate() async {
    try {
      final linked = await store?.loadMediaLink(session.subtitlePath);
      final path = await session.locateMedia(linked: linked);
      // 找的期间用户已经手动关联了一个：以手动的为准。
      if (_disposed || path == null || _path != null) return;
      _open(path);
    } on Object {
      // 见上。
    }
  }

  /// 「关联视频…」：用户手动挑的音视频。记下来，下次打开同一份字幕不用
  /// 再选；记不下来也不影响这次预览。
  Future<void> attach(String path) async {
    if (_disposed) return;
    session.mediaPath = path;
    _open(path);
    try {
      await store?.saveMediaLink(session.subtitlePath, path);
    } on Object {
      // 见上。
    }
  }

  /// 编辑页收起（切去别的分区、盖上入口页）时暂停：播放器还在，回来接着
  /// 从原位置播，但看不见的时候不该一直出声。
  Future<void> pause() async {
    if (_disposed) return;
    await _playback?.pause();
  }

  void _open(String path) {
    _playback?.dispose();
    _path = path;
    final playback = _playback = _openPlayer(path);
    notifyListeners();
    if (playback == null) return;
    unawaited(
      playback.open().catchError((Object e) {
        if (!_disposed && _playback == playback) {
          onError?.call('打不开 ${baseName(path)}：$e');
        }
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _playback?.dispose();
    _playback = null;
    super.dispose();
  }
}
