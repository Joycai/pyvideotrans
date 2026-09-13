#!/usr/bin/env python3
"""生成「字幕工具」全平台应用图标（方向 B：声波变文字）。

只依赖 Pillow。跑一次会覆盖：
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
  windows/runner/resources/app_icon.ico
  linux/icons/hicolor/<n>x<n>/apps/subtitle_studio.png（freedesktop hicolor 主题）
  packaging/icons/app_icon.icns          （dmg 卷图标）
  packaging/icons/app_icon_1024.png      （macOS 版，带透明边距）
  packaging/icons/app_icon_square_1024.png（Windows / Linux 版，满幅圆角）

用法：python3 packaging/icons/generate_icons.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]  # app/
OUT = Path(__file__).resolve().parent

# 设计系统令牌
GRADIENT_TOP = (0x5B, 0x8D, 0xF2)
GRADIENT_BOTTOM = (0x2A, 0x63, 0xF5)
WHITE = (255, 255, 255, 255)
WHITE_DIM = (255, 255, 255, 158)  # 62%
AMBER = (0xFF, 0xE5, 0x8A, 255)

# 设计稿以 512 为基准坐标
BASE = 512
WAVES = [  # (left, height)，宽 32，垂直居中
    (56, 120),
    (108, 232),
    (160, 312),
    (212, 184),
]
BARS = [  # (top, width, color)，左 288，高 40
    (196, 168, WHITE),
    (260, 120, WHITE_DIM),
    (324, 168, AMBER),
]
RADIUS_RATIO = 115 / 512  # macOS squircle 近似 22.5%

SS = 4  # 超采样倍数


def _gradient(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(GRADIENT_TOP[0] + (GRADIENT_BOTTOM[0] - GRADIENT_TOP[0]) * t)
        g = round(GRADIENT_TOP[1] + (GRADIENT_BOTTOM[1] - GRADIENT_TOP[1]) * t)
        b = round(GRADIENT_TOP[2] + (GRADIENT_BOTTOM[2] - GRADIENT_TOP[2]) * t)
        # 顶部内高光：上半段白色 18% → 0
        hl = max(0.0, 0.18 * (1 - t / 0.5)) if t < 0.5 else 0.0
        r = round(r + (255 - r) * hl)
        g = round(g + (255 - g) * hl)
        b = round(b + (255 - b) * hl)
        for x in range(size):
            px[x, y] = (r, g, b, 255)
    return img


def draw_tile(size: int, radius_ratio: float = RADIUS_RATIO) -> Image.Image:
    """画一块 size×size 的图标本体（含圆角），内部按 512 基准等比缩放。"""
    s = size * SS
    k = s / BASE
    tile = _gradient(s)

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, s - 1, s - 1), radius=round(s * radius_ratio), fill=255
    )

    fg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    for left, h in WAVES:
        w = 32 * k
        top = (BASE - h) / 2 * k
        d.rounded_rectangle(
            (left * k, top, left * k + w, top + h * k), radius=w / 2, fill=WHITE
        )
    for top, w, color in BARS:
        h = 40 * k
        d.rounded_rectangle(
            (288 * k, top * k, 288 * k + w * k, top * k + h), radius=h / 2, fill=color
        )
    tile.alpha_composite(fg)

    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def macos_icon(size: int) -> Image.Image:
    """macOS 版：1024 画布里放 824 的圆角方块（Apple 模板边距），带轻投影。"""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = round(size * 824 / 1024)
    margin = (size - inner) // 2
    tile = draw_tile(inner)

    if size >= 64:
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sh_mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(sh_mask).rounded_rectangle(
            (margin, margin, margin + inner - 1, margin + inner - 1),
            radius=round(inner * RADIUS_RATIO),
            fill=int(255 * 0.28),
        )
        shadow.putalpha(sh_mask)
        shadow = shadow.transform(
            shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -size * 0.012)
        )  # 向下偏移
        shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.012))
        canvas.alpha_composite(shadow)

    canvas.alpha_composite(tile, (margin, margin))
    return canvas


def square_icon(size: int) -> Image.Image:
    """Windows / Linux 版：满幅，圆角 20%，无边距无投影。"""
    return draw_tile(size, radius_ratio=0.20)


def main() -> None:
    iconset_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    ico_path = ROOT / "windows/runner/resources/app_icon.ico"

    # ---- macOS appiconset ----
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    mac_images: dict[int, Image.Image] = {}
    for n in mac_sizes:
        img = macos_icon(n)
        mac_images[n] = img
        img.save(iconset_dir / f"app_icon_{n}.png")
        print("wrote", iconset_dir / f"app_icon_{n}.png")
    mac_images[1024].save(OUT / "app_icon_1024.png")

    # ---- icns（dmg 卷图标 / 其他用途）----
    if shutil.which("iconutil"):
        with tempfile.TemporaryDirectory() as td:
            iconset = Path(td) / "app_icon.iconset"
            iconset.mkdir()
            for n in [16, 32, 128, 256, 512]:
                mac_images[n].save(iconset / f"icon_{n}x{n}.png")
                mac_images[n * 2].save(iconset / f"icon_{n}x{n}@2x.png")
            subprocess.run(
                ["iconutil", "-c", "icns", str(iconset), "-o", str(OUT / "app_icon.icns")],
                check=True,
            )
            print("wrote", OUT / "app_icon.icns")
    else:
        print("iconutil 不可用，跳过 icns（只能在 macOS 上生成）", file=sys.stderr)

    # ---- Windows ico ----
    win_sizes = [16, 24, 32, 48, 64, 128, 256]
    win_images = [square_icon(n) for n in win_sizes]
    win_images[-1].save(
        ico_path,
        format="ICO",
        sizes=[(n, n) for n in win_sizes],
        append_images=win_images[:-1],
    )
    print("wrote", ico_path)
    square_icon(1024).save(OUT / "app_icon_square_1024.png")
    print("wrote", OUT / "app_icon_square_1024.png")

    # ---- Linux hicolor ----
    hicolor = ROOT / "linux/icons/hicolor"
    for n in [16, 22, 24, 32, 48, 64, 128, 256, 512]:
        d = hicolor / f"{n}x{n}" / "apps"
        d.mkdir(parents=True, exist_ok=True)
        square_icon(n).save(d / "subtitle_studio.png")
    print("wrote", hicolor)


if __name__ == "__main__":
    main()
