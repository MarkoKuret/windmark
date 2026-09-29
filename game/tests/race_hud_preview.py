#!/usr/bin/env python3
"""Offline previews of the race HUD: draws what tests/race_hud_preview_dump.gd wrote
(generated/race_hud_preview/<name>.json: the screen size, the backdrop shot and every HUD block's drawing primitives,
the same list the game draws) over a course preview frame. No window opens.

    python3 game/tests/race_hud_preview.py [--publish] [name ...]

The backdrop is generated/course_preview/<shot>_<w>x<h>.png when tests/course_preview.py has rendered it at the
HUD's size, else generated/course_preview/<shot>.png, else the published tests/previews/course_<shot>.jpg (scaled to
the height and cropped to the width). Text is set in the game's Barlow Semi Condensed (game/fonts/barlow); digits get
fixed-width cells as the game's tabular figures do. Writes generated/race_hud_preview/<name>.jpg; with --publish also
tests/previews/race_hud_<name>.jpg.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SRC = os.path.join(GAME, "generated", "race_hud_preview")
FRAMES = os.path.join(GAME, "generated", "course_preview")
FONT_DIR = os.path.join(GAME, "fonts", "barlow")
FONT_FILES = {500: "BarlowSemiCondensed-Medium.ttf", 600: "BarlowSemiCondensed-SemiBold.ttf",
              700: "BarlowSemiCondensed-Bold.ttf"}
SS = 2  # supersampling
DIGITS = "0123456789"

_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(FONT_DIR, FONT_FILES.get(weight, FONT_FILES[600])),
                                         max(1, int(round(size * SS))))
    return _fonts[key]


def col(c, a_mul=1.0):
    return tuple(int(round(255 * max(0.0, min(1.0, v)))) for v in c[:3]) + (
        int(round(255 * max(0.0, min(1.0, c[3] * a_mul)))),)


def backdrop(shot, w, h):
    for p in (os.path.join(FRAMES, "%s_%dx%d.png" % (shot, w, h)), os.path.join(FRAMES, "%s.png" % shot),
              os.path.join(HERE, "previews", "course_%s.jpg" % shot)):
        if os.path.exists(p):
            img = Image.open(p).convert("RGBA")
            break
    else:
        return Image.new("RGBA", (w, h), (40, 70, 90, 255))
    if img.size != (w, h):
        s = h / img.size[1]
        img = img.resize((max(w, int(round(img.size[0] * s))), h), Image.LANCZOS)
        x0 = (img.size[0] - w) // 2
        img = img.crop((x0, 0, x0 + w, h))
    return img


class Canvas:
    """Draws primitives with alpha blending: each one on a small layer composited at its place."""

    def __init__(self, img):
        self.img = img

    def _layer(self, x0, y0, x1, y1):
        x0, y0 = int(math.floor(x0 * SS)) - 2, int(math.floor(y0 * SS)) - 2
        x1, y1 = int(math.ceil(x1 * SS)) + 2, int(math.ceil(y1 * SS)) + 2
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, self.img.size[0]), min(y1, self.img.size[1])
        if x1 <= x0 or y1 <= y0:
            return None, None, (0, 0)
        lay = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
        return lay, ImageDraw.Draw(lay), (x0, y0)

    def _put(self, lay, at):
        if lay is not None:
            self.img.alpha_composite(lay, dest=at)

    @staticmethod
    def pts(pts, o):
        return [((p[0] + o[0]) * SS, (p[1] + o[1]) * SS) for p in pts]

    @staticmethod
    def bbox(pts, pad):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad

    def draw(self, q, o, a):
        k = q["k"]
        if k in ("rect", "grad"):
            x, y, w, h = q["r"]
            x, y = x + o[0], y + o[1]
            lay, d, at = self._layer(x, y, x + w, y + h)
            if lay is None:
                return
            r = [x * SS - at[0], y * SS - at[1], (x + w) * SS - at[0] - 1, (y + h) * SS - at[1] - 1]
            if k == "rect":
                d.rectangle(r, fill=col(q["col"], a))
            else:
                top, bot = q["top"], q["bottom"]
                n = max(1, int(h * SS))
                for i in range(n):
                    f = i / max(n - 1, 1)
                    c = [top[j] + (bot[j] - top[j]) * f for j in range(4)]
                    d.line([r[0], r[1] + i, r[2], r[1] + i], fill=col(c, a))
            self._put(lay, at)
        elif k in ("line", "polyline", "poly"):
            ps = [q["a"], q["b"]] if k == "line" else q["pts"]
            if len(ps) < 2:
                return
            w = q.get("w", 1.0)
            bb = self.bbox([(p[0] + o[0], p[1] + o[1]) for p in ps], w + 2)
            lay, d, at = self._layer(*bb)
            if lay is None:
                return
            sp = [(p[0] - at[0], p[1] - at[1]) for p in self.pts(ps, o)]
            if k == "poly":
                if len(sp) >= 3:
                    d.polygon(sp, fill=col(q["col"], a))
            else:
                d.line(sp, fill=col(q["col"], a), width=max(1, int(round(w * SS))), joint="curve")
            self._put(lay, at)
        elif k in ("circle", "arc"):
            cx, cy = q["p"][0] + o[0], q["p"][1] + o[1]
            r = q["r"]
            w = q.get("w", 0.0)
            lay, d, at = self._layer(cx - r - w, cy - r - w, cx + r + w, cy + r + w)
            if lay is None:
                return
            box = [(cx - r) * SS - at[0], (cy - r) * SS - at[1], (cx + r) * SS - at[0], (cy + r) * SS - at[1]]
            if k == "circle":
                d.ellipse(box, fill=col(q["col"], a))
            else:
                a0, a1 = math.degrees(q["a0"]), math.degrees(q["a1"])
                if a1 < a0:
                    a0, a1 = a1, a0
                if a1 - a0 >= 359.9:
                    a0, a1 = 0, 360
                ww = max(1, int(round(w * SS)))
                g = ww / 2
                d.arc([box[0] - g, box[1] - g, box[2] + g, box[3] + g], a0, a1, fill=col(q["col"], a), width=ww)
            self._put(lay, at)
        elif k == "text":
            self.text(q, o, a)

    def text(self, q, o, a):
        t = q["text"]
        if not t:
            return
        size = q["size"]
        f = font(q["weight"], size)
        spacing = round(q["tracking"] * size) * SS
        cell = max(f.getlength(c) for c in DIGITS)
        adv = [(cell if c in DIGITS else f.getlength(c)) + spacing for c in t]
        width = sum(adv)
        x = (q["p"][0] + o[0]) * SS
        if q["align"] == 2:
            x -= width
        elif q["align"] == 1:
            x -= width / 2
        base = (q["p"][1] + o[1]) * SS
        asc, desc = f.getmetrics()
        lay, d, at = self._layer(x / SS - 2, (base - asc) / SS - 2, (x + width) / SS + 2, (base + desc) / SS + 4)
        if lay is None:
            return
        passes = []
        if q.get("shadow", False):
            passes.append(((0, SS), [0, 0, 0, 0.45 * q["col"][3]]))
        passes.append(((0, 0), q["col"]))
        for off, c in passes:
            cx = x
            for ch, w in zip(t, adv):
                gx = cx + ((cell - f.getlength(ch)) / 2 if ch in DIGITS else 0)
                d.text((gx - at[0] + off[0], base - asc - at[1] + off[1]), ch, font=f, fill=col(c, a))
                cx += w
        self._put(lay, at)


def render(dump):
    w, h = int(dump["size"][0]), int(dump["size"][1])
    base = backdrop(dump.get("backdrop", "start_line"), w, h).resize((w * SS, h * SS), Image.LANCZOS)
    cv = Canvas(base)
    for it in dump["items"]:
        o = (it["x"], it["y"])
        for q in it["prims"]:
            cv.draw(q, o, it.get("alpha", 1.0))
    return cv.img.resize((w, h), Image.LANCZOS).convert("RGB")


def main():
    publish = "--publish" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    names = sorted(f[:-5] for f in os.listdir(SRC) if f.endswith(".json"))
    for n in names:
        if only and n not in only:
            continue
        with open(os.path.join(SRC, n + ".json")) as fh:
            dump = json.load(fh)
        if "backdrop" not in dump:
            continue  # a dump of the old HUD
        img = render(dump)
        out = os.path.join(SRC, n + ".jpg")
        img.save(out, quality=88)
        print("wrote", out)
        if publish:
            pub = os.path.join(HERE, "previews", "race_hud_%s.jpg" % n)
            img.save(pub, quality=85)
            print("wrote", pub)


if __name__ == "__main__":
    main()
