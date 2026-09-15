/// 按扩展名判断一个文件是媒体还是字幕 —— 这决定了建什么类型的任务：
/// 音视频走转写，字幕直接走翻译。
///
/// 放在 domain 里是因为拖放区、文件选择框和任务队列都要用它，
/// 不该由某一个界面组件持有。
abstract final class MediaKinds {
  static const media = {
    'mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv',
    'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'opus',
  };
  static const subtitle = {'srt', 'vtt', 'ass', 'ssa'};

  /// 只有声音、没有画面的那些；预览时不画视频，只放声音。
  static const audio = {'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'opus'};

  /// 「转码」页收的视频容器。比 [media] 宽：转码常处理录屏、电视录制与老格式。
  static const video = {
    'mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'm4v', 'ts', 'm2ts',
    'mts', 'mpg', 'mpeg', 'vob', '3gp', 'ogv', 'asf', 'mxf',
  };

  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static bool isMedia(String path) => media.contains(extensionOf(path));
  static bool isAudio(String path) => audio.contains(extensionOf(path));
  static bool isVideo(String path) => video.contains(extensionOf(path));
  static bool isSubtitle(String path) => subtitle.contains(extensionOf(path));
  static bool isSupported(String path) => isMedia(path) || isSubtitle(path);
}
