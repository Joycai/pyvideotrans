# Flutter 与依赖升级

## 计划

1. 核对并升级到 Flutter stable 最新版本，记录 Flutter / Dart 基线。
2. 升级直接和间接 pub 依赖（包括主版本），同步原生依赖锁文件，处理兼容性变化。
3. 运行静态分析、完整测试和 macOS 构建，检查锁文件与源码差异。

应用发布版本独立于 SDK 版本，本次不调整应用版本号。

## 升级结果（2026-10-30）

- Flutter stable：3.47.8 → 3.47.9；Dart 基线：3.13.7。
- `flutter pub upgrade --major-versions` 更新 20 个直接 / 间接依赖；
  `shared_preferences` 约束同步提升到 `^2.5.6`。
- 其余直接依赖已是当前可解的最新版本，没有使用 `dependency_overrides`。

### 上游版本限制

| 包 | 当前 | 最新 | 限制 |
| --- | --- | --- | --- |
| desktop_drop | 0.8.4 | 0.9.2 | 0.9.x 要求 cross_file ^0.4.0，与 file_selector 1.1.0 经 platform_interface 引入的 ^0.3.0 冲突 |
| cross_file | 0.3.5+5 | 0.4.0 | file_selector_platform_interface 2.7.0 仍要求 ^0.3.0 |
| dbus | 0.7.15 | 0.8.0 | desktop_drop 0.8.4 要求 ^0.7.10 |
| wakelock_plus | 1.8.0 | 1.8.2 | 新版要求 dbus ^0.8.0，与 desktop_drop 0.8.4 冲突 |
| material_color_utilities | 0.13.0 | 0.13.1 | Flutter SDK 固定 0.13.0 |
| test_api | 0.7.12 | 0.7.15 | flutter_test 固定 0.7.12 |

已通过 `flutter pub outdated --json` 和 `flutter pub add 'desktop_drop:^0.9.2' --dry-run`
确认限制。后续等待上游约束兼容后再升级，避免破坏文件选择、拖放及测试工具链。

## 验证

- `flutter analyze`：通过，无问题。
- `flutter test`：1105 通过，15 跳过，无失败。
- `flutter build macos --release`：通过，产物约 97.3 MB；CocoaPods 锁文件无变化。
- `git diff --check`：通过；未改业务代码或 golden 基线。
- Windows / Linux 原生构建未在本机验证。

macOS 构建仍有上游 `media_kit_video` 的 Objective-C 类型警告；
`media_kit_libs_macos_video` 与 `media_kit_video` 尚未支持 Swift Package Manager，
当前仍由 CocoaPods 构建。Flutter 提示未来版本可能不再支持这一路径，后续升级需复查。
