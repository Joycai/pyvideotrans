import 'cue.dart';

/// 按打开弹窗时的原身份同时替换，避免 A→B、B→C 意外连锁。
SubtitleDocument mapSelectedSpeakers(
  SubtitleDocument document,
  Iterable<int> positions,
  Map<int?, int?> mapping, {
  Map<int, String> newSpeakers = const {},
}) {
  final selected = positions.toSet();
  if (selected.any((p) => p < 0 || p >= document.cues.length)) {
    throw ArgumentError('选区已失效');
  }
  final existingIds = document.speakerIds.toSet();
  final used = <int>{};
  var changed = false;
  final cues = [
    for (var i = 0; i < document.cues.length; i++)
      (() {
        final cue = document.cues[i];
        if (!selected.contains(i) || !mapping.containsKey(cue.speaker)) {
          return cue;
        }
        final target = mapping[cue.speaker];
        if (target == cue.speaker) return cue;
        if (target != null) {
          if (!existingIds.contains(target) &&
              !newSpeakers.containsKey(target)) {
            throw ArgumentError('目标说话人不存在');
          }
          used.add(target);
        }
        changed = true;
        return cue.copyWith(speaker: target, clearSpeaker: target == null);
      })(),
  ];
  if (!changed) return document;
  final names = {...document.speakers};
  for (final id in used.where(newSpeakers.containsKey)) {
    final name = newSpeakers[id]!.trim();
    if (name.isEmpty || existingIds.contains(id)) {
      throw ArgumentError('新说话人的名字或编号无效');
    }
    names[id] = name;
  }
  return document.copyWith(cues: cues, speakers: names);
}
