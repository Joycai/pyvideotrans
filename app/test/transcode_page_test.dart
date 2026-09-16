import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/transcode.dart';
import 'package:subtitle_studio/features/transcode/transcode_form.dart';
import 'package:subtitle_studio/features/transcode/transcode_page.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/provider_api.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

/// 不起进程的转码器：编码器状态与源文件信息都由测试给定。
class FakeTranscoder extends Transcoder {
  FakeTranscoder({this.states = const {}});

  final Map<String, EncoderStatus> states;

  @override
  EncoderStatus status(String encoderId) =>
      states[encoderId] ?? const EncoderStatus(EncoderState.available);

  @override
  Future<void> ensureProbed() async {}

  @override
  Future<void> refresh() async {}

  @override
  (String, List<String>) audioEncoder(AudioCodec codec) =>
      (codec.encoder, const []);

  @override
  Future<MediaProbe> probe(String path) async {
    if (path.endsWith('.wmv')) {
      return const MediaProbe(
        video: [VideoStreamInfo(codec: 'wmv3', width: 720, height: 480)],
        audio: [AudioStreamInfo(codec: 'wmav2', channels: 2)],
      );
    }
    if (path.contains('broken')) {
      throw const ProviderException('ffprobe 读不出这个文件');
    }
    return const MediaProbe(
      duration: Duration(minutes: 48, seconds: 12),
      video: [
        VideoStreamInfo(codec: 'hevc', width: 3840, height: 2160, fps: 60),
      ],
      audio: [AudioStreamInfo(codec: 'aac', channels: 2)],
    );
  }
}

/// 找不到 ffmpeg 的转码器。只用来验证「开始」下面那句拦截理由。
class _MissingFfmpegTranscoder extends FakeTranscoder {
  @override
  String? get ffmpegProblem => '找不到 ffmpeg';

  @override
  String? get ffmpegHint =>
      '在「设置 → 环境」里打开目录，把 ffmpeg.exe 放进去，再点重新检测。';
}

void main() {
  late AppSettings settings;
  late TaskQueue queue;
  late TranscodeFormController form;
  late FakeTranscoder transcoder;

  Future<void> pumpPage(
    WidgetTester tester, {
    Map<String, EncoderStatus> states = const {},
  }) async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    transcoder = FakeTranscoder(states: states);
    queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: '/tmp/none',
        transcoder: transcoder,
      ),
      settings: settings,
    );
    form = TranscodeFormController(settings: settings, transcoder: transcoder);
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: TranscodePage(form: form, queue: queue, onOpenTasks: () {}),
        ),
      ),
    );
  }

  testWidgets('空态：开始按钮禁用，页脚提示先添加视频', (tester) async {
    await pumpPage(tester);
    expect(find.text('把视频拖到这里'), findsOneWidget);
    expect(find.text('先添加视频'), findsOneWidget);
    expect(form.canStart, isFalse);
  });

  testWidgets('换编码器，参数表整块换掉：x264 有 CRF，NVENC 有 CQ 与多遍编码', (tester) async {
    await pumpPage(tester);
    expect(find.text('CRF'), findsOneWidget);
    expect(find.text('CQ'), findsNothing);

    await tester.tap(find.text('NVENC · NVIDIA'));
    await tester.pumpAndSettle();
    expect(form.options.encoderId, 'h264_nvenc');
    expect(find.text('CQ'), findsOneWidget);
    expect(find.text('多遍编码'), findsOneWidget);
    expect(find.text('CUDA 硬件解码'), findsOneWidget);
    expect(find.text('CRF'), findsNothing);
  });

  testWidgets('按编码器记住参数：切走再切回来，NVENC 的 CQ 还在', (tester) async {
    await pumpPage(tester);
    form.selectEncoder('h264_nvenc');
    form.setParam('cq', 31);
    form.selectEncoder('libx264');
    expect(form.options.resolvedParams['crf'], 23);
    form.selectEncoder('h264_nvenc');
    expect(form.options.resolvedParams['cq'], 31);
  });

  testWidgets('不可用的编码器不能选，卡片上写明原因', (tester) async {
    await pumpPage(
      tester,
      states: {
        'h264_nvenc': const EncoderStatus(
          EncoderState.failed,
          '没有找到 NVIDIA 显卡或驱动',
        ),
        'h264_qsv': const EncoderStatus(
          EncoderState.notCompiled,
          '此 FFmpeg 没有编入 h264_qsv',
        ),
      },
    );
    expect(find.text('没有找到 NVIDIA 显卡或驱动'), findsOneWidget);
    expect(find.text('未编入'), findsOneWidget);
    await tester.tap(find.text('NVENC · NVIDIA'));
    await tester.pumpAndSettle();
    expect(form.options.encoderId, 'libx264');
  });

  testWidgets('不提供 VC-1 与 Vorbis；MOV 下 AV1 与 Opus 灰掉', (tester) async {
    await pumpPage(tester);
    expect(find.text('VC-1'), findsNothing);
    expect(find.text('Vorbis'), findsNothing);

    await tester.tap(find.text('MOV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AV1'));
    // 音频段在参数面板下方，先滚到可见再点，否则点空了测不到禁用。
    await tester.ensureVisible(find.text('Opus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(form.options.videoCodec, VideoCodec.h264);
    expect(form.options.audioCodec, AudioCodec.aac);
  });

  testWidgets('选了 Opus 再切到 MOV：音频自动改成 AAC，开始不被拦', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.text('Opus'));
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(form.options.audioCodec, AudioCodec.opus);

    await tester.ensureVisible(find.text('MOV'));
    await tester.tap(find.text('MOV'));
    await tester.pumpAndSettle();
    expect(form.options.container, OutputContainer.mov);
    expect(form.options.audioCodec, AudioCodec.aac);
    expect(form.blocker, isNull);

    // 切回 MP4 不会把 AAC 再改回去。
    form.setContainer(OutputContainer.mp4);
    expect(form.options.audioCodec, AudioCodec.aac);
  });

  // 这句提示以前对所有平台都写死「macOS 执行 brew install ffmpeg」，
  // Windows 用户看到的恰恰是最没用的那句。现在按平台的建议由 Media 给出、
  // Transcoder 透传，界面只管显示。
  test('找不到 FFmpeg 时，开始的拦截理由带上按平台给的建议', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    final form = TranscodeFormController(
      settings: s,
      transcoder: _MissingFfmpegTranscoder(),
    );

    expect(form.blocker, contains('找不到 FFmpeg'));
    expect(form.blocker, contains('设置 → 环境'));
    expect(form.blocker, isNot(contains('brew')));
  });

  testWidgets('加文件、跳过不兼容的、开始后入队并清空列表', (tester) async {
    await pumpPage(tester);
    // add 里读文件大小是真 IO，在测试的假时钟里不会完成，得放到 runAsync 里。
    await tester.runAsync(
      () => form.add(['/m/interview.mkv', '/m/old.wmv', '/m/notes.txt']),
    );
    await tester.pumpAndSettle();
    expect(find.text('interview.mkv'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(form.enqueueable, hasLength(2));

    // 改成重混流：WMV3 / WMA 放不进 MP4，那一行变成不兼容。
    await tester.tap(find.text('仅重混流'));
    await tester.pumpAndSettle();
    expect(find.text('不兼容'), findsOneWidget);
    expect(form.enqueueable, hasLength(1));
    expect(form.footer.text, contains('1 个文件不兼容，将跳过'));

    await tester.tap(find.text('开始转码 · 1'));
    await tester.pump();
    expect(queue.tasks, hasLength(1));
    final task = queue.tasks.single;
    expect(task.kind, TaskKind.transcode);
    expect(task.transcode!.options.remux, isTrue);
    expect(form.files, isEmpty);
    expect(find.textContaining('已加入队列'), findsOneWidget);
    queue.cancel(task.id);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('命令预览跟着参数变', (tester) async {
    await pumpPage(tester);
    form.selectEncoder('h264_videotoolbox');
    form.setParam('quality', 72);
    form.advancedOpen = true;
    await tester.pumpAndSettle();
    expect(form.commandPreview, contains('-c:v h264_videotoolbox'));
    expect(form.commandPreview, contains('-q:v 72'));
    expect(find.textContaining('-q:v 72'), findsOneWidget);
  });
}
