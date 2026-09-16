#!/usr/bin/env bash
# 把 flutter build linux 的 bundle 安装到本机，并注册桌面图标。
# 用法：packaging/linux/install.sh                 （装到 ~/.local，当前用户）
#      sudo packaging/linux/install.sh --system    （装到 /opt 与 /usr/share，全局）
#      SKIP_BUILD=1 packaging/linux/install.sh     （跳过 flutter build）
#      SKIP_DEPS=1 packaging/linux/install.sh      （跳过安装 libmpv）
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

# 编辑器预览用 media_kit 播放音视频，Linux 上要系统的 libmpv：编译需要头文件，
# 运行需要 libmpv.so.2。按发行版的包管理器装；已经有了就不动。
install_libmpv() {
  if ldconfig -p 2>/dev/null | grep -q 'libmpv\.so\.2' && \
     pkg-config --exists mpv 2>/dev/null; then
    echo "libmpv 已安装"
    return
  fi
  local sudo=""
  [[ $EUID -ne 0 ]] && sudo="sudo"
  if command -v apt-get >/dev/null; then
    $sudo apt-get install -y libmpv-dev mpv
  elif command -v dnf >/dev/null; then
    $sudo dnf install -y mpv-libs-devel mpv
  elif command -v pacman >/dev/null; then
    $sudo pacman -S --needed --noconfirm mpv
  elif command -v zypper >/dev/null; then
    $sudo zypper install -y mpv-devel mpv
  else
    echo "不认识这个发行版的包管理器，请自行安装 libmpv（开发包 + 运行库）后重跑，或加 SKIP_DEPS=1 跳过" >&2
    exit 1
  fi
}

if [[ -z "${SKIP_DEPS:-}" ]]; then
  install_libmpv
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
