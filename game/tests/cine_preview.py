#!/usr/bin/env python3
"""Offline previews of the cinematic look (water_render.md section 4.5: colour grade, late-afternoon light), no
window. Renders water preview shots (tests/water_preview.py on the dumps of tests/water_preview_dump.gd), then
applies the colour grade as Godot does after the tone mapping (the preset's 3-D LUT, written by
tests/look_lut_dump.gd, sampled with the display colour as the coordinate, trilinear). No vignette (there is none
in the game).

    godot --headless --path game -s res://tests/look_lut_dump.gd
    godot --headless --path game -s res://tests/water_preview_dump.gd -- bay20_chase_M bay20_sun_M bay20_aerial_M
    godot --headless --path game -s res://tests/water_preview_dump.gd -- --sky=late bay20_chase_M bay20_sun_M
    python3 game/tests/cine_preview.py [--size 1280x720] [--publish]

Writes game/generated/cine_preview/*.png (with --publish also game/tests/previews/cine_*.jpg): for each shot the
graded frame and, for the fair shots, a before/after pair (left: the frame as before, right: graded). Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import sys
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import water_preview as wp  # noqa: E402

GAME = Path(__file__).resolve().parents[1]
LOOK = GAME / "generated" / "look"
OUT = GAME / "generated" / "cine_preview"
PUBLISHED = GAME / "tests" / "previews"

# (output name, dumped shot, light preset of the grade)
SHOTS = [
    ("fair_chase", "bay20_chase_M", "fair"),
    ("fair_sun", "bay20_sun_M", "fair"),
    ("fair_aerial", "bay20_aerial_M", "fair"),
    ("fair_bow", "bay20_bow_M", "fair"),
    ("late_chase", "late_bay20_chase_M", "late"),
    ("late_sun", "late_bay20_sun_M", "late"),
]


def load_lut(preset):
    strip = np.asarray(Image.open(LOOK / ("lut_%s.png" % preset)).convert("RGB"), dtype="f4") / 255.0
    n = strip.shape[0]
    # strip[g, b * n + r] -> lut[b, g, r]
    return strip.reshape(n, n, n, 3).transpose(1, 0, 2, 3)


def apply_lut(img, lut):
    """Godot's colour correction: textureLod(lut, colour) on the clamped display colour, trilinear, clamp to edge."""
    n = lut.shape[0]
    c = np.clip(img, 0.0, 1.0)
    f = np.clip(c * n - 0.5, 0.0, n - 1.0)
    i0 = np.floor(f).astype(int)
    i1 = np.minimum(i0 + 1, n - 1)
    t = f - i0
    r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
    r1, g1, b1 = i1[..., 0], i1[..., 1], i1[..., 2]
    tr, tg, tb = t[..., 0:1], t[..., 1:2], t[..., 2:3]

    def at(b, g, r):
        return lut[b, g, r]

    c00 = at(b0, g0, r0) * (1 - tr) + at(b0, g0, r1) * tr
    c01 = at(b0, g1, r0) * (1 - tr) + at(b0, g1, r1) * tr
    c10 = at(b1, g0, r0) * (1 - tr) + at(b1, g0, r1) * tr
    c11 = at(b1, g1, r0) * (1 - tr) + at(b1, g1, r1) * tr
    c0 = c00 * (1 - tg) + c01 * tg
    c1 = c10 * (1 - tg) + c11 * tg
    return c0 * (1 - tb) + c1 * tb


def to_image(a):
    return Image.fromarray((np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype("u1"))


def pair(before, after, labels):
    w, h = before.size
    out = Image.new("RGB", (2 * w + 8, h), (255, 255, 255))
    out.paste(before, (0, 0))
    out.paste(after, (w + 8, 0))
    dr = ImageDraw.Draw(out)
    for x, label in ((10, labels[0]), (w + 18, labels[1])):
        dr.rectangle([x - 4, 8, x + 7 * len(label), 28], fill=(0, 0, 0))
        dr.text((x, 12), label, fill=(255, 255, 255))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--publish", action="store_true", help="also write JPEG copies to game/tests/previews")
    a = ap.parse_args()
    size = tuple(int(x) for x in a.size.split("x"))
    if not (LOOK / "look.json").exists():
        print("no LUTs in %s: run tests/look_lut_dump.gd first" % LOOK)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    ctx = moderngl.create_standalone_context(require=410)
    for name, shot, preset in SHOTS:
        d = wp.OUT / shot
        if not (d / "scene.json").exists():
            print("skipped %s: no dump %s (run tests/water_preview_dump.gd)" % (name, d))
            continue
        before = wp.render(ctx, d, size, True, "auto")
        src = np.asarray(before, dtype="f4") / 255.0
        graded = apply_lut(src, load_lut(preset))
        reg = to_image(graded)
        outs = {name: reg}
        if preset == "fair":
            outs[name + "_compare"] = pair(before, reg, ("as before", "graded"))
        for n, img in outs.items():
            path = OUT / (n + ".png")
            img.save(path)
            print("wrote", path)
            if a.publish:
                jpg = PUBLISHED / ("cine_" + n + ".jpg")
                img.save(jpg, quality=88)
                print("wrote", jpg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
