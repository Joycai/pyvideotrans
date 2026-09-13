import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/services/audio_splitter.dart';
import 'package:subtitle_studio/services/dashscope_asr.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';

const _info = ProviderInfo(
  id: 'dashscope_qwen_asr',
  name: '阿里百炼 · Qwen3-ASR',
  vendor: '阿里百炼',
  defaultBaseUrl: 'https://dashscope.aliyuncs.com/api/v1',
  defaultModel: 'qwen3-asr-flash',
);

Endpoint _endpoint([String model = 'qwen3-asr-flash']) => Endpoint(
  baseUrl: 'https://dashscope.aliyuncs.com/api/v1/',
  model: model,
  apiKey: 'sk-test',
);

/// 不起 ffmpeg：直接把 [count] 个小文件写到 `<音频>.clips/` 里。
class FakeSplitter implements AudioSplitter {
  FakeSplitter(this.count);

  final int count;

  @override
  Future<List<AudioClip>> split(
    String audioPath, {
    required CancellationToken token,
  }) async {
    final dir = Directory('$audioPath.clips')..createSync(recursive: true);
    return [
      for (var i = 0; i < count; i++)
        AudioClip(
          path: (File('${dir.path}/clip_$i.wav')..writeAsBytesSync([i, i, i]))
              .path,
          startMs: i * 1000,
          endMs: i * 1000 + 900,
        ),
    ];
  }
}

String _qwen3Reply(String text) => jsonEncode({
  'output': {
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {
          'role': 'assistant',
          'content': [
            {'text': text},
          ],
          'annotations': [
            {'type': 'audio_info', 'language': 'zh'},
          ],
        },
      },
    ],
  },
  'usage': {'seconds': 1},
  'request_id': 'r',
});

/// http.Response 默认按 Latin-1 编码字符串，中文会炸；按 UTF-8 字节给。
http.Response _ok(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void _noProgress(int done, int total, {String? note}) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String audio;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dashscope_test_');
    audio = '${tmp.path}/a.wav';
    File(audio).writeAsBytesSync([0]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('阿里百炼识别', () {
    test('逐段识别，时间码来自切分点，请求形态是百炼原生报文', () async {
      final requests = <Map<String, Object?>>[];
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://dashscope.aliyuncs.com/api/v1${DashScopeAsrProvider.path}');
        expect(req.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(req.body) as Map<String, Object?>;
        requests.add(body);
        return _ok(_qwen3Reply('第 ${requests.length} 句'));
      });
      final provider = DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(2),
        prompt: '术语：字幕工具',
        client: client,
      );

      final cues = await provider.transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
      );

      expect(cues.map((c) => c.source), ['第 1 句', '第 2 句']);
      expect(cues.map((c) => (c.startMs, c.endMs)), [(0, 900), (1000, 1900)]);
      expect(cues.map((c) => c.index), [1, 2]);

      final body = requests.first;
      expect(body['model'], 'qwen3-asr-flash');
      final messages = ((body['input'] as Map)['messages'] as List);
      expect((messages[0] as Map)['role'], 'system');
      expect(((messages[0] as Map)['content'] as List).first, {'text': '术语：字幕工具'});
      final audioPart = ((messages[1] as Map)['content'] as List).first as Map;
      expect(audioPart['audio'], startsWith('data:audio/wav;base64,'));
      final options = (body['parameters'] as Map)['asr_options'] as Map;
      expect(options, {'language': 'zh', 'enable_lid': true, 'enable_itn': true});

      // 片段目录用完即删。
      expect(Directory('$audio.clips').existsSync(), isFalse);
    });

    test('自动检测不下发 language；没有提示词就没有 system 消息', () async {
      late Map<String, Object?> body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_qwen3Reply('x'));
      });
      await DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(1),
        client: client,
      ).transcribe(
        audioPath: audio,
        language: 'auto',
        token: CancellationToken(),
        onProgress: _noProgress,
      );
      final messages = ((body['input'] as Map)['messages'] as List);
      expect(messages, hasLength(1));
      final options = (body['parameters'] as Map)['asr_options'] as Map;
      expect(options.containsKey('language'), isFalse);
    });

    test('qwen-audio-3.0 / fun-asr 走 input_audio 报文并读 output.text', () async {
      late Map<String, Object?> body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(jsonEncode({'output': {'text': ' 你好 '}}));
      });
      final cues = await DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint('fun-asr-flash-2026-06-15'),
        splitter: FakeSplitter(1),
        client: client,
      ).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
      );
      expect(cues.single.source, '你好');
      final part = ((((body['input'] as Map)['messages'] as List).first as Map)['content'] as List).first as Map;
      expect(part['type'], 'input_audio');
      expect((part['input_audio'] as Map)['data'], startsWith('data:audio/wav;base64,'));
      expect(body['parameters'], {'format': 'wav', 'sample_rate': '16000'});
    });

    test('某段 5xx 先记进检查点，续跑只重试它', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        return n == 1
            ? http.Response('busy', 503)
            : _ok(_qwen3Reply('好的'));
      });
      final provider = DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(2),
        client: client,
      );
      final cp = RecognitionCheckpoint();

      await expectLater(
        provider.transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
          checkpoint: cp,
        ),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.message, 'message', '有 1 段识别失败')
              .having((e) => e.detail, 'detail', contains('HTTP 503')),
        ),
      );
      // 第一段失败、第二段成功，两段都发过请求。
      expect(n, 2);
      expect(cp.doneCount, 1);
      expect(cp.pending.single.failures, 1);

      final notes = <String>[];
      final cues = await provider.transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: (_, _, {note}) => notes.add(note ?? ''),
        checkpoint: cp,
      );
      // 续跑只补第一段。
      expect(n, 3);
      expect(cues.map((c) => c.source), ['好的', '好的']);
      expect(cp.doneCount, 2);
    });

    test('同一段失败 3 次后跳过，留一条空文本、低置信度的占位字幕', () async {
      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final audioPart =
            ((((body['input'] as Map)['messages'] as List).last as Map)['content']
                    as List)
                .first as Map;
        // clip_0 的字节是 [0,0,0]，编码后以 AAAA 开头；这一段永远 503。
        final broken = (audioPart['audio'] as String).endsWith('AAAA');
        return broken ? http.Response('busy', 503) : _ok(_qwen3Reply('好的'));
      });
      final provider = DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(2),
        client: client,
      );
      final cp = RecognitionCheckpoint();
      Future<List<Cue>> run() => provider.transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
        checkpoint: cp,
      );

      await expectLater(run(), throwsA(isA<ProviderException>()));
      await expectLater(run(), throwsA(isA<ProviderException>()));
      final cues = await run();

      expect(cp.skippedCount, 1);
      expect(cues, hasLength(2));
      expect(cues.first.source, '');
      expect(cues.first.confidence, 0);
      expect(cues.first.confidence! < Cue.lowConfidence, isTrue);
      expect(cues.last.source, '好的');
      // 空文本不会写进 SRT。
      expect(Srt.serialize(cues), isNot(contains('00:00:00,000')));
    });

    test('429 立即停，已识别的段留在检查点里', () async {
      var n = 0;
      final client = MockClient((_) async {
        n++;
        return n == 1
            ? _ok(_qwen3Reply('第一段'))
            : http.Response('{"code":"Throttling.RateQuota"}', 429);
      });
      final cp = RecognitionCheckpoint();
      await expectLater(
        DashScopeAsrProvider(
          info: _info,
          endpoint: _endpoint(),
          splitter: FakeSplitter(3),
          client: client,
        ).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
          checkpoint: cp,
        ),
        throwsA(
          isA<ProviderException>().having((e) => e.message, 'message', contains('限流')),
        ),
      );
      // 限流后不再碰第三段；限流不是这一段的错，不计失败。
      expect(n, 2);
      expect(cp.doneCount, 1);
      expect(cp.segment(1000, 1900).failures, 0);
      expect(cp.segment(2000, 2900).failures, 0);
    });

    test('没有人声的片段（400 ASR_RESPONSE_HAVE_NO_WORDS）当作没话，不算错', () async {
      var n = 0;
      final client = MockClient((_) async {
        n++;
        return n == 1
            ? http.Response(
                '{"code":"CLIENT_ERROR","message":"ASR_RESPONSE_HAVE_NO_WORDS"}',
                400,
              )
            : _ok(_qwen3Reply('好的'));
      });
      final cues = await DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(2),
        client: client,
      ).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
      );
      expect(cues.single.source, '好的');
      expect(cues.single.startMs, 1000);
    });
  });

  group('自动重试模式', () {
    DashScopeAsrProvider provider(
      MockClient client, {
      int clips = 3,
      List<Duration>? waits,
    }) => DashScopeAsrProvider(
      info: _info,
      endpoint: _endpoint(),
      splitter: FakeSplitter(clips),
      client: client,
      delay: (d) async => waits?.add(d),
    );

    test('失败的段原地重试，3 次后跳过，一轮跑完', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final part =
            ((((body['input'] as Map)['messages'] as List).last as Map)['content']
                    as List)
                .first as Map;
        final first = (part['audio'] as String).endsWith('AAAA');
        return first ? http.Response('busy', 503) : _ok(_qwen3Reply('好的'));
      });
      final cp = RecognitionCheckpoint()..autoRetry = true;
      final notes = <String>[];
      final cues = await provider(client).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: (_, _, {note}) => notes.add(note ?? ''),
        checkpoint: cp,
      );
      // 第 1 段试了 3 次，其余各 1 次。
      expect(n, 5);
      expect(cp.skippedCount, 1);
      expect(cues.map((c) => c.source), ['', '好的', '好的']);
      expect(notes, contains('第 1 段失败 3 次，已跳过'));
    });

    test('限流时按退避等待再试同一段，不计失败；Retry-After 优先', () async {
      var n = 0;
      final client = MockClient((_) async {
        n++;
        return switch (n) {
          1 => http.Response('{"code":"Throttling.RateQuota"}', 429),
          2 => http.Response(
            '{"code":"Throttling.RateQuota"}',
            429,
            headers: {'retry-after': '7'},
          ),
          _ => _ok(_qwen3Reply('好的')),
        };
      });
      final cp = RecognitionCheckpoint()..autoRetry = true;
      final waits = <Duration>[];
      final notes = <String>[];
      final cues = await provider(client, clips: 1, waits: waits).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: (_, _, {note}) => notes.add(note ?? ''),
        checkpoint: cp,
      );
      expect(cues.single.source, '好的');
      expect(n, 3);
      expect(cp.segment(0, 900).failures, 0);
      // 第一次没有 Retry-After 用阶梯第一档 5 秒，第二次用服务端给的 7 秒。
      expect(waits.fold(Duration.zero, (a, b) => a + b), const Duration(seconds: 12));
      expect(notes, contains('阿里百炼 限流，等待 5 秒后重试第 1 段'));
      expect(notes, contains('阿里百炼 限流，等待 7 秒后重试第 1 段'));
    });

    test('等待中取消能立刻停下', () async {
      final token = CancellationToken();
      final client = MockClient(
        (_) async => http.Response('{"code":"Throttling.RateQuota"}', 429),
      );
      final p = DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(1),
        client: client,
        delay: (_) async => token.cancel(),
      );
      await expectLater(
        p.transcribe(
          audioPath: audio,
          language: 'zh',
          token: token,
          onProgress: _noProgress,
          checkpoint: RecognitionCheckpoint()..autoRetry = true,
        ),
        throwsA(isA<TaskCancelled>()),
      );
    });

    test('鉴权错误在自动模式下也立即停', () async {
      var n = 0;
      final client = MockClient((_) async {
        n++;
        return http.Response('{"code":"InvalidApiKey"}', 401);
      });
      await expectLater(
        provider(client).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
          checkpoint: RecognitionCheckpoint()..autoRetry = true,
        ),
        throwsA(
          isA<ProviderException>().having((e) => e.hint, 'hint', contains('API Key')),
        ),
      );
      expect(n, 1);
    });
  });

  group('阿里百炼识别 · 停止与取消', () {

    test('中途失败时记录少于切分段数，续跑仍沿用检查点', () async {
      var n = 0;
      final client = MockClient((_) async {
        n++;
        // 第一轮：第 1 段成功，第 2 段 401 立即停，第 3 段没跑到。
        if (n == 2) return http.Response('{"code":"InvalidApiKey"}', 401);
        return _ok(_qwen3Reply('好的'));
      });
      final provider = DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(3),
        client: client,
      );
      final cp = RecognitionCheckpoint();
      Future<List<Cue>> run() => provider.transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
        checkpoint: cp,
      );
      await expectLater(run(), throwsA(isA<ProviderException>()));
      expect(cp.length, 2);
      expect(cp.total, 3);
      expect(cp.doneCount, 1);

      final cues = await run();
      // 续跑只补第 2、3 段，第 1 段不再请求。
      expect(n, 4);
      expect(cues, hasLength(3));
      expect(cp.doneCount, 3);
    });

    test('切分点对不上时检查点作废，从头识别', () async {
      final cp = RecognitionCheckpoint()..segment(0, 500).text = '旧的';
      var n = 0;
      final client = MockClient((_) async {
        n++;
        return _ok(_qwen3Reply('新的'));
      });
      final cues = await DashScopeAsrProvider(
        info: _info,
        endpoint: _endpoint(),
        splitter: FakeSplitter(2),
        client: client,
      ).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
        checkpoint: cp,
      );
      expect(n, 2);
      expect(cues.map((c) => c.source), ['新的', '新的']);
      expect(cp.length, 2);
    });

    test('全部段都没返回文本才报「未识别到语音」', () async {
      final client = MockClient((_) async => _ok(_qwen3Reply('')));
      expect(
        () => DashScopeAsrProvider(
          info: _info,
          endpoint: _endpoint(),
          splitter: FakeSplitter(2),
          client: client,
        ).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(
          isA<ProviderException>().having((e) => e.message, 'message', '未识别到语音'),
        ),
      );
    });

    test('401 直接停，并给出核对密钥的建议', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"code":"InvalidApiKey"}', 401);
      });
      await expectLater(
        DashScopeAsrProvider(
          info: _info,
          endpoint: _endpoint(),
          splitter: FakeSplitter(3),
          client: client,
        ).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(
          isA<ProviderException>().having((e) => e.hint, 'hint', contains('API Key')),
        ),
      );
      expect(calls, 1);
      expect(Directory('$audio.clips').existsSync(), isFalse);
    });

    test('取消后不再发请求', () async {
      final token = CancellationToken();
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        token.cancel();
        return _ok(_qwen3Reply('x'));
      });
      await expectLater(
        DashScopeAsrProvider(
          info: _info,
          endpoint: _endpoint(),
          splitter: FakeSplitter(3),
          client: client,
        ).transcribe(
          audioPath: audio,
          language: 'zh',
          token: token,
          onProgress: _noProgress,
        ),
        throwsA(isA<TaskCancelled>()),
      );
      expect(calls, 1);
    });

    test('登记表把它建成独立实现类', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(
        Registry.buildAsr('dashscope_qwen_asr', settings),
        isA<DashScopeAsrProvider>(),
      );
      expect(Registry.asrInfo('dashscope_qwen_asr')!.implemented, isTrue);
    });
  });
}
