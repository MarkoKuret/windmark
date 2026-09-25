#!/usr/bin/env python3
"""Offline previews of the race HUD: draws the HUD layout that tests/race_hud_preview_dump.gd wrote
(generated/race_hud_preview/<name>.json: panels, labels, flags, arrows, the penalty ring, gauges, bars and the
radar's drawing primitives, at 1280 x 720) over a course preview frame from tests/previews. No window opens.

    python3 game/tests/race_hud_preview.py [--publish]

Writes generated/race_hud_preview/<name>.jpg; with --publish also tests/previews/race_hud_<name>.jpg.
The text is set in a system font (Arial Unicode), not the game's default font, so line widths differ a little.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SRC = os.path.join(GAME, "generated", "race_hud_preview")
BACKDROP = {"start": "course_start_line.jpg", "beat": "course_windward.jpg", "incident": "course_race_aerial.jpg",
            "results": "course_committee.jpg"}
FONTS = ["/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/Library/Fonts/Arial Unicode.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
SS = 2  # supersampling


def font(size):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, int(size * SS))
    return ImageFont.load_default()


def col(c, a_mul=1.0):
    return tuple(int(round(255 * max(0.0, min(1.0, v)))) for v in c[:3]) + (int(round(255 * c[3] * a_mul)),)


def s(v):
    return v * SS


def draw_flag(d, f, x, y, w, h):
    blue, yellow, red, white, black = (26, 64, 178), (250, 209, 26), (217, 31, 31), (247, 247, 247), (13, 13, 13)
    box = [s(x), s(y), s(x + w), s(y + h)]
    cx, cy = x + w / 2, y + h / 2
    if f == "class":
        d.rectangle(box, fill=white)
        d.rectangle([s(x), s(y + h * 0.35), s(x + w), s(y + h * 0.65)], fill=blue)
    elif f == "P":
        d.rectangle(box, fill=blue)
        d.rectangle([s(cx - w * 0.2), s(cy - h * 0.2), s(cx + w * 0.2), s(cy + h * 0.2)], fill=white)
    elif f == "I":
        d.rectangle(box, fill=yellow)
        r = h * 0.3
        d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=black)
    elif f == "X":
        d.rectangle(box, fill=white)
        d.rectangle([s(cx - 3), s(y), s(cx + 3), s(y + h)], fill=blue)
        d.rectangle([s(x), s(cy - 3), s(x + w), s(cy + 3)], fill=blue)
    elif f == "black":
        d.rectangle(box, fill=black)
    else:
        d.rectangle(box, fill=(128, 128, 128))
    d.rectangle(box, outline=(0, 0, 0, 150), width=SS)


def render(name, dump):
    bd = os.path.join(HERE, "previews", BACKDROP.get(name, "course_start_line.jpg"))
    w, h = int(dump["size"][0]), int(dump["size"][1])
    base = Image.open(bd).convert("RGBA").resize((int(w * SS), int(h * SS)))
    over = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for it in dump["items"]:
        k = it["k"]
        x, y, iw, ih = it["x"], it["y"], it["w"], it["h"]
        if k == "panel":
            d.rounded_rectangle([s(x), s(y), s(x + iw), s(y + ih)], radius=s(6), fill=col(it["col"]))
        elif k == "label":
            fnt = font(it["size"])
            lines = it["text"].split("\n")
            ty = y
            for line in lines:
                tw = d.textlength(line, font=fnt) / SS
                tx = x + (iw - tw) / 2 if it["align"] == 1 else x
                c = col(it["col"], it.get("alpha", 1.0))
                if it["size"] >= 22:
                    for ox, oy in [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
                        d.text((s(tx) + ox * SS, s(ty) + oy * SS), line, font=fnt, fill=(0, 0, 0, 200))
                d.text((s(tx), s(ty)), line, font=fnt, fill=c)
                ty += it["size"] * 1.25
        elif k == "flags":
            fx = x
            for f in it["flags"]:
                draw_flag(d, f, fx, y, 34, 22)
                lab = {"class": "Class", "1st substitute": "1st sub", "black": "Black"}.get(f, f)
                fnt = font(12)
                tw = d.textlength(lab, font=fnt) / SS
                d.text((s(fx + (34 - tw) / 2), s(y + 24)), lab, font=fnt, fill=(255, 255, 255, 230))
                fx += 44
        elif k == "arrows":
            ax = x
            for sd in it["sides"]:
                port = sd == 0
                c = (242, 77, 64) if port else (77, 217, 89)
                cy = y + ih / 2
                tip = (ax + (2 if port else 26), cy)
                tail = (ax + (26 if port else 2), cy)
                d.line([s(tail[0]), s(cy), s(tip[0] + (6 if port else -6)), s(cy)], fill=c, width=s(4))
                b = 10 if port else -10
                d.polygon([(s(tip[0]), s(cy)), (s(tip[0] + b), s(cy - 8)), (s(tip[0] + b), s(cy + 8))], fill=c)
                ax += 32
        elif k == "ring":
            cx, cy, r = x + 28, y + 30, 22
            d.arc([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], 0, 360, fill=(255, 255, 255, 50), width=s(6))
            if it["f"] > 0:
                d.arc([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], -90, -90 + 360 * it["f"], fill=(255, 191, 51),
                      width=s(6))
            fnt = font(13)
            d.text((s(x + 52), s(y + 8)), "T", font=fnt, fill=(77, 217, 89) if it["tack"] else (255, 255, 255, 77))
            d.text((s(x + 52), s(y + 36)), "G", font=fnt, fill=(77, 217, 89) if it["gybe"] else (255, 255, 255, 77))
        elif k == "gauge":
            fnt = font(15)
            d.text((s(x), s(y)), it["title"].title(), font=fnt, fill=(255, 255, 255))
            gy = y + 24
            d.rectangle([s(x), s(gy), s(x + iw), s(gy + 12)], fill=(255, 255, 255, 30))
            d.rectangle([s(x + iw * 0.25), s(gy), s(x + iw * 0.75), s(gy + 12)], fill=(255, 255, 255, 30))
            nx = x + (max(-2.0, min(2.0, it["needle"])) + 2.0) / 4.0 * iw
            d.line([s(nx), s(gy - 3), s(nx), s(gy + 15)], fill=col(it["col"]), width=s(3))
            d.text((s(x), s(y + 40)), it["telltale"], font=fnt, fill=(255, 255, 255))
        elif k == "bar":
            d.rectangle([s(x), s(y), s(x + iw), s(y + ih)], fill=(255, 255, 255, 38))
            def bx(v):
                t = (v + 1) * 0.5 if it["centred"] else v
                return x + max(0.0, min(1.0, t)) * iw
            x0, x1 = bx(0.0), bx(it["value"])
            d.rectangle([s(min(x0, x1)), s(y + 1), s(max(x0, x1)), s(y + ih - 1)], fill=(230, 230, 230))
            if it["mark"] is not None:
                xm = bx(it["mark"])
                d.line([s(xm), s(y - 2), s(xm), s(y + ih + 2)], fill=(255, 191, 51), width=s(2))
        elif k == "radar":
            for q in it["prims"]:
                c = col(q["col"])
                if q["k"] == "circle":
                    px, py = x + q["p"][0], y + q["p"][1]
                    r = q["r"]
                    d.ellipse([s(px - r), s(py - r), s(px + r), s(py + r)], fill=c)
                elif q["k"] == "arc":
                    px, py = x + q["p"][0], y + q["p"][1]
                    r = q["r"]
                    a0, a1 = math.degrees(q["a0"]), math.degrees(q["a1"])
                    if a1 < a0:
                        a0, a1 = a1, a0
                    d.arc([s(px - r), s(py - r), s(px + r), s(py + r)], a0, a1, fill=c, width=max(1, int(s(q["w"]))))
                elif q["k"] == "line":
                    d.line([s(x + q["a"][0]), s(y + q["a"][1]), s(x + q["b"][0]), s(y + q["b"][1])], fill=c,
                           width=max(1, int(s(q["w"]))))
                elif q["k"] == "poly":
                    d.polygon([(s(x + p[0]), s(y + p[1])) for p in q["pts"]], fill=c)
                elif q["k"] == "polyline":
                    d.line([(s(x + p[0]), s(y + p[1])) for p in q["pts"]], fill=c, width=max(1, int(s(q["w"]))))
                elif q["k"] == "text":
                    fnt = font(q["size"])
                    d.text((s(x + q["p"][0]), s(y + q["p"][1] - q["size"])), q["text"], font=fnt, fill=c)
    img = Image.alpha_composite(base, over).resize((w, h), Image.LANCZOS).convert("RGB")
    return img


def main():
    publish = "--publish" in sys.argv
    names = sorted(f[:-5] for f in os.listdir(SRC) if f.endswith(".json"))
    for n in names:
        with open(os.path.join(SRC, n + ".json")) as fh:
            dump = json.load(fh)
        img = render(n, dump)
        out = os.path.join(SRC, n + ".jpg")
        img.save(out, quality=88)
        print("wrote", out)
        if publish:
            pub = os.path.join(HERE, "previews", "race_hud_%s.jpg" % n)
            img.save(pub, quality=85)
            print("wrote", pub)


if __name__ == "__main__":
    main()
