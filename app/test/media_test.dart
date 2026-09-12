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

    test('字幕读出条数与时间跨度，不走 ffprobe', () async {
      final srt = File('${dir.path}/a.srt')
        ..writeAsStringSync(
          '1\n00:00:01,000 --> 00:00:02,000\n第一句\n\n'
          '2\n00:00:10,000 --> 00:00:12,500\n第二句\n',
        );
      final info = await Media().probeFile(srt.path);
      expect(info.cueCount, 2);
      expect(info.duration, const Duration(milliseconds: 12500));
      expect(info.isEmptySubtitle, isFalse);
      expect(info.exists, isTrue);
      expect(info.fileName, 'a.srt');
    });

    // 拖进来一个不是字幕的 .srt，要在建任务之前就标出来，
    // 否则跑起来是个空任务，用户等半天才发现。
    test('解析不出内容的字幕标为 0 条', () async {
      final srt = File('${dir.path}/bad.srt')..writeAsStringSync('x' * 2048);
      final info = await Media().probeFile(srt.path);
      expect(info.cueCount, 0);
      expect(info.isEmptySubtitle, isTrue);
      expect(info.duration, isNull);
      expect(info.sizeLabel, '2.0 KB');
    });

    test('非 UTF-8 的字幕仍然数得出条数', () async {
      final srt = File('${dir.path}/latin.srt')
        ..writeAsBytesSync([
          ...'1\n00:00:01,000 --> 00:00:02,000\n'.codeUnits,
          0xE9, 0xE8, // latin1 的 é è，按 UTF-8 解码会抛
          ...'\n'.codeUnits,
        ]);
      final info = await Media().probeFile(srt.path);
      expect(info.cueCount, 1);
    });

    test('音视频没有条数这一项', () async {
      final mp4 = File('${dir.path}/a.mp4')..writeAsStringSync('x');
      expect((await Media().probeFile(mp4.path)).cueCount, isNull);
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
