@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/services/audio_splitter.dart';
import 'package:subtitle_studio/services/dashscope_asr.dart';
import 'package:subtitle_studio/services/media.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';

/// 对真实的百炼服务跑一遍：macOS `say` 合成两句中文，中间留 1.2s 停顿，
/// 期望切成两段并各自识别出文本。密钥来自环境变量，不落盘。
void main() {
  final key = Platform.environment['DASHSCOPE_API_KEY'] ?? '';
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
      for (final model in Registry.asrInfo('dashscope_qwen_asr')!.models) {
        final notes = <String>[];
        final provider = DashScopeAsrProvider(
          info: Registry.asrInfo('dashscope_qwen_asr')!,
          endpoint: Endpoint(
            baseUrl: 'https://dashscope.aliyuncs.com/api/v1',
            model: model,
            apiKey: key,
          ),
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
}
