# 打包与图标

所有平台的图标都从 `icons/generate_icons.py` 生成（方向 B「声波变文字」，设计稿见
Claude Design 项目「字幕工具 App 图标」）。改图标只改这个脚本，然后重跑：

```bash
python3 packaging/icons/generate_icons.py   # 需要 Pillow
```

它会覆盖：

| 产物 | 用途 |
|------|------|
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | macOS 应用图标（1024 画布、824 内容、轻投影，Apple 模板） |
| `windows/runner/resources/app_icon.ico` | Windows 应用、安装包、卸载项图标（满幅、圆角 20%） |
| `linux/icons/hicolor/<n>x<n>/apps/subtitle_studio.png` | Linux 桌面 / 任务栏图标（freedesktop hicolor 主题，16–512 九档，同方形版） |
| `icons/app_icon.icns` | dmg 卷图标 |
| `icons/app_icon_1024.png` / `app_icon_square_1024.png` | 两个版本的原图 |

## 应用名

英文环境 `Joycai Subtitle Studio`，中文环境 `Joycai字幕工具`。同一个名字在五处各存一份，
**改名要五处一起改** —— 系统层面的名字在 Dart 起来之前就定了，共用不了一份：

| 位置 | 管什么 |
|------|--------|
| `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME` | `.app` 的文件名（也是非中英语言下的兜底名） |
| `macos/Runner/{en,zh-Hans,zh-Hant}.lproj/InfoPlist.strings` | 访达、程序坞、菜单栏里按系统语言显示的名字 |
| `windows/runner/main.cpp` + `Runner.rc` | 窗口标题、任务管理器里的说明 |
| `packaging/windows/installer.iss` 的 `[CustomMessages]` | 开始菜单、桌面快捷方式、「应用和功能」里的名字（跟安装语言走） |
| `linux/subtitle_studio.desktop` + `linux/runner/my_application.cc` | 应用菜单条目、窗口标题 |

界面内的那份在 `lib/domain/app_branding.dart`（`MaterialApp.title`）。可执行文件名、安装目录、
dmg / setup 的文件名都保持英文不跟语言走 —— 落盘的路径换语言就变，升级和脚本都会找不到。

## macOS dmg

```bash
brew install create-dmg
packaging/macos/make_dmg.sh        # 产物 build/dist/Joycai Subtitle Studio-<版本>.dmg
```

## Windows 安装包

安装 [Inno Setup 7](https://jrsoftware.org/isinfo.php)（`winget install JRSoftware.InnoSetup.7`，
并把 `C:\Program Files\Inno Setup 7` 加进 PATH），然后：

```bat
flutter build windows --release
iscc packaging\windows\installer.iss
```

产物在 `build\dist\JoycaiSubtitleStudio-<版本>-setup.exe`。安装向导里选中文，装出来叫
「Joycai字幕工具」；选英文叫「Joycai Subtitle Studio」（见下节）。

## Linux

`flutter build linux` 的 bundle 里会自带 `share/icons/hicolor/...` 与
`share/applications/subtitle_studio.desktop`（由 `linux/CMakeLists.txt` 安装），
窗口运行时也会直接从 bundle 里读图标，所以解压即用时任务栏图标就是对的。
要出现在应用菜单里，跑一次安装脚本：

```bash
packaging/linux/install.sh            # 装到 ~/.local，当前用户
sudo packaging/linux/install.sh --system   # 装到 /opt 与 /usr/share
```

它会先按发行版的包管理器装好 libmpv（编辑器预览播放音视频要用；apt / dnf /
pacman / zypper，已装则跳过，`SKIP_DEPS=1` 可跳过这一步），然后复制 bundle、
注册 hicolor 图标和 .desktop，并刷新图标缓存。
