import 'cue.dart';

/// SRT / VTT 的解析与序列化。
///
/// 时间码格式 `00:00:01,200`（VTT 用 `.` 作小数点，解析时一并接受）。
abstract final class Srt {
  static final _timeLine = RegExp(
    r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*'
    r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})',
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
    final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})$')
        .firstMatch(raw.trim());
    if (m == null) return null;
    return _toMs(m, 1);
  }

  /// 时长（不含毫秒），用于任务列表的 `48:12` / `1:32:05`。
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${_pad(m)}:${_pad(s)}' : '${_pad(m)}:${_pad(s)}';
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

      final timeIndex = lines.indexWhere((l) => _timeLine.hasMatch(l));
      if (timeIndex < 0) continue;

      final m = _timeLine.firstMatch(lines[timeIndex])!;
      final start = _toMs(m, 1);
      final end = _toMs(m, 5);

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

  /// 序列化为 SRT。
  ///
  /// [field] 决定写哪一路文本：原文、译文，或双语（译文在上、原文在下，
  /// 与大多数播放器的双语习惯一致）。
  static String serialize(
    List<Cue> cues, {
    SrtField field = SrtField.source,
  }) {
    final buffer = StringBuffer();
    var line = 0;
    for (final cue in cues) {
      final text = switch (field) {
        SrtField.source => cue.source,
        SrtField.translation => cue.translation ?? '',
        SrtField.bilingual => [
          if (cue.hasTranslation) cue.translation!,
          cue.source,
        ].join('\n'),
      };
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

  static int _toMs(RegExpMatch m, int group) {
    final frac = m.group(group + 3)!;
    return int.parse(m.group(group)!) * 3600000 +
        int.parse(m.group(group + 1)!) * 60000 +
        int.parse(m.group(group + 2)!) * 1000 +
        // VTT 允许 1–2 位小数，补齐到毫秒。
        int.parse(frac.padRight(3, '0'));
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}

enum SrtField { source, translation, bilingual }
