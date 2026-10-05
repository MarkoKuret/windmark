"""The staged boat atlas (data_format.md §8.5 "Staged boat atlas"): per livery, the hull, deck (with the painted
hardware), transom and keel images packed into one atlas per map for the game's one boat material
(sail_visuals.md §11.4). Generated at stage time from the hand-owned images, which stay the masters.

Layout (v down): the hull (2:1) across the top, the deck at its own aspect below it, then the transom and the keel
side by side in the band left; every region padded by its edge texels into a gutter (16 texels at 2048, scaled
with the size), so mipmaps do not bleed between regions.
"""
import json

import numpy as np
from PIL import Image
from scipy import ndimage

from . import painted
from .common import F32, lin_to_srgb, srgb_to_lin

SIZE = 2048
SCHEMA = "windmark.boatatlas/1"
KEEL_ROUGH = 0.75


def layout(size, deck_aspect, transom_aspect, keel_aspect):
    """Region pixel rectangles {name: (x, y, w, h)} for an atlas of `size`; aspects are height / width."""
    g = int(round(16 * size / 2048))
    W = size - 2 * g
    hull = (g, g, W, W // 2)
    y = hull[1] + hull[3] + 2 * g
    deck = (g, y, W, int(round(W * deck_aspect)))
    y = deck[1] + deck[3] + 2 * g
    hb = size - g - y
    if hb < 8:
        raise ValueError("the deck leaves no room for the transom and keel")
    tw, kw = hb / transom_aspect, hb / keel_aspect
    s = min(1.0, (W - 2 * g) / (tw + kw))
    th = int(np.floor(hb * s))
    tr = (g, y, int(round(th / transom_aspect)), th)
    kh = int(np.floor(hb * s))
    kx = tr[0] + tr[2] + 2 * g
    keel = (kx, y, min(int(round(kh / keel_aspect)), size - g - kx), kh)
    return {"hull": hull, "deck": deck, "transom": tr, "keel": keel}


def _load(path, mode="RGB"):
    return Image.open(path).convert(mode)


def _fit(img, w, h):
    return np.asarray(img.resize((w, h), Image.LANCZOS), dtype=F32) / 255.0


def _unit(n):
    n = n * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    return n


def build(folder, geo, rope_set, size=SIZE):
    """The atlas of a livery folder (data/liveries/<class>/<livery>/): ({"albedo", "normal", "orm"}: uint8
    (size, size, 3) images, atlas.json dict)."""
    folder = str(folder)
    hull = {k: _load(f"{folder}/hull_{k}.png") for k in ("albedo", "normal", "orm")}
    deck = {k: _load(f"{folder}/deck_{k}.png") for k in ("albedo", "normal", "orm")}
    trn = {k: _load(f"{folder}/transom_{k}.png") for k in ("albedo", "normal", "orm")}
    keel = _load(f"{folder}/keel_albedo.png")
    asp = lambda im: im.size[1] / im.size[0]
    rects = layout(size, asp(deck["albedo"]), asp(trn["albedo"]), asp(keel))
    alb = np.zeros((size, size, 3), F32)
    nrm = np.zeros((size, size, 3), F32)
    orm = np.zeros((size, size, 3), F32)
    valid = np.zeros((size, size), bool)

    def put(name, a, n, o):
        x, y, w, h = rects[name]
        alb[y:y + h, x:x + w] = a
        nrm[y:y + h, x:x + w] = n
        orm[y:y + h, x:x + w] = o
        valid[y:y + h, x:x + w] = True

    for name, src in (("hull", hull), ("transom", trn)):
        _, _, w, h = rects[name]
        put(name, _fit(src["albedo"], w, h), _unit(_fit(src["normal"], w, h)) * 0.5 + 0.5, _fit(src["orm"], w, h))
    # the deck with the painted hardware over it
    _, _, w, h = rects["deck"]
    da = srgb_to_lin(_fit(deck["albedo"], w, h))
    dn = _unit(_fit(deck["normal"], w, h))
    do = _fit(deck["orm"], w, h)
    pieces = geo.get("painted", [])
    if pieces:
        layer = painted.bake(pieces, geo["deck"]["plan"], w, h, rope_set)
        da, dn, do = painted.composite(da, dn, do, layer)
    put("deck", lin_to_srgb(da), dn * 0.5 + 0.5, do)
    _, _, w, h = rects["keel"]
    put("keel", _fit(keel, w, h), np.broadcast_to(np.array([0.5, 0.5, 1.0], F32), (h, w, 3)),
        np.broadcast_to(np.array([1.0, KEEL_ROUGH, 0.0], F32), (h, w, 3)))
    # gutters and the rest: the nearest region texel
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    out = {}
    for k, a in (("albedo", alb), ("normal", nrm), ("orm", orm)):
        a = a[idx[0], idx[1]]
        out[k] = (np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    meta = {"schema": SCHEMA, "size": [size, size],
            "regions": {k: [round(v[0] / size, 6), round(v[1] / size, 6), round(v[2] / size, 6),
                            round(v[3] / size, 6)] for k, v in rects.items()},
            "pixels": {k: list(v) for k, v in rects.items()}}
    return out, meta


def write(folder_out, images, meta):
    """Writes atlas_<map>.png and atlas.json into `folder_out`; returns the paths written (changed only)."""
    import io
    from pathlib import Path
    folder_out = Path(folder_out)
    folder_out.mkdir(parents=True, exist_ok=True)
    changed = []
    for k, a in images.items():
        buf = io.BytesIO()
        Image.fromarray(a).save(buf, "PNG", compress_level=6)
        p = folder_out / f"atlas_{k}.png"
        if not p.exists() or p.read_bytes() != buf.getvalue():
            p.write_bytes(buf.getvalue())
            changed.append(p)
    p = folder_out / "atlas.json"
    js = json.dumps(meta, indent=1) + "\n"
    if not p.exists() or p.read_text() != js:
        p.write_text(js)
        changed.append(p)
    return changed
