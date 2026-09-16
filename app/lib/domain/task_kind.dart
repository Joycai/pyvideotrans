// 任务类型与流水线阶段独立放置，避免 TaskOptions 与 SubtitleTask 循环依赖。

/// 流水线的阶段，顺序固定。每种任务只走其中一部分（见 [TaskKind.stages]），
/// 界面上的阶段条画的就是那一部分。
enum TaskStage {
  queued('排队'),
  prepare('准备'),
  recognize('识别'),
  segment('断句'),
  translate('翻译'),
  transcode('转码'),
  finish('完成');

  const TaskStage(this.label);

  final String label;
}

enum TaskKind {
  /// 音视频 → 原文字幕。
  transcribe('转写'),

  /// 音视频 → 原文字幕 → 译文字幕。
  transcribeAndTranslate('转写并翻译'),

  /// 已有字幕 → 译文字幕。
  translate('翻译'),

  /// 视频 → 另一种编码或容器的视频。FFmpeg 跑，不产字幕。
  transcode('转码');

  const TaskKind(this.label);

  final String label;

  bool get needsRecognition =>
      this == TaskKind.transcribe || this == TaskKind.transcribeAndTranslate;
  bool get needsTranslation =>
      this == TaskKind.transcribeAndTranslate || this == TaskKind.translate;

  /// 这种任务走的阶段。字幕任务是固定的六段（不需要的那段记为跳过，
  /// 阶段条上画成虚线）；转码只有四段。
  List<TaskStage> get stages => this == TaskKind.transcode
      ? const [
          TaskStage.queued,
          TaskStage.prepare,
          TaskStage.transcode,
          TaskStage.finish,
        ]
      : const [
          TaskStage.queued,
          TaskStage.prepare,
          TaskStage.recognize,
          TaskStage.segment,
          TaskStage.translate,
          TaskStage.finish,
        ];
}
