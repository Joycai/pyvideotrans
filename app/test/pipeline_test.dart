import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

const _asrInfo = ProviderInfo(id: 'fake_asr', name: '假识别', vendor: '测试');
const _mtInfo = ProviderInfo(id: 'fake_mt', name: '假翻译', vendor: '测试');

/// 记录调用次数的假识别服务，用来验证续跑时不会重做已完成阶段。
class FakeAsr implements AsrProvider {
  FakeAsr({this.failTimes = 0});

  int calls = 0;
  int failTimes;

  @override
  ProviderInfo get info => _asrInfo;

  @override
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
  }) async {
    calls++;
    if (failTimes-- > 0) {
      throw const ProviderException('识别服务挂了', hint: '稍后重试');
    }
    onProgress(1, 1, note: '完成');
    return const [
      Cue(index: 1, startMs: 0, endMs: 2000, source: '第一句', confidence: 0.95),
      Cue(index: 2, startMs: 2000, endMs: 4000, source: '第二句', confidence: 0.5),
    ];
  }
}

class FakeTranslator implements TranslationProvider {
  FakeTranslator({this.rejectLargerThan, this.failWith});

  final int? rejectLargerThan;
  final ProviderException? failWith;
  final batchSizes = <int>[];
  int calls = 0;

  @override
  ProviderInfo get info => _mtInfo;

  @override
  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  }) async {
    token.throwIfCancelled();
    calls++;
    batchSizes.add(lines.length);
    if (failWith != null) throw failWith!;
    if (rejectLargerThan != null && lines.length > rejectLargerThan!) {
      throw const ProviderException(
        '译文与原文条数对不上',
        hint: '减半重试',
        batchTooLarge: true,
      );
    }
    return [for (final l in lines) 'EN:$l'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;
  late AppSettings settings;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('subtitle_studio_test');
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    settings.outputDir = work.path;
  });

  tearDown(() => work.deleteSync(recursive: true));

  /// 构造一个「翻译已有 SRT」的任务，这条链路不需要 ffmpeg。
  Future<(SubtitleTask, TaskRunner, TranslationProvider)> translateTask({
    TranslationProvider? translator,
    int batchSize = 20,
  }) async {
    final srt = File('${work.path}/in.srt')
      ..writeAsStringSync(
        Srt.serialize([
          for (var i = 1; i <= 5; i++)
            Cue(
              index: i,
              startMs: i * 1000,
              endMs: i * 1000 + 900,
              source: '第 $i 句',
            ),
        ]),
      );

    settings.translationBatchSize = batchSize;
    final mt = translator ?? FakeTranslator();
    final runner = TaskRunner(
      settings: settings,
      workDir: work.path,
      asrFactory: (_, _) => FakeAsr(),
      translationFactory: (_, _) => mt,
    );

    final task = SubtitleTask(
      id: 't1',
      sourcePath: srt.path,
      kind: TaskKind.translate,
      asrProviderId: 'fake_asr',
      translationProviderId: 'fake_mt',
      sourceLanguage: '中文',
      targetLanguage: '英文',
    );
    return (task, runner, mt);
  }

  group('流水线', () {
    test('翻译任务跑完，识别与断句被跳过', () async {
      final (task, runner, _) = await translateTask();
      await runner.run(
        task,
        token: CancellationToken(),
        onChange: () {},
      );

      expect(task.status, TaskStatus.done);
      expect(task.stages[TaskStage.recognize]!.state, StageState.skipped);
      expect(task.stages[TaskStage.segment]!.state, StageState.skipped);
      expect(task.stages[TaskStage.translate]!.state, StageState.done);
      expect(task.document.cues.first.translation, 'EN:第 1 句');
      expect(task.document.untranslatedCount, 0);
    });

    test('写出译文 SRT', () async {
      final (task, runner, _) = await translateTask();
      await runner.run(task, token: CancellationToken(), onChange: () {});

      final out = File('${work.path}/in.英文.srt');
      expect(out.existsSync(), isTrue);
      expect(Srt.parse(out.readAsStringSync()).first.source, 'EN:第 1 句');
    });

    test('条数对不上时把批量减半重试', () async {
      final mt = FakeTranslator(rejectLargerThan: 2);
      final (task, runner, _) = await translateTask(
        translator: mt,
        batchSize: 5,
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.done);
      // 5 条被拒 → 降到 3 被拒 → 降到 2 成功，之后一直用 2。
      expect(mt.batchSizes, [5, 3, 2, 2, 1]);
    });

    test('网络类错误不减半，直接失败并给出建议', () async {
      final mt = FakeTranslator(
        failWith: const ProviderException(
          '无法连接到 测试',
          hint: '检查网络与服务地址',
        ),
      );
      final (task, runner, _) = await translateTask(
        translator: mt,
        batchSize: 5,
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.failed);
      expect(mt.calls, 1);
      expect(task.error!.hint, contains('检查网络'));
      expect(task.stages[TaskStage.translate]!.state, StageState.failed);
      // 准备阶段的结果被保留。
      expect(task.stages[TaskStage.prepare]!.state, StageState.done);
    });

    test('失败后续跑不重做已完成阶段，且保留已翻译的条目', () async {
      // 第一次：翻完前 2 条后失败。
      var allow = 1;
      final mt = _StatefulTranslator(() {
        if (allow-- <= 0) {
          throw const ProviderException('临时故障', hint: '重试');
        }
      });
      final (task, runner, _) = await translateTask(
        translator: mt,
        batchSize: 2,
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.failed);
      expect(task.document.cues.where((c) => c.hasTranslation), hasLength(2));

      // 第二次：从翻译阶段继续，只翻剩下的 3 条。
      allow = 99;
      mt.batchSizes.clear();
      task.stages[TaskStage.translate] = const StageRecord();
      task.status = TaskStatus.queued;
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.done);
      expect(mt.batchSizes.fold(0, (a, b) => a + b), 3);
      expect(task.document.untranslatedCount, 0);
    });

    test('取消时保留已完成阶段，状态为已取消', () async {
      final token = CancellationToken();
      final mt = _StatefulTranslator(() => token.cancel());
      final (task, runner, _) = await translateTask(
        translator: mt,
        batchSize: 2,
      );
      await runner.run(task, token: token, onChange: () {});

      expect(task.status, TaskStatus.cancelled);
      expect(task.stages[TaskStage.prepare]!.state, StageState.done);
      expect(task.stages[TaskStage.translate]!.state, StageState.cancelled);
    });

    test('空字幕文件给出可行动的错误', () async {
      final empty = File('${work.path}/empty.srt')..writeAsStringSync('');
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _) => FakeAsr(),
        translationFactory: (_, _) => FakeTranslator(),
      );
      final task = SubtitleTask(
        id: 't2',
        sourcePath: empty.path,
        kind: TaskKind.translate,
        asrProviderId: 'fake_asr',
        translationProviderId: 'fake_mt',
        sourceLanguage: '中文',
        targetLanguage: '英文',
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.failed);
      expect(task.error!.hint, contains('SRT'));
    });
  });

  group('续跑点', () {
    test('指向第一个未完成且未跳过的阶段', () {
      final task = SubtitleTask(
        id: 't3',
        sourcePath: 'a.mp4',
        kind: TaskKind.transcribe,
        asrProviderId: 'x',
        translationProviderId: 'y',
        sourceLanguage: '中文',
        targetLanguage: '英文',
      );
      task.stages[TaskStage.queued] = const StageRecord(state: StageState.done);
      task.stages[TaskStage.prepare] = const StageRecord(state: StageState.done);
      task.stages[TaskStage.recognize] =
          const StageRecord(state: StageState.failed);

      expect(task.resumeStage, TaskStage.recognize);
    });
  });

  group('队列', () {
    test('串行执行，完成后自动取下一个', () async {
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _) => FakeAsr(),
        translationFactory: (_, _) => FakeTranslator(),
      );
      final queue = TaskQueue(runner: runner, settings: settings);

      for (var i = 0; i < 2; i++) {
        final srt = File('${work.path}/q$i.srt')
          ..writeAsStringSync(
            Srt.serialize([
              Cue(index: 1, startMs: 0, endMs: 1000, source: '句 $i'),
            ]),
          );
        queue.enqueue(
          sourcePath: srt.path,
          kind: TaskKind.translate,
          translationProviderId: 'fake_mt',
        );
      }

      // 等队列跑空。
      for (var i = 0; i < 200 && queue.tasks.any((t) => t.isActive); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(queue.tasks.every((t) => t.status == TaskStatus.done), isTrue);
    });

    test('排队中取消不会再开跑', () async {
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _) => FakeAsr(),
        translationFactory: (_, _) => FakeTranslator(),
      );
      final queue = TaskQueue(runner: runner, settings: settings);
      final task = queue.enqueue(
        sourcePath: '${work.path}/nope.srt',
        kind: TaskKind.translate,
      );
      queue.cancel(task.id);
      expect(task.status, isNot(TaskStatus.done));
    });
  });
}

/// 每批调用前执行一个钩子，用来制造「翻到一半出事」的场景。
class _StatefulTranslator implements TranslationProvider {
  _StatefulTranslator(this.beforeBatch);

  final void Function() beforeBatch;
  final batchSizes = <int>[];

  @override
  ProviderInfo get info => _mtInfo;

  @override
  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  }) async {
    token.throwIfCancelled();
    beforeBatch();
    token.throwIfCancelled();
    batchSizes.add(lines.length);
    return [for (final l in lines) 'EN:$l'];
  }
}
