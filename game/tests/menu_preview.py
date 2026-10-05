#!/usr/bin/env python3
"""Offline previews of the menus: draws what tests/menu_preview_dump.gd wrote (generated/menu_preview/<shot>.json:
the boxes, texts, colour rects and the course map the menu draws at 1280 x 800) over a backdrop. No window opens.

    godot --headless --path game -s res://tests/menu_preview_dump.gd
    python3 game/tests/menu_preview.py [--publish]

The backdrop stands in for the live sail scene (menus.md section 4): a published render, tests/previews/
cine_fair_chase.jpg, scaled to cover the frame. Text is set in the game's Barlow Semi Condensed (game/fonts/barlow)
with the dump's tracking; the layout is the game's own (every rect comes from Godot). Writes
generated/menu_preview/<shot>.jpg; with --publish also docs/design/frames/menus_<shot>.jpg (the race end shots as
race_end_results*.jpg).
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
REPO = os.path.dirname(GAME)
SRC = os.path.join(GAME, "generated", "menu_preview")
FONT_DIR = os.path.join(GAME, "fonts", "barlow")
BACKDROP = os.path.join(HERE, "previews", "cine_fair_chase.jpg")
PUBLISH = os.path.join(REPO, "docs", "design", "frames")
SS = 2

INK = (6, 18, 27)
PAPER = (245, 248, 250)
MARK = (255, 210, 63)
HAZE = (228, 236, 233)

_fonts = {}


def font(name, size):
    key = (name, size)
    if key not in _fonts:
        path = os.path.join(FONT_DIR, name) if name else os.path.join(FONT_DIR, "BarlowSemiCondensed-Medium.ttf")
        if not os.path.exists(path):
            path = os.path.join(FONT_DIR, "BarlowSemiCondensed-Medium.ttf")
        _fonts[key] = ImageFont.truetype(path, max(1, int(round(size * SS))))
    return _fonts[key]


def c255(c, alpha=None):
    a = c[3] if alpha is None else alpha
    return (int(round(c[0] * 255)), int(round(c[1] * 255)), int(round(c[2] * 255)), int(round(a * 255)))


def S(v):
    return v * SS


def text_width(f, t, spacing):
    w = 0.0
    for ch in t:
        w += f.getlength(ch) + S(spacing)
    return w - (S(spacing) if t else 0)


def draw_text_line(d, x, y, t, f, col, spacing, stroke=0.0, stroke_col=None):
    # the outline first under every letter (Godot strokes outline_size / 4 px each side), then the fills
    if stroke > 0:
        sx = x
        for ch in t:
            d.text((sx, y), ch, font=f, fill=stroke_col, stroke_width=int(round(S(stroke))), stroke_fill=stroke_col)
            sx += f.getlength(ch) + S(spacing)
    for ch in t:
        d.text((x, y), ch, font=f, fill=col)
        x += f.getlength(ch) + S(spacing)


def wrap(t, f, spacing, width):
    out = []
    for para in t.split("\n"):
        words = para.split(" ")
        line = ""
        for w in words:
            cand = (line + " " + w) if line else w
            if text_width(f, cand, spacing) <= width or not line:
                line = cand
            else:
                out.append(line)
                line = w
        out.append(line)
    return out


def draw_text(d, it):
    f = font(it["font"], it["size"])
    x, y, w, h = [S(v) for v in it["r"]]
    asc, desc = f.getmetrics()
    lh = asc + desc
    lines = wrap(it["t"], f, it["spacing"], w) if it["wrap"] else it["t"].split("\n")
    total = lh * len(lines)
    if it["valign"] == 1:
        ty = y + (h - total) / 2
    elif it["valign"] == 2:
        ty = y + h - total
    else:
        ty = y
    col = c255(it["col"])
    for ln in lines:
        tw = text_width(f, ln, it["spacing"])
        if it["align"] == 1:
            tx = x + (w - tw) / 2
        elif it["align"] == 2:
            tx = x + w - tw
        else:
            tx = x
        draw_text_line(d, tx, ty, ln, f, col, it["spacing"], it.get("outline", 0) / 4.0,
                       c255(it.get("outline_col", [0, 0, 0, 0])))
        ty += lh


def draw_box(layer, it):
    x, y, w, h = [S(v) for v in it["r"]]
    d = ImageDraw.Draw(layer)
    if it["shadow"] > 0 and it["shadow_col"][3] > 0:
        sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        ox, oy = S(it["shadow_off"][0]), S(it["shadow_off"][1])
        steps = 8
        for i in range(steps):
            g = S(it["shadow"]) * (1 - i / steps)
            a = it["shadow_col"][3] / steps
            sd.rounded_rectangle([x + ox - g, y + oy - g, x + ox + w + g, y + oy + h + g], radius=S(it["radius"]) + g,
                                 fill=c255(it["shadow_col"], a))
        layer.alpha_composite(sh)
        d = ImageDraw.Draw(layer)
    if it["bg"][3] > 0 and it.get("draw_center", True):
        d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=S(it["radius"]), fill=c255(it["bg"]))
    if it["bl"] > 0:
        d.rectangle([x, y, x + S(it["bl"]) - 1, y + h - 1], fill=c255(it["bc"]))
    if it["bb"] > 0:
        d.rectangle([x, y + h - S(it["bb"]), x + w - 1, y + h - 1], fill=c255(it["bc"]))


def draw_map(layer, it):
    x, y, w, h = [S(v) for v in it["r"]]
    d = ImageDraw.Draw(layer)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=INK + (255,))
    step = S(40)
    gx = x + (w / 2) % step
    while gx < x + w:
        d.line([gx, y, gx, y + h], fill=(14, 26, 35, 255), width=SS)
        gx += step
    gy = y + (h / 2) % step
    while gy < y + h:
        d.line([x, gy, x + w, gy], fill=(14, 26, 35, 255), width=SS)
        gy += step

    def P(p):
        return (x + S(p[0]), y + S(p[1]))

    if len(it["path"]) >= 2:
        d.line([P(p) for p in it["path"]], fill=(73, 84, 92, 255), width=int(1.5 * SS), joint="curve")
    for key, ln in it["lines"].items():
        a, b = P(ln[:2]), P(ln[2:])
        n = max(2, int(math.dist(a, b) / S(6)))
        for i in range(n):
            p0 = (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
            p1 = (a[0] + (b[0] - a[0]) * (i + 1) / n, a[1] + (b[1] - a[1]) * (i + 1) / n)
            if key == "finish":
                d.line([p0, p1], fill=(PAPER if i % 2 == 0 else (44, 58, 68)) + (255,), width=S(4))
            elif i % 2 == 0:
                d.line([p0, p1], fill=PAPER + (255,), width=S(2))
    for mk in it["marks"]:
        px, py = P(mk["p"])
        t = mk["type"]
        if t == "virtual":
            continue
        if t in ("committee_boat", "mark_boat"):
            l = S(7 if t == "committee_boat" else 5)
            d.polygon([(px, py - l), (px + l * .45, py + l * .3), (px + l * .3, py + l * .8), (px - l * .3, py + l * .8),
                       (px - l * .45, py + l * .3)], fill=PAPER + (255,))
        elif mk["rounding"]:
            r = S(6)
            d.polygon([(px, py - r), (px + r, py), (px, py + r), (px - r, py)], fill=MARK + (255,))
        else:
            r = S(3)
            d.ellipse([px - r, py - r, px + r, py + r], fill=PAPER + (255,))
    # wind arrow, top right
    cx, cy = x + w - S(34), y + S(34)
    to = math.radians(it["wind_from"]) + math.pi
    dx, dy = math.sin(to), -math.cos(to)
    tail = (cx - dx * S(16), cy - dy * S(16))
    tip = (cx + dx * S(16), cy + dy * S(16))
    d.line([tail, (tip[0] - dx * S(6), tip[1] - dy * S(6))], fill=PAPER + (255,), width=int(2.5 * SS))
    sx, sy = -dy, dx
    d.polygon([tip, (tip[0] - dx * S(9) + sx * S(5.5), tip[1] - dy * S(9) + sy * S(5.5)),
               (tip[0] - dx * S(9) - sx * S(5.5), tip[1] - dy * S(9) - sy * S(5.5))], fill=PAPER + (255,))
    f = font("BarlowSemiCondensed-SemiBold.ttf", 13)
    t = "%d KN  %03d°" % (round(it["wind_kn"]), round(it["wind_from"]) % 360)
    tw = text_width(f, t, 0.8)
    draw_text_line(d, x + w - S(10) - tw, cy + S(34) - f.getmetrics()[0], t, f, PAPER + (255,), 0.8)
    draw_text_line(d, x + S(18) - f.getlength("N") / 2, y + S(26) - f.getmetrics()[0], "N", f, (164, 170, 175, 255), 0)
    d.line([x + S(18), y + S(30), x + S(18), y + S(44)], fill=(164, 170, 175, 255), width=int(1.5 * SS))


def backdrop(w, h):
    img = Image.open(BACKDROP).convert("RGB")
    k = max(w / img.width, h / img.height)
    img = img.resize((int(math.ceil(img.width * k)), int(math.ceil(img.height * k))), Image.LANCZOS)
    ox, oy = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((ox, oy, ox + w, oy + h)).convert("RGBA")


def haze(layer, r):
    w, h = S(r[2]), S(r[3])
    hw, hh = w * 0.6, h * 0.45
    g = Image.new("L", (int(hw), int(hh)), 0)
    px = g.load()
    for j in range(int(hh)):
        for i in range(0, int(hw)):
            u, v = i / hw, j / hh
            a = max(0.0, 1.0 - (u + v)) * 0.55
            px[i, j] = int(a * 255)
    col = Image.new("RGBA", g.size, HAZE + (255,))
    col.putalpha(g)
    layer.alpha_composite(col, (0, 0))


def render(path):
    data = json.load(open(path))
    w, h = data["size"]
    base = backdrop(S(w), S(h))
    groups = []
    for it in data["items"]:
        clip = tuple(it.get("clip", [0, 0, w, h]))
        if not groups or groups[-1][0] != clip:
            groups.append([clip, []])
        groups[-1][1].append(it)
    for clip, items in groups:
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        for it in items:
            k = it["k"]
            if k == "haze":
                haze(layer, it["r"])
            elif k == "box":
                draw_box(layer, it)
            elif k == "rect":
                x, y, rw, rh = [S(v) for v in it["r"]]
                ImageDraw.Draw(layer).rectangle([x, y, x + rw - 1, y + rh - 1], fill=c255(it["col"]))
            elif k == "poly":
                ImageDraw.Draw(layer).polygon([(S(p[0]), S(p[1])) for p in it["pts"]], fill=c255(it["col"]))
            elif k == "text":
                draw_text(ImageDraw.Draw(layer), it)
            elif k == "map":
                draw_map(layer, it)
        cx, cy, cw, ch = [int(round(S(v))) for v in clip]
        mask = Image.new("L", base.size, 0)
        ImageDraw.Draw(mask).rectangle([cx, cy, cx + cw - 1, cy + ch - 1], fill=255)
        alpha = Image.composite(layer.getchannel("A"), Image.new("L", base.size, 0), mask)
        layer.putalpha(alpha)
        base.alpha_composite(layer)
    return base.resize((w, h), Image.LANCZOS).convert("RGB")


def main():
    publish = "--publish" in sys.argv
    for f in sorted(os.listdir(SRC)):
        if not f.endswith(".json"):
            continue
        img = render(os.path.join(SRC, f))
        name = f[:-5]
        out = os.path.join(SRC, name + ".jpg")
        img.save(out, quality=90)
        print(out)
        if publish:
            pub = name.replace("race_end", "race_end_results") if name.startswith("race_end") else "menus_" + name
            img.save(os.path.join(PUBLISH, "%s.jpg" % pub), quality=88)


if __name__ == "__main__":
    main()
