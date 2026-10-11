#!/usr/bin/env python3
"""Offline previews of the daylight model (water_render.md section 4.5: time of day, conditions, colour grade),
no window. Dumps the chase shot of the water test scene at several hours and conditions
(tests/water_preview_dump.gd with --time, --conditions and --tag), renders them (tests/water_preview.py), applies
each shot's own colour grade (its LUT strip, sampled as Godot does, tests/cine_preview.py; no vignette, there is
none in the game), and composes labelled contact sheets:

    python3 game/tests/daylight_preview.py [--dump] [--size 960x540] [--publish]

--dump runs the Godot dumps first (godot on the path, or GODOT=...). Writes game/generated/daylight_preview/*.png
(with --publish also game/tests/previews/daylight_*.jpg):
  times       the chase camera at 08:00, 11:00, 14:00, 17:00 and 19:00 in fair conditions (Practice Waters, 25 Aug)
  conditions  14:00 in clear, fair, hazy and overcast
  grade       14:00 and 19:00 fair, grade off against the default
Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import water_preview as wp  # noqa: E402
import cine_preview as cp  # noqa: E402

GAME = Path(__file__).resolve().parents[1]
OUT = GAME / "generated" / "daylight_preview"
PUBLISHED = GAME / "tests" / "previews"
SHOT = "bay20_chase_M"

# (tag, time, conditions)
TIMES = [("d0800", "08:00", "fair"), ("d1100", "11:00", "fair"), ("d1400", "14:00", "fair"),
         ("d1700", "17:00", "fair"), ("d1900", "19:00", "fair")]
CONDITIONS = [("c_clear", "14:00", "clear"), ("d1400", "14:00", "fair"), ("c_hazy", "14:00", "hazy"),
              ("c_overcast", "14:00", "overcast")]


def dump(tag, time, cond):
    godot = os.environ.get("GODOT", "godot")
    cmd = [godot, "--headless", "--path", str(GAME), "-s", "res://tests/water_preview_dump.gd", "--",
           "--time=" + time, "--conditions=" + cond, "--tag=" + tag, SHOT]
    print(" ".join(cmd))
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def load_strip(path):
    strip = np.asarray(Image.open(path).convert("RGB"), dtype="f4") / 255.0
    n = strip.shape[0]
    return strip.reshape(n, n, n, 3).transpose(1, 0, 2, 3)


def frames(ctx, tag, size):
    """(before: the tone-mapped frame, after: graded, the light) of one dumped shot."""
    d = wp.OUT / ("%s_%s" % (tag, SHOT))
    scene = json.loads((d / "scene.json").read_text())
    before = wp.render(ctx, d, size, True, "auto")
    src = np.asarray(before, dtype="f4") / 255.0
    graded = cp.apply_lut(src, load_strip(d / "lut.png"))
    after = cp.to_image(graded)
    return before, after, scene.get("light", {})


def label(img, text):
    dr = ImageDraw.Draw(img)
    w = 7 * len(text) + 12
    dr.rectangle([8, 8, 8 + w, 30], fill=(0, 0, 0))
    dr.text((14, 13), text, fill=(255, 255, 255))
    return img


def light_text(li):
    h = li.get("hour", 0.0)
    m = int(round(h * 60))
    return "%02d:%02d %s, sun %d deg at %03d" % (m // 60, m % 60, li.get("conditions", ""),
                                                  round(li.get("sun_elevation_deg", 0)), round(li.get("sun_azimuth_deg", 0)))


def sheet(tiles, cols):
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cols * w + (cols - 1) * 6, rows * h + (rows - 1) * 6), (255, 255, 255))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % cols) * (w + 6), (i // cols) * (h + 6)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="960x540")
    ap.add_argument("--dump", action="store_true", help="run the Godot dumps first")
    ap.add_argument("--publish", action="store_true", help="also write JPEG copies to game/tests/previews")
    a = ap.parse_args()
    size = tuple(int(x) for x in a.size.split("x"))
    if a.dump:
        for tag, time, cond in TIMES + CONDITIONS[:1] + CONDITIONS[2:]:
            dump(tag, time, cond)
    OUT.mkdir(parents=True, exist_ok=True)
    ctx = moderngl.create_standalone_context(require=410)
    cache = {}

    def get(tag):
        if tag not in cache:
            cache[tag] = frames(ctx, tag, size)
        return cache[tag]

    outs = {}
    outs["times"] = sheet([label(get(t)[1].copy(), light_text(get(t)[2])) for t, _, _ in TIMES], 3)
    outs["conditions"] = sheet([label(get(t)[1].copy(), light_text(get(t)[2])) for t, _, _ in CONDITIONS], 2)
    tiles = []
    for t in ("d1400", "d1900"):
        b, af, li = get(t)
        tiles.append(label(b.copy(), "grade off, " + light_text(li)))
        tiles.append(label(af.copy(), "default grade"))
    outs["grade"] = sheet(tiles, 2)
    for t, _, _ in TIMES + CONDITIONS:
        outs["shot_" + t] = get(t)[1]
    for n, img in outs.items():
        path = OUT / (n + ".png")
        img.save(path)
        print("wrote", path)
        if a.publish and not n.startswith("shot_"):
            jpg = PUBLISHED / ("daylight_" + n + ".jpg")
            img.save(jpg, quality=86)
            print("wrote", jpg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
