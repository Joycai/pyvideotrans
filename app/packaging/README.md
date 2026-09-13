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
| `icons/app_icon.icns` | dmg 卷图标 |
| `icons/app_icon_1024.png` / `app_icon_square_1024.png` | 两个版本的原图，Linux 桌面图标可直接用方形版 |

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
