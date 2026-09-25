import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/recognition_checkpoint.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';

import 'helpers.dart';

const _asrInfo = ProviderInfo(id: 'fake_asr', name: '假识别', vendor: '测试');
const _mtInfo = ProviderInfo(id: 'fake_mt', name: '假翻译', vendor: '测试');

/// 记录调用次数的假识别服务，用来验证续跑时不会重做已完成阶段。
/// 不碰 ffmpeg 的假实现 —— 转写链路的前两阶段只关心「有没有产出音频」。
class FakeMedia extends Media {
  @override
  Future<Duration?> probeDuration(String path) async =>
      const Duration(seconds: 42);

  @override
  Future<String> extractAudio({
    required String sourcePath,
    required String outputPath,
    required CancellationToken token,
  }) async {
    await File(outputPath).writeAsString('not really audio');
    return outputPath;
  }
}

class FakeAsr implements AsrProvider {
  FakeAsr({this.failTimes = 0, this.cues});

  /// 覆盖返回的识别结果，用来构造「需要合并的短句」这类场景。
  final List<Cue>? cues;

  int calls = 0;
  int failTimes;

  /// 记下最后一次收到的语言，用来核对下发的是代码而不是中文名。
  String? lastLanguage;

  /// 每次收到的检查点，用来核对续跑时交回的是同一份。
  final checkpoints = <RecognitionCheckpoint?>[];

  @override
  ProviderInfo get info => _asrInfo;

  @override
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
    RecognitionCheckpoint? checkpoint,
  }) async {
    calls++;
    lastLanguage = language;
    checkpoints.add(checkpoint);
    if (failTimes-- > 0) {
      // 失败前已经识别了一段，记进检查点。
      checkpoint?.segment(0, 2000).text = '第一句';
      throw const ProviderException('识别服务挂了', hint: '稍后重试');
    }
    onProgress(1, 1, note: '完成');
    if (cues != null) return cues!;
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

class _BlockingRunner extends TaskRunner {
  _BlockingRunner({required super.settings, required super.workDir});

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

    final mt = translator ?? FakeTranslator();
    final runner = TaskRunner(
      settings: settings,
      workDir: work.path,
      asrFactory: (_, _, _) => FakeAsr(),
      translationFactory: (_, _, _) => mt,
    );

    final task = SubtitleTask(
      id: 't1',
      sourcePath: srt.path,
      kind: TaskKind.translate,
      options: testOptions(
        asr: 'fake_asr',
        mt: 'fake_mt',
        source: 'zh',
        target: 'en',
        batchSize: batchSize,
        outputLocation: OutputLocation.custom,
        outputDir: work.path,
      ),
    );
    return (task, runner, mt);
  }

  group('流水线', () {
    test('翻译任务跑完，识别与断句被跳过', () async {
      final (task, runner, _) = await translateTask();
      await runner.run(task, token: CancellationToken(), onChange: () {});

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

      final out = File('${work.path}/in.en.srt');
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
        failWith: const ProviderException('无法连接到 测试', hint: '检查网络与服务地址'),
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
      final mt = _StatefulTranslator(token.cancel);
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
        asrFactory: (_, _, _) => FakeAsr(),
        translationFactory: (_, _, _) => FakeTranslator(),
      );
      final task = SubtitleTask(
        id: 't2',
        sourcePath: empty.path,
        kind: TaskKind.translate,
        options: testOptions(
          asr: 'fake_asr',
          mt: 'fake_mt',
          source: 'zh',
          target: 'en',
        ),
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.failed);
      expect(task.error!.hint, contains('SRT'));
    });
  });

  group('转写链路', () {
    Future<(SubtitleTask, TaskRunner, FakeAsr)> transcribeTask({
      String source = 'zh',
      bool translate = false,
      List<Cue>? cues,
    }) async {
      final video = File('${work.path}/demo.mp4')..writeAsStringSync('x');
      final asr = FakeAsr(cues: cues);
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        media: FakeMedia(),
        asrFactory: (_, _, _) => asr,
        translationFactory: (_, _, _) => FakeTranslator(),
      );
      final task = SubtitleTask(
        id: 'tr1',
        sourcePath: video.path,
        kind: translate ? TaskKind.transcribeAndTranslate : TaskKind.transcribe,
        options: testOptions(
          source: source,
          translate: translate,
          outputLocation: OutputLocation.custom,
          outputDir: work.path,
        ),
      );
      return (task, runner, asr);
    }

    // 识别接口要的是 ISO 代码；把界面上的中文名直接发过去会被服务端拒掉。
    test('下发给识别服务的是语言代码，不是中文名', () async {
      final (task, runner, asr) = await transcribeTask(source: 'zh');
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(asr.lastLanguage, 'zh');
    });

    test('自动检测时把 auto 原样交给服务端自己判断', () async {
      final (task, runner, asr) = await transcribeTask(source: 'auto');
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(asr.lastLanguage, 'auto');
    });

    /// 两条紧邻的短句，断句阶段应当并成一条。
    List<Cue> shortPair(String a, String b) => [
      Cue(index: 1, startMs: 0, endMs: 300, source: a),
      Cue(index: 2, startMs: 400, endMs: 700, source: b),
    ];

    // 之前这里拿界面上的中文名去和 'zh' 做前缀匹配，永远匹配不上，
    // 于是中文字幕合并后中间多出一个空格。
    test('中文合并短句不加空格', () async {
      final (task, runner, _) = await transcribeTask(
        source: 'zh',
        cues: shortPair('你好', '世界'),
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(task.document.cues, hasLength(1));
      expect(task.document.cues.first.source, '你好世界');
    });

    test('西文合并短句要加空格', () async {
      final (task, runner, _) = await transcribeTask(
        source: 'en',
        cues: shortPair('hello', 'world'),
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(task.document.cues.first.source, 'hello world');
    });

    test('识别被跳过的空字幕不送去翻译，导出时在日志里提示', () async {
      final (task, runner, _) = await transcribeTask(
        translate: true,
        cues: const [
          Cue(index: 1, startMs: 0, endMs: 2000, source: '第一句'),
          Cue(index: 2, startMs: 2000, endMs: 4000, source: '', confidence: 0),
        ],
      );
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(task.status, TaskStatus.done);
      expect(task.document.cues[0].translation, 'EN:第一句');
      expect(task.document.cues[1].translation, isNull);
      expect(
        task.log.any(
          (l) => l.level == LogLevel.warn && l.message.contains('有 1 条字幕原文为空'),
        ),
        isTrue,
      );
    });

    test('识别失败后续跑，检查点原样交回，完成后清掉', () async {
      final (task, runner, asr) = await transcribeTask();
      asr.failTimes = 1;
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(task.status, TaskStatus.failed);
      expect(task.recognition, isNotNull);
      expect(task.recognition!.doneCount, 1);

      // 与队列 resume 相同的复位：失败的阶段退回待执行，检查点不动。
      task.status = TaskStatus.queued;
      task.error = null;
      task.stages[TaskStage.recognize] = const StageRecord();
      await runner.run(task, token: CancellationToken(), onChange: () {});

      expect(task.status, TaskStatus.done);
      expect(asr.checkpoints, hasLength(2));
      expect(identical(asr.checkpoints[0], asr.checkpoints[1]), isTrue);
      expect(task.recognition, isNull);
      expect(task.log.any((l) => l.message.contains('识别续跑：1 段已完成')), isTrue);
    });

    test('不翻译时跳过翻译阶段，只写出原文', () async {
      final (task, runner, _) = await transcribeTask();
      await runner.run(task, token: CancellationToken(), onChange: () {});
      expect(task.status, TaskStatus.done);
      expect(task.stages[TaskStage.translate]!.state, StageState.skipped);
      expect(File('${work.path}/demo.zh.srt').existsSync(), isTrue);
      expect(File('${work.path}/demo.en.srt').existsSync(), isFalse);
    });
  });

  group('续跑点', () {
    test('指向第一个未完成且未跳过的阶段', () {
      final task = SubtitleTask(
        id: 't3',
        sourcePath: 'a.mp4',
        kind: TaskKind.transcribe,
        options: testOptions(asr: 'x', mt: 'y', source: 'zh', target: 'en'),
      );
      task.stages[TaskStage.queued] = const StageRecord(state: StageState.done);
      task.stages[TaskStage.prepare] = const StageRecord(
        state: StageState.done,
      );
      task.stages[TaskStage.recognize] = const StageRecord(
        state: StageState.failed,
      );

      expect(task.resumeStage, TaskStage.recognize);
    });
  });

  group('队列', () {
    test('插队任务会在当前任务完成后优先执行', () async {
      final runner = _BlockingRunner(settings: settings, workDir: work.path);
      final queue = TaskQueue(runner: runner, settings: settings);
      final first = queue.enqueue(sourcePath: '/v/first.srt');
      await runner.started.future;
      final second = queue.enqueue(sourcePath: '/v/second.srt');

      queue.prioritize(second.id);
      expect(queue.tasks.last.id, second.id);

      runner.release.complete();
      for (var i = 0; i < 100 && queue.running != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(first.status, TaskStatus.done);
    });

    test('串行执行，完成后自动取下一个', () async {
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _, _) => FakeAsr(),
        translationFactory: (_, _, _) => FakeTranslator(),
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
          options: testOptions(mt: 'fake_mt'),
        );
      }

      // 等队列跑空。
      for (var i = 0; i < 200 && queue.tasks.any((t) => t.isActive); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(queue.tasks.every((t) => t.status == TaskStatus.done), isTrue);
    });

    test('「自动重试」在检查点上打开自动模式，普通续跑关掉', () async {
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _, _) => FakeAsr(),
        translationFactory: (_, _, _) => FakeTranslator(),
      );
      final queue = TaskQueue(runner: runner, settings: settings);
      final task = queue.enqueue(
        sourcePath: '${work.path}/nope.mp4',
        options: testOptions(translate: false),
      );
      // 等它因为文件不存在而失败。
      for (var i = 0; i < 200 && task.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(task.status, TaskStatus.failed);
      queue.cancel(task.id);

      queue.resumeAuto(task.id);
      expect(task.recognition?.autoRetry, isTrue);
      expect(task.log.any((l) => l.message.startsWith('自动重试：')), isTrue);
      queue.cancel(task.id);
      for (var i = 0; i < 200 && task.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      queue.resume(task.id);
      expect(task.recognition?.autoRetry ?? false, isFalse);
      queue.cancel(task.id);
      for (var i = 0; i < 200 && task.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    test('排队中取消不会再开跑', () async {
      final runner = TaskRunner(
        settings: settings,
        workDir: work.path,
        asrFactory: (_, _, _) => FakeAsr(),
        translationFactory: (_, _, _) => FakeTranslator(),
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

  group('产物写出', () {
    TaskRunner runner() => TaskRunner(
      settings: settings,
      workDir: work.path,
      asrFactory: (_, _, _) => FakeAsr(),
      translationFactory: (_, _, _) => FakeTranslator(),
    );

    SubtitleTask done({
      required TaskKind kind,
      BilingualLayout bilingual = BilingualLayout.targetOnly,
      SubtitleFormat format = SubtitleFormat.srt,
    }) {
      final srt = File('${work.path}/demo.srt')..writeAsStringSync('x');
      return SubtitleTask(
        id: 'w1',
        sourcePath: srt.path,
        kind: kind,
        options: testOptions(
          source: 'zh',
          target: 'en',
          bilingual: bilingual,
          format: format,
          outputLocation: OutputLocation.custom,
          outputDir: work.path,
        ),
        document: const SubtitleDocument(
          cues: [
            Cue(
              index: 1,
              startMs: 0,
              endMs: 1000,
              source: '第一句',
              translation: 'Line one',
            ),
          ],
        ),
      );
    }

    List<String> names(List<String> paths) =>
        [for (final p in paths) p.split('/').last]..sort();

    // 纯翻译任务的原文就是用户选的那个文件，再写一份只是重复。
    test('纯翻译任务只写译文，不复制一份原文', () async {
      final written = await runner().writeOutputs(
        done(kind: TaskKind.translate),
      );
      expect(names(written), ['demo.en.srt']);
    });

    test('转写并翻译时原文与译文各一份', () async {
      final written = await runner().writeOutputs(
        done(kind: TaskKind.transcribeAndTranslate),
      );
      expect(names(written), ['demo.en.srt', 'demo.zh.srt']);
    });

    test('双语产物带上两种语言，与单语那份区分得开', () async {
      final written = await runner().writeOutputs(
        done(kind: TaskKind.translate, bilingual: BilingualLayout.targetAbove),
      );
      expect(names(written), ['demo.zh-en.srt']);
      expect(
        File(written.single).readAsStringSync(),
        contains('Line one\n第一句'),
      );
    });

    test('译文在下时上下颠倒', () async {
      final written = await runner().writeOutputs(
        done(kind: TaskKind.translate, bilingual: BilingualLayout.targetBelow),
      );
      expect(
        File(written.single).readAsStringSync(),
        contains('第一句\nLine one'),
      );
    });

    // 纯文本没有「两行」的概念，界面会灰显这一项，这里再兜一次底。
    test('纯文本格式下双语回落到仅译文', () async {
      final written = await runner().writeOutputs(
        done(
          kind: TaskKind.translate,
          bilingual: BilingualLayout.targetAbove,
          format: SubtitleFormat.txt,
        ),
      );
      expect(names(written), ['demo.en.txt']);
      expect(File(written.single).readAsStringSync().trim(), 'Line one');
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
