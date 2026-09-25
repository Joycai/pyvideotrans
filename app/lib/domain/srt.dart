import 'cue.dart';

/// SRT / VTT 的解析与序列化。
///
/// 时间码格式 `00:00:01,200`（VTT 用 `.` 作小数点，解析时一并接受）。
abstract final class Srt {
  static final _timeLine = RegExp(
    r'^\s*((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})\s*-->\s*'
    r'((?:\d+:)?\d{1,2}:\d{1,2}[,.]\d{1,3})(?:\s+.*)?\s*$',
  );

  /// 毫秒 → `00:00:01,200`。
  static String formatTimecode(int ms, {String decimalMark = ','}) {
    final clamped = ms < 0 ? 0 : ms;
    final h = clamped ~/ 3600000;
    final m = (clamped % 3600000) ~/ 60000;
    final s = (clamped % 60000) ~/ 1000;
    final milli = clamped % 1000;
    return '${_pad(h)}:${_pad(m)}:${_pad(s)}$decimalMark'
        '${milli.toString().padLeft(3, '0')}';
  }

  /// `01:02:03,450` → 毫秒。格式不合法时返回 null。
  static int? parseTimecode(String raw) {
    return _parseTimestamp(raw.trim());
  }

  /// 时长（不含毫秒），用于任务列表的 `48:12` / `1:32:05`。
  ///
  /// [alwaysHours] 为 true 时不足一小时也写出小时位（`0:48:12`）：批量文件的
  /// 总时长经常过小时，位数固定才好前后比较。
  static String formatDuration(Duration d, {bool alwaysHours = false}) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 || alwaysHours
        ? '$h:${_pad(m)}:${_pad(s)}'
        : '${_pad(m)}:${_pad(s)}';
  }

  /// 解析 SRT / VTT 文本。
  ///
  /// 容错：允许缺失序号、CRLF、BOM、块间多个空行；时间码行之前的所有行都当序号丢弃。
  /// 时间码不合法的块会被跳过而不是让整份文件解析失败。
  static List<Cue> parse(String text) {
    final normalized = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final cues = <Cue>[];
    for (final block in normalized.split(RegExp(r'\n[ \t]*\n'))) {
      final lines = block
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      final timeIndex = lines.indexWhere(_timeLine.hasMatch);
      if (timeIndex < 0) continue;

      final m = _timeLine.firstMatch(lines[timeIndex])!;
      final start = _parseTimestamp(m.group(1)!);
      final end = _parseTimestamp(m.group(2)!);
      if (start == null || end == null) continue;

      final body = lines.sublist(timeIndex + 1).join('\n').trim();
      if (body.isEmpty) continue;

      cues.add(
        Cue(
          index: cues.length + 1,
          startMs: start,
          endMs: end < start ? start : end,
          source: body,
        ),
      );
    }
    return cues;
  }

  /// 行首说话人标签：「周老师：正文」「Speaker 2: text」。
  static final _speakerLabel = RegExp(
    r'^\s*([^\s:：][^:：\n]{0,15}?)\s*[:：]\s*(\S.*)$',
  );
  static final _genericSpeaker = RegExp(
    r'^(?:说话人|speaker\s*)(\d{1,3})$',
    caseSensitive: false,
  );
  static final _labelPunctuation = RegExp(r'[,，。.!?！？、;；"“”()（）\[\]【】/]');

  /// 识别整份字幕行首的说话人标签：去掉标签，换成说话人编号。
  ///
  /// 至少 30% 的非空条目带标签才算数 —— 零星一两句「注意：」不该把整份文件
  /// 改掉；不同标签超过 20 种也不算，那更像是正文里的冒号。
  /// 「说话人3」「Speaker 3」这类默认标签直接换回编号 2，不记名字；其他标签
  /// 按出现顺序依次占用还空着的最小编号，并记下名字 —— 第一个开口的人是
  /// 1 号，徽标颜色与名单顺序都从他开始。没带标签的条目保持原样。
  static SpeakerLabelDetection? detectSpeakerLabels(List<Cue> cues) {
    final found = <int, ({String label, String rest})>{};
    var nonEmpty = 0;
    for (final (i, cue) in cues.indexed) {
      if (cue.source.trim().isEmpty) continue;
      nonEmpty++;
      final lines = cue.source.split('\n');
      final m = _speakerLabel.firstMatch(lines.first);
      if (m == null) continue;
      final label = m.group(1)!.trim();
      if (!_isSpeakerLabel(label)) continue;
      found[i] = (
        label: label,
        rest: [m.group(2)!, ...lines.skip(1)].join('\n').trim(),
      );
    }
    // Set 字面量保持插入顺序，即标签第一次出现的顺序。
    final labels = {for (final f in found.values) f.label};
    if (nonEmpty == 0 ||
        found.length < nonEmpty * 0.3 ||
        labels.length > 20) {
      return null;
    }

    final ids = <String, int>{};
    for (final label in labels) {
      final generic = _genericSpeaker.firstMatch(label);
      final n = generic == null ? 0 : int.parse(generic.group(1)!);
      if (n >= 1) ids[label] = n - 1;
    }
    final taken = ids.values.toSet();
    var next = 0;
    final names = <int, String>{};
    for (final label in labels) {
      if (ids.containsKey(label)) continue;
      while (taken.contains(next)) {
        next++;
      }
      ids[label] = next;
      names[next] = label;
      taken.add(next);
    }

    return SpeakerLabelDetection(
      cues: [
        for (final (i, cue) in cues.indexed)
          switch (found[i]) {
            final f? => cue.copyWith(source: f.rest, speaker: ids[f.label]),
            null => cue,
          },
      ],
      speakers: names,
      labels: labels.toList(),
    );
  }

  /// 像不像人名：不超过 16 个字、三个词，不含句读，不是纯数字（「10:30」
  /// 是时间），也不是网址的协议头。
  static bool _isSpeakerLabel(String label) {
    if (label.isEmpty || label.length > 16) return false;
    if (RegExp(r'^\d+$').hasMatch(label)) return false;
    if (_labelPunctuation.hasMatch(label)) return false;
    if (label.split(RegExp(r'\s+')).length > 3) return false;
    return !RegExp(r'^https?$', caseSensitive: false).hasMatch(label);
  }

  /// 序列化为 SRT。
  ///
  /// [field] 决定写哪一路文本：原文、译文，或双语（两行挤在同一条字幕里，
  /// 不是两个文件）。
  ///
  /// [wrapSource] / [wrapTranslation] 在写出前处理文本，用来做单行字数折行 ——
  /// 折行只发生在产物里，文档本身始终保持不带硬换行的干净文本，否则用户在
  /// 编辑器里改一个字就得重新折一遍。两路分开传是因为双语字幕的两行往往
  /// 语种不同，中日韩一行 15 字、拉丁语一行 40 字，用同一个上限必然有一边难看。
  ///
  /// [speakerLabel] 把说话人编号（0 起）变成写在字幕前面的标签，比如
  /// 「说话人1：」；不传就不写标签，编号只留在文档里。
  static String serialize(
    List<Cue> cues, {
    SrtField field = SrtField.source,
    String Function(String)? wrapSource,
    String Function(String)? wrapTranslation,
    String Function(int)? speakerLabel,
  }) {
    final buffer = StringBuffer();
    var line = 0;
    for (final cue in cues) {
      final text = textOf(
        cue,
        field,
        wrapSource: wrapSource,
        wrapTranslation: wrapTranslation,
        speakerLabel: speakerLabel,
      );
      if (text.trim().isEmpty) continue;

      line++;
      buffer
        ..writeln(line)
        ..writeln(
          '${formatTimecode(cue.startMs)} --> ${formatTimecode(cue.endMs)}',
        )
        ..writeln(text)
        ..writeln();
    }
    return buffer.toString();
  }

  /// 序列化为 WebVTT。与 SRT 只差一个文件头和小数点分隔符。
  static String serializeVtt(
    List<Cue> cues, {
    SrtField field = SrtField.source,
    String Function(String)? wrapSource,
    String Function(String)? wrapTranslation,
    String Function(int)? speakerLabel,
  }) {
    final buffer = StringBuffer()
      ..writeln('WEBVTT')
      ..writeln();
    for (final cue in cues) {
      final text = textOf(
        cue,
        field,
        wrapSource: wrapSource,
        wrapTranslation: wrapTranslation,
        speakerLabel: speakerLabel,
      );
      if (text.trim().isEmpty) continue;
      buffer
        ..writeln(
          '${formatTimecode(cue.startMs, decimalMark: '.')} --> '
          '${formatTimecode(cue.endMs, decimalMark: '.')}',
        )
        ..writeln(text)
        ..writeln();
    }
    return buffer.toString();
  }

  /// 只要文字，不要时间码 —— 拿去做纪要或喂给别的工具。
  static String serializePlain(
    List<Cue> cues, {
    SrtField field = SrtField.source,
    String Function(int)? speakerLabel,
  }) {
    final buffer = StringBuffer();
    for (final cue in cues) {
      final text = textOf(cue, field, speakerLabel: speakerLabel);
      if (text.trim().isEmpty) continue;
      buffer.writeln(text.replaceAll('\n', ' '));
    }
    return buffer.toString();
  }

  static String textOf(
    Cue cue,
    SrtField field, {
    String Function(String)? wrapSource,
    String Function(String)? wrapTranslation,
    String Function(int)? speakerLabel,
  }) {
    String source() => wrapSource == null ? cue.source : wrapSource(cue.source);
    String translation() {
      final text = cue.translation ?? '';
      return wrapTranslation == null ? text : wrapTranslation(text);
    }

    final body = _fieldText(cue, field, source, translation);
    final speaker = cue.speaker;
    // 标签只加在第一行：双语两行各加一遍既啰嗦又把译文那行挤长。
    if (speaker == null || speakerLabel == null || body.trim().isEmpty) {
      return body;
    }
    return '${speakerLabel(speaker)}$body';
  }

  static String _fieldText(
    Cue cue,
    SrtField field,
    String Function() source,
    String Function() translation,
  ) {
    return switch (field) {
      SrtField.source => source(),
      SrtField.translation => translation(),
      // 双语里译文缺失时只写原文 —— 留一行空的会让播放器多顶一行高度，
      // 而这条恰恰是用户最该看清原文的时候。
      SrtField.bilingualTargetAbove => [
        if (cue.hasTranslation) translation(),
        source(),
      ].join('\n'),
      SrtField.bilingualTargetBelow => [
        source(),
        if (cue.hasTranslation) translation(),
      ].join('\n'),
    };
  }

  static int? _parseTimestamp(String raw) {
    final parts = raw.trim().split(RegExp(r'[:,.]'));
    if (parts.length != 3 && parts.length != 4) return null;
    final offset = parts.length == 4 ? 1 : 0;
    final hours = offset == 1 ? int.tryParse(parts[0]) : 0;
    final minutes = int.tryParse(parts[offset]);
    final seconds = int.tryParse(parts[offset + 1]);
    final fraction = int.tryParse(parts[offset + 2]);
    if (hours == null ||
        minutes == null ||
        seconds == null ||
        fraction == null) {
      return null;
    }
    // SRT/VTT timestamps use 0..59 for minutes and seconds. Hours may grow
    // beyond two digits for long recordings.
    if (minutes > 59 || seconds > 59 || fraction > 999) return null;
    final millis = int.parse(fraction.toString().padRight(3, '0'));
    return hours * 3600000 + minutes * 60000 + seconds * 1000 + millis;
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}

/// [Srt.detectSpeakerLabels] 的结果。
class SpeakerLabelDetection {
  const SpeakerLabelDetection({
    required this.cues,
    required this.speakers,
    required this.labels,
  });

  /// 去掉了标签、带上说话人编号的字幕。
  final List<Cue> cues;

  /// 起过名字的说话人。「说话人1」这类默认标签不在里面。
  final Map<int, String> speakers;

  /// 文件里出现过的标签，按第一次出现的顺序，给界面提示用。
  final List<String> labels;
}

/// 一条字幕写出哪一路文本。
///
/// 两个双语值的差别只是上下顺序：译文在上更适合「看译文、原文兜底」，
/// 译文在下更适合学语言。播放器两种都认，是纯粹的口味问题，所以给两个选项
/// 而不是替用户选一个。
enum SrtField {
  source,
  translation,
  bilingualTargetAbove,
  bilingualTargetBelow;

  bool get isBilingual =>
      this == bilingualTargetAbove || this == bilingualTargetBelow;
}
