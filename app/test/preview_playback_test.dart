import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/editor/editor_media.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/preview_playback.dart';
import 'package:subtitle_studio/services/editor_store.dart';

import 'helpers.dart';

Cue _cue(int index, int start, int end) =>
    Cue(index: index, startMs: start, endMs: end, source: 's$index');

/// 播放器跟着走的字幕表；这里的播放器是假的，用不到它的内容。
class _Cues extends ChangeNotifier implements PlaybackCues {
  @override
  SubtitleDocument get document => SubtitleDocument.empty;

  @override
  int selected = 0;

  @override
  Cue? get current => null;

  @override
  void select(int indexInDocument) {}
}

void main() {
  group('cueIndexAt', () {
    final cues = [_cue(1, 0, 1000), _cue(2, 1500, 2500), _cue(3, 2000, 3000)];

    test('含开始不含结束，空白处为 null', () {
      expect(cueIndexAt(cues, 0), 0);
      expect(cueIndexAt(cues, 999), 0);
      expect(cueIndexAt(cues, 1000), isNull);
      expect(cueIndexAt(cues, 1500), 1);
      expect(cueIndexAt(cues, 3000), isNull);
    });

    test('重叠段优先当前选中条，播放头不来回跳', () {
      expect(cueIndexAt(cues, 2200), 1);
      expect(cueIndexAt(cues, 2200, preferred: 2), 2);
      // 选中条不含播放头时不影响结果。
      expect(cueIndexAt(cues, 200, preferred: 2), 0);
      expect(cueIndexAt(cues, 200, preferred: 99), 0);
    });
  });

  group('findSiblingMedia', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('preview_media');
    });

    tearDown(() => dir.delete(recursive: true));

    String at(String name) => '${dir.path}${Platform.pathSeparator}$name';

    test('找去掉语言段后同名的音视频，视频优先于音频', () async {
      for (final name in ['ep12.mp3', 'ep12.mp4', 'ep12.zh.srt', 'other.mp4']) {
        await File(at(name)).writeAsString('');
      }
      expect(await findSiblingMedia(at('ep12.zh.srt'), 'ep12'), at('ep12.mp4'));
      await File(at('ep12.mp4')).delete();
      expect(await findSiblingMedia(at('ep12.zh.srt'), 'ep12'), at('ep12.mp3'));
    });

    test('字幕自己的完整主干也算', () async {
      await File(at('talk.en.mkv')).writeAsString('');
      expect(
        await findSiblingMedia(at('talk.en.srt'), 'talk'),
        at('talk.en.mkv'),
      );
    });

    test('没有配套文件或目录不存在时为 null', () async {
      await File(at('a.srt')).writeAsString('');
      expect(await findSiblingMedia(at('a.srt'), 'a'), isNull);
      expect(await findSiblingMedia('/nonexistent/dir/a.srt', 'a'), isNull);
    });
  });

  group('EditorSession.locateMedia', () {
    test('本地会话找旁边的视频，手动关联的文件不存在时重新找', () async {
      final dir = await Directory.systemTemp.createTemp('preview_session');
      addTearDown(() => dir.delete(recursive: true));
      final srt = File('${dir.path}/a.zh.srt')..writeAsStringSync('');
      final mp4 = File('${dir.path}/a.mp4')..writeAsStringSync('');
      final source = LocalSubtitleFile(
        path: srt.path,
        cues: [_cue(1, 0, 1000)],
      );
      final session = FileSession.open(source: source, defaults: _defaults());
      expect(await session.locateMedia(), mp4.path);
      session.mediaPath = '${dir.path}/gone.mp4';
      expect(await session.locateMedia(), mp4.path);
    });

    test('手动关联过的优先于旁边的同名文件；文件没了就回落', () async {
      final dir = await Directory.systemTemp.createTemp('preview_link');
      addTearDown(() => dir.delete(recursive: true));
      final srt = File('${dir.path}/a.srt')..writeAsStringSync('');
      final sibling = File('${dir.path}/a.mp4')..writeAsStringSync('');
      final linked = File('${dir.path}/other.mkv')..writeAsStringSync('');
      FileSession open() => FileSession.open(
        source: LocalSubtitleFile(path: srt.path, cues: [_cue(1, 0, 1000)]),
        defaults: _defaults(),
      );
      expect(await open().locateMedia(linked: linked.path), linked.path);
      expect(
        await open().locateMedia(linked: '${dir.path}/gone.mkv'),
        sibling.path,
      );
    });
  });

  group('EditorMedia', () {
    late Directory dir;
    late EditorStore store;
    late FileSession session;
    late List<String> opened;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('editor_media');
      store = EditorStore('${dir.path}/editor');
      final srt = File('${dir.path}/a.srt')..writeAsStringSync('');
      session = FileSession.open(
        source: LocalSubtitleFile(path: srt.path, cues: [_cue(1, 0, 1000)]),
        defaults: _defaults(),
      );
      opened = [];
    });

    tearDown(() => dir.delete(recursive: true));

    // 不建真播放器：测试环境没有 media_kit 的原生库。
    EditorMedia media() => EditorMedia(
      session: session,
      cues: _Cues(),
      store: store,
      openPlayer: (path) {
        opened.add(path);
        return null;
      },
    );

    test('只找一次：上次手动关联的优先', () async {
      File('${dir.path}/a.mp4').writeAsStringSync('');
      final linked = File('${dir.path}/other.mkv')..writeAsStringSync('');
      await store.saveMediaLink(session.subtitlePath, linked.path);
      final m = media();
      var notified = 0;
      m.addListener(() => notified++);
      await Future.wait([m.locate(), m.locate()]);
      await m.locate();
      expect(m.path, linked.path);
      expect(opened, [linked.path]);
      expect(notified, 1);
      m.dispose();
    });

    test('找不到时不开播放器', () async {
      final m = media();
      await m.locate();
      expect(m.path, isNull);
      expect(opened, isEmpty);
      m.dispose();
    });

    test('手动关联：换上并记下，下次打开同一份字幕直接用', () async {
      File('${dir.path}/a.mp4').writeAsStringSync('');
      final picked = File('${dir.path}/picked.mov')..writeAsStringSync('');
      final m = media();
      // 找的期间用户已经手动关联：以手动的为准，找到的旁边文件不再换上。
      final locating = m.locate();
      await m.attach(picked.path);
      await locating;
      expect(m.path, picked.path);
      expect(session.mediaPath, picked.path);
      expect(opened, [picked.path]);
      expect(await store.loadMediaLink(session.subtitlePath), picked.path);
      m.dispose();
    });

    test('释放后找到的结果不再用', () async {
      File('${dir.path}/a.mp4').writeAsStringSync('');
      final m = media();
      final locating = m.locate();
      m.dispose();
      await locating;
      expect(opened, isEmpty);
    });
  });

  group('EditorStore 的音视频关联', () {
    test('按字幕路径存取，读不到时为 null', () async {
      final dir = await Directory.systemTemp.createTemp('preview_store');
      addTearDown(() => dir.delete(recursive: true));
      final store = EditorStore('${dir.path}/editor');
      expect(await store.loadMediaLink('/x/a.srt'), isNull);
      await store.saveMediaLink('/x/a.srt', '/x/a.mp4');
      await store.saveMediaLink('/x/b.srt', '/x/b.mkv');
      expect(await store.loadMediaLink('/x/a.srt'), '/x/a.mp4');
      expect(await store.loadMediaLink('/x/b.srt'), '/x/b.mkv');
      await store.saveMediaLink('/x/a.srt', '/y/a.mov');
      expect(await store.loadMediaLink('/x/a.srt'), '/y/a.mov');
    });
  });
}

TaskOptions _defaults() => testOptions();
