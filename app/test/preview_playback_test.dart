import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/features/editor/editor_session.dart';
import 'package:subtitle_studio/features/editor/preview_playback.dart';

import 'helpers.dart';

Cue _cue(int index, int start, int end) =>
    Cue(index: index, startMs: start, endMs: end, source: 's$index');

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
  });
}

TaskOptions _defaults() => testOptions();
