#!/usr/bin/env python3
"""Offline preview of the running sheets through their edge cases, step 2 (no window): renders the shots that
tests/ropes_preview_dump.gd dumped under one or more tags with tests/sail_preview.py and writes one strip per
scenario, a row per moment, the tags side by side (the first on the left).

    godot --headless --path game -s res://tests/ropes_preview_dump.gd -- before     (on the old ropes)
    godot --headless --path game -s res://tests/ropes_preview_dump.gd -- after
    python3 game/tests/ropes_preview.py before after [--out DIR] [--size 800x500]

Default output: docs/design/ropes_2026-11-07/<shot>.jpg. Needs numpy, Pillow and moderngl.
"""
import argparse
import json
import sys
from pathlib import Path

import moderngl
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sail_preview as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "game" / "generated" / "ropes_preview"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tags", nargs="+")
    ap.add_argument("--out", default=str(REPO / "docs" / "design" / "ropes_2026-11-07"))
    ap.add_argument("--size", default="800x500")
    a = ap.parse_args()
    w, h = (int(x) for x in a.size.split("x"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    ctx = moderngl.create_standalone_context(require=410)
    names = json.loads((SRC / a.tags[0] / "index.json").read_text())
    shots = {}
    for n in names:
        shots.setdefault(n.rsplit("_", 1)[0], []).append(n)
    for shot, frames in shots.items():
        head = 26
        cap = 18
        sheet = Image.new("RGB", (len(a.tags) * w, head + len(frames) * (h + cap)), (24, 24, 24))
        d = ImageDraw.Draw(sheet)
        for c, tag in enumerate(a.tags):
            d.text((c * w + 8, 7), tag, fill=(240, 240, 240))
        for r, n in enumerate(frames):
            y = head + r * (h + cap)
            for c, tag in enumerate(a.tags):
                if not (SRC / tag / n / "scene.json").exists():
                    continue
                img, note = sp.render(ctx, SRC / tag / n, (w, h))
                sheet.paste(img, (c * w, y + cap))
                if c == 0:
                    d.text((8, y + 3), note, fill=(220, 220, 220))
        sheet.save(out / f"{shot}.jpg", quality=88)
        print(f"wrote {out / (shot + '.jpg')}")


if __name__ == "__main__":
    main()
