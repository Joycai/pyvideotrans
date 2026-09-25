import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 第一个任务停在运行中，直到测试放行 —— 好让队列里同时有运行中与排队中的任务。
class _BlockingRunner extends TaskRunner {
  _BlockingRunner({required super.settings}) : super(workDir: '/unused');

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> run(
    SubtitleTask task, {
    required CancellationToken token,
    required void Function() onChange,
  }) async {
    task.status = TaskStatus.running;
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    task.status = TaskStatus.done;
  }
}

void main() {
  late AppSettings settings;
  late _BlockingRunner runner;
  late TaskQueue queue;
  // 显式给路径：不依赖这台机器装没装 ffmpeg。
  final media = Media(ffmpegPath: '/x/ffmpeg', ffprobePath: '/x/ffprobe');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    runner = _BlockingRunner(settings: settings);
    queue = TaskQueue(runner: runner, settings: settings);
  });

  tearDown(() {
    if (!runner.release.isCompleted) runner.release.complete();
  });

  StatusSnapshot snapshot({String? note}) => StatusSnapshot.from(
    settings: settings,
    media: media,
    queue: queue,
    note: note,
  );

  test('服务三种状态：未选择、未配置、已配置', () {
    settings
      ..asrProviderId = 'no_such_asr'
      ..translationProviderId = 'deepseek';
    var s = snapshot();
    expect(s.ffmpeg, 'ffmpeg · 就绪');
    expect(s.asr, (connected: false, label: '识别 · 未选择'));
    // 要密钥而没填。
    expect(s.translation.connected, isFalse);
    expect(s.translation.label, endsWith(' · 未配置'));

    settings
      ..asrProviderId = 'openai'
      ..translationProviderId = 'ollama';
    s = snapshot();
    expect(s.asr.connected, isFalse);
    // 本机服务不要密钥，地址与模型有默认值，开箱即算配好。
    expect(s.translation, (connected: true, label: 'Ollama · 已配置'));

    settings.setConfig('openai', const ProviderConfig(apiKey: 'sk-test'));
    expect(snapshot().asr.connected, isTrue);
    expect(snapshot().asr.label, endsWith(' · 已配置'));
  });

  test('运行中与排队中都算进任务数；备注原样带上', () async {
    expect(snapshot().runningTasks, 0);
    queue.enqueue(sourcePath: '/v/a.srt');
    await runner.started.future;
    queue.enqueue(sourcePath: '/v/b.srt');
    final s = snapshot(note: '未保存 3 处修改');
    expect(s.runningTasks, 2);
    expect(s.note, '未保存 3 处修改');
  });
}
