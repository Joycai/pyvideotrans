/// J/K 留给字幕导航；映射绑定身份编号，不能随名单排序漂移。
const speakerHotkeyLetters = 'abcdefghilmnopqrstuvwxyz';

/// null 表示清除说话人，-1 表示目标已失效，缺少键表示未配置。
Map<String, int?> readSpeakerHotkeys(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final e in raw.entries)
      if (e.key is String &&
          (e.key as String).length == 1 &&
          speakerHotkeyLetters.contains(e.key as String) &&
          (e.value == null || e.value is int))
        e.key as String: e.value as int?,
  };
}
