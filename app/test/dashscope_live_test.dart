@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/services/audio_splitter.dart';
import 'package:subtitle_studio/services/dashscope_asr.dart';
import 'package:subtitle_studio/services/dashscope_filetrans.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';

/// 对真实的百炼服务跑一遍：macOS `say` 合成两句中文，中间留 1.2s 停顿，
/// 期望切成两段并各自识别出文本。密钥来自环境变量，不落盘。
void main() {
  final key = Platform.environment['DASHSCOPE_API_KEY'] ?? '';
  // 专属域名（如 token-plan）可用 DASHSCOPE_BASE_URL 覆盖；
  // DASHSCOPE_MODELS 用逗号列出要跑的模型，不设就跑登记表里的全部。
  final baseUrl =
      Platform.environment['DASHSCOPE_BASE_URL'] ??
      'https://dashscope.aliyuncs.com/api/v1';
  final models = ProviderConfig.splitModels(
    Platform.environment['DASHSCOPE_MODELS'],
  );
  final media = Media();

  test(
    '合成语音 → 切分 → 百炼识别',
    () async {
      final tmp = Directory.systemTemp.createTempSync('dashscope_live_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final aiff = '${tmp.path}/say.aiff';
      final wav = '${tmp.path}/say.wav';
      final say = await Process.run('say', [
        '-v', 'Tingting',
        '-o', aiff,
        '今天天气很好。[[slnc 1200]] 我们去公园散步吧。',
      ]);
      expect(say.exitCode, 0, reason: say.stderr.toString());
      await media.extractAudio(
        sourcePath: aiff,
        outputPath: wav,
        token: CancellationToken(),
      );

      // 登记表里列出的每个模型都真跑一遍：两族报文形态都要能通。
      for (final model in models.isEmpty
          ? Registry.asrInfo('dashscope_qwen_asr')!.models
          : models) {
        final notes = <String>[];
        final provider = DashScopeAsrProvider(
          info: Registry.asrInfo('dashscope_qwen_asr')!,
          endpoint: Endpoint(baseUrl: baseUrl, model: model, apiKey: key),
          splitter: FfmpegAudioSplitter(media),
        );
        final cues = await provider.transcribe(
          audioPath: wav,
          language: 'zh',
          token: CancellationToken(),
          onProgress: (d, t, {note}) => notes.add('$d/$t $note'),
        );

        // ignore: avoid_print
        print('[$model]');
        for (final c in cues) {
          // ignore: avoid_print
          print('  ${c.startMs}–${c.endMs}  ${c.source}');
        }

        expect(cues, isNotEmpty, reason: model);
        expect(cues.map((c) => c.source).join(), contains('天气'), reason: model);
        expect(cues.map((c) => c.source).join(), contains('公园'), reason: model);
      }
    },
    skip: key.isEmpty ? '未设置 DASHSCOPE_API_KEY' : false,
  );

  test(
    '录音文件转写：上传 → 异步任务 → 整份结果带说话人',
    () async {
      final tmp = Directory.systemTemp.createTempSync('dashscope_filetrans_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final wav = '${tmp.path}/dialog.wav';
      final parts = <String>[];
      // 两个都是系统自带、不用额外下载的中文嗓音；Eddy / Flo 这类新嗓音
      // 没装时 say 会静默产出空文件。
      // 一男一女两个系统自带的英文嗓音：两个合成中文女声（Tingting /
      // Meijia）太像，服务端分不开；Eddy / Flo 这类新嗓音没装时 say 会
      // 静默产出空文件。
      for (final (i, (voice, text)) in [
        ('Samantha', "Hi, let's go over the project status today."),
        ('Daniel', "Sure. I'll start with this week's progress, the front end is done."),
        ('Samantha', 'Great, the back end integration is almost finished too.'),
        ('Daniel', "Then let's sync again next Wednesday."),
      ].indexed) {
        final aiff = '${tmp.path}/p$i.aiff';
        final say = await Process.run('say', ['-v', voice, '-o', aiff, text]);
        expect(say.exitCode, 0, reason: say.stderr.toString());
        parts.add(aiff);
      }
      final concat = await Process.run('ffmpeg', [
        '-y', '-loglevel', 'error',
        for (final p in parts) ...['-i', p],
        '-filter_complex', '[0][1][2][3]concat=n=4:v=0:a=1',
        '-ar', '16000', '-ac', '1', wav,
      ]);
      expect(concat.exitCode, 0, reason: concat.stderr.toString());

      final model = models
          .where(DashScopeFileTransProvider.isFileTransModel)
          .firstOrNull ?? 'qwen-audio-3.0-asr-flash-filetrans';
      final notes = <String>[];
      final List<Cue> cues;
      try {
        cues = await DashScopeFileTransProvider(
          info: Registry.asrInfo('dashscope_qwen_asr')!,
          endpoint: Endpoint(baseUrl: baseUrl, model: model, apiKey: key),
          media: media,
          diarize: true,
        ).transcribe(
          audioPath: wav,
          language: 'en',
          token: CancellationToken(),
          onProgress: (d, t, {note}) => notes.add('$d/$t $note'),
        );
      } on ProviderException catch (e) {
        // 失败原因全打出来：服务端的错误码与说明都在 detail 里。
        // ignore: avoid_print
        print('FAILED: ${e.message}\n  detail: ${e.detail}\n  hint: ${e.hint}\n'
            '  notes: ${notes.join(' | ')}');
        rethrow;
      }
      for (final c in cues) {
        // ignore: avoid_print
        print('  ${c.startMs}–${c.endMs}  [说话人${c.speaker}] ${c.source}');
      }
      // ignore: avoid_print
      print(notes.join('\n'));
      expect(cues, isNotEmpty);
      expect(cues.map((c) => c.source).join().toLowerCase(), contains('project'));
      expect(
        cues.map((c) => c.speaker).toSet().length,
        greaterThan(1),
        reason: '应至少分出两位说话人',
      );
    },
    skip: key.isEmpty ? '未设置 DASHSCOPE_API_KEY' : false,
  );
}
