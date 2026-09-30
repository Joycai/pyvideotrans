import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/services/openai_compatible.dart';
import 'package:subtitle_studio/services/provider_api.dart';

// OpenAI 兼容识别的请求形状。这条链路之前没有任何测试：重构服务与模型的
// 配置方式时，靠这里保证「不改设置，发出去的请求一个字段都不变」。

const _info = AsrProviderInfo(
  id: 'test_asr',
  name: '测试',
  vendor: '测试服务',
  defaultBaseUrl: 'https://example.invalid/v1',
);

const _endpoint = Endpoint(
  baseUrl: 'https://example.invalid/v1',
  model: 'whisper-1',
  apiKey: 'k',
);

/// 截下来的一次请求。multipart 的字段直接从请求对象上读，不去解析正文 ——
/// 要钉住的是「发了哪些字段」，不是 http 包怎么拼分隔符。
class _Captured {
  late Uri url;
  late String method;
  late Map<String, String> headers;
  late Map<String, String> fields;
  late List<({String field, String? filename})> files;
  int calls = 0;
}

MockClient _client(_Captured seen, {int status = 200, Object? body}) =>
    MockClient.streaming((request, bodyStream) async {
      // 不读完的话，上传文件的句柄会一直开着。
      await bodyStream.drain<void>();
      final multipart = request as http.MultipartRequest;
      seen
        ..calls += 1
        ..url = multipart.url
        ..method = multipart.method
        ..headers = multipart.headers
        ..fields = Map.of(multipart.fields)
        ..files = [
          for (final f in multipart.files)
            (field: f.field, filename: f.filename),
        ];
      final text = body is String ? body : jsonEncode(body ?? _segments);
      return http.StreamedResponse(
        Stream.value(utf8.encode(text)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

const _segments = {
  'text': '你好 世界',
  'duration': 3.5,
  'segments': [
    {'start': 0.0, 'end': 1.25, 'text': ' 你好 ', 'avg_logprob': 0},
    {'start': 1.25, 'end': 1.5, 'text': '  '},
    {'start': 1.5, 'end': 3.5, 'text': '世界', 'confidence': 0.4},
  ],
};

void main() {
  late Directory dir;
  late String audio;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('openai_asr_test');
    audio = '${dir.path}/audio.wav';
    File(audio).writeAsBytesSync(List.filled(64, 0));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<Cue>> run(
    MockClient client, {
    String prompt = '',
    String language = 'auto',
    CancellationToken? token,
    String? path,
  }) => OpenAiCompatibleAsrProvider(
    info: _info,
    endpoint: _endpoint,
    prompt: prompt,
    client: client,
  ).transcribe(
    audioPath: path ?? audio,
    language: language,
    token: token ?? CancellationToken(),
    onProgress: (_, _, {note}) {},
  );

  group('请求形状', () {
    test('没有提示词、语言自动：只有三个固定字段和一个文件', () async {
      final seen = _Captured();
      await run(_client(seen));

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://example.invalid/v1/audio/transcriptions');
      expect(seen.headers['Authorization'], 'Bearer k');
      // 用整张表比：多发一个字段也算变了。
      expect(seen.fields, {
        'model': 'whisper-1',
        'response_format': 'verbose_json',
        'timestamp_granularities[]': 'segment',
      });
      expect(seen.files, [(field: 'file', filename: 'audio.wav')]);
    });

    test('有提示词才带 prompt，并去掉首尾空白', () async {
      final seen = _Captured();
      await run(_client(seen), prompt: '  Ollama、百炼 \n');
      expect(seen.fields['prompt'], 'Ollama、百炼');

      final blank = _Captured();
      await run(_client(blank), prompt: ' \n ');
      expect(blank.fields.containsKey('prompt'), isFalse);
    });

    test('语言只发主语种的小写代码，auto 与空串不发', () async {
      Future<String?> languageOf(String language) async {
        final seen = _Captured();
        await run(_client(seen), language: language);
        return seen.fields['language'];
      }

      expect(await languageOf('zh-CN'), 'zh');
      expect(await languageOf('EN'), 'en');
      expect(await languageOf('auto'), isNull);
      expect(await languageOf(''), isNull);
    });

    test('提示词与语言都有时一共五个字段', () async {
      final seen = _Captured();
      await run(_client(seen), prompt: '术语', language: 'ja');
      expect(seen.fields, {
        'model': 'whisper-1',
        'response_format': 'verbose_json',
        'timestamp_granularities[]': 'segment',
        'prompt': '术语',
        'language': 'ja',
      });
    });
  });

  group('结果解析', () {
    test('按分段出字幕：秒转毫秒、跳过空段、序号连续', () async {
      final cues = await run(_client(_Captured()), language: 'zh');

      expect(cues.map((c) => (c.index, c.startMs, c.endMs, c.source)), [
        (1, 0, 1250, '你好'),
        (2, 1500, 3500, '世界'),
      ]);
      // avg_logprob 0 → 置信度 1；没有 logprob 时读 confidence。
      expect(cues[0].confidence, 1.0);
      expect(cues[1].confidence, 0.4);
    });

    test('没有分段时退回整段文本，时间码用总时长', () async {
      final cues = await run(
        _client(_Captured(), body: {'text': ' 整段 ', 'duration': 2}),
        language: 'zh',
      );

      expect(cues, hasLength(1));
      expect(cues.single.source, '整段');
      expect((cues.single.startMs, cues.single.endMs), (0, 2000));
    });

    test('既没有分段也没有文本：报「未识别到语音」', () async {
      expect(
        () => run(_client(_Captured(), body: {'text': '', 'segments': []})),
        throwsA(
          isA<ActionableException>().having(
            (e) => e.message,
            'message',
            '未识别到语音',
          ),
        ),
      );
    });
  });

  group('失败与取消', () {
    test('401 给出核对密钥的建议', () async {
      expect(
        () => run(_client(_Captured(), status: 401, body: 'no')),
        throwsA(
          isA<ActionableException>()
              .having((e) => e.message, 'message', contains('拒绝'))
              .having((e) => e.detail, 'detail', contains('HTTP 401'))
              .having((e) => e.hint, 'hint', contains('API 密钥')),
        ),
      );
    });

    test('返回的不是 JSON：提示核对服务地址', () async {
      expect(
        () => run(_client(_Captured(), body: '<html>404</html>')),
        throwsA(
          isA<ActionableException>().having(
            (e) => e.hint,
            'hint',
            contains('服务地址'),
          ),
        ),
      );
    });

    test('已取消的任务不发请求', () async {
      final seen = _Captured();
      await expectLater(
        run(_client(seen), token: CancellationToken()..cancel()),
        throwsA(isA<TaskCancelled>()),
      );
      expect(seen.calls, 0);
    });

    test('音频文件不存在时不发请求', () async {
      final seen = _Captured();
      await expectLater(
        run(_client(seen), path: '${dir.path}/没有.wav'),
        throwsA(
          isA<ActionableException>().having(
            (e) => e.message,
            'message',
            '音频文件不存在',
          ),
        ),
      );
      expect(seen.calls, 0);
    });
  });
}
