import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/cue.dart';
import 'provider_api.dart';
import 'translation_protocol.dart';

/// 连接参数。本地后端与在线服务用的是同一个结构 —— 这正是本地模型方案的前提：
/// 客户端只认 baseUrl + model，不关心对面跑在哪台机器上。
class Endpoint {
  const Endpoint({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.timeout = const Duration(minutes: 10),
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration timeout;

  /// 拼接路径，容忍 baseUrl 带不带结尾斜杠。
  Uri resolve(String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> get authHeaders =>
      apiKey.isEmpty ? const {} : {'Authorization': 'Bearer $apiKey'};
}

/// OpenAI 兼容的语音识别：`POST {baseUrl}/audio/transcriptions`。
///
/// 覆盖 OpenAI 本身、以及所有照抄这套接口的服务（中转站、SiliconFlow、Groq…），
/// **并且是第二期本地 Python 后端要实现的协议** —— 届时只需把 baseUrl
/// 指向本地进程，这个类原样复用。
class OpenAiCompatibleAsrProvider implements AsrProvider {
  OpenAiCompatibleAsrProvider({
    required this.info,
    required this.endpoint,
    this.prompt = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final ProviderInfo info;

  final Endpoint endpoint;

  /// 交给模型的领域提示（专有名词、术语），提高识别准确率。
  final String prompt;

  final http.Client _client;

  @override
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
  }) async {
    token.throwIfCancelled();

    final file = File(audioPath);
    if (!file.existsSync()) {
      throw ProviderException(
        '音频文件不存在',
        detail: audioPath,
        hint: '准备阶段没有产出音频，请从准备阶段继续。',
      );
    }

    onProgress(0, 1, note: '上传音频至 ${info.vendor}');

    final request = http.MultipartRequest(
      'POST',
      endpoint.resolve('/audio/transcriptions'),
    )
      ..headers.addAll(endpoint.authHeaders)
      ..fields['model'] = endpoint.model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'segment'
      ..files.add(await http.MultipartFile.fromPath('file', audioPath));

    if (prompt.trim().isNotEmpty) request.fields['prompt'] = prompt.trim();
    // `auto` 表示交给服务端自动判定，不下发 language 参数。
    final code = language.split('-').first.toLowerCase();
    if (code.isNotEmpty && code != 'auto') request.fields['language'] = code;

    token.throwIfCancelled();

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(endpoint.timeout);
      response = await http.Response.fromStream(streamed);
    } on SocketException catch (e) {
      throw ProviderException(
        '无法连接到 ${info.vendor}',
        detail: '${endpoint.baseUrl} · $e',
        hint: '检查网络与服务地址；已完成的阶段已保留，可从识别阶段继续。',
      );
    }

    token.throwIfCancelled();
    _throwForStatus(response);

    onProgress(1, 1, note: '解析识别结果');

    final body = _decodeJson(response);
    final segments = body['segments'];
    if (segments is! List || segments.isEmpty) {
      // 没有分段时退回整段文本：至少不丢内容，时间码按音频时长兜底。
      final text = (body['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        throw const ProviderException(
          '未识别到语音',
          hint: '确认音视频中确有人声，且所选语言与实际语言一致。',
        );
      }
      return [Cue(index: 1, startMs: 0, endMs: 0, source: text)];
    }

    final cues = <Cue>[];
    for (final raw in segments) {
      if (raw is! Map) continue;
      final text = (raw['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      cues.add(
        Cue(
          index: cues.length + 1,
          startMs: _seconds(raw['start']),
          endMs: _seconds(raw['end']),
          source: text,
          confidence: _confidence(raw),
        ),
      );
    }

    if (cues.isEmpty) {
      throw const ProviderException(
        '未识别到语音',
        hint: '确认音视频中确有人声，且所选语言与实际语言一致。',
      );
    }
    return cues;
  }

  static int _seconds(Object? v) =>
      ((v is num ? v.toDouble() : 0.0) * 1000).round();

  /// OpenAI 给的是 avg_logprob（自然对数），转成 0..1 的直观置信度。
  static double? _confidence(Map raw) {
    final logprob = raw['avg_logprob'];
    if (logprob is num) {
      final p = _exp(logprob.toDouble());
      return p.clamp(0.0, 1.0);
    }
    final conf = raw['confidence'];
    return conf is num ? conf.toDouble().clamp(0.0, 1.0) : null;
  }

  static double _exp(double x) {
    // 只在 avg_logprob 的合理区间内使用，越界直接夹住。
    if (x <= -10) return 0;
    if (x >= 0) return 1;
    var result = 1.0;
    var term = 1.0;
    for (var n = 1; n <= 24; n++) {
      term *= x / n;
      result += term;
    }
    return result;
  }

  void _throwForStatus(http.Response r) {
    if (r.statusCode == 200) return;
    final body = r.body.length > 600 ? '${r.body.substring(0, 600)}…' : r.body;
    throw ProviderException(
      _statusTitle(r.statusCode, info.vendor),
      detail: 'HTTP ${r.statusCode} · $body',
      hint: _statusHint(r.statusCode),
    );
  }

  Map<String, Object?> _decodeJson(http.Response r) {
    try {
      return jsonDecode(_bodyText(r)) as Map<String, Object?>;
    } catch (_) {
      throw ProviderException(
        '${info.vendor} 返回了无法解析的内容',
        detail: r.body.length > 600 ? '${r.body.substring(0, 600)}…' : r.body,
        hint: '通常是服务地址填成了网页地址或中转站返回了错误页。核对服务地址。',
      );
    }
  }
}

/// OpenAI 兼容的翻译：`POST {baseUrl}/chat/completions`。
///
/// 覆盖 OpenAI、DeepSeek、SiliconFlow、OpenRouter，以及 Ollama / LM Studio
/// 这类本地服务 —— 它们都说同一套协议，所以「本地」在客户端这里不是一条单独的代码路径。
class OpenAiCompatibleTranslationProvider implements TranslationProvider {
  OpenAiCompatibleTranslationProvider({
    required this.info,
    required this.endpoint,
    this.extraGuidance,
    this.temperature = 0.3,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final ProviderInfo info;

  final Endpoint endpoint;

  /// 用户在设置里填的额外要求（术语表、语气）。
  final String? extraGuidance;

  final double temperature;
  final http.Client _client;

  @override
  Future<List<String>> translateBatch({
    required List<String> lines,
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken token,
  }) async {
    token.throwIfCancelled();
    if (lines.isEmpty) return const [];

    final payload = jsonEncode({
      'model': endpoint.model,
      'temperature': temperature,
      'messages': [
        {
          'role': 'system',
          'content': TranslationProtocol.systemPrompt(
            targetLanguageName: targetLanguage,
            extraGuidance: extraGuidance,
          ),
        },
        {
          'role': 'user',
          'content': '<INPUT>\n${TranslationProtocol.encode(lines)}\n</INPUT>',
        },
      ],
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint.resolve('/chat/completions'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              ...endpoint.authHeaders,
            },
            body: utf8.encode(payload),
          )
          .timeout(endpoint.timeout);
    } on SocketException catch (e) {
      throw ProviderException(
        '无法连接到 ${info.vendor}',
        detail: '${endpoint.baseUrl} · $e',
        hint: info.runsLocally
            ? '确认本地服务已启动并监听该端口。'
            : '检查网络与服务地址；已翻译的条目已保留，可从翻译阶段继续。',
      );
    }

    token.throwIfCancelled();

    if (response.statusCode != 200) {
      final body = response.body.length > 600
          ? '${response.body.substring(0, 600)}…'
          : response.body;
      throw ProviderException(
        _statusTitle(response.statusCode, info.vendor),
        detail: 'HTTP ${response.statusCode} · $body',
        hint: _statusHint(response.statusCode),
      );
    }

    final Map<String, Object?> body;
    try {
      body = jsonDecode(_bodyText(response)) as Map<String, Object?>;
    } catch (_) {
      throw ProviderException(
        '${info.vendor} 返回了无法解析的内容',
        detail: response.body,
        hint: '核对服务地址是否为 OpenAI 兼容接口的根地址。',
      );
    }

    final choices = body['choices'];
    String? content;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map ? first['message'] : null;
      if (message is Map) content = message['content'] as String?;
    }

    if (content == null || content.trim().isEmpty) {
      throw const ProviderException(
        '模型返回了空内容',
        hint: '多为内容审核拦截或上下文超长。减小每批条数后重试。',
        batchTooLarge: true,
      );
    }

    final decoded = TranslationProtocol.decode(content, lines.length);
    if (decoded == null) {
      throw ProviderException(
        '译文与原文条数对不上',
        detail: '期望 ${lines.length} 条，模型返回：\n'
            '${content.length > 400 ? '${content.substring(0, 400)}…' : content}',
        hint: '模型合并或丢弃了字幕行。流水线会自动减半批量重试。',
        batchTooLarge: true,
      );
    }
    return decoded;
  }
}

/// 响应正文转文本。
///
/// 优先按 UTF-8 解，因为服务端即使没在 Content-Type 里标 charset，
/// 实际发的也几乎都是 UTF-8（而 http 包在缺 charset 时会按 latin1 解，
/// 把中文译文变成乱码）。真不是合法 UTF-8 时才退回 http 包的解码结果。
String _bodyText(http.Response r) {
  try {
    return utf8.decode(r.bodyBytes);
  } on FormatException {
    return r.body;
  }
}

String _statusTitle(int status, String vendor) => switch (status) {
  401 || 403 => '$vendor 拒绝了这个密钥',
  404 => '$vendor 找不到该接口或模型',
  413 => '文件超出 $vendor 的大小上限',
  429 => '$vendor 限流',
  >= 500 => '$vendor 服务端错误',
  _ => '$vendor 返回错误',
};

String _statusHint(int status) => switch (status) {
  401 || 403 => '在设置里核对 API 密钥，确认账户有该模型的权限。',
  404 => '核对服务地址与模型名。地址应当填到 /v1 为止。',
  413 => '改用更长的分段或压缩音频后重试。',
  429 => '降低并发或稍后重试。已完成的部分已保留。',
  >= 500 => '服务端问题，稍后从中断处继续即可。',
  _ => '查看详情中的原始返回。',
};
