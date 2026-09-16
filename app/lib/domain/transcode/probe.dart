import 'codecs.dart';
import 'options.dart';

class VideoStreamInfo {
  const VideoStreamInfo({
    required this.codec,
    this.width,
    this.height,
    this.fps,
    this.pixFmt,
  });

  final String codec;
  final int? width;
  final int? height;
  final double? fps;
  final String? pixFmt;

  /// 「3840×2160 · 60p」。
  String get shape => [
    if (width != null && height != null) '$width×$height',
    if (fps != null) '${fps! % 1 == 0 ? fps!.toInt() : fps!.toStringAsFixed(2)}p',
  ].join(' · ');
}

class AudioStreamInfo {
  const AudioStreamInfo({required this.codec, this.channels});

  final String codec;
  final int? channels;
}

/// ffprobe 读出的流信息。附图（封面）不算视频流。
class MediaProbe {
  const MediaProbe({
    this.duration,
    this.video = const [],
    this.audio = const [],
    this.subtitleCount = 0,
  });

  final Duration? duration;
  final List<VideoStreamInfo> video;
  final List<AudioStreamInfo> audio;
  final int subtitleCount;

  bool get isEmpty => video.isEmpty && audio.isEmpty;

  /// 解析 `ffprobe -show_streams -show_format -of json` 的输出。
  factory MediaProbe.fromJson(Map<String, Object?> json) {
    final streams = (json['streams'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => s.cast<String, Object?>());
    final video = <VideoStreamInfo>[];
    final audio = <AudioStreamInfo>[];
    var subs = 0;
    for (final s in streams) {
      final codec = s['codec_name'] as String? ?? 'unknown';
      final disposition = s['disposition'];
      final attachedPic =
          disposition is Map && disposition['attached_pic'] == 1;
      switch (s['codec_type']) {
        case 'video' when !attachedPic:
          video.add(
            VideoStreamInfo(
              codec: codec,
              width: s['width'] as int?,
              height: s['height'] as int?,
              fps: _rate(s['avg_frame_rate']) ?? _rate(s['r_frame_rate']),
              pixFmt: s['pix_fmt'] as String?,
            ),
          );
        case 'audio':
          audio.add(
            AudioStreamInfo(codec: codec, channels: s['channels'] as int?),
          );
        case 'subtitle':
          subs++;
      }
    }
    final seconds = double.tryParse(
      '${(json['format'] as Map?)?['duration'] ?? ''}',
    );
    return MediaProbe(
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      video: video,
      audio: audio,
      subtitleCount: subs,
    );
  }

  /// 「30000/1001」→ 29.97；「0/0」→ null。
  static double? _rate(Object? raw) {
    final parts = '$raw'.split('/');
    if (parts.length != 2) return double.tryParse('$raw');
    final n = double.tryParse(parts[0]);
    final d = double.tryParse(parts[1]);
    if (n == null || d == null || d == 0 || n == 0) return null;
    return (n / d * 100).round() / 100;
  }

  /// 按 [options] 转进 [container] 时哪路流放不进去。null 表示都能放。
  String? incompatibility(TranscodeOptions options) {
    final container = options.container;
    if (options.effectiveVideo == VideoCodec.copy) {
      for (final v in video) {
        if (!container.acceptsVideoCopy(v.codec)) {
          return '${codecLabel(v.codec)} 视频不能直接放进 ${container.label}';
        }
      }
    }
    if (options.effectiveAudio == AudioCodec.copy) {
      for (final a in audio) {
        if (!container.acceptsAudioCopy(a.codec)) {
          return '${codecLabel(a.codec)} 音频不能直接放进 ${container.label}';
        }
      }
    }
    return null;
  }

  /// ffprobe 的编码名 → 界面上的写法。
  static String codecLabel(String codec) => switch (codec) {
    'h264' => 'H.264',
    'hevc' => 'HEVC',
    'av1' => 'AV1',
    'vc1' => 'VC-1',
    'vp9' => 'VP9',
    'vp8' => 'VP8',
    'mpeg4' => 'MPEG-4',
    'mpeg2video' => 'MPEG-2',
    'prores' => 'ProRes',
    'wmv3' => 'WMV3',
    'wmv2' => 'WMV2',
    'aac' => 'AAC',
    'mp3' => 'MP3',
    'opus' => 'Opus',
    'vorbis' => 'Vorbis',
    'flac' => 'FLAC',
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'dts' => 'DTS',
    'truehd' => 'TrueHD',
    'alac' => 'ALAC',
    final c when c.startsWith('wma') => 'WMA',
    final c when c.startsWith('pcm_') => 'PCM',
    final c => c.toUpperCase(),
  };
}
