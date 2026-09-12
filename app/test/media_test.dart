import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/media_kinds.dart';
import 'package:subtitle_studio/services/media.dart';

void main() {
  group('文件类型', () {
    test('按扩展名分辨媒体与字幕', () {
      expect(MediaKinds.isMedia('/a/b/c.MP4'), isTrue);
      expect(MediaKinds.isMedia('/a/b/c.m4a'), isTrue);
      expect(MediaKinds.isSubtitle('/a/b/c.srt'), isTrue);
      expect(MediaKinds.isSupported('/a/b/c.pdf'), isFalse);
    });

    // 目录名里带点、或者文件根本没有扩展名时，不能误判成支持的类型。
    test('目录里的点不算扩展名', () {
      expect(MediaKinds.extensionOf('/a.mp4/b/c'), '');
      expect(MediaKinds.isSupported('/a.mp4/b/c'), isFalse);
    });
  });

  group('文件信息', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('subtitle_studio_media');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('读得到大小；字幕不去探时长', () async {
      final srt = File('${dir.path}/a.srt')..writeAsStringSync('x' * 2048);
      final info = await Media().probeFile(srt.path);
      expect(info.sizeBytes, 2048);
      expect(info.duration, isNull);
      expect(info.exists, isTrue);
      expect(info.fileName, 'a.srt');
      expect(info.sizeLabel, '2.0 KB');
    });

    // 文件列表显示不出信息不该拦着用户建任务，真正的报错留给准备阶段。
    test('文件不存在时不抛异常', () async {
      final info = await Media().probeFile('${dir.path}/nope.mp4');
      expect(info.exists, isFalse);
      expect(info.sizeBytes, 0);
      expect(info.sizeLabel, '—');
    });
  });
}
