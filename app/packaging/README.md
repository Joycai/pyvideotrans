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

## macOS dmg

```bash
brew install create-dmg
packaging/macos/make_dmg.sh        # 产物 build/dist/字幕工具-<版本>.dmg
```

## Windows 安装包

安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)，然后：

```bat
flutter build windows --release
iscc packaging\windows\installer.iss
```

产物在 `build\dist\字幕工具-<版本>-setup.exe`。

## Linux

`flutter build linux` 的 bundle 里会自带 `share/icons/hicolor/...` 与
`share/applications/subtitle_studio.desktop`（由 `linux/CMakeLists.txt` 安装），
窗口运行时也会直接从 bundle 里读图标，所以解压即用时任务栏图标就是对的。
要出现在应用菜单里，跑一次安装脚本：

```bash
packaging/linux/install.sh            # 装到 ~/.local，当前用户
sudo packaging/linux/install.sh --system   # 装到 /opt 与 /usr/share
```

它会复制 bundle、注册 hicolor 图标和 .desktop，并刷新图标缓存。
