#!/usr/bin/env python3
"""The lofted kite against the hinge model (docs/specs/sail_visuals.md 6.5), offline and without a window: renders
the shots tests/sail_preview_dump.gd dumps with `-- kite_loft` (wm7 at 12 kn, its kite on each model at AWA about
64, 95 and 124 deg) with tests/sail_preview.py, and writes one comparison sheet per view (the leeward side, the stern
quarter, the bow quarter): a row per AWA, the hinge model left, the lofted one right.

    godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_loft
    python3 game/tests/kite_loft_preview.py [--out DIR] [--size 960x600]

Default output: docs/design/kite_loft_2026-11-03/kite_loft_<view>.jpg. Needs numpy, Pillow and moderngl.
"""
import argparse
import sys
from pathlib import Path

import moderngl
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sail_preview as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
AWAS = (64, 95, 124)
MODELS = ("hinge", "loft")
VIEWS = {"side": "from the leeward side", "stern": "from the leeward stern quarter",
         "bow": "from the leeward bow quarter"}


def _font(size):
    for f in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "docs" / "design" / "kite_loft_2026-11-03"))
    ap.add_argument("--size", default="960x600")
    a = ap.parse_args()
    w, h = (int(x) for x in a.size.split("x"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    ctx = moderngl.create_standalone_context(require=410)
    head = 46
    f, fs = _font(26), _font(17)
    for view, title in VIEWS.items():
        sheet = Image.new("RGB", (2 * w, head + len(AWAS) * (h + 30)), (245, 245, 242))
        d = ImageDraw.Draw(sheet)
        d.text((14, 10), f"wm7 kite, hinge model (left) and lofted from the J/80 sections (right), {title}, 12 kn",
               fill=(20, 20, 30), font=f)
        for r, awa in enumerate(AWAS):
            for c, model in enumerate(MODELS):
                name = f"kite_loft_{awa}_{model}_{view}"
                img, note = sp.render(ctx, sp.OUT / name, (w, h))
                y = head + r * (h + 30)
                sheet.paste(img, (c * w, y + 30))
                short = note.split("|")[0].strip()
                d.text((c * w + 10, y + 6), f"{model}: {short}", fill=(30, 30, 40), font=fs)
                print(f"{name}: {note}")
        path = out / f"kite_loft_{view}.jpg"
        sheet.save(path, quality=90)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
