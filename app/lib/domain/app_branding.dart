/// 应用名。英文环境用 `Joycai Subtitle Studio`，中文环境用 `Joycai字幕工具`。
///
/// 同一个名字在四个地方各有一份，且**没法共用这一份**——系统层面的名字在 Dart
/// 启动之前就定了，读不到这里：macOS `Runner/*.lproj/InfoPlist.strings`、
/// Windows 安装包的 `[CustomMessages]` 与 `runner/main.cpp`、
/// Linux `subtitle_studio.desktop` 与 `runner/my_application.cc`。改名要一起改。
library;

const String appNameEnglish = 'Joycai Subtitle Studio';
const String appNameChinese = 'Joycai字幕工具';

/// `languageCode` 取自系统区域设置（`PlatformDispatcher.instance.locale`）。
String appNameFor(String languageCode) =>
    languageCode == 'zh' ? appNameChinese : appNameEnglish;
