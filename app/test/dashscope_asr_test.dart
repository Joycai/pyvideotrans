import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    test('某段 5xx 跳过继续，全部失败才报错', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        return n == 1
            ? http.Response('busy', 503)
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

      final allFail = MockClient((_) async => http.Response('busy', 503));
      expect(
        () => DashScopeAsrProvider(
          info: _info,
          endpoint: _endpoint(),
          splitter: FakeSplitter(2),
          client: allFail,
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
