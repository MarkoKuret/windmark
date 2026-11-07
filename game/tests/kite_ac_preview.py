#!/usr/bin/env python3
"""The kites from measured surfaces against the hinge model (docs/specs/sail_visuals.md 6.5, the surface source),
offline and without a window: renders the shots tests/sail_preview_dump.gd dumps with `-- kite_ac` (wm7 with the AC33
asymmetric at AWA about 60, 95 and 130 deg; wm21 with the IACC symmetric series at TWA about 150 and 180 deg; 12 kn)
with tests/sail_preview.py, and writes one sheet per class and view (the leeward side, the stern quarter, the bow
quarter): a row per wind angle, the hinge model (the current one) left, the surface shape right.

    godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_ac
    python3 game/tests/kite_ac_preview.py [--out DIR] [--size 960x600]
    godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_ac2
    python3 game/tests/kite_ac_preview.py --second      (every class: docs/design/kite_ac_2026-11-06b/)
    godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_ac3
    python3 game/tests/kite_ac_preview.py --third       (wm9 and wm21: docs/design/kite_ac_2026-11-07/)

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


SECOND = {"wm7": ("AWA", (60, 95, 130), "the AC33"), "wm10": ("AWA", (60, 95, 130), "the AC33"),
          "wm12": ("AWA", (60, 95, 130), "the AC33"), "wm16": ("AWA", (60, 95, 130), "the AC33"),
          "wm9": ("TWA", (150, 177), "the IACC series"), "wm21": ("TWA", (150, 177), "the IACC series")}
FIRST = REPO / "docs" / "design" / "kite_ac_2026-11-06"     # the first pass's sheets (tag kite-ac-v1)


def second(ctx, out, w, h):
    """Every spinnaker class on its surface (`-- kite_ac2` shots): wm7 and wm21 against the first pass (the right
    column of its sheets, the same shots), the others against the hinge model."""
    head = 46
    f, fs = _font(24), _font(17)
    for cls, (kind, angles, what) in SECOND.items():
        for view, title in VIEWS.items():
            old = cls in ("wm7", "wm21")
            left = "first pass (kite-ac-v1)" if old else "hinge model (now)"
            sheet = Image.new("RGB", (2 * w, head + len(angles) * (h + 30)), (245, 245, 242))
            d = ImageDraw.Draw(sheet)
            d.text((14, 10), f"{cls} kite: {left} (left), {what} with the foot lift and the run set (right), {title}, 12 kn",
                   fill=(20, 20, 30), font=f)
            prev = Image.open(FIRST / f"{cls}_{view}.jpg") if old else None
            for r, ang in enumerate(angles):
                y = head + r * (h + 30)
                if old:
                    sheet.paste(prev.crop((w, y + 30, 2 * w, y + 30 + h)), (0, y + 30))
                    d.text((10, y + 6), left, fill=(30, 30, 40), font=fs)
                else:
                    img, note = sp.render(ctx, sp.OUT / f"kite_ac2_{cls}_{kind.lower()}{ang}_hinge_{view}", (w, h))
                    sheet.paste(img, (0, y + 30))
                    d.text((10, y + 6), f"{left}: {note.split('|')[0].split(':', 1)[-1].strip()}", fill=(30, 30, 40),
                           font=fs)
                name = f"kite_ac2_{cls}_{kind.lower()}{ang}_loft_{view}"
                img, note = sp.render(ctx, sp.OUT / name, (w, h))
                sheet.paste(img, (w, y + 30))
                d.text((w + 10, y + 6), f"new: {note.split('|')[0].split(':', 1)[-1].strip()}", fill=(30, 30, 40),
                       font=fs)
                print(f"{name}: {note}")
            path = out / f"{cls}_{view}.jpg"
            sheet.save(path, quality=90)
            print(f"wrote {path}")


SECOND_DIR = REPO / "docs" / "design" / "kite_ac_2026-11-06b"   # the second pass's sheets


def third(ctx, out, w, h):
    """wm9 and wm21 (`-- kite_ac3` shots, the run set as at TWA 150) against the second pass (the right column of its
    sheets, the same shots)."""
    head = 46
    f, fs = _font(24), _font(17)
    for cls in ("wm9", "wm21"):
        kind, angles, what = SECOND[cls]
        for view, title in VIEWS.items():
            sheet = Image.new("RGB", (2 * w, head + len(angles) * (h + 30)), (245, 245, 242))
            d = ImageDraw.Draw(sheet)
            d.text((14, 10), f"{cls} kite: before, the pole end raised on a run (left), now, the run set as at TWA 150 "
                   f"(right), {title}, 12 kn", fill=(20, 20, 30), font=f)
            prev = Image.open(SECOND_DIR / f"{cls}_{view}.jpg")
            for r, ang in enumerate(angles):
                y = head + r * (h + 30)
                sheet.paste(prev.crop((w, y + 30, 2 * w, y + 30 + h)), (0, y + 30))
                d.text((10, y + 6), "before (2026-11-06b)", fill=(30, 30, 40), font=fs)
                name = f"kite_ac3_{cls}_{kind.lower()}{ang}_loft_{view}"
                img, note = sp.render(ctx, sp.OUT / name, (w, h))
                sheet.paste(img, (w, y + 30))
                d.text((w + 10, y + 6), f"now: {note.split('|')[0].split(':', 1)[-1].strip()}", fill=(30, 30, 40),
                       font=fs)
                print(f"{name}: {note}")
            path = out / f"{cls}_{view}.jpg"
            sheet.save(path, quality=90)
            print(f"wrote {path}")


THIRD_DIR = REPO / "docs" / "design" / "kite_ac_2026-11-07"     # the third pass's sheets


V2_DIR = REPO / "docs" / "design" / "kite_ac_2026-11-07b"      # the accepted state (tag kite-ac-v2)


def fifth(ctx, out, w, h):
    """wm9 and wm21 (`-- kite_ac5` shots: the run shape projected forward, wm21's fractional rig) against kite-ac-v2
    (the right column of its sheets, the same shots), from the side, the bow quarter and above."""
    head = 46
    f, fs = _font(24), _font(17)
    views = {"side": VIEWS["side"], "bow": VIEWS["bow"], "top": "from above the masthead"}
    for cls in ("wm9", "wm21"):
        kind, angles, what = SECOND[cls]
        rig = ", the fractional rig" if cls == "wm21" else ""
        for view, title in views.items():
            sheet = Image.new("RGB", (2 * w, head + len(angles) * (h + 30)), (245, 245, 242))
            d = ImageDraw.Draw(sheet)
            d.text((14, 10), f"{cls} kite: kite-ac-v2 (left), the run projected forward{rig} (right), {title}, 12 kn",
                   fill=(20, 20, 30), font=f)
            prev = Image.open(V2_DIR / f"{cls}_{view}.jpg")
            for r, ang in enumerate(angles):
                y = head + r * (h + 30)
                sheet.paste(prev.crop((w, y + 30, 2 * w, y + 30 + h)), (0, y + 30))
                d.text((10, y + 6), "kite-ac-v2", fill=(30, 30, 40), font=fs)
                name = f"kite_ac5_{cls}_{kind.lower()}{ang}_loft_{view}"
                img, note = sp.render(ctx, sp.OUT / name, (w, h))
                sheet.paste(img, (w, y + 30))
                d.text((w + 10, y + 6), f"now: {note.split('|')[0].split(':', 1)[-1].strip()}", fill=(30, 30, 40),
                       font=fs)
                print(f"{name}: {note}")
            path = out / f"{cls}_{view}.jpg"
            sheet.save(path, quality=90)
            print(f"wrote {path}")


def fourth(ctx, out, w, h):
    """wm9 and wm21 (`-- kite_ac4` shots, ahead of the forestay) against the third pass (the right column of its
    sheets), and a sheet from above the masthead (the new state only: the third pass has no such view)."""
    head = 46
    f, fs = _font(24), _font(17)
    views = dict(VIEWS, top="from above the masthead")
    for cls in ("wm9", "wm21"):
        kind, angles, what = SECOND[cls]
        for view, title in views.items():
            sheet = Image.new("RGB", (2 * w, head + len(angles) * (h + 30)), (245, 245, 242))
            d = ImageDraw.Draw(sheet)
            d.text((14, 10), f"{cls} kite: before (left), now, never behind the forestay (right), {title}, 12 kn",
                   fill=(20, 20, 30), font=f)
            prev = Image.open(THIRD_DIR / f"{cls}_{view}.jpg") if view != "top" else None
            for r, ang in enumerate(angles):
                y = head + r * (h + 30)
                if prev is not None:
                    sheet.paste(prev.crop((w, y + 30, 2 * w, y + 30 + h)), (0, y + 30))
                    d.text((10, y + 6), "before (2026-11-07)", fill=(30, 30, 40), font=fs)
                else:
                    d.text((10, y + 6), "(no view from above before)", fill=(30, 30, 40), font=fs)
                name = f"kite_ac4_{cls}_{kind.lower()}{ang}_loft_{view}"
                img, note = sp.render(ctx, sp.OUT / name, (w, h))
                sheet.paste(img, (w, y + 30))
                d.text((w + 10, y + 6), f"now: {note.split('|')[0].split(':', 1)[-1].strip()}", fill=(30, 30, 40),
                       font=fs)
                print(f"{name}: {note}")
            path = out / f"{cls}_{view}.jpg"
            sheet.save(path, quality=90)
            print(f"wrote {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--size", default="960x600")
    ap.add_argument("--second", action="store_true", help="every class (-- kite_ac2), into kite_ac_2026-11-06b")
    ap.add_argument("--third", action="store_true", help="wm9 and wm21 (-- kite_ac3), into kite_ac_2026-11-07")
    ap.add_argument("--fourth", action="store_true", help="wm9 and wm21 (-- kite_ac4), into kite_ac_2026-11-07b")
    ap.add_argument("--fifth", action="store_true", help="wm9 and wm21 (-- kite_ac5), into kite_ac_2026-11-07c")
    a = ap.parse_args()
    if a.fifth:
        w, h = (int(x) for x in a.size.split("x"))
        out = Path(a.out or REPO / "docs" / "design" / "kite_ac_2026-11-07c")
        out.mkdir(parents=True, exist_ok=True)
        fifth(moderngl.create_standalone_context(require=410), out, w, h)
        return
    if a.fourth:
        w, h = (int(x) for x in a.size.split("x"))
        out = Path(a.out or REPO / "docs" / "design" / "kite_ac_2026-11-07b")
        out.mkdir(parents=True, exist_ok=True)
        fourth(moderngl.create_standalone_context(require=410), out, w, h)
        return
    if a.third:
        w, h = (int(x) for x in a.size.split("x"))
        out = Path(a.out or REPO / "docs" / "design" / "kite_ac_2026-11-07")
        out.mkdir(parents=True, exist_ok=True)
        third(moderngl.create_standalone_context(require=410), out, w, h)
        return
    if a.second:
        w, h = (int(x) for x in a.size.split("x"))
        out = Path(a.out or REPO / "docs" / "design" / "kite_ac_2026-11-06b")
        out.mkdir(parents=True, exist_ok=True)
        second(moderngl.create_standalone_context(require=410), out, w, h)
        return
    a.out = a.out or str(FIRST)
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
