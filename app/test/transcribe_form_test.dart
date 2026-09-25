import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/features/tasks/transcribe_form.dart';
import 'package:subtitle_studio/services/ffmpeg.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 可控的探测：每个路径一个 Completer，测试决定什么时候「探完」。
class GatedFfmpeg extends Ffmpeg {
  final gates = <String, Completer<MediaFileInfo>>{};

  @override
  Future<MediaFileInfo> probeFile(String path) =>
      (gates[path] ??= Completer<MediaFileInfo>()).future;

  void finish(String path, {bool exists = true, Duration? duration}) {
    (gates[path] ??= Completer<MediaFileInfo>()).complete(
      MediaFileInfo(
        path: path,
        sizeBytes: 1024,
        duration: duration ?? const Duration(minutes: 1),
        exists: exists,
      ),
    );
  }
}

Future<AppSettings> _settings({bool withKey = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  if (withKey) {
    settings
      ..setConfig('openai', const ProviderConfig(apiKey: 'sk-test'))
      ..setConfig('deepseek', const ProviderConfig(apiKey: 'sk-test'));
  }
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('文件列表', () {
    test('先以「探测中」入列，探完再就绪；探测中不阻断提交', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/a.mp4']);

      expect(form.files.single.state, StagedFileState.probing);
      expect(form.probingCount, 1);
      expect(form.canStart, isTrue);
      expect(form.footer.text, contains('1 个文件仍在探测'));

      media.finish('/v/a.mp4', duration: const Duration(minutes: 3));
      await done;
      expect(form.files.single.state, StagedFileState.ready);
      expect(form.totalDuration, const Duration(minutes: 3));
      expect(form.footer.text, '将创建 1 个转写并翻译任务，加入队列后在任务页查看进度');
    });

    test('读不出来的文件不入队、不计入总数，全都读不出时拦住', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/ok.mp4', '/v/bad.mkv']);
      media.finish('/v/ok.mp4');
      media.finish('/v/bad.mkv', exists: false);
      await done;

      expect(form.unreadableCount, 1);
      expect(form.enqueueable.map((f) => f.path), ['/v/ok.mp4']);
      expect(form.submit()!.paths, ['/v/ok.mp4']);

      form.remove(form.files.first);
      expect(form.canStart, isFalse);
      expect(form.footer.error, isTrue);
      expect(form.footer.text, contains('读不出来'));
    });

    test('探测期间被移除的文件不会再冒出来', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      final done = form.add(['/v/a.mp4']);
      form.remove(form.files.single);
      media.finish('/v/a.mp4');
      await done;
      expect(form.files, isEmpty);
    });

    test('拒收说明压过其他所有文案，清掉后恢复', () async {
      final media = GatedFfmpeg();
      final form = TranscribeFormController(
        settings: await _settings(),
        media: media,
      );
      form.handleDrop(['/v/a.mp4', '/v/sub.srt']);
      expect(form.dropError, '已忽略 1 个字幕文件，字幕请用「新建翻译」');
      expect(form.footer.error, isTrue);
      expect(form.files.map((f) => f.path), ['/v/a.mp4']);

      form.clearDropError();
      expect(form.footer.error, isFalse);
    });
  });

  group('上次参数', () {
    test('提交时记下参数，下次可整份填回', () async {
      final settings = await _settings();
      final media = GatedFfmpeg();
      final form = TranscribeFormController(settings: settings, media: media);
      expect(form.hasLastUsed, isFalse);
      expect(form.applyLastUsed(), isFalse);

      final done = form.add(['/v/a.mp4']);
      media.finish('/v/a.mp4');
      await done;
      form.update(
        (o) => o.copyWith(translate: false, cjkLineLength: 22, asrPrompt: 'X'),
      );
      expect(form.submit(), isNotNull);

      final again = TranscribeFormController(settings: settings, media: media);
      expect(again.options.translate, isTrue);
      expect(again.hasLastUsed, isTrue);
      expect(again.applyLastUsed(), isTrue);
      expect(again.options.translate, isFalse);
      expect(again.options.cjkLineLength, 22);
      expect(again.options.asrPrompt, 'X');

      again.reset();
      expect(again.options.translate, isTrue);
      expect(again.options.cjkLineLength, 15);
    });

    test('不能开始时提交不记参数', () async {
      final settings = await _settings(withKey: false);
      final form = TranscribeFormController(
        settings: settings,
        media: GatedFfmpeg(),
      );
      expect(form.submit(), isNull);
      expect(settings.lastTranscribeOptions, isNull);
    });
  });
}
