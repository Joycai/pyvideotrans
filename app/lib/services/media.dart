import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/cue.dart';
import '../domain/speech_segments.dart';
import '../domain/media_kinds.dart';
import '../domain/srt.dart';
import 'provider_api.dart';

/// 文件列表里一行要显示的东西。
class MediaFileInfo {
  const MediaFileInfo({
    required this.path,
    required this.sizeBytes,
    this.duration,
    this.cueCount,
    this.exists = true,
  });

  final String path;
  final int sizeBytes;

  /// 音视频是媒体时长，字幕是最后一条的结束时间。探测不到时为 null。
  final Duration? duration;

  /// 字幕文件解析出的条数。非字幕文件为 null。
  ///
  /// 0 表示这是个字幕文件但一条都没读出来 —— 空文件、编码坏、或根本不是字幕。
  /// 这类文件跑起来必然是空任务，要在界面上先标出来。
  final int? cueCount;

  final bool exists;

  /// 字幕文件解析不出内容。
  bool get isEmptySubtitle => cueCount == 0;

  String get fileName => path.split(RegExp(r'[/\\]')).last;

  /// 「1.2 GB」「734 MB」这样的人类可读大小。
  String get sizeLabel {
    if (sizeBytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = sizeBytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

/// ffmpeg / ffprobe 的定位与调用。
///
/// 识别服务要的是 16kHz 单声道音频，不是原视频 —— 直接上传 mp4 既慢又常触发
/// 大小限制。抽音放在「准备」阶段，产物落在任务的工作目录里，
/// 这样识别阶段失败重试时不需要重新抽。
class Media {
  Media({String? ffmpegPath, String? ffprobePath})
    : _ffmpeg = ffmpegPath,
      _ffprobe = ffprobePath;

  String? _ffmpeg;
  String? _ffprobe;

  /// 除 PATH 外还会找的位置。macOS 上 GUI 应用拿不到用户 shell 的 PATH，
  /// Homebrew 装的 ffmpeg 必须显式找。
  static const _searchDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/snap/bin',
  ];

  String get ffmpeg => _ffmpeg ??= _locate('ffmpeg');
  String get ffprobe => _ffprobe ??= _locate('ffprobe');

  bool get available {
    try {
      ffmpeg;
      return true;
    } on ProviderException {
      return false;
    }
  }

  static String _locate(String name) {
    final exe = Platform.isWindows ? '$name.exe' : name;

    // 与可执行文件同级的 ffmpeg/ 目录（打包分发时把二进制放这儿）。
    final bundled = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}$exe',
    );
    if (bundled.existsSync()) return bundled.path;

    for (final dir in _searchDirs) {
      final candidate = File('$dir${Platform.pathSeparator}$exe');
      if (candidate.existsSync()) return candidate.path;
    }

    // 最后交给 PATH。能跑通就用它。
    try {
      final probe = Process.runSync(exe, ['-version']);
      if (probe.exitCode == 0) return exe;
    } on ProcessException {
      // 落到下面统一报错。
    }

    throw ProviderException(
      '找不到 $name',
      detail: '已查找：应用目录/ffmpeg、${_searchDirs.join('、')}、PATH',
      hint: 'macOS 执行 brew install ffmpeg；'
          'Windows 把 ffmpeg.exe 放到应用目录的 ffmpeg 文件夹下。',
    );
  }

  /// 读取媒体时长。取不到时返回 null，不让它阻断流水线。
  Future<Duration?> probeDuration(String path) async {
    try {
      final result = await Process.run(ffprobe, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        path,
      ]);
      if (result.exitCode != 0) return null;
      final seconds = double.tryParse(result.stdout.toString().trim());
      return seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round());
    } on ProviderException {
      return null;
    } on ProcessException {
      return null;
    }
  }

  /// 选完文件后要在列表里显示的那点信息：大小与时长。
  ///
  /// 探测失败不抛异常 —— 文件列表显示不出时长，不该拦着用户建任务；
  /// 真正读不了的文件会在准备阶段报错，那里的报错信息更具体。
  Future<MediaFileInfo> probeFile(String path) async {
    final file = File(path);
    var size = 0;
    try {
      size = await file.length();
    } on FileSystemException {
      size = 0;
    }
    if (MediaKinds.isSubtitle(path)) {
      final cues = await _readCues(file, size);
      return MediaFileInfo(
        path: path,
        sizeBytes: size,
        duration: cues.isEmpty
            ? null
            : Duration(milliseconds: cues.last.endMs),
        cueCount: cues.length,
        exists: file.existsSync(),
      );
    }

    return MediaFileInfo(
      path: path,
      sizeBytes: size,
      duration: await probeDuration(path),
      exists: file.existsSync(),
    );
  }

  /// 解析字幕文件，拿条数与时间跨度。任何失败都当作「读不出内容」。
  ///
  /// 不走 ffprobe：字幕就是文本，自己解析比起一个进程快得多，而且 ffprobe
  /// 对 ASS/SSA 的时长报得并不准。
  static Future<List<Cue>> _readCues(File file, int size) async {
    // 正常字幕撑死几百 KB。超过这个量级多半是拖错了文件，别把整份读进内存。
    if (size <= 0 || size > 8 * 1024 * 1024) return const [];
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return const [];
    }
    // 不是 UTF-8 就按 latin1 读。正文会是乱码，但时间码是 ASCII，
    // 条数与时间跨度照样准 —— 这两项才是文件列表要显示的东西。
    // （不能用 readAsString：dart:io 把解码失败包成 FileSystemException，
    // 与「文件读不了」混在一起，分不开。）
    try {
      return Srt.parse(utf8.decode(bytes));
    } on FormatException {
      return Srt.parse(latin1.decode(bytes));
    }
  }

  /// 用 silencedetect 找出静音区间。给不带时间戳的识别接口切句用。
  ///
  /// [noiseDb] 是判定为静音的响度阈值，[minSilenceMs] 是最短静音时长；
  /// 默认值与原 Python 实现的 VAD 参数（600 ms）对齐。
  Future<List<TimeRange>> detectSilences(
    String audioPath, {
    required CancellationToken token,
    int noiseDb = -35,
    int minSilenceMs = 600,
  }) async {
    final total = await probeDuration(audioPath);
    final stderr = await _runFfmpeg([
      '-i', audioPath,
      '-af', 'silencedetect=noise=${noiseDb}dB:d=${minSilenceMs / 1000}',
      '-f', 'null',
      '-',
    ], token: token, what: '静音检测');
    return SpeechSegments.parseSilenceDetect(
      stderr,
      total?.inMilliseconds ?? 0,
    );
  }

  /// 从 [sourcePath] 切出 [startMs, endMs) 到 [outputPath]，保持 16 kHz 单声道。
  ///
  /// [padMs] 在片段前后各补一段静音，而不是多截真实音频：多截会把相邻片段
  /// 的半个词带进来，识别出的文字与时间码对不上，相邻两段还会重复识别同一个词。
  Future<void> cutAudio({
    required String sourcePath,
    required String outputPath,
    required int startMs,
    required int endMs,
    required CancellationToken token,
    int padMs = 0,
  }) async {
    await File(outputPath).parent.create(recursive: true);
    // 用 -ss + -t（时长）而不是 -to：-to 放在 -i 之前时，
    // 不同 ffmpeg 版本里它相对的是输入起点还是 seek 之后并不一致，
    // 切出来的长度会差出一个 startMs。wav 没有关键帧，输入端 seek 是逐样本精确的。
    // -t 也放在输入端：只限定读多少原音频，补的静音不受它截断。
    await _runFfmpeg([
      '-y',
      '-ss', (startMs / 1000).toStringAsFixed(3),
      '-t', ((endMs - startMs) / 1000).toStringAsFixed(3),
      '-i', sourcePath,
      if (padMs > 0) ...[
        '-af',
        'adelay=$padMs:all=1,apad=pad_dur=${(padMs / 1000).toStringAsFixed(3)}',
      ],
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'pcm_s16le',
      outputPath,
    ], token: token, what: '切分音频');
  }

  /// 连子进程一起杀。Scoop / Chocolatey 装的 ffmpeg.exe 是个 shim，真正干活
  /// 的 ffmpeg 是它的子进程，只杀 shim 的话 ffmpeg 照跑。子进程要先杀：父进程
  /// 一死，taskkill /T 就找不到这棵树了。
  static Future<void> killTree(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } else {
        await Process.run('pkill', ['-KILL', '-P', '${process.pid}']);
      }
    } on ProcessException {
      // 没有 taskkill / pkill 时退回只杀直接子进程。
    }
    process.kill();
  }

  /// 取消后每 200ms 杀一次 [process] 的进程树，直到返回的订阅被取消。
  static StreamSubscription<void> killOnCancel(
    Process process,
    CancellationToken token,
  ) {
    var killing = false;
    return Stream<void>.periodic(const Duration(milliseconds: 200)).listen((
      _,
    ) async {
      if (!token.isCancelled || killing) return;
      killing = true;
      await killTree(process);
      killing = false;
    });
  }

  /// 跑一次 ffmpeg，返回 stderr（ffmpeg 把进度与滤镜输出都写在那里）。
  /// 取消时杀掉子进程；非零退出码报错并附上 stderr 末尾。
  Future<String> _runFfmpeg(
    List<String> args, {
    required CancellationToken token,
    required String what,
  }) async {
    token.throwIfCancelled();
    final process = await Process.start(ffmpeg, args);
    final stderr = StringBuffer();
    final drain = process.stderr.map(String.fromCharCodes).listen(stderr.write);
    final watchdog = killOnCancel(process, token);
    final exitCode = await process.exitCode;
    await drain.cancel();
    await watchdog.cancel();
    token.throwIfCancelled();
    if (exitCode != 0) {
      final tail = stderr.toString().trimRight();
      throw ProviderException(
        '$what失败',
        detail: tail.length > 600 ? '…${tail.substring(tail.length - 600)}' : tail,
        hint: '准备阶段产出的音频可能已损坏，请从准备阶段继续。',
      );
    }
    return stderr.toString();
  }

  /// 抽成 16kHz 单声道 WAV。这是各家识别接口的通用输入格式。
  Future<String> extractAudio({
    required String sourcePath,
    required String outputPath,
    required CancellationToken token,
  }) async {
    token.throwIfCancelled();

    if (!File(sourcePath).existsSync()) {
      throw ProviderException(
        '源文件不存在',
        detail: sourcePath,
        hint: '文件可能已被移动或删除。重新选择文件。',
      );
    }

    await File(outputPath).parent.create(recursive: true);

    final process = await Process.start(ffmpeg, [
      '-y',
      '-i', sourcePath,
      '-vn',
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'pcm_s16le',
      outputPath,
    ]);

    // ffmpeg 把进度写在 stderr，不读会把管道塞满导致进程卡死。
    final stderr = StringBuffer();
    final drain = process.stderr
        .map(String.fromCharCodes)
        .listen(stderr.write);

    // 取消时杀掉子进程，不然它会一直跑到文件结束。
    final watchdog = killOnCancel(process, token);

    final exitCode = await process.exitCode;
    await drain.cancel();
    await watchdog.cancel();

    token.throwIfCancelled();

    if (exitCode != 0) {
      final tail = stderr.toString().trimRight();
      throw ProviderException(
        '抽取音频失败',
        detail: tail.length > 600
            ? '…${tail.substring(tail.length - 600)}'
            : tail,
        hint: '多为文件损坏或格式不受支持。用播放器确认文件能正常播放。',
      );
    }

    final out = File(outputPath);
    if (!out.existsSync() || out.lengthSync() == 0) {
      throw const ProviderException(
        '抽取出的音频为空',
        hint: '源文件可能没有音轨。',
      );
    }
    return outputPath;
  }
}
