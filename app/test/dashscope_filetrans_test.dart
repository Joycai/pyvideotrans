import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/services/dashscope_filetrans.dart';
import 'package:subtitle_studio/services/media.dart';
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

Endpoint _endpoint([String model = 'qwen-audio-3.0-asr-flash-filetrans']) =>
    Endpoint(
      baseUrl: 'https://dashscope.aliyuncs.com/api/v1/',
      model: model,
      apiKey: 'sk-test',
    );

/// 不起 ffprobe。
class _FakeMedia extends Media {
  _FakeMedia([this.duration = const Duration(minutes: 3)]);
  final Duration duration;

  @override
  Future<Duration?> probeDuration(String path) async => duration;
}

http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _policy = {
  'request_id': 'r',
  'data': {
    'policy': 'POLICY',
    'signature': 'SIG',
    'upload_dir': 'dashscope-instant/acc/2026-09-13/x',
    'upload_host': 'https://dashscope-file.oss-cn-beijing.aliyuncs.com',
    'expire_in_seconds': '300',
    'max_file_size_mb': '2048',
    'capacity_limit_mb': '10240',
    'oss_access_key_id': 'LTAI',
    'x_oss_object_acl': 'private',
    'x_oss_forbid_overwrite': 'true',
  },
};

Map<String, Object?> _transcript() => {
  'file_url': 'oss://x',
  'transcripts': [
    {
      'channel_id': 0,
      'text': '你好，我们今天讨论项目进度。好的，我先汇报一下。',
      'sentences': [
        {
          'begin_time': 100,
          'end_time': 3820,
          'text': '你好，我们今天讨论项目进度。',
          'speaker_id': 0,
          'words': [
            {'begin_time': 100, 'end_time': 596, 'text': '你好', 'punctuation': '，'},
            {'begin_time': 600, 'end_time': 3820, 'text': '我们今天讨论项目进度', 'punctuation': '。'},
          ],
        },
        {
          'begin_time': 3820,
          'end_time': 6500,
          'text': '好的，我先汇报一下。',
          'speaker_id': 1,
        },
        // 空句跳过。
        {'begin_time': 6500, 'end_time': 6600, 'text': '  ', 'speaker_id': 1},
      ],
    },
  ],
};

void _noProgress(int done, int total, {String? note}) {}

/// 一套完整的假服务端：凭证 → 上传 → 提交 → 轮询 N 次 → 结果。
class _Server {
  _Server({this.pendingRounds = 1, Map<String, Object?>? transcript})
    : transcript = transcript ?? _transcript();

  final int pendingRounds;
  final Map<String, Object?> transcript;
  final log = <String>[];
  http.Request? submit;
  http.Request? upload;
  int polls = 0;

  MockClient get client => MockClient((req) async {
    final url = req.url.toString();
    log.add('${req.method} $url');
    if (url.contains('/uploads?action=getPolicy')) {
      expect(req.url.queryParameters['model'], endsWith('-filetrans'));
      expect(req.headers['Authorization'], 'Bearer sk-test');
      return _ok(_policy);
    }
    if (url.startsWith('https://dashscope-file.oss')) {
      upload = req;
      return http.Response('', 200);
    }
    if (url.endsWith(DashScopeFileTransProvider.submitPath)) {
      submit = req;
      return _ok({
        'output': {'task_id': 'task-1', 'task_status': 'PENDING'},
        'request_id': 'r',
      });
    }
    if (url.contains('/tasks/task-1')) {
      polls++;
      if (polls <= pendingRounds) {
        return _ok({
          'output': {'task_id': 'task-1', 'task_status': polls == 1 ? 'PENDING' : 'RUNNING'},
        });
      }
      return _ok({
        'output': {
          'task_id': 'task-1',
          'task_status': 'SUCCEEDED',
          'results': [
            {
              'file_url': 'oss://x',
              'subtask_status': 'SUCCEEDED',
              'transcription_url': 'https://result.example/t.json',
            },
          ],
        },
      });
    }
    if (url == 'https://result.example/t.json') {
      expect(req.headers.containsKey('Authorization'), isFalse);
      return _ok(transcript);
    }
    return http.Response('nope', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String audio;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('filetrans_test_');
    audio = '${tmp.path}/a.wav';
    File(audio).writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  DashScopeFileTransProvider build(
    MockClient client, {
    String model = 'qwen-audio-3.0-asr-flash-filetrans',
    bool diarize = true,
    Media? media,
  }) => DashScopeFileTransProvider(
    info: _info,
    endpoint: _endpoint(model),
    media: media ?? _FakeMedia(),
    diarize: diarize,
    client: client,
    delay: (_) async {},
  );

  group('录音文件转写', () {
    test('上传 → 提交 → 轮询 → 下载结果，句子变字幕并带说话人', () async {
      final server = _Server(pendingRounds: 2);
      final notes = <String>[];
      final cp = RecognitionCheckpoint();
      final cues = await build(server.client).transcribe(
        audioPath: audio,
        language: 'zh-CN',
        token: CancellationToken(),
        onProgress: (d, t, {note}) => notes.add('$d/$t $note'),
        checkpoint: cp,
      );

      expect(cues.map((c) => c.source), [
        '你好，我们今天讨论项目进度。',
        '好的，我先汇报一下。',
      ]);
      expect(cues.map((c) => c.speaker), [0, 1]);
      expect(cues.map((c) => (c.startMs, c.endMs)), [(100, 3820), (3820, 6500)]);
      expect(cues.map((c) => c.index), [1, 2]);

      // 上传报文：字段齐全，file 在最后，key 落在 upload_dir 下。
      final up = server.upload!;
      expect(up.headers['content-type'], startsWith('multipart/form-data'));
      final body = utf8.decode(up.bodyBytes, allowMalformed: true);
      final order = [
        'name="OSSAccessKeyId"',
        'name="policy"',
        'name="Signature"',
        'name="key"',
        'name="x-oss-object-acl"',
        'name="x-oss-forbid-overwrite"',
        'name="success_action_status"',
        'name="file"',
      ];
      var last = -1;
      for (final o in order) {
        final i = body.indexOf(o);
        expect(i, greaterThan(last), reason: o);
        last = i;
      }
      final key = RegExp(r'name="key"\r\n\r\n(\S+)').firstMatch(body)!.group(1)!;
      expect(key, startsWith('dashscope-instant/acc/2026-09-13/x/'));
      expect(key, endsWith('_a.wav'));

      // 提交报文：oss 地址、异步头、说话人分离、语言提示。
      final sub = server.submit!;
      expect(sub.headers['X-DashScope-Async'], 'enable');
      expect(sub.headers['X-DashScope-OssResourceResolve'], 'enable');
      final payload = jsonDecode(sub.body) as Map;
      expect(payload['model'], 'qwen-audio-3.0-asr-flash-filetrans');
      expect((payload['input'] as Map)['file_urls'], ['oss://$key']);
      expect(payload['parameters'], {
        'channel_id': [0],
        'enable_words': true,
        'diarization_enabled': true,
        'language_hints': ['zh'],
      });

      expect(server.polls, 3);
      expect(notes.first, contains('上传'));
      expect(notes.where((n) => n.contains('已等待')).length, 2);
      expect(notes.last, contains('下载'));
      // 跑完就清掉任务号，下次是新任务。
      expect(cp.asyncTaskId, isNull);
    });

    test('qwen3 族用 file_url 与 language；不开分离、自动检测时不带这些参数', () async {
      final server = _Server();
      await build(
        server.client,
        model: 'qwen3-asr-flash-filetrans',
        diarize: false,
      ).transcribe(
        audioPath: audio,
        language: 'auto',
        token: CancellationToken(),
        onProgress: _noProgress,
      );
      final payload = jsonDecode(server.submit!.body) as Map;
      expect((payload['input'] as Map).keys, ['file_url']);
      expect(payload['parameters'], {
        'channel_id': [0],
        'enable_words': true,
      });

      final p = build(server.client, model: 'qwen3-asr-flash-filetrans');
      expect(
        p.submitPayload('oss://k', 'ja')['parameters'],
        containsPair('language', 'ja'),
      );
    });

    test('检查点里有任务号就直接轮询，不再上传、不再提交', () async {
      final server = _Server();
      final cp = RecognitionCheckpoint()..asyncTaskId = 'task-1';
      final cues = await build(server.client).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: _noProgress,
        checkpoint: cp,
      );
      expect(cues, hasLength(2));
      expect(server.upload, isNull);
      expect(server.submit, isNull);
      expect(server.log.where((l) => l.contains('/uploads')), isEmpty);
    });

    test('轮询等待时取消能立刻停下，任务号留在检查点里', () async {
      final token = CancellationToken();
      var polls = 0;
      final client = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('getPolicy')) return _ok(_policy);
        if (url.startsWith('https://dashscope-file.oss')) return http.Response('', 200);
        if (url.endsWith(DashScopeFileTransProvider.submitPath)) {
          return _ok({'output': {'task_id': 'task-1', 'task_status': 'PENDING'}});
        }
        polls++;
        token.cancel();
        return _ok({'output': {'task_id': 'task-1', 'task_status': 'RUNNING'}});
      });
      final cp = RecognitionCheckpoint();
      await expectLater(
        build(client).transcribe(
          audioPath: audio,
          language: 'zh',
          token: token,
          onProgress: _noProgress,
          checkpoint: cp,
        ),
        throwsA(isA<TaskCancelled>()),
      );
      expect(polls, 1);
      expect(cp.asyncTaskId, 'task-1');
    });

    test('任务 FAILED 时报服务端给的原因', () async {
      final client = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('getPolicy')) return _ok(_policy);
        if (url.startsWith('https://dashscope-file.oss')) return http.Response('', 200);
        if (url.endsWith(DashScopeFileTransProvider.submitPath)) {
          return _ok({'output': {'task_id': 'task-1', 'task_status': 'PENDING'}});
        }
        return _ok({
          'output': {
            'task_id': 'task-1',
            'task_status': 'FAILED',
            'code': 'InvalidFile.DownloadFailed',
            'message': 'The file url download failed',
          },
        });
      });
      await expectLater(
        build(client).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.message, 'message', contains('失败'))
              .having((e) => e.detail, 'detail', contains('DownloadFailed'))
              .having((e) => e.hint, 'hint', contains('重新上传')),
        ),
      );
    });

    test('鉴权失败与找不到任务各给对应提示', () async {
      final denied = MockClient((req) async => http.Response('{"code":"InvalidApiKey"}', 401));
      await expectLater(
        build(denied).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(isA<ProviderException>().having((e) => e.hint, 'hint', contains('API Key'))),
      );

      final gone = MockClient((req) async => http.Response('{"code":"NotFound"}', 404));
      final cp = RecognitionCheckpoint()..asyncTaskId = 'old';
      await expectLater(
        build(gone).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
          checkpoint: cp,
        ),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('找不到该任务'))),
      );
    });

    test('上传大小超限、时长超限在上传前就拦住', () async {
      final smallPolicy = {
        ..._policy,
        'data': {...(_policy['data'] as Map), 'max_file_size_mb': '0'},
      };
      var uploaded = false;
      final client = MockClient((req) async {
        if (req.url.toString().contains('getPolicy')) return _ok(smallPolicy);
        uploaded = true;
        return http.Response('', 200);
      });
      File(audio).writeAsBytesSync(List.filled(1024 * 1024 + 1, 0));
      await expectLater(
        build(client).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('大小限制'))),
      );
      expect(uploaded, isFalse);

      await expectLater(
        build(client, media: _FakeMedia(const Duration(hours: 13))).transcribe(
          audioPath: audio,
          language: 'zh',
          token: CancellationToken(),
          onProgress: _noProgress,
        ),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('时长上限'))),
      );
    });

    test('开了分离但结果里没有说话人时提示', () async {
      final t = _transcript();
      for (final s in ((t['transcripts'] as List).first as Map)['sentences'] as List) {
        (s as Map).remove('speaker_id');
      }
      final server = _Server(transcript: t);
      final notes = <String>[];
      final cues = await build(server.client).transcribe(
        audioPath: audio,
        language: 'zh',
        token: CancellationToken(),
        onProgress: (d, t, {note}) => notes.add(note ?? ''),
      );
      expect(cues.every((c) => c.speaker == null), isTrue);
      expect(notes.last, contains('没有返回说话人信息'));
    });

    test('长句按词级时间戳再切，词上没有说话人时沿用句级的', () {
      final cues = DashScopeFileTransProvider.parseTranscript({
        'transcripts': [
          {
            'sentences': [
              {
                'begin_time': 0,
                'end_time': 30000,
                'text': 'x',
                'speaker_id': 2,
                'words': [
                  {'begin_time': 0, 'end_time': 1000, 'text': '第一句', 'punctuation': '。'},
                  {'begin_time': 1000, 'end_time': 2000, 'text': '第二句', 'punctuation': '。'},
                ],
              },
            ],
          },
        ],
      });
      expect(cues.map((c) => c.source), ['第一句。', '第二句。']);
      expect(cues.map((c) => c.speaker), [2, 2]);
      expect(cues.map((c) => (c.startMs, c.endMs)), [(0, 1000), (1000, 2000)]);
      expect(DashScopeFileTransProvider.parseTranscript({}), isEmpty);
    });

    test('登记表按模型名后缀选实现类', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load()
        ..setConfig('dashscope_qwen_asr', const ProviderConfig(apiKey: 'sk'));
      expect(
        Registry.buildAsr(
          'dashscope_qwen_asr',
          settings,
          model: 'qwen3-asr-flash-filetrans',
          media: _FakeMedia(),
        ),
        isA<DashScopeFileTransProvider>(),
      );
      expect(
        Registry.buildAsr(
          'dashscope_qwen_asr',
          settings,
          model: 'qwen-audio-3.0-asr-flash',
          media: _FakeMedia(),
        ),
        isNot(isA<DashScopeFileTransProvider>()),
      );
    });
  });
}
