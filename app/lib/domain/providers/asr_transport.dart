/// 识别模型怎么接：同一家服务下的模型可以走完全不同的接口。
///
/// 以前这件事靠模型名猜（`-filetrans` 结尾就是异步），用户自填的名字一旦
/// 不合这个规律就走错接口。现在它是模型声明里的一个字段，随任务入队冻结。
enum AsrTransport {
  /// OpenAI `/audio/transcriptions`：整文件上传，verbose_json 给分段时间戳。
  openaiTranscription('OpenAI 转写接口'),

  /// 百炼同步 multimodal-generation：接口不返回时间戳，本地按静音切片后
  /// 逐段识别，时间码来自切片边界。
  dashscopeSync('同步逐段'),

  /// 百炼录音文件转写：上传 → 提交 → 轮询，返回句级与词级时间戳。
  dashscopeFileTrans('异步整文件');

  const AsrTransport(this.label);

  final String label;

  /// 百炼的两种接入方式下，不同模型族的报文不一样，必须再声明一个报文族。
  bool get needsDialect => this != openaiTranscription;
}

/// 百炼三族模型的报文方言。
///
/// 同步接口：Qwen3-ASR 用 `audio` 内容块 + `asr_options`，另两族用
/// `input_audio` 内容块。录音文件转写：Qwen3-ASR 用 `file_url` + `language`，
/// 另两族用 `file_urls` + `language_hints`。
enum DashScopeDialect {
  qwen3Asr('Qwen3-ASR'),
  qwenAudio3('Qwen-Audio 3.0'),
  funAsr('Fun-ASR');

  const DashScopeDialect(this.label);

  final String label;
}

/// 一个识别模型能做什么。
///
/// 这是随软件发布的只读数据，不是用户设置：界面的开关显隐、就绪检查的
/// 提示、服务实现发不发某个字段，都读这一张表，不各自再判断一遍。
final class AsrCapabilities {
  const AsrCapabilities({
    required this.diarization,
    required this.contextPrompt,
    required this.timing,
  });

  /// 能按说话人分离（给每条字幕标说话人编号）。
  final bool diarization;

  /// 接受上下文提示：词表与识别提示会发给它。
  final bool contextPrompt;

  /// 时间码来自哪里，界面上的一个短语。
  final String timing;

  static const _openai = AsrCapabilities(
    diarization: false,
    contextPrompt: true,
    timing: '分段时间戳',
  );

  // 实测：同步接口带 `diarization_enabled` 会被静默忽略，三族都一样。
  // 只有 Qwen3-ASR 的同步报文有放提示的位置（system 消息）。
  static const _syncQwen3 = AsrCapabilities(
    diarization: false,
    contextPrompt: true,
    timing: '切片时间码',
  );
  static const _syncOther = AsrCapabilities(
    diarization: false,
    contextPrompt: false,
    timing: '切片时间码',
  );

  // 录音文件转写没有提示位。分离：Qwen-Audio 3.0 实测可用，Fun-ASR 按文档
  // 支持，Qwen3-ASR 按文档不支持。
  static const _fileQwen3 = AsrCapabilities(
    diarization: false,
    contextPrompt: false,
    timing: '句级时间戳',
  );
  static const _fileOther = AsrCapabilities(
    diarization: true,
    contextPrompt: false,
    timing: '句级时间戳',
  );

  /// 查表。百炼的两种接入方式缺报文族时抛 [StateError] —— 那是一份
  /// 不完整的声明，不该悄悄当成某一族用。
  static AsrCapabilities of(AsrTransport transport, DashScopeDialect? dialect) {
    if (transport.needsDialect && dialect == null) {
      throw StateError('${transport.name} 的模型必须声明报文族');
    }
    final qwen3 = dialect == DashScopeDialect.qwen3Asr;
    return switch (transport) {
      AsrTransport.openaiTranscription => _openai,
      AsrTransport.dashscopeSync => qwen3 ? _syncQwen3 : _syncOther,
      AsrTransport.dashscopeFileTrans => qwen3 ? _fileQwen3 : _fileOther,
    };
  }
}
