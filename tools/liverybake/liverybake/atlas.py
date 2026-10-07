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
from .common import F32, blur, fbm, lin_to_srgb, seed_of, smoothstep, srgb_to_lin

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


def _plan_grid(plan, w, h):
    x0, yt, pw, ph = plan
    xs = x0 + (np.arange(w) + 0.5) * pw / w
    ys = yt - (np.arange(h) + 0.5) * ph / h
    return np.meshgrid(xs.astype(F32), ys.astype(F32))


def _resize(a, w, h):
    zy, zx = h / a.shape[0], w / a.shape[1]
    return ndimage.zoom(np.asarray(a, dtype=F32), (zy, zx), order=1)[:h, :w]


def face_base(da, dn, do, geo, w, h):
    """The coachroof's aft face rectangle of the deck image (data_format.md §8.5, boatgen Deck.face_frame): plain deck
    gelcoat (the median of the deck's smooth gelcoat), flat, a little occlusion along its foot (the cockpit floor's
    corner) and its top edge. In place."""
    f = geo.get("face")
    if not f:
        return
    x0, yt, pw, ph = geo["deck"]["plan"]
    i0 = int(np.floor((f["x0"] - x0) / pw * w))
    i1 = int(np.ceil((f["x0"] + f["w"] - x0) / pw * w))
    j0 = int(np.floor((yt - f["y_top"]) / ph * h))
    j1 = int(np.ceil((yt - f["y_top"] + f["h"]) / ph * h))
    i0, i1, j0, j1 = max(i0 - 2, 0), min(i1 + 2, w), max(j0 - 2, 0), min(j1 + 2, h)
    smooth = do[..., 2] < 0.05
    gel = np.median(da[smooth], axis=0) if smooth.any() else np.array([0.6, 0.6, 0.58], F32)
    rough = float(np.median(do[smooth][:, 1])) if smooth.any() else 0.25
    t = (np.arange(j1 - j0) + 0.5) / max(j1 - j0, 1)
    occ = (1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.12, 1.0 - t)) - 0.12 * (1.0 - smoothstep(0.0, 0.05, t)))[:, None]
    da[j0:j1, i0:i1] = gel * (0.94 + 0.06 * occ[..., None])
    dn[j0:j1, i0:i1] = np.array([0.0, 0.0, 1.0], F32)
    do[j0:j1, i0:i1, 0] = occ
    do[j0:j1, i0:i1, 1] = rough
    do[j0:j1, i0:i1, 2] = 0.0


def deck_wear(da, do, geo, w, h, seed):
    """Baked realism on the deck (data_format.md §8.5): ambient occlusion and contact shadows from the height field
    of everything on the deck (geometry.ao_heights: under and round every fitting, along the coachroof's base, the
    toe rail, the cockpit's corners, the mast foot and the vang), a little grime where it is occluded, wear on the
    non-slip in the traffic areas (round the winches, the cockpit floor, the mast foot) and a faint variation of the
    gelcoat's colour and roughness. Subtle: a well-kept race boat. Deterministic per class. In place."""
    ao = geo.get("ao")
    if not ao:
        return
    Z = ao["Z"]
    step = float(ao["step"])
    occ_sum = np.zeros_like(Z)
    for r, wgt in ((0.015, 0.4), (0.05, 0.35), (0.12, 0.25)):
        occ_sum += wgt * np.clip((blur(Z, r / step) - Z) / (0.6 * r), 0.0, 1.0)
    occ = np.clip(1.0 - 0.55 * occ_sum, 0.45, 1.0)
    X, Y = _plan_grid(ao["plan"], Z.shape[1], Z.shape[0])
    traffic = np.zeros_like(Z)
    for (wx, wy) in ao["wear"]:
        traffic = np.maximum(traffic, np.exp(-((X - wx) ** 2 + (Y - wy) ** 2) / (2 * 0.3 ** 2)))
    traffic = np.maximum(traffic, 0.6 * blur(ao["floor"].astype(F32), 0.05 / step))
    blotch = 0.5 + 0.5 * fbm(X / 0.25, Y / 0.25, seed_of(seed, "wear"), 4)
    wear = np.clip(traffic * (0.4 + 0.8 * blotch), 0.0, 1.0)
    tint = fbm(X / 1.5, Y / 1.5, seed_of(seed, "tint"), 3)
    rvar = fbm(X / 0.4, Y / 0.4, seed_of(seed, "rough"), 3)
    occ, wear, tint, rvar = (_resize(a, w, h) for a in (occ, wear, tint, rvar))
    grime = smoothstep(0.85, 0.55, occ)
    face = np.zeros((h, w), bool)
    f = geo.get("face")
    if f:
        x0, yt, pw, ph = geo["deck"]["plan"]
        face[int((yt - f["y_top"]) / ph * h):int((yt - f["y_top"] + f["h"]) / ph * h) + 1,
             int((f["x0"] - x0) / pw * w):int((f["x0"] + f["w"] - x0) / pw * w) + 1] = True
    k = (~face).astype(F32)
    g = np.array([0.93, 0.91, 0.86], F32)                    # grime: a faint warm grey
    a = da * (1.0 + (0.015 * tint + 0.03 * wear)[..., None])
    a = a * (1.0 - (0.30 * (1.0 - occ) + 0.05 * grime)[..., None]) * (1.0 - grime[..., None] * (1.0 - g) * 0.4)
    da[:] = da * (1.0 - k[..., None]) + a * k[..., None]
    do[..., 0] = do[..., 0] * (1.0 - k + k * occ)
    do[..., 1] = np.clip(do[..., 1] * (1.0 + k * (0.06 * rvar)) + k * (0.08 * grime - 0.06 * wear), 0.03, 1.0)
    do[..., 2] = do[..., 2] * (1.0 - k * 0.25 * wear)


def faint_variation(alb, orm, seed, amount=0.008, rough=0.03, streaks=False):
    """A very faint colour and roughness variation (the hull and transom maps; data_format.md §8.5), and on the
    transom faint dried streaks below the cockpit's drain. Linear albedo and ORM, in place."""
    h, w = alb.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(F32)
    u, v = x / w, y / h
    t = fbm(u * 6.0, v * 3.0, seed_of(seed, "var"), 3)
    r = fbm(u * 14.0, v * 7.0, seed_of(seed, "rvar"), 3)
    alb *= (1.0 + amount * t)[..., None]
    orm[..., 1] = np.clip(orm[..., 1] * (1.0 + rough * r), 0.03, 1.0)
    if streaks:
        s = 0.5 + 0.5 * fbm(u * 60.0, v * 1.5, seed_of(seed, "streak"), 3)
        mask = smoothstep(0.2, 0.0, np.abs(u - 0.5) - 0.2) * smoothstep(0.1, 0.5, v)
        alb *= (1.0 - 0.035 * smoothstep(0.55, 0.8, s) * mask)[..., None]


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

    seed = geo.get("id", "boat")
    for name, src in (("hull", hull), ("transom", trn)):
        _, _, w, h = rects[name]
        a = srgb_to_lin(_fit(src["albedo"], w, h))
        o = _fit(src["orm"], w, h)
        faint_variation(a, o, f"{seed}:{name}", streaks=name == "transom")
        put(name, lin_to_srgb(a), _unit(_fit(src["normal"], w, h)) * 0.5 + 0.5, o)
    # the deck with the painted hardware over it
    _, _, w, h = rects["deck"]
    da = srgb_to_lin(_fit(deck["albedo"], w, h))
    dn = _unit(_fit(deck["normal"], w, h))
    do = _fit(deck["orm"], w, h)
    face_base(da, dn, do, geo, w, h)
    deck_wear(da, do, geo, w, h, seed)
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
