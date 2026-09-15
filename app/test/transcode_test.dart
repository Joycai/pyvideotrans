import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/task_options.dart';
import 'package:subtitle_studio/domain/transcode.dart';
import 'package:subtitle_studio/services/transcoder.dart';

import 'helpers.dart';

TranscodeOptions _opts({
  VideoCodec codec = VideoCodec.h264,
  String? encoder,
  Map<String, Object> params = const {},
  TranscodeMode mode = TranscodeMode.transcode,
  OutputContainer container = OutputContainer.mp4,
  AudioCodec audio = AudioCodec.aac,
  ResolutionLimit resolution = ResolutionLimit.keep,
  int? fps,
  String extra = '',
}) {
  // 复制视频时没有编码器，这时 enc 为 null。
  final enc = encoder == null
      ? VideoEncoders.defaultFor(codec)
      : VideoEncoders.byId(encoder)!;
  return TranscodeOptions(
    mode: mode,
    container: container,
    videoCodec: codec,
    encoderId: enc?.id ?? '',
    encoderParams: {...?enc?.defaults, ...params},
    audioCodec: audio,
    resolution: resolution,
    fps: fps,
    extraArgs: extra,
  );
}

List<String> _build(TranscodeOptions o) => TranscodeCommand.build(
  options: o,
  input: '/in/a.mkv',
  output: '/in/a.out.mp4',
);

/// 取参数 [flag] 后面紧跟的值。
String? _after(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

void main() {
  group('编码器目录', () {
    test('每种编码都有 CPU 编码器排第一，复制没有编码器', () {
      for (final codec in [VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1]) {
        expect(VideoEncoders.defaultFor(codec)!.backend, EncoderBackend.cpu);
        final backends = VideoEncoders.forCodec(codec).map((e) => e.backend);
        expect(backends, containsAll(EncoderBackend.values.where(
          (b) => !(codec == VideoCodec.av1 && b == EncoderBackend.videotoolbox),
        )));
      }
      expect(VideoEncoders.forCodec(VideoCodec.copy), isEmpty);
    });

    test('同是 H.264，x264 与 NVENC 的参数表不同', () {
      final x264 = VideoEncoders.byId('libx264')!.params.map((p) => p.key);
      final nvenc = VideoEncoders.byId('h264_nvenc')!.params.map((p) => p.key);
      expect(x264, contains('crf'));
      expect(x264, isNot(contains('cq')));
      expect(nvenc, containsAll(['cq', 'multipass', 'lookahead', 'hwdec']));
      expect(nvenc, isNot(contains('crf')));
    });

    test('参数值收拾：越界夹回、非法选项回默认、多余键丢掉', () {
      final enc = VideoEncoders.byId('libx264')!;
      final v = enc.sanitize({'crf': 99, 'preset': 'warp', 'bogus': 1});
      expect(v['crf'], 51);
      expect(v['preset'], 'medium');
      expect(v.containsKey('bogus'), isFalse);
      expect(v['rc'], 'crf');
    });

    test('码率控制决定哪个数值框可见', () {
      final enc = VideoEncoders.byId('h264_nvenc')!;
      final cq = enc.sanitize({'rc': 'cq'});
      final vbr = enc.sanitize({'rc': 'vbr'});
      expect(enc.param('cq')!.isVisible(cq), isTrue);
      expect(enc.param('bitrate')!.isVisible(cq), isFalse);
      expect(enc.param('bitrate')!.isVisible(vbr), isTrue);
      expect(enc.param('maxrate')!.isVisible(vbr), isTrue);
    });
  });

  group('命令', () {
    test('x264 CRF：preset、crf、8 位像素格式、快速启动、容器', () {
      final args = _build(_opts(params: {'crf': 20, 'preset': 'slow'}));
      expect(_after(args, '-c:v'), 'libx264');
      expect(_after(args, '-crf'), '20');
      expect(_after(args, '-preset'), 'slow');
      expect(_after(args, '-pix_fmt'), 'yuv420p');
      expect(_after(args, '-movflags'), '+faststart');
      expect(_after(args, '-f'), 'mp4');
      expect(args.last, '/in/a.out.mp4');
      expect(args, isNot(contains('-tune')));
    });

    test('NVENC CQ 模式：-rc vbr -cq N -b:v 0，硬件解码放在 -i 前面', () {
      final args = _build(
        _opts(
          encoder: 'hevc_nvenc',
          codec: VideoCodec.hevc,
          params: {'cq': 19, 'preset': 'p6', 'hwdec': true, 'lookahead': 20},
        ),
      );
      expect(_after(args, '-c:v'), 'hevc_nvenc');
      expect(_after(args, '-rc'), 'vbr');
      expect(_after(args, '-cq'), '19');
      expect(_after(args, '-b:v'), '0');
      expect(_after(args, '-preset'), 'p6');
      expect(_after(args, '-rc-lookahead'), '20');
      expect(_after(args, '-tag:v'), 'hvc1');
      expect(args.indexOf('-hwaccel'), lessThan(args.indexOf('-i')));
      expect(_after(args, '-hwaccel'), 'cuda');
    });

    test('VideoToolbox 恒定质量与固定码率', () {
      final q = _build(_opts(encoder: 'h264_videotoolbox', params: {'quality': 70}));
      expect(_after(q, '-q:v'), '70');
      expect(_after(q, '-hwaccel'), 'videotoolbox');
      final cbr = _build(
        _opts(
          encoder: 'h264_videotoolbox',
          params: {'rc': 'cbr', 'bitrate': 8000, 'hwdec': false},
        ),
      );
      expect(_after(cbr, '-b:v'), '8000k');
      expect(_after(cbr, '-constant_bit_rate'), '1');
      expect(cbr, isNot(contains('-hwaccel')));
    });

    test('QSV ICQ 与 AMF CQP', () {
      final qsv = _build(_opts(encoder: 'h264_qsv', params: {'quality': 25}));
      expect(_after(qsv, '-global_quality'), '25');
      expect(_after(qsv, '-pix_fmt'), 'nv12');
      final amf = _build(_opts(encoder: 'h264_amf', params: {'qp': 21}));
      expect(_after(amf, '-rc'), 'cqp');
      expect(_after(amf, '-qp_i'), '21');
      expect(_after(amf, '-qp_b'), '21');
    });

    test('重混流：视频音频都复制，缩放与帧率不生效', () {
      final args = _build(
        _opts(
          mode: TranscodeMode.remux,
          resolution: ResolutionLimit.p720,
          fps: 30,
        ),
      );
      expect(_after(args, '-c:v'), 'copy');
      expect(_after(args, '-c:a'), 'copy');
      expect(args, isNot(contains('-vf')));
    });

    test('只缩小不放大；帧率接在缩放后面；额外参数支持引号', () {
      final args = _build(
        _opts(
          resolution: ResolutionLimit.p1080,
          fps: 30,
          extra: "-x264-params 'aq-mode=3' -metadata title=\"a b\"",
        ),
      );
      expect(_after(args, '-vf'), "scale=w=-2:h='min(1080,ih)',fps=30");
      expect(_after(args, '-x264-params'), 'aq-mode=3');
      expect(_after(args, '-metadata'), 'title=a b');
    });

    test('音频编码器替补与声道', () {
      final args = TranscodeCommand.build(
        options: _opts(audio: AudioCodec.opus).copyWith(audioChannels: 2),
        input: 'a.mkv',
        output: 'b.mp4',
        audioEncoder: ('opus', ['-strict', '-2']),
      );
      expect(_after(args, '-c:a'), 'opus');
      expect(_after(args, '-strict'), '-2');
      expect(_after(args, '-ac'), '2');
    });

    test('进度输出只在跑任务时加', () {
      expect(_build(_opts()), isNot(contains('-progress')));
      final run = TranscodeCommand.build(
        options: _opts(),
        input: 'a',
        output: 'b',
        progress: true,
      );
      expect(_after(run, '-progress'), 'pipe:1');
    });

    test('命令展示给带空格的参数加引号', () {
      expect(
        TranscodeCommand.display(['-i', '/a b/c.mkv', '-vf', "x='y'"]),
        "ffmpeg -i '/a b/c.mkv' -vf 'x='\\''y'\\'''",
      );
    });
  });

  group('产物路径', () {
    test('源文件旁、带后缀、不覆盖已有文件', () {
      final o = _opts(codec: VideoCodec.hevc);
      final taken = {'/m/a.hevc.mp4', '/m/a.hevc-2.mp4'};
      expect(
        TranscodeCommand.outputPath(
          input: '/m/a.mkv',
          options: o,
          exists: taken.contains,
        ),
        '/m/a.hevc-3.mp4',
      );
    });

    test('指定目录与自定义后缀；与源文件同名时也加序号', () {
      final o = _opts().copyWith(
        outputLocation: OutputLocation.custom,
        outputDir: '/out/',
        suffix: '',
      );
      expect(
        TranscodeCommand.outputPath(input: '/m/a.mp4', options: o, exists: (_) => false),
        '/out/a.h264.mp4',
      );
      final same = _opts().copyWith(suffix: 'x');
      expect(
        TranscodeCommand.outputPath(
          input: '/m/a.x.mp4',
          options: same,
          exists: (_) => false,
        ),
        '/m/a.x.x.mp4',
      );
    });

    test('重混流默认后缀 remux', () {
      expect(_opts(mode: TranscodeMode.remux).resolvedSuffix, 'remux');
    });
  });

  group('容器兼容', () {
    test('参数本身的问题：MOV 里的 AV1、MOV 里的 Opus', () {
      expect(
        _opts(codec: VideoCodec.av1, container: OutputContainer.mov).problem,
        contains('AV1'),
      );
      expect(
        _opts(audio: AudioCodec.opus, container: OutputContainer.mov).problem,
        contains('Opus'),
      );
      expect(_opts(audio: AudioCodec.opus).problem, isNull);
      // 重混流不重新编码音频，所选音频编码不起作用。
      expect(
        _opts(
          mode: TranscodeMode.remux,
          container: OutputContainer.mov,
          audio: AudioCodec.opus,
        ).problem,
        isNull,
      );
    });

    test('复制流时按源文件编码判断（名单来自本机实测）', () {
      const wmv = MediaProbe(
        video: [VideoStreamInfo(codec: 'wmv3')],
        audio: [AudioStreamInfo(codec: 'wmav2')],
      );
      final remux = _opts(mode: TranscodeMode.remux);
      expect(wmv.incompatibility(remux), contains('WMV3'));
      // 视频转码、音频复制：卡在 WMA 上。
      expect(
        wmv.incompatibility(_opts(audio: AudioCodec.copy)),
        contains('WMA'),
      );
      expect(wmv.incompatibility(_opts()), isNull);

      const flacVp9 = MediaProbe(
        video: [VideoStreamInfo(codec: 'vp9')],
        audio: [AudioStreamInfo(codec: 'flac')],
      );
      expect(flacVp9.incompatibility(remux), isNull);
      expect(
        flacVp9.incompatibility(
          _opts(mode: TranscodeMode.remux, container: OutputContainer.mov),
        ),
        isNotNull,
      );
    });
  });

  group('ffprobe / 进度解析', () {
    test('跳过封面附图，帧率取 avg_frame_rate', () {
      final probe = MediaProbe.fromJson({
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'hevc',
            'width': 3840,
            'height': 2160,
            'avg_frame_rate': '60000/1001',
            'disposition': {'attached_pic': 0},
          },
          {
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'disposition': {'attached_pic': 1},
          },
          {'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2},
          {'codec_type': 'subtitle', 'codec_name': 'subrip'},
        ],
        'format': {'duration': '2892.5'},
      });
      expect(probe.video, hasLength(1));
      expect(probe.video.single.shape, '3840×2160 · 59.94p');
      expect(probe.audio.single.channels, 2);
      expect(probe.subtitleCount, 1);
      expect(probe.duration, const Duration(milliseconds: 2892500));
    });

    test('进度区块', () {
      final p = TranscodeProgress.parse({
        'frame': '90',
        'out_time_us': '3018594',
        'speed': '26.1x',
        'progress': 'end',
      });
      expect(p.frame, 90);
      expect(p.position.inMilliseconds, 3018);
      expect(p.speed, 26.1);
      expect(p.done, isTrue);
      expect(TranscodeProgress.parse({'out_time_us': 'N/A'}).position, Duration.zero);
    });

    test('ffmpeg -encoders 列表', () {
      const out = '''
Encoders:
 V..... = Video
 ------
 V....D libx264              libx264 H.264 / AVC
 V....D h264_videotoolbox    VideoToolbox H.264 Encoder (codec h264)
 A..X.D vorbis               Vorbis
''';
      expect(
        Transcoder.parseEncoderList(out),
        containsAll(['libx264', 'h264_videotoolbox', 'vorbis']),
      );
      expect(Transcoder.parseEncoderList(out), isNot(contains('=')));
    });

    test('失败原因分类', () {
      expect(
        Transcoder.describeFailure(
          '[mp4 @ 0x1] Could not find tag for codec wmv2 in stream #0',
          'copy',
        ).message,
        '容器装不下其中一路流',
      );
      expect(
        Transcoder.describeFailure(
          '[h264_nvenc @ 0x1] No capable devices found\n'
          'Error while opening encoder',
          'h264_nvenc',
        ).message,
        'h264_nvenc 初始化失败',
      );
      expect(
        Transcoder.explainEncoderFailure(
          VideoEncoders.byId('hevc_nvenc')!,
          'Cannot load libnvcuvid.so.1',
        ),
        '没有找到 NVIDIA 显卡或驱动',
      );
      // AMD 核显不支持 AV1：-v error 下 stderr 末行是「Nothing was written」，
      // 不能把那句原样给用户。
      expect(
        Transcoder.explainEncoderFailure(
          VideoEncoders.byId('av1_amf')!,
          '[vf#0:0 @ 0x1] Terminating thread with return code -1129203192 (Encoder not found)\n'
          '[vost#0:0/av1_amf @ 0x1] [enc:av1_amf @ 0x1] Could not open encoder before EOF\n'
          '[out#0/null @ 0x1] Nothing was written into output file, because at least one of its streams received no packets.',
        ),
        '显卡不支持 AV1 编码',
      );
      expect(
        Transcoder.explainEncoderFailure(
          VideoEncoders.byId('av1_amf')!,
          '[av1_amf @ 0x1] CreateComponent(AMFVideoEncoderHW_AV1) failed with error 30',
        ),
        '显卡不支持 AV1 编码',
      );
    });
  });

  group('任务', () {
    test('转码任务只有四个阶段，识别与翻译不算需要', () {
      expect(TaskKind.transcode.stages, [
        TaskStage.queued,
        TaskStage.prepare,
        TaskStage.transcode,
        TaskStage.finish,
      ]);
      expect(TaskKind.transcode.needsRecognition, isFalse);
      expect(TaskKind.transcode.needsTranslation, isFalse);
      expect(TaskKind.translate.stages, isNot(contains(TaskStage.transcode)));
    });

    test('存档往返保留转码参数与产物', () {
      final task = SubtitleTask(
        id: 't1',
        sourcePath: '/m/a.mkv',
        kind: TaskKind.transcode,
        options: testOptions(),
        transcode: TranscodeJob(
          options: _opts(
            encoder: 'hevc_videotoolbox',
            codec: VideoCodec.hevc,
            params: {'quality': 72},
          ),
          outputPath: '/m/a.hevc.mp4',
          command: 'ffmpeg …',
          sourceVideo: 'H.264',
        ),
      );
      task.stages[TaskStage.prepare] = const StageRecord(state: StageState.done);
      final back = SubtitleTask.fromJson(
        task.toJson(),
        fallbackOptions: testOptions(),
      );
      expect(back.kind, TaskKind.transcode);
      expect(back.resumeStage, TaskStage.queued);
      final job = back.transcode!;
      expect(job.options.encoderId, 'hevc_videotoolbox');
      expect(job.options.resolvedParams['quality'], 72);
      expect(job.outputPath, '/m/a.hevc.mp4');
      expect(job.direction, 'H.264 → HEVC · MP4');
    });

    test('旧存档里的编码器与编码对不上时回落到默认编码器', () {
      final o = TranscodeOptions.fromJson({
        'videoCodec': 'av1',
        'encoderId': 'libx264',
        'encoderParams': {'crf': 10},
      });
      expect(o.encoderId, 'libsvtav1');
      expect(o.resolvedParams['crf'], 35);
    });
  });
}
