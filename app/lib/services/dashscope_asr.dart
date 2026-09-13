import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/cue.dart';
import 'audio_splitter.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';

/// 阿里百炼的语音识别：`POST {baseUrl}/services/aigc/multimodal-generation/generation`。
///
/// 与 OpenAI 兼容接口的两点不同决定了这个类的形状：
/// 1. 音频以 base64 data URI 塞在消息体里，单次有时长与体积上限；
/// 2. **只返回整段文本，不带时间戳**。所以先用 [AudioSplitter] 按静音把音频
///    切成句子，逐段识别，每段音频的起止就是这条字幕的时间码。
///
/// 支持两代模型的报文：`qwen3-asr-flash` 走 `audio` 内容块 + `asr_options`，
/// `qwen-audio-3.0-asr-flash` / `fun-asr-flash` 走 `input_audio` 内容块 +
/// `format/sample_rate` 参数，与原 Python 实现一致。
class DashScopeAsrProvider implements AsrProvider {
  DashScopeAsrProvider({
    required this.info,
    required this.endpoint,
    required this.splitter,
    this.prompt = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final ProviderInfo info;

  final Endpoint endpoint;
  final AudioSplitter splitter;

  /// 领域提示（专有名词、术语）。Qwen3-ASR 用 system 消息做上下文偏置。
  final String prompt;

  final http.Client _client;

  static const path = '/services/aigc/multimodal-generation/generation';

  /// `qwen-audio-3.0` 与 `fun-asr` 两族用 OpenAI 风格的 `input_audio` 内容块，
  /// 其余（qwen3-asr-flash）用百炼原生的 `audio` 内容块。
  bool get _qwen3Shape =>
      !(endpoint.model.startsWith('qwen-audio-3.0-asr-flash') ||
          endpoint.model.startsWith('fun-asr-flash'));

  @override
  Future<List<Cue>> transcribe({
    required String audioPath,
    required String language,
    required CancellationToken token,
    required ProgressSink onProgress,
  }) async {
    token.throwIfCancelled();
    if (!File(audioPath).existsSync()) {
      throw ProviderException(
        '音频文件不存在',
        detail: audioPath,
        hint: '准备阶段没有产出音频，请从准备阶段继续。',
      );
    }

    onProgress(0, 1, note: '按静音切分音频');
    final clips = await splitter.split(audioPath, token: token);

    final code = language.split('-').first.toLowerCase();
    final lang = code.isEmpty || code == 'auto' ? null : code;

    final cues = <Cue>[];
    String? lastError;
    try {
      for (final (i, clip) in clips.indexed) {
        token.throwIfCancelled();
        onProgress(i, clips.length, note: '识别第 ${i + 1} / ${clips.length} 段');

        final text = await _recognize(clip, lang);
        if (text == null) {
          lastError ??= '第 ${i + 1} 段返回为空';
          continue;
        }
        if (text.isEmpty) continue;
        cues.add(
          Cue(
            index: cues.length + 1,
            startMs: clip.startMs,
            endMs: clip.endMs,
            source: text,
          ),
        );
      }
    } finally {
      // 片段目录只是中转，识别完就删；失败重试会重新切。
      final dir = File(clips.first.path).parent;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    onProgress(clips.length, clips.length, note: '解析识别结果');

    if (cues.isEmpty) {
      throw ProviderException(
        '未识别到语音',
        detail: lastError,
        hint: '确认音视频中确有人声，且所选语言与实际语言一致。',
      );
    }
    return cues;
  }

  /// 识别一段。返回 null 表示服务端没给出文本（已记录原因），
  /// 空串表示这段确实没有话。鉴权、参数类错误直接抛出，不再往下跑。
  Future<String?> _recognize(AudioClip clip, String? lang) async {
    final bytes = await File(clip.path).readAsBytes();
    final dataUri = 'data:audio/wav;base64,${base64Encode(bytes)}';

    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint.resolve(path),
            headers: {
              ...endpoint.authHeaders,
              'Content-Type': 'application/json',
              'X-DashScope-SSE': 'disable',
            },
            body: jsonEncode(_payload(dataUri, lang)),
          )
          .timeout(endpoint.timeout);
    } on SocketException catch (e) {
      throw ProviderException(
        '无法连接到 ${info.vendor}',
        detail: '${endpoint.baseUrl} · $e',
        hint: '检查网络与服务地址；已完成的阶段已保留，可从识别阶段继续。',
      );
    }

    if (response.statusCode != 200) {
      final body = _clip(_bodyText(response));
      // 4xx 是配置问题，换一段音频也不会好，直接停。
      if (response.statusCode < 500) {
        throw ProviderException(
          _statusTitle(response.statusCode, info.vendor),
          detail: 'HTTP ${response.statusCode} · $body',
          hint: _statusHint(response.statusCode),
        );
      }
      return null;
    }

    final Map<String, Object?> json;
    try {
      json = jsonDecode(_bodyText(response)) as Map<String, Object?>;
    } catch (_) {
      throw ProviderException(
        '${info.vendor} 返回了无法解析的内容',
        detail: _clip(response.body),
        hint: '核对服务地址是否为百炼的 API 地址（以 /api/v1 结尾）。',
      );
    }
    return extractText(json);
  }

  Map<String, Object?> _payload(String dataUri, String? lang) {
    if (!_qwen3Shape) {
      return {
        'model': endpoint.model,
        'input': {
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'input_audio',
                  'input_audio': {'data': dataUri},
                },
              ],
            },
          ],
        },
        'parameters': {'format': 'wav', 'sample_rate': '16000'},
      };
    }
    return {
      'model': endpoint.model,
      'input': {
        'messages': [
          if (prompt.trim().isNotEmpty)
            {
              'role': 'system',
              'content': [
                {'text': prompt.trim()},
              ],
            },
          {
            'role': 'user',
            'content': [
              {'audio': dataUri},
            ],
          },
        ],
      },
      'parameters': {
        'result_format': 'message',
        'asr_options': {
          'language': ?lang,
          'enable_lid': true,
          'enable_itn': true,
        },
      },
    };
  }

  /// 从两种响应形态里取文本：`output.text`，或
  /// `output.choices[0].message.content[*].text` 拼接。取不到返回 null。
  static String? extractText(Map<String, Object?> json) {
    final output = json['output'];
    if (output is! Map) return null;
    final direct = output['text'];
    if (direct is String) return direct.trim();
    final choices = output['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is String) return content.trim();
    if (content is! List) return null;
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is Map && part['text'] is String) buffer.write(part['text']);
    }
    return buffer.toString().trim();
  }

  static String _bodyText(http.Response r) {
    try {
      return utf8.decode(r.bodyBytes);
    } catch (_) {
      return r.body;
    }
  }

  static String _clip(String s) => s.length > 600 ? '${s.substring(0, 600)}…' : s;

  static String _statusTitle(int status, String vendor) => switch (status) {
    401 || 403 => '$vendor 拒绝了密钥',
    404 => '$vendor 上找不到该接口',
    413 => '音频片段超出 $vendor 的大小限制',
    429 => '$vendor 限流',
    _ => '$vendor 返回错误',
  };

  static String? _statusHint(int status) => switch (status) {
    401 || 403 => '核对 API Key 是否正确、是否已开通百炼服务。',
    404 => '核对服务地址：默认为 https://dashscope.aliyuncs.com/api/v1。',
    429 => '稍后从识别阶段继续，已识别的阶段不会重做。',
    400 || 422 => '核对模型名与语言设置；该模型可能不支持所选语种。',
    _ => null,
  };
}
