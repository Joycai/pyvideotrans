@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';
import 'package:subtitle_studio/domain/task.dart';
import 'package:subtitle_studio/domain/transcode/codecs.dart';
import 'package:subtitle_studio/domain/transcode/command.dart';
import 'package:subtitle_studio/domain/transcode/encoder_catalog.dart';
import 'package:subtitle_studio/domain/transcode/encoder_params.dart';
import 'package:subtitle_studio/domain/transcode/options.dart';
import 'package:subtitle_studio/domain/transcode/probe.dart';
import 'package:subtitle_studio/features/shared/page_chrome.dart';
import 'package:subtitle_studio/features/shell/app_shell.dart';
import 'package:subtitle_studio/features/shell/nav_rail.dart';
import 'package:subtitle_studio/features/shell/status_bar.dart';
import 'package:subtitle_studio/features/tasks/tasks_board.dart';
import 'package:subtitle_studio/features/transcode/transcode_form.dart';
import 'package:subtitle_studio/features/transcode/transcode_page.dart';
import 'package:subtitle_studio/pipeline/task_queue.dart';
import 'package:subtitle_studio/pipeline/task_runner.dart';
import 'package:subtitle_studio/services/settings.dart';
import 'package:subtitle_studio/services/transcoder.dart';

import '../helpers.dart';

/// 与 render_test.dart 同样的字体处理：测试默认字体不含汉字。
Future<void> _loadCjkFont() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/STHeiti Light.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync().buffer.asByteData();
    for (final family in ['Noto Sans SC', 'JetBrains Mono']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    return;
  }
}

ThemeData _readable(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Noto Sans SC'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Noto Sans SC'),
);

/// 设计稿 M-TranscodePage 的样例：这台 Mac 上 CPU 与 VideoToolbox 可用，
/// NVENC / QSV / AMF 没编进 ffmpeg。`lecture_week3.mp4` 永远停在读取中。
class _FakeTranscoder extends Transcoder {
  @override
  EncoderStatus status(String id) {
    final enc = VideoEncoders.byId(id);
    return switch (enc?.backend) {
      EncoderBackend.cpu ||
      EncoderBackend.videotoolbox => const EncoderStatus(EncoderState.available),
      _ => EncoderStatus(EncoderState.notCompiled, '此 FFmpeg 没有编入 $id'),
    };
  }

  @override
  Future<void> ensureProbed() async {}

  @override
  (String, List<String>) audioEncoder(AudioCodec codec) =>
      (codec.encoder, const []);

  @override
  Future<MediaProbe> probe(String path) {
    final name = path.split('/').last;
    return switch (name) {
      'interview_ep12.mkv' => Future.value(
        const MediaProbe(
          duration: Duration(minutes: 48, seconds: 12),
          video: [
            VideoStreamInfo(codec: 'hevc', width: 3840, height: 2160, fps: 60),
          ],
          audio: [AudioStreamInfo(codec: 'aac', channels: 2)],
        ),
      ),
      'product_demo.mov' => Future.value(
        const MediaProbe(
          duration: Duration(minutes: 6, seconds: 40),
          video: [
            VideoStreamInfo(codec: 'h264', width: 1920, height: 1080, fps: 30),
          ],
          audio: [AudioStreamInfo(codec: 'aac', channels: 2)],
        ),
      ),
      'old_capture.wmv' => Future.value(
        const MediaProbe(
          duration: Duration(minutes: 12, seconds: 5),
          video: [
            VideoStreamInfo(codec: 'wmv3', width: 720, height: 480, fps: 29.97),
          ],
          audio: [AudioStreamInfo(codec: 'wmav2', channels: 2)],
        ),
      ),
      _ => Completer<MediaProbe>().future,
    };
  }
}

const _sizes = {
  'interview_ep12.mkv': 6657199308,
  'product_demo.mov': 851443712,
  'lecture_week3.mp4': 1288490188,
  'old_capture.wmv': 402653184,
};

void main() {
  setUpAll(_loadCjkFont);

  Future<void> frame(
    WidgetTester tester, {
    required Brightness brightness,
    required AppSection section,
    required PageChrome Function() chrome,
    required Listenable live,
    required Widget child,
    double height = 900,
  }) async {
    tester.view
      ..physicalSize = Size(1440, height)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(
          brightness == Brightness.light ? lightTheme : darkTheme,
        ),
        home: AppShell(
          section: section,
          onSectionChanged: (_) {},
          chrome: chrome,
          status: () => const StatusSnapshot(
            ffmpeg: 'ffmpeg · 就绪',
            asr: (connected: true, label: '阿里百炼 · 已配置'),
            translation: (connected: true, label: 'DeepSeek · 已配置'),
          ),
          live: live,
          child: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> shoot(
    WidgetTester tester, {
    required String file,
    required Brightness brightness,
    required String variant,
    String encoder = 'hevc_videotoolbox',
    Map<String, Object> params = const {},
    double height = 900,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final transcoder = _FakeTranscoder();
    final form = TranscodeFormController(
      settings: settings,
      transcoder: transcoder,
      fileSize: (p) async => _sizes[p.split('/').last] ?? 0,
    );
    addTearDown(form.dispose);
    final queue = TaskQueue(
      runner: TaskRunner(
        settings: settings,
        workDir: '/tmp',
        transcoder: transcoder,
      ),
      settings: settings,
    );

    form.setVideoCodec(VideoCodec.hevc);
    form.selectEncoder(encoder);
    for (final e in params.entries) {
      form.setParam(e.key, e.value);
    }
    switch (variant) {
      case 'B':
        form.handleDrop([
          '/Users/mia/Movies/采访/interview_ep12.mkv',
          '/Users/mia/Movies/产品/product_demo.mov',
          '/Users/mia/Movies/课程/lecture_week3.mp4',
        ]);
      case 'C':
        form
          ..handleDrop([
            '/Users/mia/Movies/产品/product_demo.mov',
            '/Users/mia/Movies/旧素材/old_capture.wmv',
          ])
          ..update((o) => o.copyWith(mode: TranscodeMode.remux))
          ..advancedOpen = true;
    }

    await frame(
      tester,
      brightness: brightness,
      section: AppSection.transcode,
      chrome: () => transcodeChrome(form),
      live: form,
      height: height,
      child: TranscodePage(form: form, queue: queue, onOpenTasks: () {}),
    );

    if (variant == 'D') {
      tester
          .state<TranscodePageState>(find.byType(TranscodePage))
          .showEnqueuedBanner(3);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 1));

    await expectLater(find.byType(AppShell), matchesGoldenFile('$file.png'));
    await tester.pump(const Duration(seconds: 7));
  }

  testWidgets('转码页 · A 空态 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_empty_light',
      brightness: Brightness.light,
      variant: 'A',
    );
  });

  testWidgets('转码页 · B 常态 VideoToolbox · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_light',
      brightness: Brightness.light,
      variant: 'B',
    );
  });

  testWidgets('转码页 · B 常态 · 深色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_dark',
      brightness: Brightness.dark,
      variant: 'B',
    );
  });

  testWidgets('转码页 · B 常态 x265 参数 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_x265_light',
      brightness: Brightness.light,
      variant: 'B',
      encoder: 'libx265',
    );
  });

  // 参数面板拉高到不用滚动，逐个编码器核对「参数表随编码器变」。
  // 截图里 NVENC / QSV / AMF 显示「未编入」—— 状态来自假转码器，参数表照常画出。
  for (final (name, encoder, params) in <(String, String, Map<String, Object>)>[
    ('videotoolbox', 'hevc_videotoolbox', {}),
    ('nvenc', 'hevc_nvenc', {'rc': 'vbr'}),
    ('qsv', 'hevc_qsv', {}),
    ('amf', 'hevc_amf', {}),
  ]) {
    testWidgets('转码页 · 编码器参数 $name · 浅色', (tester) async {
      await shoot(
        tester,
        file: 'transcode_params_${name}_light',
        brightness: Brightness.light,
        variant: 'A',
        encoder: encoder,
        params: params,
        height: 2000,
      );
    });
  }

  testWidgets('转码页 · C 仅重混流 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_remux_light',
      brightness: Brightness.light,
      variant: 'C',
    );
  });

  testWidgets('转码页 · D 提交后 · 浅色', (tester) async {
    await shoot(
      tester,
      file: 'transcode_page_submitted_light',
      brightness: Brightness.light,
      variant: 'D',
    );
  });

  testWidgets('任务页 · 转码任务进行中 + 详情 · 浅色', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final running = SubtitleTask(
      id: 'tc1',
      sourcePath: '/Users/mia/Movies/采访/interview_ep12.mkv',
      kind: TaskKind.transcode,
      options: testOptions(),
      status: TaskStatus.running,
      stage: TaskStage.transcode,
      progress: 0.42,
      mediaDuration: const Duration(minutes: 48, seconds: 12),
      eta: const Duration(minutes: 6),
      transcode: TranscodeJob(
        options: TranscodeOptions(
          videoCodec: VideoCodec.hevc,
          encoderId: 'hevc_videotoolbox',
          encoderParams: VideoEncoders.byId('hevc_videotoolbox')!.defaults,
        ),
        sourceVideo: 'HEVC',
        outputPath: '/Users/mia/Movies/采访/interview_ep12.hevc.mp4',
        command:
            'ffmpeg -hide_banner -nostdin -y -hwaccel videotoolbox -i '
            '/Users/mia/Movies/采访/interview_ep12.mkv -map 0:V? -map 0:a? '
            '-c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 -c:a aac -b:a 160k '
            '-movflags +faststart -f mp4 '
            '/Users/mia/Movies/采访/interview_ep12.hevc.mp4',
      ),
    )
      ..stages[TaskStage.queued] = const StageRecord(state: StageState.done)
      ..stages[TaskStage.prepare] = const StageRecord(
        state: StageState.done,
        duration: Duration(seconds: 2),
        note: 'ffprobe · 2 路流',
      )
      ..stages[TaskStage.transcode] = const StageRecord(
        state: StageState.active,
        note: '帧 72944 · 2.4x',
      )
      // 不用 note()：它给日志盖的是 DateTime.now() 的时间戳，详情面板把它
      // 显示出来，截图就会每天自己对不上。直接写死一条。
      ..log.add(
        LogEntry(
          DateTime(2026, 9, 13, 14, 2, 11),
          LogLevel.info,
          '开始转码 · hevc_videotoolbox',
        ),
      );
    final done = SubtitleTask(
      id: 'tc2',
      sourcePath: '/Users/mia/Movies/产品/product_demo.mov',
      kind: TaskKind.transcode,
      options: testOptions(),
      status: TaskStatus.done,
      stage: TaskStage.finish,
      progress: 1,
      mediaDuration: const Duration(minutes: 6, seconds: 40),
      transcode: TranscodeJob(
        options: const TranscodeOptions(mode: TranscodeMode.remux),
        sourceVideo: 'H.264',
        outputPath: '/Users/mia/Movies/产品/product_demo.remux.mp4',
        outputBytes: 851443712,
      ),
    );
    for (final s in TaskKind.transcode.stages) {
      done.stages[s] = const StageRecord(state: StageState.done);
    }
    final subtitle = SubtitleTask(
      id: 'st1',
      sourcePath: '/Users/mia/Movies/采访/interview_ep11.mp4',
      kind: TaskKind.transcribe,
      options: testOptions(asr: 'dashscope_qwen_asr', translate: false),
      status: TaskStatus.queued,
      mediaDuration: const Duration(minutes: 51, seconds: 3),
    );
    final tasks = [running, done, subtitle];
    await frame(
      tester,
      brightness: Brightness.light,
      section: AppSection.tasks,
      chrome: () => const PageChrome(title: '任务', subtitle: '3 个任务 · 1 个进行中 · 0 个失败'),
      live: ChangeNotifier(),
      child: TasksBoard(
        tasks: tasks,
        filter: 'all',
        counts: const {'all': 3, 'running': 2, 'failed': 0, 'done': 1},
        selectedId: 'tc1',
        onFilterChanged: (_) {},
        onSelect: (_) {},
        onAction: (_, _) {},
        onFiles: (_) {},
        onBrowse: () {},
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('transcode_tasks_light.png'),
    );
  });
}
