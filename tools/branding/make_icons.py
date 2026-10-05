#!/usr/bin/env python3
"""Makes the platform icons from the app icon master (docs/specs/menus.md section 1.2).

    python3 tools/branding/make_icons.py

Reads docs/branding/app_icon_1080.png (kept out of the game so it does not ship) and writes to game/branding/: app_icon_512.png, app_icon_256.png, app_icon.ico
(16, 32, 48, 64, 128, 256 px) and app_icon.icns (16 to 1024 px, with the 2x sizes). Needs Pillow.
"""
import os
import shutil
import subprocess
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "branding")
MASTER = os.path.join(os.path.dirname(os.path.dirname(HERE)), "docs", "branding", "app_icon_1080.png")


def sized(img, px):
    return img.resize((px, px), Image.LANCZOS)


def icns(img, path):
    # iconutil (macOS) when there is one, else Pillow's writer
    if shutil.which("iconutil"):
        with tempfile.TemporaryDirectory() as tmp:
            iconset = os.path.join(tmp, "app_icon.iconset")
            os.mkdir(iconset)
            for px in (16, 32, 128, 256, 512):
                sized(img, px).save(os.path.join(iconset, "icon_%dx%d.png" % (px, px)))
                sized(img, px * 2).save(os.path.join(iconset, "icon_%dx%d@2x.png" % (px, px)))
            subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)
    else:
        sized(img, 1024).save(path, format="ICNS")


def main():
    img = Image.open(MASTER).convert("RGBA")
    for px in (512, 256):
        sized(img, px).save(os.path.join(OUT, "app_icon_%d.png" % px), optimize=True)
    sizes = [16, 32, 48, 64, 128, 256]
    sized(img, 256).save(os.path.join(OUT, "app_icon.ico"), format="ICO", sizes=[(s, s) for s in sizes])
    icns(img, os.path.join(OUT, "app_icon.icns"))
    for f in sorted(os.listdir(OUT)):
        print(os.path.join(OUT, f), os.path.getsize(os.path.join(OUT, f)))


if __name__ == "__main__":
    main()
