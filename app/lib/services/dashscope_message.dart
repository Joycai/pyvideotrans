import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/cue.dart';
import '../domain/recognition_checkpoint.dart';
import 'provider_api.dart';
import 'qwen_asr_enhancement.dart';

/// Message 是双向 WebSocket 协议，不能发到同步 generation 接口。
/// 文件按接近实时的速率发送；只接收最终句子，避免中间结果重复进字幕。
class DashScopeMessageProvider implements AsrProvider {
  DashScopeMessageProvider({
    required this.info,
    required this.endpoint,
    this.prompt = '',
    this.vocabulary = const {},
  });

  @override
  final ProviderInfo info;
  final Endpoint endpoint;
  final String prompt;
  final Map<String, int> vocabulary;

  Uri get socketUri {
    final base = Uri.parse(endpoint.baseUrl);
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '')
        .replaceFirst(RegExp(r'/api/v1$'), '');
    return base.replace(
      scheme: base.scheme == 'http' || base.scheme == 'ws' ? 'ws' : 'wss',
      path: '$prefix/api-ws/v1/inference',
      query: null,
      fragment: null,
    );
  }

  Map<String, Object?> startPayload(String taskId, String language) {
    final code = language.split('-').first.toLowerCase();
    return {
      'header': {'action': 'run-task', 'task_id': taskId, 'streaming': 'duplex'},
      'payload': {
        'task_group': 'audio', 'task': 'asr', 'function': 'recognition',
        'model': endpoint.model,
        'parameters': {
          'format': 'wav', 'sample_rate': 16000,
          'intermediate_result_enabled': false,
          'heartbeat': true,
          if (vocabulary.isNotEmpty) 'vocabulary': vocabulary,
          if (code.isNotEmpty && code != 'auto') 'language_hints': [code],
        },
        'input': {
          if (prompt.trim().isNotEmpty)
            'context': QwenAsrEnhancement.context(prompt),
        },
      },
    };
  }

  @override
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
    RecognitionCheckpoint? checkpoint,
  }) async {
    token.throwIfCancelled();
    final file = File(audioPath);
    if (!file.existsSync()) throw const ActionableException('音频文件不存在');
    final client = HttpClient();
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    Future<void>? sending;
    final done = Completer<void>();
    // 提前安装错误监听，连接尚未建立时取消也不会产生未处理异常。
    final completion = done.future;
    unawaited(completion.catchError((Object _) {}));
    // 只有服务端响应才重置超时；本地写入缓冲区不代表对端仍在处理。
    var lastActivity = DateTime.now();
    var started = false;
    var sent = false;
    final sentences = <int, Cue>{};
    void fail(Object error) {
      if (!done.isCompleted) done.completeError(error);
    }
    final watch = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (token.isCancelled) {
        fail(const TaskCancelled());
        client.close(force: true);
        unawaited(socket?.close());
      } else if (DateTime.now().difference(lastActivity) > endpoint.timeout) {
        fail(const ActionableException('流式识别响应超时', hint: '检查连接后重试；本次流式识别将从头开始。'));
        client.close(force: true);
        unawaited(socket?.close());
      }
    });
    try {
      onProgress(0, 1, note: '连接流式识别服务');
      final connection = WebSocket.connect(socketUri.toString(),
        headers: endpoint.authHeaders, customClient: client);
      // 取消或超时后若握手才完成，也立即关闭迟到的连接。
      unawaited(connection.then((ws) {
        if (done.isCompleted) unawaited(ws.close());
      }, onError: (Object _) {}));
      socket = await Future.any<WebSocket>([
        connection,
        completion.then<WebSocket>((_) => throw const TaskCancelled()),
      ]);
      token.throwIfCancelled();
      final ws = socket;
      final taskId = const Uuid().v4();
      Future<void> sendAudio() async {
        final audio = await file.open();
        var offset = 0;
        try {
          final total = await audio.length();
          while (!done.isCompleted) {
            token.throwIfCancelled();
            final bytes = await audio.read(3200);
            token.throwIfCancelled();
            if (done.isCompleted) return;
            if (bytes.isEmpty) break;
            ws.add(bytes);
            offset += bytes.length;
            onProgress(offset, total, note: '流式识别音频');
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (done.isCompleted) return;
          sent = true;
          ws.add(jsonEncode({
            'header': {'action': 'finish-task', 'task_id': taskId, 'streaming': 'duplex'},
            'payload': {'input': <String, Object?>{}},
          }));
        } finally {
          await audio.close();
        }
      }
      subscription = ws.listen((raw) {
        if (done.isCompleted) return;
        try {
          final event = jsonDecode(raw as String) as Map;
          final header = event['header'] as Map;
          if (header['task_id'] != taskId) return;
          lastActivity = DateTime.now();
          switch (header['event']) {
            case 'task-started':
              if (!started) {
                started = true;
                sending = sendAudio().catchError(fail);
              }
            case 'result-generated':
              final payload = event['payload'] as Map?;
              final output = payload?['output'] as Map?;
              final sentence = output?['sentence'];
              if (sentence is! Map || sentence['heartbeat'] == true ||
                  sentence['sentence_end'] != true) {
                return;
              }
              final text = (sentence['text'] as String?)?.trim() ?? '';
              if (text.isEmpty) return;
              final start = sentence['begin_time'];
              final end = sentence['end_time'];
              final id = sentence['sentence_id'];
              if (start is! int || end is! int || id is! int || start < 0 || end <= start) {
                throw const FormatException('无效的句级时间戳');
              }
              sentences[id] = Cue(index: id, startMs: start, endMs: end, source: text);
            case 'task-finished':
              if (!sent) throw const FormatException('音频发送完成前任务已结束');
              done.complete();
            case 'task-failed':
              fail(ActionableException('流式识别失败',
                detail: '${header['error_code']}：${header['error_message']}',
                hint: '核对模型、服务地址和密钥后重试。'));
          }
        } catch (error) {
          fail(error is ActionableException ? error :
            const ActionableException('流式识别返回了无法解析的结果'));
        }
      }, onError: (Object _) => fail(const ActionableException('流式识别连接异常')),
        onDone: () {
          if (!done.isCompleted) {
            fail(const ActionableException('流式识别连接提前关闭',
              hint: '结果尚未完整返回，请重新识别。'));
          }
        });
      ws.add(jsonEncode(startPayload(taskId, language)));
      await completion;
      token.throwIfCancelled();
      if (sentences.isEmpty) throw const ActionableException('未识别到语音');
      final cues = sentences.values.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      return [for (var i = 0; i < cues.length; i++)
        Cue(index: i + 1, startMs: cues[i].startMs, endMs: cues[i].endMs, source: cues[i].source)];
    } on WebSocketException {
      token.throwIfCancelled();
      throw const ActionableException('无法建立流式识别连接', hint: '核对服务地址、区域和 API Key。');
    } on SocketException {
      token.throwIfCancelled();
      throw const ActionableException('无法连接识别服务', hint: '检查网络和服务地址。');
    } finally {
      watch.cancel();
      if (!done.isCompleted) done.complete();
      await subscription?.cancel();
      unawaited(socket?.close());
      client.close(force: true);
      await sending;
    }
  }
}
