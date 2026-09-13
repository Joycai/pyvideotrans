import 'package:subtitle_studio/features/editor/editor_session.dart';

import 'helpers.dart';

/// 设计稿 M-EditorFrame 本地会话那 14 行：原文带说话人标签，译文少一条、
/// 多一条找不到原文的。
const _rows = [
  (
    '00:00:01,200',
    '00:00:04,350',
    'Mia',
    '周老师，先请您介绍一下这次的实验。',
    'Professor Zhou, could you start by introducing this experiment?',
  ),
  (
    '00:00:04,350',
    '00:00:06,500',
    'Mia',
    '我们从第二章开始聊。',
    "Let's start from chapter two.",
  ),
  (
    '00:00:06,500',
    '00:00:10,040',
    '周老师',
    '好，这一批样本是去年十月采集的。',
    'Sure. This batch of samples was collected last October.',
  ),
  (
    '00:00:10,040',
    '00:00:13,170',
    '周老师',
    '一共四百多份，分三次送检。',
    'More than four hundred in total, sent in three rounds.',
  ),
  ('00:00:13,170', '00:00:13,920', '说话人3', '嗯。', 'Mm-hmm.'),
  (
    '00:00:13,920',
    '00:00:17,260',
    '周老师',
    '第一次的结果和预期差得比较远。',
    'The first round came out quite far from what we expected.',
  ),
  ('00:00:17,260', '00:00:19,030', 'Mia', '差在哪一块？', 'Where was the gap?'),
  (
    '00:00:19,030',
    '00:00:22,680',
    '周老师',
    '主要是低浓度区间的信号不稳。',
    'Mostly unstable signal in the low-concentration range.',
  ),
  ('00:00:22,680', '00:00:26,120', '周老师', '所以我们把采样间隔改成了三十秒。', ''),
  (
    '00:00:26,120',
    '00:00:29,100',
    '周老师',
    '改完之后重复性好了很多。',
    'Repeatability improved a lot after the change.',
  ),
  (
    '00:00:29,100',
    '00:00:31,520',
    'Mia',
    '这个结论写进论文了吗？',
    'Did that finding make it into the paper?',
  ),
  (
    '00:00:31,520',
    '00:00:35,260',
    '周老师',
    '写进附录了，正文只留了结论。',
    "It's in the appendix; the main text only keeps the conclusion.",
  ),
  (
    '00:00:36,620',
    '00:00:39,920',
    'Mia',
    '明白，我们下一段聊设备。',
    "Got it. Next we'll talk about the equipment.",
  ),
];

String get localZhSrt => [
  for (final (i, r) in _rows.indexed)
    '${i + 1}\n${r.$1} --> ${r.$2}\n${r.$3}：${r.$4}\n',
].join('\n');

String get localEnSrt {
  final blocks = <String>[
    for (final r in _rows)
      if (r.$5.isNotEmpty) '${r.$1} --> ${r.$2}\n${r.$5}\n',
    // 两条原文之间的空档里多出来的一句。
    '00:00:35,260 --> 00:00:36,620\nRight, in batches.\n',
  ]..sort();
  return [for (final (i, b) in blocks.indexed) '${i + 1}\n$b'].join('\n');
}

LocalSubtitleFile localZhFile() => LocalSubtitleFile.parse(
  '/Users/mia/Movies/采访/interview_ep12.zh.srt',
  localZhSrt,
);

LocalSubtitleFile localEnFile() => LocalSubtitleFile.parse(
  '/Users/mia/Movies/采访/interview_ep12.en.srt',
  localEnSrt,
);

FileSession localSession({bool withTranslation = true}) => FileSession.open(
  source: localZhFile(),
  translation: withTranslation ? localEnFile() : null,
  defaults: testOptions(source: 'zh', target: 'en'),
);
