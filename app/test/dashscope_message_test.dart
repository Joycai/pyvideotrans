import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/providers/asr_transport.dart';
import 'package:subtitle_studio/domain/providers/model_spec.dart';
import 'package:subtitle_studio/domain/providers/provider_catalog.dart';
import 'package:subtitle_studio/services/dashscope_filetrans.dart';
import 'package:subtitle_studio/services/dashscope_message.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/readiness.dart';
import 'package:subtitle_studio/services/registry.dart';
import 'package:subtitle_studio/services/settings.dart';

void main() {
  final info = ProviderCatalog.asrInfo('dashscope_qwen_asr')!;
  const model = 'qwen-audio-3.1-asr-flash-message';
  late HttpServer server;
  late Directory dir;
  late File audio;
  late DashScopeMessageProvider provider;
  final sockets = <WebSocket>[];
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dir = await Directory.systemTemp.createTemp('message-test');
    audio = File('${dir.path}/audio.wav')..writeAsBytesSync(List.filled(100, 0));
    provider = DashScopeMessageProvider(info: info,
      endpoint: Endpoint(baseUrl: 'http://127.0.0.1:${server.port}/api/v1', model: model, apiKey: 'test'),
      prompt: '专有词');
  });
  tearDown(() async {
    for (final ws in sockets) { unawaited(ws.close()); }
    sockets.clear();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  Future<void> serve(FutureOr<void> Function(WebSocket, dynamic) onEvent, {void Function()? onClosed}) async {
    server.listen((request) async {
      expect(request.uri.path, '/api-ws/v1/inference');
      expect(request.headers.value('authorization'), 'Bearer test');
      final ws = await WebSocketTransformer.upgrade(request);
      sockets.add(ws);
      ws.listen((raw) => onEvent(ws, raw), onDone: onClosed);
    });
  }
  void event(WebSocket ws, String id, String type, [Map<String, Object?> payload = const {}]) {
    ws.add(jsonEncode({'header': {'task_id': id, 'event': type}, 'payload': payload}));
  }
  Future<List<Cue>> run([CancellationToken? token]) => provider.transcribe(
    audioPath: audio.path, language: 'zh', token: token ?? CancellationToken(),
    onProgress: (_, _, {note}) {});

  test('握手、音频、最终句子去重、结束；模型声明可往返', () async {
    var bytes = 0;
    await serve((ws, raw) {
      if (raw is List<int>) { bytes += raw.length; return; }
      final json = jsonDecode(raw as String) as Map;
      final header = json['header'] as Map;
      final id = header['task_id'] as String;
      if (header['action'] == 'run-task') {
        final payload = json['payload'] as Map;
        expect(payload['model'], model);
        expect(payload['parameters'], containsPair('language_hints', ['zh']));
        expect((payload['input'] as Map)['context'], isNotEmpty);
        event(ws, id, 'task-started');
      } else {
        expect(bytes, 100);
        for (final finalResult in [false, true, true]) {
          event(ws, id, 'result-generated', {'output': {'sentence': {
            'sentence_id': 1, 'begin_time': 120, 'end_time': 1700,
            'text': finalResult ? '你好。' : '你', 'sentence_end': finalResult,
          }}});
        }
        event(ws, id, 'task-finished');
      }
    });
    final cues = await run();
    expect(cues, hasLength(1));
    expect(cues.first.source, '你好。');
    expect(cues.first.startMs, 120);
    final spec = info.guess(model);
    expect(spec.transport, AsrTransport.dashscopeMessage);
    expect(ModelSpec.fromJson(spec.toJson()), spec);
  });

  test('服务端提前断连不能当成功', () async {
    await serve((ws, raw) => ws.close());
    await expectLater(run(), throwsA(isA<ActionableException>()));
  });

  test('等待 task-started 时取消会结束并关闭连接', () async {
    final token = CancellationToken();
    final closed = Completer<void>();
    await serve((ws, raw) {
      token.cancel();
    }, onClosed: closed.complete);
    await expectLater(run(token), throwsA(isA<TaskCancelled>()));
    await closed.future.timeout(const Duration(seconds: 2));
  });

  test('服务端不响应会超时', () async {
    provider = DashScopeMessageProvider(info: info, endpoint: Endpoint(
      baseUrl: 'http://127.0.0.1:${server.port}/api/v1', model: model,
      apiKey: 'test', timeout: const Duration(milliseconds: 150)));
    await serve((_, _) {});
    await expectLater(run(), throwsA(isA<ActionableException>().having((e) => e.message, 'message', contains('超时'))));
  });

  test('task-failed 不发布部分结果', () async {
    await serve((ws, raw) {
      final json = jsonDecode(raw as String) as Map;
      ws.add(jsonEncode({'header': {
        'task_id': (json['header'] as Map)['task_id'],
        'event': 'task-failed', 'error_code': 'InvalidParameter',
        'error_message': 'unsupported model',
      }}));
    });
    await expectLater(run(), throwsA(isA<ActionableException>()
      .having((e) => e.detail, 'detail', contains('InvalidParameter'))));
  });

  test('发送过程中取消会关闭连接，不发送 finish-task', () async {
    audio.writeAsBytesSync(List.filled(64000, 0));
    final token = CancellationToken();
    var count = 0;
    await serve((ws, raw) {
      if (raw is List<int>) {
        count += raw.length;
        token.cancel();
        return;
      }
      final json = jsonDecode(raw as String) as Map;
      final header = json['header'] as Map;
      expect(header['action'], 'run-task');
      event(ws, header['task_id'] as String, 'task-started');
    });
    await expectLater(run(token), throwsA(isA<TaskCancelled>()));
    expect(count, greaterThan(0));
    expect(count, lessThan(64000));
  });

  test('三家暂停服务同时被就绪检查与工厂拦截；翻译仍可用', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.asrProviderId, info.id);
    for (final id in ['openai', 'groq', 'siliconflow']) {
      settings.setConfig(id, const ProviderConfig(apiKey: 'test'));
      expect(ProviderCatalog.asrInfo(id)!.available, isFalse);
      expect(ProviderReadiness.asr(id, settings).message, contains('暂时禁用'));
      expect(() => Registry.buildAsr(id, settings, model: ProviderCatalog.defaultAsrSpec(id)),
        throwsA(isA<ActionableException>()));
      expect(settings.configFor(id).apiKey, 'test');
    }
    expect(ProviderCatalog.translationInfo('openai_chat')!.available, isTrue);
    expect(ProviderCatalog.translationInfo('siliconflow_chat')!.available, isTrue);
    final fileSpec = info.guess('qwen-audio-3.1-asr-flash-filetrans');
    final fileProvider = Registry.buildAsr(info.id, settings, model: fileSpec) as DashScopeFileTransProvider;
    expect(fileProvider.submitPayload('oss://test', 'zh')['input'], {'file_urls': ['oss://test']});
    expect(fileSpec.capabilities.diarization, isTrue);
    expect(Registry.buildAsr(info.id, settings, model: info.guess(model)), isA<DashScopeMessageProvider>());
  });
}
