#!/usr/bin/env bash
# 把 flutter build macos 的产物打成 dmg，卷图标与应用图标统一用 packaging/icons/app_icon.icns。
# 用法：packaging/macos/make_dmg.sh            （先自动 flutter build macos --release）
#      SKIP_BUILD=1 packaging/macos/make_dmg.sh （已有构建产物时跳过编译）
# 依赖：brew install create-dmg
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$APP_DIR"

# .app 的名字跟 AppInfo.xcconfig 的 PRODUCT_NAME 一致；中文名由 app 内的
# zh-Hans.lproj/InfoPlist.strings 提供，dmg 这类落盘文件不跟语言走，统一用英文。
APP_NAME="Joycai Subtitle Studio"
DISPLAY_NAME="Joycai Subtitle Studio"
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)"
ICNS="$APP_DIR/packaging/icons/app_icon.icns"
APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="$APP_DIR/build/dist"
DMG="$DIST/${DISPLAY_NAME}-${VERSION}.dmg"

if [[ ! -f "$ICNS" ]]; then
  echo "缺少 $ICNS，先跑 python3 packaging/icons/generate_icons.py" >&2
  exit 1
fi
command -v create-dmg >/dev/null || { echo "需要 create-dmg：brew install create-dmg" >&2; exit 1; }

if [[ -z "${SKIP_BUILD:-}" ]]; then
  flutter build macos --release
fi
[[ -d "$APP_BUNDLE" ]] || { echo "找不到 $APP_BUNDLE" >&2; exit 1; }

mkdir -p "$DIST"
rm -f "$DMG"

create-dmg \
  --volname "$DISPLAY_NAME" \
  --volicon "$ICNS" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 150 190 \
  --app-drop-link 450 190 \
  --hide-extension "${APP_NAME}.app" \
  "$DMG" \
  "$APP_BUNDLE"

echo "已生成 $DMG"
