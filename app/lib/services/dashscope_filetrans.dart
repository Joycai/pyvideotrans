import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/cue.dart';
import 'dashscope_asr.dart';
import 'media.dart';
import 'openai_compatible.dart';
import 'provider_api.dart';

/// 阿里百炼的**录音文件转写**（模型名以 `-filetrans` 结尾）。
///
/// 与 [DashScopeAsrProvider] 的逐段同步识别不同，这条路把整段音频交给
/// 服务端一次处理，拿回带句级时间戳（和说话人编号）的整份结果：
///
/// 1. `GET {baseUrl}/uploads?action=getPolicy&model=…` 取一次性上传凭证；
/// 2. 按凭证把音频 multipart 上传到百炼的临时存储，得到 `oss://…` 地址
///    （48 小时有效）；
/// 3. `POST {baseUrl}/services/audio/asr/transcription` 提交任务
///    （头 `X-DashScope-Async: enable`、`X-DashScope-OssResourceResolve: enable`）；
/// 4. `GET {baseUrl}/tasks/{id}` 轮询到 SUCCEEDED / FAILED；
/// 5. 下载 `transcription_url` 指向的 JSON，取 `transcripts[0].sentences`。
///
/// 说话人分离在这条路上是文档正式支持的（`diarization_enabled`），
/// 编号在整个文件内一致，不存在逐段识别时跨段对不上号的问题。
///
/// 任务号记在检查点里：中途停下再「从识别阶段继续」时直接查同一个任务，
/// 不重新上传、不重复计费。
class DashScopeFileTransProvider implements AsrProvider {
  DashScopeFileTransProvider({
    required this.info,
    required this.endpoint,
    required this.media,
    this.diarize = false,
    http.Client? client,
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? ((d) => Future<void>.delayed(d));

  @override
  final ProviderInfo info;

  final Endpoint endpoint;
  final Media media;
  final bool diarize;

  final http.Client _client;
  final Future<void> Function(Duration) _delay;

  static const uploadPolicyPath = '/uploads';
  static const submitPath = '/services/audio/asr/transcription';
  static const taskPath = '/tasks/';

  /// 轮询间隔：开头勤一点，之后放慢，最慢 10 秒一次。
  static const pollIntervals = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ];

  /// 文档：单个文件不超过 12 小时。
  static const maxDuration = Duration(hours: 12);

  static bool isFileTransModel(String model) => model.endsWith('-filetrans');

  /// 两族模型的参数名不同：Qwen-Audio-3.0 用 `language_hints` 列表，
  /// Qwen3-ASR 用 `language`。
  bool get _qwen3 => endpoint.model.startsWith('qwen3-asr');

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
    if (!file.existsSync()) {
      throw ProviderException(
        '音频文件不存在',
        detail: audioPath,
        hint: '准备阶段没有产出音频，请从准备阶段继续。',
      );
    }
    final duration = await media.probeDuration(audioPath);
    if (duration != null && duration > maxDuration) {
      throw ProviderException(
        '音频超过录音文件转写的时长上限',
        detail: '${duration.inMinutes} 分钟，上限 ${maxDuration.inHours} 小时',
        hint: '把文件切短，或改用逐段识别的模型（不带 -filetrans）。',
      );
    }

    final code = language.split('-').first.toLowerCase();
    final lang = code.isEmpty || code == 'auto' ? null : code;
    final cp = checkpoint ?? RecognitionCheckpoint();

    var taskId = cp.asyncTaskId;
    if (taskId == null) {
      onProgress(0, 3, note: '上传音频到百炼临时存储');
      final url = await _upload(file, token);
      token.throwIfCancelled();
      onProgress(1, 3, note: '提交转写任务');
      taskId = await _submit(url, lang);
      cp.asyncTaskId = taskId;
    } else {
      onProgress(1, 3, note: '继续查询之前提交的任务');
    }

    final resultUrl = await _poll(taskId, token, onProgress);
    onProgress(3, 3, note: '下载识别结果');
    final json = await _fetchResult(resultUrl);
    final cues = parseTranscript(json);
    if (cues.isEmpty) {
      throw const ProviderException(
        '未识别到语音',
        hint: '确认音视频中确有人声，且所选语言与实际语言一致。',
      );
    }
    if (diarize && cues.every((c) => c.speaker == null)) {
      onProgress(
        3,
        3,
        note: '服务端没有返回说话人信息，字幕不带说话人编号；确认模型支持说话人分离',
      );
    }
    // 任务已消费完，续跑时不该再拿旧任务号。
    cp.asyncTaskId = null;
    return cues;
  }

  // —— 上传 ——————————————————————————————————————————————

  Future<String> _upload(File file, CancellationToken token) async {
    final policyResponse = await _guard(
      () => _client
          .get(
            endpoint.resolve(
              '$uploadPolicyPath?action=getPolicy&model=${endpoint.model}',
            ),
            headers: {...endpoint.authHeaders, 'Content-Type': 'application/json'},
          )
          .timeout(endpoint.timeout),
      what: '获取上传凭证',
    );
    _throwIfRejected(policyResponse, what: '获取上传凭证');
    final policy = _json(policyResponse, what: '上传凭证');
    final data = policy['data'];
    if (data is! Map) {
      throw ProviderException(
        '${info.vendor} 没有返回上传凭证',
        detail: _clip(policyResponse.body),
        hint: '该服务地址可能不支持临时文件上传；核对是否为百炼的 API 地址。',
      );
    }
    final maxMb = int.tryParse('${data['max_file_size_mb'] ?? ''}');
    final sizeMb = file.lengthSync() / (1024 * 1024);
    if (maxMb != null && sizeMb > maxMb) {
      throw ProviderException(
        '音频超过 ${info.vendor} 的上传大小限制',
        detail: '${sizeMb.toStringAsFixed(1)} MB，上限 $maxMb MB',
        hint: '把文件切短，或改用逐段识别的模型（不带 -filetrans）。',
      );
    }
    token.throwIfCancelled();

    final host = '${data['upload_host'] ?? ''}';
    final dir = '${data['upload_dir'] ?? ''}';
    final name = file.uri.pathSegments.last;
    final key =
        '$dir/${DateTime.now().millisecondsSinceEpoch}_${name.isEmpty ? 'audio.wav' : name}';
    // 字段顺序有讲究：OSS 要求 file 是最后一个；http 的 MultipartRequest
    // 先写 fields 再写 files，正好。
    final request = http.MultipartRequest('POST', Uri.parse(host))
      ..fields['OSSAccessKeyId'] = '${data['oss_access_key_id'] ?? ''}'
      ..fields['policy'] = '${data['policy'] ?? ''}'
      ..fields['Signature'] = '${data['signature'] ?? ''}'
      ..fields['key'] = key
      ..fields['x-oss-object-acl'] = '${data['x_oss_object_acl'] ?? 'private'}'
      ..fields['x-oss-forbid-overwrite'] =
          '${data['x_oss_forbid_overwrite'] ?? 'true'}'
      ..fields['success_action_status'] = '200'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await _guard(
      () => _client.send(request).timeout(endpoint.timeout),
      what: '上传音频',
    );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ProviderException(
        '上传音频失败',
        detail: 'HTTP ${response.statusCode} · ${_clip(_bodyText(response))}',
        hint: response.statusCode == 403
            ? '上传凭证过期或不匹配，重新从识别阶段继续会重新获取。'
            : '检查网络后从识别阶段继续。',
      );
    }
    return 'oss://$key';
  }

  // —— 提交 ——————————————————————————————————————————————

  Future<String> _submit(String fileUrl, String? lang) async {
    final response = await _guard(
      () => _client
          .post(
            endpoint.resolve(submitPath),
            headers: {
              ...endpoint.authHeaders,
              'Content-Type': 'application/json',
              'X-DashScope-Async': 'enable',
              'X-DashScope-OssResourceResolve': 'enable',
            },
            body: jsonEncode(submitPayload(fileUrl, lang)),
          )
          .timeout(endpoint.timeout),
      what: '提交转写任务',
    );
    _throwIfRejected(response, what: '提交转写任务');
    final json = _json(response, what: '提交结果');
    final output = json['output'];
    final id = output is Map ? output['task_id'] : null;
    if (id is! String || id.isEmpty) {
      throw ProviderException(
        '${info.vendor} 没有返回任务号',
        detail: _clip(response.body),
        hint: '核对服务地址与模型名。',
      );
    }
    return id;
  }

  /// 提交任务的报文。公开出来是为了测试能直接核对。
  Map<String, Object?> submitPayload(String fileUrl, String? lang) => {
    'model': endpoint.model,
    'input': _qwen3 ? {'file_url': fileUrl} : {
      'file_urls': [fileUrl],
    },
    'parameters': {
      'channel_id': [0],
      // 要词级时间戳：长句才能在换人 / 句末处再切开。
      'enable_words': true,
      if (diarize) 'diarization_enabled': true,
      if (lang != null)
        if (_qwen3) 'language': lang else 'language_hints': [lang],
    },
  };

  // —— 轮询 ——————————————————————————————————————————————

  Future<String> _poll(
    String taskId,
    CancellationToken token,
    ProgressSink onProgress,
  ) async {
    final started = DateTime.now();
    var round = 0;
    while (true) {
      token.throwIfCancelled();
      final response = await _guard(
        () => _client
            .get(
              endpoint.resolve('$taskPath$taskId'),
              headers: {
                ...endpoint.authHeaders,
                'Content-Type': 'application/json',
              },
            )
            .timeout(endpoint.timeout),
        what: '查询转写任务',
      );
      if (response.statusCode == 404) {
        throw ProviderException(
          '${info.vendor} 上找不到该任务',
          detail: 'task $taskId · ${_clip(_bodyText(response))}',
          hint: '任务可能已过期。从识别阶段重新开始会重新上传并提交。',
        );
      }
      _throwIfRejected(response, what: '查询转写任务');
      final json = _json(response, what: '任务状态');
      final output = json['output'];
      final status = output is Map ? '${output['task_status'] ?? ''}' : '';
      switch (status) {
        case 'SUCCEEDED':
          return _resultUrl(output as Map, taskId);
        case 'FAILED' || 'CANCELED' || 'UNKNOWN':
          final out = output as Map;
          throw ProviderException(
            '${info.vendor} 转写任务失败',
            detail: '${out['code'] ?? ''} ${out['message'] ?? ''}'.trim(),
            hint: _failureHint('${out['code'] ?? ''}${out['message'] ?? ''}'),
          );
        default:
          final elapsed = DateTime.now().difference(started).inSeconds;
          onProgress(
            2,
            3,
            note: '服务端转写中（${status == 'PENDING' ? '排队' : '处理'}），已等待 $elapsed 秒',
          );
          final wait = pollIntervals[round.clamp(0, pollIntervals.length - 1)];
          round++;
          await _sleep(wait, token);
      }
    }
  }

  String _resultUrl(Map output, String taskId) {
    final results = output['results'];
    if (results is List) {
      for (final r in results) {
        if (r is! Map) continue;
        final url = r['transcription_url'];
        if ('${r['subtask_status'] ?? 'SUCCEEDED'}' == 'SUCCEEDED' &&
            url is String &&
            url.isNotEmpty) {
          return url;
        }
        throw ProviderException(
          '${info.vendor} 转写子任务失败',
          detail: '${r['code'] ?? ''} ${r['message'] ?? ''}'.trim(),
          hint: _failureHint('${r['code'] ?? ''}${r['message'] ?? ''}'),
        );
      }
    }
    final direct = output['transcription_url'];
    if (direct is String && direct.isNotEmpty) return direct;
    throw ProviderException(
      '${info.vendor} 没有返回结果地址',
      detail: 'task $taskId · ${_clip(jsonEncode(output))}',
    );
  }

  Future<Map<String, Object?>> _fetchResult(String url) async {
    final response = await _guard(
      () => _client.get(Uri.parse(url)).timeout(endpoint.timeout),
      what: '下载识别结果',
    );
    if (response.statusCode != 200) {
      throw ProviderException(
        '下载识别结果失败',
        detail: 'HTTP ${response.statusCode} · ${_clip(_bodyText(response))}',
        hint: '结果地址有时效，从识别阶段继续会重新查询任务。',
      );
    }
    return _json(response, what: '识别结果');
  }

  // —— 结果解析 ——————————————————————————————————————————

  /// 把 `transcripts[].sentences[]` 变成字幕。每句一条；开了词级时间戳的
  /// 长句按换人 / 句末标点 / 过长再切。多声道时只取第一路。
  static List<Cue> parseTranscript(Map<String, Object?> json) {
    final transcripts = json['transcripts'];
    if (transcripts is! List || transcripts.isEmpty) return const [];
    final first = transcripts.first;
    if (first is! Map) return const [];
    final sentences = first['sentences'];
    if (sentences is! List) return const [];

    final cues = <Cue>[];
    void add(int start, int end, String text, int? speaker) {
      final t = text.trim();
      if (t.isEmpty) return;
      cues.add(
        Cue(
          index: cues.length + 1,
          startMs: start,
          endMs: end > start ? end : start + 1,
          source: t,
          speaker: speaker,
        ),
      );
    }

    for (final raw in sentences) {
      if (raw is! Map) continue;
      final begin = (raw['begin_time'] as num?)?.toInt() ?? 0;
      final end = (raw['end_time'] as num?)?.toInt() ?? begin;
      final text = raw['text'] as String? ?? '';
      final speaker = DashScopeAsrProvider.speakerOf(raw);
      final words = raw['words'];
      // 词级时间戳是相对整个文件的，不用再加偏移。
      final pieces = words is List && words.isNotEmpty
          ? DashScopeAsrProvider.splitWords(
              words,
              offsetMs: 0,
              minMs: begin,
              maxMs: end,
            )
          : const <SegmentPiece>[];
      if (pieces.isEmpty) {
        add(begin, end, text, speaker);
        continue;
      }
      for (final p in pieces) {
        // 词上没有 speaker_id 时沿用句级的。
        add(p.startMs, p.endMs, p.text, p.speaker ?? speaker);
      }
    }
    return cues;
  }

  // —— 杂项 ——————————————————————————————————————————————

  Future<T> _guard<T>(Future<T> Function() send, {required String what}) async {
    try {
      return await send();
    } on SocketException catch (e) {
      throw ProviderException(
        '无法连接到 ${info.vendor}（$what）',
        detail: '${endpoint.baseUrl} · $e',
        hint: '检查网络与服务地址；从识别阶段继续会接着上次的任务。',
      );
    } on TimeoutException {
      throw ProviderException(
        '${info.vendor} 响应超时（$what）',
        detail: '超过 ${endpoint.timeout.inSeconds} 秒没有返回',
        hint: '检查网络；从识别阶段继续会接着上次的任务。',
      );
    }
  }

  void _throwIfRejected(http.Response response, {required String what}) {
    final status = response.statusCode;
    if (status == 200) return;
    throw ProviderException(
      switch (status) {
        401 || 403 => '${info.vendor} 拒绝了密钥',
        404 => '${info.vendor} 上找不到该接口',
        429 => '${info.vendor} 限流',
        _ => '${info.vendor} 返回错误（$what）',
      },
      detail: 'HTTP $status · ${_clip(_bodyText(response))}',
      hint: switch (status) {
        401 || 403 => '核对 API Key 是否正确、是否已开通百炼服务。',
        404 =>
          '核对服务地址是否支持录音文件转写（默认为 '
              'https://dashscope.aliyuncs.com/api/v1），以及模型名是否可用。',
        429 => '稍后从识别阶段继续。',
        _ => '核对模型名与参数。',
      },
    );
  }

  static String? _failureHint(String text) {
    final t = text.toLowerCase();
    if (t.contains('download') || t.contains('url') || t.contains('file')) {
      return '服务端取不到上传的音频；从识别阶段重新开始会重新上传。';
    }
    if (t.contains('duration') || t.contains('too long')) {
      return '音频过长；把文件切短，或改用逐段识别的模型。';
    }
    return '从识别阶段重新开始会重新上传并提交。';
  }

  Map<String, Object?> _json(http.Response response, {required String what}) {
    try {
      return jsonDecode(_bodyText(response)) as Map<String, Object?>;
    } catch (_) {
      throw ProviderException(
        '${info.vendor} 返回了无法解析的$what',
        detail: _clip(_bodyText(response)),
        hint: '核对服务地址是否为百炼的 API 地址（以 /api/v1 结尾）。',
      );
    }
  }

  Future<void> _sleep(Duration d, CancellationToken token) async {
    var left = d;
    const tick = Duration(milliseconds: 250);
    while (left > Duration.zero) {
      token.throwIfCancelled();
      final step = left < tick ? left : tick;
      await _delay(step);
      left -= step;
    }
    token.throwIfCancelled();
  }

  static String _bodyText(http.Response r) {
    try {
      return utf8.decode(r.bodyBytes);
    } catch (_) {
      return r.body;
    }
  }

  static String _clip(String s) =>
      s.length > 600 ? '${s.substring(0, 600)}…' : s;
}
