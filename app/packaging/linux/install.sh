#!/usr/bin/env bash
# 把 flutter build linux 的 bundle 安装到本机，并注册桌面图标。
# 用法：packaging/linux/install.sh                 （装到 ~/.local，当前用户）
#      sudo packaging/linux/install.sh --system    （装到 /opt 与 /usr/share，全局）
#      SKIP_BUILD=1 packaging/linux/install.sh     （跳过 flutter build）
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$APP_DIR"
APP_NAME="subtitle_studio"
BUNDLE="$APP_DIR/build/linux/x64/release/bundle"

if [[ "${1:-}" == "--system" ]]; then
  OPT_DIR="/opt/$APP_NAME"
  BIN_DIR="/usr/local/bin"
  SHARE_DIR="/usr/share"
else
  OPT_DIR="$HOME/.local/opt/$APP_NAME"
  BIN_DIR="$HOME/.local/bin"
  SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
fi

if [[ -z "${SKIP_BUILD:-}" ]]; then
  flutter build linux --release
fi
[[ -d "$BUNDLE" ]] || { echo "找不到 $BUNDLE" >&2; exit 1; }

rm -rf "$OPT_DIR"
mkdir -p "$OPT_DIR" "$BIN_DIR" "$SHARE_DIR/applications"
cp -r "$BUNDLE"/. "$OPT_DIR"/
ln -sf "$OPT_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"

# bundle/share 里已经带了 hicolor 图标与 .desktop（由 linux/CMakeLists.txt 安装）
cp -r "$BUNDLE/share/icons" "$SHARE_DIR/"
cp "$BUNDLE/share/applications/$APP_NAME.desktop" "$SHARE_DIR/applications/"

command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$SHARE_DIR/icons/hicolor" || true
command -v update-desktop-database >/dev/null && update-desktop-database -q "$SHARE_DIR/applications" || true

echo "已安装到 $OPT_DIR，桌面入口 $SHARE_DIR/applications/$APP_NAME.desktop"
