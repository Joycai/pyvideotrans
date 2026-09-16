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

  // 投放目录是 Windows 用户的主要出路：设置页开这个文件夹，把可执行文件拖进去。
  // 这些用例不碰真实 ffmpeg —— 查找只看文件在不在，建个空文件就够，
  // 因此在装了和没装 ffmpeg 的机器上结果一样。
  group('查找 ffmpeg', () {
    late Directory dropIn;
    late Directory other;
    final original = Media.dropInDir;

    setUp(() async {
      dropIn = await Directory.systemTemp.createTemp('subtitle_studio_dropin');
      other = await Directory.systemTemp.createTemp('subtitle_studio_dropin2');
      Media.dropInDir = dropIn.path;
    });
    tearDown(() {
      // 静态量，不还原会污染同一个 isolate 里后面的用例。
      Media.dropInDir = original;
      dropIn.deleteSync(recursive: true);
      other.deleteSync(recursive: true);
    });

    File place(Directory dir) =>
        File('${dir.path}${Platform.pathSeparator}${Media.dropInNames.first}')
          ..writeAsStringSync('');

    // 用户特意放进来的那份，就该盖过系统里和随包带的。
    test('投放目录优先于其他位置', () {
      final placed = place(dropIn);
      expect(Media().ffmpeg, placed.path);
    });

    test('投放目录是空的就继续往下找', () {
      final placed = '${dropIn.path}${Platform.pathSeparator}'
          '${Media.dropInNames.first}';
      expect(Media().ffmpegOrNull, isNot(placed));
    });

    // 「放进去 → 重新检测」这条路必须真的生效：找到过一次之后结果会缓存住，
    // 不作废它，换了文件也还是用旧的。
    test('reset 之后改用新投放的那份', () {
      final first = place(dropIn);
      final media = Media();
      expect(media.ffmpeg, first.path);

      Media.dropInDir = other.path;
      final second = place(other);
      expect(media.ffmpeg, first.path, reason: '没 reset 前应该还用缓存');

      media.reset();
      expect(media.ffmpeg, second.path);
    });

    // 构造时显式指定的路径是「就用这一份」的意思，reset 不该把它一起清掉。
    test('reset 退回构造时指定的路径', () {
      final media = Media(ffmpegPath: '/x/ffmpeg', ffprobePath: '/x/ffprobe');
      media.reset();
      expect(media.ffmpeg, '/x/ffmpeg');
      expect(media.ffprobe, '/x/ffprobe');
    });

    // ffmpeg 有、ffprobe 没有是最难懂的半坏状态：抽音能跑，读时长却失败。
    // 界面照着 dropInNames 提示要放哪几个文件，两个名字都得在。
    test('提示要放的文件名包含 ffmpeg 与 ffprobe', () {
      expect(Media.dropInNames, hasLength(2));
      expect(Media.dropInNames.first, contains('ffmpeg'));
      expect(Media.dropInNames.last, contains('ffprobe'));
    });
  });
}
