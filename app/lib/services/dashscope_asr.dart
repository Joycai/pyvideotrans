import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/cue.dart';
import '../domain/recognition_checkpoint.dart';
import 'audio_splitter.dart';
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
    this.diarize = false,
    http.Client? client,
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  @override
  final ProviderInfo info;

  final Endpoint endpoint;
  final AudioSplitter splitter;

  /// 领域提示（专有名词、术语）。Qwen3-ASR 用 system 消息做上下文偏置。
  final String prompt;

  /// 说话人分离：请求里带 `diarization_enabled`，按返回的词级
  /// `speaker_id` 把每段切成带说话人编号的多条字幕。
  ///
  /// 文档只承诺 Qwen-Audio-3.0-ASR 与 Fun-ASR 两族支持；qwen3-asr-flash
  /// 不下发这个参数。服务端没给说话人时退化为不带编号的普通字幕。
  final bool diarize;

  /// 开说话人分离时的片段上限。编号只在同一次请求内一致，片段越长跨段
  /// 对不上号的机会越少；2 分钟的 16k 单声道 wav 约 3.8 MB，base64 后
  /// 约 5 MB，留在 flash 模型 10 MB 的上限之内。
  static const diarizeClipMs = 120000;

  /// 分离出来的一条字幕最长多久 / 多少字，超过就在下一个词前断开。
  /// 字数上限按文字种类：中日韩 40 字，拉丁文 90 字符（一个词好几个字母）。
  static const _maxPieceMs = 10000;
  static const _maxPieceCharsCjk = 40;
  static const _maxPieceCharsLatin = 90;

  final http.Client _client;

  /// 等待用的睡眠函数，测试里换成立即返回的。
  final Future<void> Function(Duration) _delay;

  /// 限流 / 断网时的等待阶梯。服务端给了 Retry-After 就用服务端的。
  static const backoff = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

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
    RecognitionCheckpoint? checkpoint,
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
    if (clips.isEmpty) {
      throw const ProviderException('未识别到语音', hint: '整段音频都是静音。确认音视频中确有人声。');
    }

    final code = language.split('-').first.toLowerCase();
    final lang = code.isEmpty || code == 'auto' ? null : code;

    // 没给检查点就用一份临时的，逻辑不分叉。
    final cp = checkpoint ?? RecognitionCheckpoint();
    if (!cp.matches(clips.map((c) => (startMs: c.startMs, endMs: c.endMs)))) {
      // 切分点对不上：音频变了，之前的记录不能用。
      cp.clear();
    }
    cp.total = clips.length;
    final resumedFrom = cp.doneCount;

    String? lastError;
    // 连续等待了几次（限流 / 断网），决定退避时长；一次成功就归零。
    var waits = 0;
    try {
      for (final (i, clip) in clips.indexed) {
        token.throwIfCancelled();
        final record = cp.segment(clip.startMs, clip.endMs);
        if (record.done) continue;

        void progress(String note) => onProgress(i, clips.length, note: note);
        progress(
          resumedFrom > 0 && i == resumedFrom
              ? '从第 ${i + 1} 段继续，前面 $resumedFrom 段已识别'
              : '识别第 ${i + 1} / ${clips.length} 段'
                    '${cp.skippedCount > 0 ? '，已跳过 ${cp.skippedCount} 段' : ''}',
        );

        // 同一段在这一轮里最多试到放弃为止；非自动模式只试一次。
        while (!record.done) {
          token.throwIfCancelled();
          final outcome = await _recognize(clip, lang);
          switch (outcome) {
            case _Ok(:final text, :final pieces):
              record
                ..text = text
                ..pieces = pieces;
              waits = 0;
            case _Wait(:final reason, :final retryAfter):
              // 限流与断网不是这一段的错，不计失败：非自动模式停下来
              // 让用户稍后继续；自动模式等一等再试同一段。
              if (!cp.autoRetry) {
                throw ProviderException(
                  reason.title,
                  detail: reason.detail,
                  hint: reason.hint,
                );
              }
              final wait =
                  retryAfter ?? backoff[waits.clamp(0, backoff.length - 1)];
              waits++;
              progress('${reason.title}，等待 ${wait.inSeconds} 秒后重试第 ${i + 1} 段');
              await _sleep(wait, token);
            case _Failed(:final error, :final fatal):
              lastError = '第 ${i + 1} 段：${error.detail ?? error.title}';
              final skipped = cp.fail(record, lastError);
              // 鉴权、地址这类错误换一段也不会好；非自动模式下任何请求
              // 错误都停下来。已识别的段留在检查点里，续跑从这段接着来。
              if (fatal || !cp.autoRetry) {
                throw ProviderException(
                  error.title,
                  detail: error.detail,
                  hint: error.hint,
                );
              }
              if (skipped) {
                progress('第 ${i + 1} 段失败 ${record.failures} 次，已跳过');
              } else {
                progress('第 ${i + 1} 段失败，第 ${record.failures + 1} 次重试');
                await _sleep(const Duration(seconds: 2), token);
              }
            case _Transient(:final error):
              // 5xx / 空响应：记一次失败。非自动模式先跑完其余段，
              // 结束时一并报告；自动模式原地重试。
              lastError = '第 ${i + 1} 段：$error';
              final skipped = cp.fail(record, lastError);
              if (!cp.autoRetry) break;
              if (skipped) {
                progress('第 ${i + 1} 段失败 ${record.failures} 次，已跳过');
              } else {
                progress('第 ${i + 1} 段失败，第 ${record.failures + 1} 次重试');
                await _sleep(const Duration(seconds: 2), token);
              }
          }
          if (!cp.autoRetry) break;
        }
      }
    } finally {
      // 片段目录只是中转，识别完就删；续跑会重新切，切分点一样。
      final dir = File(clips.first.path).parent;
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Cleanup failure must not hide the recognition result/error.
        }
      }
    }

    final failed = cp.pending.length;
    if (failed > 0) {
      throw ProviderException(
        '有 $failed 段识别失败',
        detail: lastError,
        hint:
            '从识别阶段继续只会重试失败的段；同一段失败 '
            '${RecognitionCheckpoint.maxFailures} 次后会跳过并留下待校对的空字幕。',
      );
    }
    onProgress(clips.length, clips.length, note: '解析识别结果');

    final cues = <Cue>[];
    for (final clip in clips) {
      final record = cp.segment(clip.startMs, clip.endMs);
      if (record.skipped) {
        // 占位：空文本不会写进产物，置信度 0 让编辑器把它标成待校对。
        cues.add(
          Cue(
            index: cues.length + 1,
            startMs: clip.startMs,
            endMs: clip.endMs,
            source: '',
            confidence: 0,
          ),
        );
        continue;
      }
      final text = record.text ?? '';
      if (text.isEmpty) continue;
      final pieces = record.pieces;
      if (pieces != null && pieces.isNotEmpty) {
        for (final piece in pieces) {
          if (piece.text.isEmpty) continue;
          cues.add(
            Cue(
              index: cues.length + 1,
              startMs: piece.startMs,
              endMs: piece.endMs,
              source: piece.text,
              speaker: piece.speaker,
            ),
          );
        }
        continue;
      }
      cues.add(
        Cue(
          index: cues.length + 1,
          startMs: clip.startMs,
          endMs: clip.endMs,
          source: text,
        ),
      );
    }

    if (cues.isEmpty) {
      throw const ProviderException('未识别到语音', hint: '确认音视频中确有人声，且所选语言与实际语言一致。');
    }
    if (diarize && cues.every((c) => c.speaker == null)) {
      onProgress(
        clips.length,
        clips.length,
        note: '服务端没有返回说话人信息，字幕不带说话人编号；确认模型支持说话人分离',
      );
    }
    return cues;
  }

  /// 可被取消的等待：每 250ms 看一眼取消标记。
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

  /// 识别一段，把请求结果归成四类，怎么处理由调用方按模式决定。
  Future<_Outcome> _recognize(AudioClip clip, String? lang) async {
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
      return _Wait(
        _ErrorInfo(
          '无法连接到 ${info.vendor}',
          detail: '${endpoint.baseUrl} · $e',
          hint: '检查网络与服务地址；已完成的阶段已保留，可从识别阶段继续。',
        ),
      );
    } on TimeoutException {
      return _Wait(
        _ErrorInfo(
          '${info.vendor} 响应超时',
          detail: '超过 ${endpoint.timeout.inSeconds} 秒没有返回',
          hint: '检查网络；已识别的段已保留，可从识别阶段继续。',
        ),
      );
    }

    final status = response.statusCode;
    if (status == 200) {
      final Map<String, Object?> json;
      try {
        json = jsonDecode(_bodyText(response)) as Map<String, Object?>;
      } catch (_) {
        return _Failed(
          _ErrorInfo(
            '${info.vendor} 返回了无法解析的内容',
            detail: _clip(response.body),
            hint: '核对服务地址是否为百炼的 API 地址（以 /api/v1 结尾）。',
          ),
          fatal: true,
        );
      }
      final text = extractText(json);
      if (text == null) return const _Transient('服务端没有返回文本');
      return _Ok(text, pieces: diarize ? extractPieces(json, clip) : null);
    }

    final body = _clip(_bodyText(response));
    // 百炼对没有人声的片段返回 400 + ASR_RESPONSE_HAVE_NO_WORDS，
    // 这不是错误，是这段确实没话。
    if (status == 400 && body.contains('ASR_RESPONSE_HAVE_NO_WORDS')) {
      return const _Ok('');
    }
    if (status == 429) {
      return _Wait(
        _ErrorInfo(
          _statusTitle(status, info.vendor),
          detail: 'HTTP $status · $body',
          hint: _statusHint(status),
        ),
        retryAfter: _retryAfter(response),
      );
    }
    if (status >= 500) return _Transient('HTTP $status · $body');
    return _Failed(
      _ErrorInfo(
        _statusTitle(status, info.vendor),
        detail: 'HTTP $status · $body',
        hint: _statusHint(status),
      ),
      // 鉴权、地址、体积上限：换一段也不会好，任何模式下都停。
      fatal: const {401, 403, 404, 413}.contains(status),
    );
  }

  /// Retry-After 只认秒数形式；HTTP 日期形式极少见，交给退避阶梯。
  static Duration? _retryAfter(http.Response r) {
    final raw = r.headers['retry-after'];
    final seconds = raw == null ? null : int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds.clamp(1, 300));
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
        'parameters': {
          'format': 'wav',
          'sample_rate': '16000',
          if (diarize) 'diarization_enabled': true,
        },
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

  /// 开说话人分离时把一段的返回拆成小块：按 `output.sentence.words[]`
  /// 的词级时间与 `speaker_id`，换人、句末标点、过长处断开。
  /// 没有词级信息就整段一块，说话人取句级 `speaker_id`。
  ///
  /// 词的时间戳相对片段文件起点，用 [AudioClip.fileStartMs] 换算回原音频，
  /// 并夹在片段范围内，免得 200ms 的切分余量让字幕越界。
  static List<SegmentPiece> extractPieces(
    Map<String, Object?> json,
    AudioClip clip,
  ) {
    final text = extractText(json) ?? '';
    final output = json['output'];
    final sentence = output is Map && output['sentence'] is Map
        ? output['sentence'] as Map
        : json['sentence'] is Map
        ? json['sentence'] as Map
        : null;
    final fallback = SegmentPiece(
      startMs: clip.startMs,
      endMs: clip.endMs,
      text: text,
      speaker: sentence == null ? null : speakerOf(sentence),
    );
    final words = sentence?['words'];
    if (words is! List || words.isEmpty) return [fallback];
    final pieces = splitWords(
      words,
      offsetMs: clip.fileStartMs,
      minMs: clip.startMs,
      maxMs: clip.endMs,
    );
    // 词全是空的：退回整段。
    return pieces.isEmpty ? [fallback] : pieces;
  }

  /// 百炼两种接口里的 `speaker_id` 都可能是数字或数字字符串。
  static int? speakerOf(Map m) => switch (m['speaker_id']) {
    final int id => id,
    final String s => int.tryParse(s),
    _ => null,
  };

  /// 把一串带时间戳的词攒成小块：换说话人、句末标点、超过
  /// [_maxPieceMs] / [_maxPieceChars] 处断开。词时间加上 [offsetMs]
  /// 后夹在 [minMs]..[maxMs] 之间。同步接口与录音文件转写共用。
  static List<SegmentPiece> splitWords(
    List<Object?> words, {
    required int offsetMs,
    required int minMs,
    required int maxMs,
  }) {
    int clampMs(int ms) => ms.clamp(minMs, maxMs);

    final pieces = <SegmentPiece>[];
    StringBuffer? buffer;
    int? pieceStart;
    int? pieceEnd;
    int? pieceSpeaker;
    var endsSentence = false;

    void flush() {
      final t = buffer?.toString().trim() ?? '';
      if (t.isNotEmpty && pieceStart != null && pieceEnd != null) {
        pieces.add(
          SegmentPiece(
            startMs: pieceStart!,
            endMs: pieceEnd! > pieceStart! ? pieceEnd! : pieceStart! + 1,
            text: t,
            speaker: pieceSpeaker,
          ),
        );
      }
      buffer = null;
      pieceStart = null;
      pieceEnd = null;
      endsSentence = false;
    }

    for (final raw in words) {
      if (raw is! Map) continue;
      final wordText = (raw['text'] as String? ?? '').trim();
      final punct = (raw['punctuation'] as String? ?? '').trim();
      if (wordText.isEmpty && punct.isEmpty) continue;
      final begin = clampMs(
        offsetMs + ((raw['begin_time'] as num?)?.toInt() ?? 0),
      );
      final end = clampMs(
        offsetMs + ((raw['end_time'] as num?)?.toInt() ?? begin),
      );
      final speaker = speakerOf(raw);

      final current = buffer;
      if (current != null) {
        final limit = _cjk.hasMatch(current.toString())
            ? _maxPieceCharsCjk
            : _maxPieceCharsLatin;
        final tooLong =
            end - pieceStart! > _maxPieceMs ||
            current.length + wordText.length > limit;
        if (speaker != pieceSpeaker || endsSentence || tooLong) flush();
      }
      if (buffer == null) {
        buffer = StringBuffer();
        pieceStart = begin;
        pieceSpeaker = speaker;
      } else if (_needsSpace(buffer!.toString(), wordText)) {
        buffer!.write(' ');
      }
      buffer!
        ..write(wordText)
        ..write(punct);
      pieceEnd = end;
      endsSentence = _sentenceEnd.hasMatch(punct);
    }
    flush();
    return pieces;
  }

  static final _sentenceEnd = RegExp(r'[。！？.!?;；]');
  static final _latinEdge = RegExp(r'[A-Za-z0-9]');
  static final _asciiPunct = RegExp(r'[,.;:!?]');
  static final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]');

  /// 两个相邻词之间要不要空格：下一个词是拉丁字母 / 数字，且前面以拉丁
  /// 字母、数字或英文标点结尾才加（"Hi," + "let's" → "Hi, let's"）；中文不加。
  static bool _needsSpace(String before, String next) {
    if (before.isEmpty || next.isEmpty || !_latinEdge.hasMatch(next[0])) {
      return false;
    }
    final last = before[before.length - 1];
    return _latinEdge.hasMatch(last) || _asciiPunct.hasMatch(last);
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

  static String _clip(String s) =>
      s.length > 600 ? '${s.substring(0, 600)}…' : s;

  static String _statusTitle(int status, String vendor) => switch (status) {
    401 || 403 => '$vendor 拒绝了密钥',
    404 => '$vendor 上找不到该接口',
    413 => '音频片段超出 $vendor 的大小限制',
    429 => '$vendor 限流',
    _ => '$vendor 返回错误',
  };

  static String? _statusHint(int status) => switch (status) {
    401 || 403 => '核对 API Key 是否正确、是否已开通百炼服务。',
    // 有些网关（如阿里云百炼的 token-plan 专属域名）对不存在的模型也回 404。
    404 =>
      '核对模型名是否在该服务上可用，以及服务地址（默认为 '
          'https://dashscope.aliyuncs.com/api/v1）。',
    429 => '稍后从识别阶段继续，已识别的阶段不会重做。',
    400 || 422 => '核对模型名与语言设置；该模型可能不支持所选语种。',
    _ => null,
  };
}

// —— 单段请求的四种结果 ——————————————————————————————————

class _ErrorInfo {
  const _ErrorInfo(this.title, {this.detail, this.hint});

  final String title;
  final String? detail;
  final String? hint;
}

sealed class _Outcome {
  const _Outcome();
}

/// 拿到文本；空串表示这段没话。[pieces] 是说话人分离切出来的小块。
final class _Ok extends _Outcome {
  const _Ok(this.text, {this.pieces});

  final String text;
  final List<SegmentPiece>? pieces;
}

/// 限流或断网：不是这一段的错，等一等再试同一段。
final class _Wait extends _Outcome {
  const _Wait(this.reason, {this.retryAfter});

  final _ErrorInfo reason;
  final Duration? retryAfter;
}

/// 请求被拒（4xx）。[fatal] 的换一段也不会好。
final class _Failed extends _Outcome {
  const _Failed(this.error, {this.fatal = false});

  final _ErrorInfo error;
  final bool fatal;
}

/// 服务端问题（5xx / 空响应）：记一次失败，稍后可重试。
final class _Transient extends _Outcome {
  const _Transient(this.error);

  final String error;
}
