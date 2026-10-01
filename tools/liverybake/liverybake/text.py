"""Text masks in Barlow Semi Condensed Bold (game/fonts/barlow, OFL), with the proportions of the game's per-boat
text texture (game/scripts/livery/livery_text.gd): rows of 128 units, cap band from 17 to 102 (the baseline),
tracking 0.05 of the font size, and the insignia in bold italic over a wave mark.

A mask is rendered at `scale` times those units and returned with its box: the whole row (insignia) or the cap
band (letters and digits), so a box `h` high in metres maps onto the band exactly as in the game.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from .common import FONT

SIZE = 120
ROW = 128
CAP_TOP = 17
BASELINE = 102
PAD = 10
TRACK = 0.05
SLANT = 0.22

_fonts = {}


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(str(FONT), size)
    return _fonts[size]


def measure(text):
    """Ink width of `text` in row units (advances plus tracking, as LiveryText.measure)."""
    f = font(SIZE)
    return sum(f.getlength(c) for c in text) + TRACK * SIZE * max(len(text) - 1, 0)


def aspect(text, insignia=False):
    """Width over height of the text's box: the whole row for the insignia, else the cap band."""
    w = measure(text) + (SLANT * (BASELINE - CAP_TOP) if insignia else 0.0) + 4.0
    return w / (ROW if insignia else BASELINE - CAP_TOP)


def mask(text, insignia=False, scale=4):
    """Coverage (H, W) float32 of the text's box at `scale` px per row unit (see the module notes)."""
    s = scale
    f = font(SIZE * s)
    w = int(np.ceil((measure(text) + SLANT * ROW + 2 * PAD + 8) * s))
    img = Image.new("L", (w, ROW * s), 0)
    d = ImageDraw.Draw(img)
    x = PAD * s
    for c in text:
        d.text((x, BASELINE * s), c, fill=255, font=f, anchor="ls")
        x += f.getlength(c) + TRACK * SIZE * s
    a = np.asarray(img, dtype=np.float32) / 255.0
    ink_r = x - TRACK * SIZE * s
    if insignia:
        # bold italic: each row shifted right by its height above the baseline
        out = np.zeros_like(a)
        for r in range(a.shape[0]):
            sh = int(round(SLANT * (BASELINE * s - r)))
            if sh >= 0:
                out[r, sh:] = a[r, :a.shape[1] - sh] if sh else a[r]
            else:
                out[r, :sh] = a[r, -sh:]
        a = out
        ink_r += SLANT * (BASELINE - CAP_TOP) * s
        # the wave mark under the letters
        xs = np.arange(PAD * s, int(ink_r) + 1)
        t = (xs - PAD * s) / max(ink_r - PAD * s, 1.0)
        yc = (BASELINE + 14.0 - 6.0 * np.sin(2 * np.pi * (t * 1.25 + 0.1))) * s
        th = (4.0 + 4.0 * np.sin(np.pi * t)) * s
        rr = np.arange(a.shape[0])[:, None]
        wave = np.clip(0.5 * th[None, :] - np.abs(rr - yc[None, :]) + 0.5, 0, 1)
        a[:, xs] = np.maximum(a[:, xs], wave)
    x0 = int(round((PAD - 2) * s))
    x1 = int(round(ink_r + 2 * s))
    a = a[:, x0:x1]
    if not insignia:
        a = a[CAP_TOP * s:BASELINE * s]
    return np.ascontiguousarray(a)
