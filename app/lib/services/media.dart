import 'dart:io';

import '../domain/media_kinds.dart';
import 'provider_api.dart';

/// 文件列表里一行要显示的东西。
class MediaFileInfo {
  const MediaFileInfo({
    required this.path,
    required this.sizeBytes,
    this.duration,
    this.exists = true,
  });

  final String path;
  final int sizeBytes;

  /// 探测不到时为 null（字幕文件、或 ffprobe 读不了）。
  final Duration? duration;

  final bool exists;

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
    return MediaFileInfo(
      path: path,
      sizeBytes: size,
      duration: MediaKinds.isSubtitle(path) ? null : await probeDuration(path),
      exists: file.existsSync(),
    );
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
    final watchdog = Stream.periodic(const Duration(milliseconds: 200)).listen((
      _,
    ) {
      if (token.isCancelled) process.kill();
    });

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
