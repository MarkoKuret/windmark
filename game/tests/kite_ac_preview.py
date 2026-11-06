#!/usr/bin/env python3
"""The kites from measured surfaces against the hinge model (docs/specs/sail_visuals.md 6.5, the surface source),
offline and without a window: renders the shots tests/sail_preview_dump.gd dumps with `-- kite_ac` (wm7 with the AC33
asymmetric at AWA about 60, 95 and 130 deg; wm21 with the IACC symmetric series at TWA about 150 and 180 deg; 12 kn)
with tests/sail_preview.py, and writes one sheet per class and view (the leeward side, the stern quarter, the bow
quarter): a row per wind angle, the hinge model (the current one) left, the surface shape right.

    godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_ac
    python3 game/tests/kite_ac_preview.py [--out DIR] [--size 960x600]

Default output: docs/design/kite_ac_2026-11-06/<class>_<view>.jpg. Needs numpy, Pillow and moderngl.
"""
import argparse
import sys
from pathlib import Path

import moderngl
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sail_preview as sp  # noqa: E402
from kite_loft_preview import VIEWS, _font  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CLASSES = {"wm7": ("AWA", (60, 95, 130), "the AC33 asymmetric (wind tunnel, AWA 55)"),
           "wm21": ("TWA", (150, 177), "the IACC symmetric series")}
MODELS = (("hinge", "hinge model (now)"), ("loft", "measured surface (new)"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "docs" / "design" / "kite_ac_2026-11-06"))
    ap.add_argument("--size", default="960x600")
    a = ap.parse_args()
    w, h = (int(x) for x in a.size.split("x"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    ctx = moderngl.create_standalone_context(require=410)
    head = 46
    f, fs = _font(24), _font(17)
    for cls, (kind, angles, what) in CLASSES.items():
        for view, title in VIEWS.items():
            sheet = Image.new("RGB", (2 * w, head + len(angles) * (h + 30)), (245, 245, 242))
            d = ImageDraw.Draw(sheet)
            d.text((14, 10), f"{cls} kite: hinge model (left), {what} (right), {title}, 12 kn",
                   fill=(20, 20, 30), font=f)
            for r, ang in enumerate(angles):
                for c, (model, label) in enumerate(MODELS):
                    name = f"kite_ac_{cls}_{kind.lower()}{ang}_{model}_{view}"
                    img, note = sp.render(ctx, sp.OUT / name, (w, h))
                    y = head + r * (h + 30)
                    sheet.paste(img, (c * w, y + 30))
                    short = note.split("|")[0].split(":", 1)[-1].strip()
                    d.text((c * w + 10, y + 6), f"{label}: {short}", fill=(30, 30, 40), font=fs)
                    print(f"{name}: {note}")
            path = out / f"{cls}_{view}.jpg"
            sheet.save(path, quality=90)
            print(f"wrote {path}")


if __name__ == "__main__":
    main()
