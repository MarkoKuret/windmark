"""A kite's fixed flying shape taken from a complete measured 3D surface (docs/specs/sail_visuals.md 6.5, the surface
source; the file format is docs/specs/data_format.md 3.7.6): the surface is resampled onto the class's sail grid by
(uc, h), each vertex at its row's stripe h (a share of the luff and of the leech) and its share uc of the row's girth,
and mapped onto the class's corners by one linear map in the sail's plane (the tack and the head where the flat sail
has them, the clew where the measured foot and leech, scaled by the class's own, put it), the depth scaled with the
chord. The measured outline, its edge curvature and its corners are kept; nothing is rebuilt from section numbers.

Two surface forms:
- `grid`: the measured surface itself, already resampled by (h, uc) (`points`, rows from the foot, columns from the
  luff), written once from the source geometry by `python3 -m boatgen.kite_surface ac33 <file.igs>`.
- `moore_iacc`: the closed-form parametric symmetric spinnaker series of Moore (2004) and Lasher and Richards (2007),
  coefficients as reprinted by Peart (2022), appendix A, evaluated here.

`python3 -m boatgen.kite_surface render [--out DIR]` draws every surface of the surface files alone (no boat, plain
shaded, three views) for the raw-data check.
"""
import json
import math
import os
import sys

import numpy as np

from .kite_loft import DATA_DIR, KiteShapeError, sail_frame

SCHEMA = "windmark.kiteshape/1"
KIND = "surface"
GRID = (49, 41)        # rows (h) and columns (uc) a surface is resampled to before it is mapped onto a class grid
N_ROW = 801            # samples along a row for its girth
DEPTH_RANGE = (0.5, 1.5)
FOOT_LIFT_H = 0.25     # the foot lift fades out over this lower share of the height


# ---------------------------------------------------------------------------- the file


def is_surface(d):
    return isinstance(d, dict) and d.get("kind") == KIND


def validate(d, where="kite shape"):
    """A surface kite shape file: {"name", "source", "surfaces": {name: spec}, "shapes": [{"awa" (rad), "surface",
    "depth"}] sorted by AWA}."""
    if not isinstance(d, dict) or d.get("schema") != SCHEMA or d.get("kind") != KIND:
        raise KiteShapeError(f"{where}: schema must be {SCHEMA} with kind {KIND!r}")
    src = d.get("source")
    if not isinstance(src, dict) or not str(src.get("citation", "")).strip():
        raise KiteShapeError(f"{where}: source.citation is required")
    if not str(src.get("licence", "")).strip():
        raise KiteShapeError(f"{where}: source.licence is required")
    surfs = d.get("surfaces")
    if not isinstance(surfs, dict) or not surfs:
        raise KiteShapeError(f"{where}: surfaces must name one or more surfaces")
    for k, s in surfs.items():
        w = f"{where}.surfaces.{k}"
        form = s.get("form") if isinstance(s, dict) else None
        if form == "grid":
            p = np.asarray(s.get("points"), dtype=np.float64)
            if p.ndim != 3 or p.shape[2] != 3 or p.shape[0] < 4 or p.shape[1] < 4 or not np.all(np.isfinite(p)):
                raise KiteShapeError(f"{w}.points must be rows (4+) of columns (4+) of [a, l, n]")
        elif form == "moore_iacc":
            c = s.get("coef")
            if not isinstance(c, dict) or [len(c.get(x, [])) for x in "abcd"] != [5, 5, 4, 4]:
                raise KiteShapeError(f"{w}.coef needs a (5), b (5), c (4) and d (4)")
            if len(s.get("k", [])) != 3:
                raise KiteShapeError(f"{w}.k must be [kx, ky, kz]")
        else:
            raise KiteShapeError(f"{w}.form must be grid or moore_iacc")
    shapes = d.get("shapes")
    if not isinstance(shapes, list) or not shapes:
        raise KiteShapeError(f"{where}: shapes needs one or more apparent wind angles")
    out = []
    for i, s in enumerate(shapes):
        w = f"{where}.shapes[{i}]"
        awa = s.get("awa_deg")
        if isinstance(awa, bool) or not isinstance(awa, (int, float)) or not 20 <= awa <= 180:
            raise KiteShapeError(f"{w}.awa_deg must be a number from 20 to 180")
        if s.get("surface") not in surfs:
            raise KiteShapeError(f"{w}.surface must name one of {sorted(surfs)}")
        dep = s.get("depth", 1.0)
        if isinstance(dep, bool) or not isinstance(dep, (int, float)) or not DEPTH_RANGE[0] <= dep <= DEPTH_RANGE[1]:
            raise KiteShapeError(f"{w}.depth must be a number from {DEPTH_RANGE[0]:g} to {DEPTH_RANGE[1]:g}")
        lift = s.get("foot_lift", 0.0)
        if isinstance(lift, bool) or not isinstance(lift, (int, float)) or not 0.0 <= lift <= 1.0:
            raise KiteShapeError(f"{w}.foot_lift must be a number from 0 to 1")
        bow = s.get("run_bow", 0.0)
        if isinstance(bow, bool) or not isinstance(bow, (int, float)) or not 0.0 <= bow <= 0.2:
            raise KiteShapeError(f"{w}.run_bow must be a number from 0 to 0.2")
        ease = s.get("clew_ease", 0.0)
        if isinstance(ease, bool) or not isinstance(ease, (int, float)) or not 0.0 <= ease <= 90.0:
            raise KiteShapeError(f"{w}.clew_ease must be a number from 0 to 90")
        out.append({"awa": math.radians(awa), "surface": s["surface"], "depth": float(dep), "foot_lift": float(lift),
                    "run_bow": float(bow), "clew_ease": math.radians(ease)})
    out.sort(key=lambda s: s["awa"])
    if len({s["awa"] for s in out}) != len(out):
        raise KiteShapeError(f"{where}: one shape per apparent wind angle")
    return {"name": d.get("name", where), "source": src, "surfaces": surfs, "shapes": out}


def load(name, data_dir=None):
    path = os.path.join(data_dir or DATA_DIR, f"{name}.kite_shape.json")
    if not os.path.exists(path):
        raise KiteShapeError(f"kite shape {name!r}: no file {path}")
    with open(path) as f:
        return validate(json.load(f), name)


# ---------------------------------------------------------------------------- the surfaces by (h, uc)


def _arc(P):
    return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=-1))])


def _resample(P, s):
    """The polyline P (n, 3) at the shares s of its length (a polyline of no length: its first point)."""
    a = _arc(P)
    if a[-1] < 1e-12:
        return np.repeat(P[:1], len(np.atleast_1d(s)), 0)
    t = np.asarray(s) * a[-1]
    return np.stack([np.interp(t, a, P[:, k]) for k in range(3)], -1)


def in_frame(M, depth=None):
    """The (h, uc) grid M (rows, cols, 3) in its own sail frame: from the tack M[0, 0], `l` toward the head (the
    head row's mean), `a` square to it in the plane of the tack, the head and the clew M[0, -1], toward the clew,
    `n` square to both, on the belly's side. With `depth` (a direction of M's frame, the belly's side) the depth is
    taken along it instead of square to the plane (an oblique frame: a point is T + a e_a + l e_l + n depth), so a
    surface whose sections are level and whose belly lies down the wind keeps them so when its luff is stood on the
    sail's luff axis."""
    T, H, C = M[0, 0], M[-1].mean(0), M[0, -1]
    el = (H - T) / np.linalg.norm(H - T)
    ea = (C - T) - el * ((C - T) @ el)
    ea /= np.linalg.norm(ea)
    en = np.cross(ea, el)
    d = M - T
    if depth is None:
        out = np.stack([d @ ea, d @ el, d @ en], -1)
        if out[..., 2].mean() < 0:
            out[..., 2] *= -1
    else:
        w = np.asarray(depth, dtype=np.float64)
        w = w / np.linalg.norm(w)
        if w @ en < 0:
            en = -en
        B = np.stack([ea, el, w], -1)
        out = d @ np.linalg.inv(B).T
    out[-1] = out[-1].mean(0)          # a pointed head
    return out


def moore_point(coef, k, s, t):
    """The Moore / Lasher-Richards surface at (s, t): x lateral (luff to luff, s from -0.5 to 0.5), y up, z the
    belly's side (downwind)."""
    a, b, c, d = (np.asarray(coef[x], dtype=np.float64) for x in "abcd")
    with np.errstate(all="ignore"):     # the BLAS behind numpy may flag spurious overflows on small matrix products
        return _moore(a, b, c, d, k, s, t)


def _moore(a, b, c, d, k, s, t):
    s, t = np.broadcast_arrays(np.asarray(s, dtype=np.float64), np.asarray(t, dtype=np.float64))
    tn5 = np.stack([t ** n for n in range(5)], -1)
    x = k[0] * (tn5 @ a * s ** 3 + tn5 @ b * s)
    y = k[1] * (t - 0.1)
    z = k[2] * (tn5[..., :4] @ c * s ** 2 + tn5[..., :4] @ d)
    return np.stack([x, y, z], -1)


def moore_head(coef, k):
    """The t (>= 0.9) at which the series' luffs meet (the half width at s = 0.5 is zero): the head."""
    lo, hi = 0.9, 1.1
    f = lambda t: float(moore_point(coef, k, 0.5, t)[0])
    for _ in range(60):
        m = 0.5 * (lo + hi)
        if f(m) > 0:
            lo = m
        else:
            hi = m
    return 0.5 * (lo + hi)


def moore_grid(spec, rows=GRID[0], cols=GRID[1]):
    """A Moore / Lasher-Richards sail by (h, uc): the rows are its horizontal sections (constant t), at the stripe h
    of the luff's length from the foot (t = 0.1) to where the luffs meet; each row resampled by its girth."""
    coef, k = spec["coef"], spec["k"]
    th = moore_head(coef, k)
    tt = np.linspace(0.1, th, 4001)
    luff = moore_point(coef, k, -0.5, tt)
    a = _arc(luff)
    hs = np.linspace(0.0, 1.0, rows)
    ts = np.interp(hs * a[-1], a, tt)
    ss = np.linspace(-0.5, 0.5, N_ROW)
    uc = np.linspace(0.0, 1.0, cols)
    return np.stack([_resample(moore_point(coef, k, ss, t), uc) for t in ts])


def surface_grid(spec, rows=GRID[0], cols=GRID[1]):
    """Any surface of a file by (h, uc), in its own sail frame (in_frame)."""
    if spec["form"] == "grid":
        M = np.asarray(spec["points"], dtype=np.float64)
        if M.shape[:2] != (rows, cols):
            M = sample(M, np.linspace(0, 1, rows)[:, None].repeat(cols, 1),
                       np.linspace(0, 1, cols)[None].repeat(rows, 0))
        return in_frame(M)
    return in_frame(moore_grid(spec, rows, cols), depth=(0.0, 0.0, 1.0))   # level sections, the belly down the wind


def _cr(p0, p1, p2, p3, t):
    t = t[..., None]
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)


def sample(M, h, uc):
    """The (h, uc) grid M (rows, cols, 3) at the shares h, uc (same shape), Catmull-Rom across both (the ends
    extended linearly, so the edges stay where they are)."""
    R, C = M.shape[:2]
    E = np.concatenate([2 * M[:1] - M[1:2], M, 2 * M[-1:] - M[-2:-1]], 0)
    E = np.concatenate([2 * E[:, :1] - E[:, 1:2], E, 2 * E[:, -1:] - E[:, -2:-1]], 1)
    x = np.clip(np.asarray(h, dtype=np.float64), 0, 1) * (R - 1)
    y = np.clip(np.asarray(uc, dtype=np.float64), 0, 1) * (C - 1)
    i = np.minimum(np.floor(x).astype(int), R - 2)
    j = np.minimum(np.floor(y).astype(int), C - 2)
    tx, ty = x - i, y - j
    rows = [_cr(*(E[i + a, j + b] for b in range(4)), ty) for a in range(4)]
    return _cr(*rows, tx)


# ---------------------------------------------------------------------------- onto the class


def outline(G):
    """Edge lengths along the cloth of a grid (rows, cols, 3): luff, leech, foot and the girth of the half-height
    row (the mid girth along the cloth), plus the straight distances between the corners."""
    r = (G.shape[0] - 1) / 2
    lo, hi = int(math.floor(r)), int(math.ceil(r))
    mid = 0.5 * (_arc(G[lo])[-1] + _arc(G[hi])[-1])
    T, H, C = G[0, 0], G[-1].mean(0), G[0, -1]
    return {"luff": float(_arc(G[:, 0])[-1]), "leech": float(_arc(G[:, -1])[-1]), "foot": float(_arc(G[0])[-1]),
            "mid_girth": float(mid), "tack_head": float(np.linalg.norm(H - T)), "tack_clew": float(np.linalg.norm(C - T)),
            "head_clew": float(np.linalg.norm(C - H))}


def corner_map(M, P):
    """The linear map of the measured surface M (in its frame, in_frame) onto the flat class grid P: (A (2 x 2, on
    (a, l)), the depth scale, the target clew (a, l)). The head goes to the flat head (the luff's straight length),
    the clew to where the measured tack-clew and head-clew distances, each scaled by the class's over the measured
    foot and leech along the cloth, meet; the depth scales as the measured `a` direction does."""
    T, Ah, Lh, Nh = sail_frame(P)
    mo, co = outline(M), outline(P)
    th_c = float((P[-1, 0] - T) @ Lh)
    d_tc = mo["tack_clew"] * co["foot"] / mo["foot"]
    d_hc = mo["head_clew"] * co["leech"] / mo["leech"]
    lc = (d_tc ** 2 - d_hc ** 2 + th_c ** 2) / (2 * th_c)
    ac = math.sqrt(max(d_tc ** 2 - lc ** 2, 1e-9))
    Hm, Cm = M[-1, 0, :2], M[0, -1, :2]
    src = np.array([[Cm[0], Hm[0]], [Cm[1], Hm[1]]])
    dst = np.array([[ac, 0.0], [lc, th_c]])
    A = dst @ np.linalg.inv(src)
    return A, float(np.linalg.norm(A[:, 0])), (ac, lc)


def class_shape(M, P, depth=1.0):
    """The measured surface M (in its frame) on the flat class grid P (rows, cols, 3): every vertex at its row's
    stripe and its share of the row's flat girth, mapped by corner_map; (rows * cols, 3) local positions (a, l, n)
    in the sail frame of sail_visuals.md 3.2 (from the tack), the belly to port, the depth times `depth`."""
    rows, cols = P.shape[:2]
    seg = np.linalg.norm(np.diff(P, axis=1), axis=-1)
    g = np.concatenate([np.zeros((rows, 1)), np.cumsum(seg, 1)], 1)
    uc = np.where(g[:, -1:] > 1e-9, g / np.maximum(g[:, -1:], 1e-9), np.linspace(0, 1, cols)[None])
    h = np.repeat((np.arange(rows) / (rows - 1))[:, None], cols, 1)
    S = sample(M, h, uc)
    A, sd, _ = corner_map(M, P)
    al = S[..., :2] @ A.T
    out = np.concatenate([al, S[..., 2:] * sd * depth], -1)
    out[-1] = out[-1].mean(0)
    return out.reshape(-1, 3)


def foot_lifted(L, f):
    """The local shape L (rows, cols, 3) with the share f of its foot's sag below the straight tack-clew line (along
    l) lifted out, fading out over the lower FOOT_LIFT_H of the height (sail_visuals.md 6.5)."""
    if f <= 0.0:
        return L
    rows = L.shape[0]
    a_c, l_c = L[0, -1, 0], L[0, -1, 1]
    sag = np.maximum(0.0, l_c * L[0, :, 0] / a_c - L[0, :, 1])
    h = np.arange(rows) / (rows - 1)
    x = np.clip(h / FOOT_LIFT_H, 0.0, 1.0)
    fade = 1.0 - x * x * (3.0 - 2.0 * x)
    out = L.copy()
    out[..., 1] += f * fade[:, None] * sag[None, :]
    return out


def run_projected(L, bow, ease):
    """The local shape L (rows, cols, 3) with a running kite's forward projection (sail_visuals.md 6.5): every row
    moved toward the belly by bow * (the luff along the cloth) * sin(PI h), and turned about the luff axis by
    ease * (1 - h)^2, the clew toward the belly. The luff axis, so the tack and the head, stays."""
    if bow <= 0.0 and ease <= 0.0:
        return L
    rows = L.shape[0]
    h = np.arange(rows) / (rows - 1)
    out = L.copy()
    out[..., 2] += (bow * _arc(L[:, 0])[-1] * np.sin(np.pi * h))[:, None]
    t = (ease * (1.0 - h) ** 2)[:, None]
    a, n = out[..., 0].copy(), out[..., 2].copy()
    out[..., 0] = a * np.cos(t) - n * np.sin(t)
    out[..., 2] = a * np.sin(t) + n * np.cos(t)
    out[-1] = L[-1]
    return out


def sheet_angle(L, place, awa):
    """The sheet's angle off the clew corner's bisector (rad, test 25's measure) of the local shape L set alone at its
    nominal trim for `awa` (`place(awa, loc)`: the placed grid and the sheet's lead)."""
    from .kite_loft import clew_angle
    G, lead = place(awa, L.reshape(-1, 3))
    return clew_angle(G, lead)


def sidecar_block(P, name, shape=None, place=None):
    """The sidecar's `loft` block of a kite whose shape file is a surface (sail_visuals.md 6.5): as kite_loft's
    (`awa`, `shapes` per AWA in the sail frame, grid order) plus the outlines it was mapped between, the foot lift
    and, with `place` (as kite_loft.loft takes it), the sheet's angle off the clew's bisector at each AWA's nominal
    trim."""
    shape = shape or load(name)
    rows, cols = P.shape[:2]
    grids = {}
    shapes, clew = [], []
    for s in shape["shapes"]:
        if s["surface"] not in grids:
            grids[s["surface"]] = surface_grid(shape["surfaces"][s["surface"]])
        L = class_shape(grids[s["surface"]], P, s["depth"]).reshape(rows, cols, 3)
        L = foot_lifted(L, s["foot_lift"])
        L = run_projected(L, s["run_bow"], s["clew_ease"])
        if place is not None:
            clew.append({"sheet_off_bisector_deg": round(math.degrees(sheet_angle(L, place, s["awa"])), 2)})
        shapes.append(L.reshape(-1, 3))
    first = grids[shape["shapes"][0]["surface"]]
    mo, co = outline(first), outline(P)
    _, sd, _ = corner_map(first, P)
    rnd = lambda d: {k: round(v, 4) for k, v in d.items()}
    return {"shape": name, "kind": KIND, "source": shape["source"].get("citation", ""),
            "map": {"measured": rnd({k: v / mo["luff"] for k, v in mo.items()}),
                    "class": rnd({k: v / co["luff"] for k, v in co.items()}), "depth_scale": round(sd, 6),
                    "note": "edge lengths along the cloth and corner distances, over the luff"},
            "frame": "sail frame of sail_visuals.md 3.2 from the tack: a aft square to the luff, l along the luff, "
                     "n to port (the belly); grid order",
            "awa": [round(s["awa"], 6) for s in shape["shapes"]],
            "depth": [s["depth"] for s in shape["shapes"]],
            "surface": [s["surface"] for s in shape["shapes"]],
            "foot_lift": [s["foot_lift"] for s in shape["shapes"]],
            "run_bow": [s["run_bow"] for s in shape["shapes"]],
            "clew_ease_deg": [round(math.degrees(s["clew_ease"]), 3) for s in shape["shapes"]],
            "clew": clew,
            "shapes": [np.round(s, 5).tolist() for s in shapes]}


# ---------------------------------------------------------------------------- the AC33 import (run once)


def iges_kite(path, rows=GRID[0], cols=GRID[1]):
    """The sail surface of a rigid kite model in an IGES file, by (h, uc): its largest trimmed surface (the outer
    face of the model; the mounting bosses and the thin edge faces are left out), whose parameter lines run from a
    pointed head to the foot one way and from edge to edge the other. The longer edge is the luff. Row h runs, in
    the surface's parameters, straight from the luff's stripe h to the leech's (both from the foot), and is
    resampled by its girth; at h = 0 that is the foot."""
    from .iges import read, trimmed_surfaces
    ents = read(path)
    best, area = None, -1.0
    for t in trimmed_surfaces(ents):
        S = t["surface"]
        G = S.grid(np.linspace(S.u0, S.u1, 40), np.linspace(S.v0, S.v1, 40))
        a = np.linalg.norm(np.cross(G[1:, :-1] - G[:-1, :-1], G[:-1, 1:] - G[:-1, :-1]), axis=-1).sum()
        if a > area:
            best, area = S, a
    S = best
    nu = 2001
    us = np.linspace(S.u0, S.u1, nu)
    e0 = S.grid(us, [S.v0])[0]
    e1 = S.grid(us, [S.v1])[0]
    if np.linalg.norm(e0[0] - e1[0]) > np.linalg.norm(e0[-1] - e1[-1]):
        us = us[::-1]               # the head first
        e0, e1 = e0[::-1], e1[::-1]
    # stripes from the foot: arc length measured from the foot end
    luff_v, leech_v = (S.v0, S.v1) if _arc(e0)[-1] > _arc(e1)[-1] else (S.v1, S.v0)
    eL, eR = (e0, e1) if luff_v == S.v0 else (e1, e0)
    aL, aR = _arc(eL[::-1]), _arc(eR[::-1])
    uL_f, uR_f = us[::-1], us[::-1]
    hs = np.linspace(0.0, 1.0, rows)
    uL = np.interp(hs * aL[-1], aL, uL_f)
    uR = np.interp(hs * aR[-1], aR, uR_f)
    w = np.linspace(0.0, 1.0, N_ROW)
    vv = luff_v + (leech_v - luff_v) * w
    uc = np.linspace(0.0, 1.0, cols)
    out = []
    for i in range(rows):
        uu = (1 - w) * uL[i] + w * uR[i]
        out.append(_resample(S.at(uu, vv), uc))
    return np.array(out)


def ac33_file(igs_path, rows=GRID[0], cols=GRID[1]):
    M = in_frame(iges_kite(igs_path, rows, cols))
    return {
        "schema": SCHEMA, "kind": KIND,
        "name": "AC33 benchmark asymmetric spinnaker, flying shape measured in a twisted-flow wind tunnel at AWA 55 deg",
        "source": {
            "citation": "Arredondo-Galeana A., Viola I. M. (2020). PIV dataset for near wake of spinnaker: Vortex flows "
                        "of downwind sails [dataset]. University of Edinburgh, School of Engineering. "
                        "https://doi.org/10.7488/ds/2857, file Geometries/IGS_format/Spinnaker_high_twist_16deg.igs. "
                        "Geometry: Viola I. M., Flay R. G. J. (2011), Sail aerodynamics: understanding pressure "
                        "distributions on upwind sails / downwind sails, Ocean Engineering 38; Arredondo-Galeana A. "
                        "(2019), PhD thesis, University of Edinburgh.",
            "url": "https://datashare.ed.ac.uk/handle/10283/3676",
            "licence": "CC-BY-4.0",
            "method": "the flying shape of an AC33-class asymmetric spinnaker measured by photogrammetry in the "
                      "Auckland twisted-flow wind tunnel at its optimum AWA of 55 deg, built as a rigid 1:106 model "
                      "(16 deg twist foot to head); the outer face of that model's IGES geometry, resampled by "
                      "boatgen.kite_surface (rows: stripes at equal shares of the luff and the leech from the foot; "
                      "columns: equal shares of each row's girth from the luff)",
            "sail": "AC33 A-sail, designed area 510 m2 full size; model span 300 mm",
        },
        "definitions": {
            "points": "rows from the foot (h = row / (rows - 1): the row's stripe, a share of the luff and of the "
                      "leech) of columns from the luff (uc = column / (cols - 1): a share of the row's girth); "
                      "[a, l, n] in model millimetres from the tack: l toward the head, a square to it toward the "
                      "clew in the tack-head-clew plane, n square to both on the belly's (leeward) side",
            "shapes": "the run is the measured reach shape turned whole by the trim and a little deeper (depth); the reach "
                      "has half its foot sag below the tack-clew line lifted out (foot_lift)",
        },
        "surfaces": {"ac33": {"form": "grid", "points": np.round(M, 3).tolist()}},
        "shapes": [{"awa_deg": 55, "surface": "ac33", "foot_lift": 0.5}, {"awa_deg": 130, "surface": "ac33", "depth": 1.1}],
    }


# ---------------------------------------------------------------------------- the raw-data check


def _mesh(M):
    R, C = M.shape[:2]
    idx = []
    for i in range(R - 1):
        for j in range(C - 1):
            a, b, c, d = i * C + j, i * C + j + 1, (i + 1) * C + j, (i + 1) * C + j + 1
            idx += [a, b, d, a, d, c]
    return M.reshape(-1, 3), np.array(idx, dtype=np.int32)


RAW_VS = """
#version 410
in vec3 in_pos; in vec3 in_nrm; uniform mat4 mvp; out vec3 v_nrm;
void main() { v_nrm = in_nrm; gl_Position = mvp * vec4(in_pos, 1.0); }
"""
RAW_FS = """
#version 410
in vec3 v_nrm; uniform vec3 light; uniform vec3 eye; uniform vec3 col; uniform int line; out vec4 frag;
void main() {
    if (line == 1) { frag = vec4(0.1, 0.1, 0.15, 1.0); return; }
    vec3 n = normalize(v_nrm);
    if (!gl_FrontFacing) n = -n;
    float d = max(dot(n, light), 0.0);
    float e = abs(dot(n, eye));
    vec3 c = gl_FrontFacing ? col : col * vec3(0.85, 0.9, 1.0);
    frag = vec4(c * (0.2 + 0.45 * d + 0.4 * e), 1.0);
}
"""


def render_raw(M, path, title, size=(720, 720)):
    """The surface M (in its frame: a toward the clew, l up, n the belly) alone, plain shaded with its outline and
    every fourth grid line, from three sides: the belly side (leeward), the concave side (windward, from ahead of
    the luff) and from the clew end; one image of three panels."""
    import moderngl
    from PIL import Image, ImageDraw
    from .render import look_at, ortho
    from .bake import gl_context
    from .kite_preview import _font
    ctx = gl_context()
    W, H = size
    R, C = M.shape[:2]
    X = M[..., [0, 1, 2]] / max(np.ptp(M[..., 1]), 1e-9)     # l up: x = a, y = l, z = n
    X = X - np.array([X[..., 0].mean(), 0.5, X[..., 2].mean()])
    du = np.gradient(X, axis=1)
    dv = np.gradient(X, axis=0)
    N = np.cross(du, dv)
    N /= np.maximum(np.linalg.norm(N, axis=-1, keepdims=True), 1e-12)
    pos, idx = _mesh(X)
    prog = ctx.program(vertex_shader=RAW_VS, fragment_shader=RAW_FS)
    vbo = ctx.buffer(np.hstack([pos, N.reshape(-1, 3)]).astype("f4").tobytes())
    vao = ctx.vertex_array(prog, [(vbo, "3f 3f", "in_pos", "in_nrm")], ctx.buffer(idx.tobytes()))
    lines = [X[0], X[:, -1], X[:, 0]] + [X[i] for i in range(4, R - 1, 4)] + [X[:, j] for j in range(4, C - 1, 4)]
    lv = []
    for L in lines:
        for k in range(len(L) - 1):
            lv += [L[k], np.zeros(3), L[k + 1], np.zeros(3)]
    lbuf = ctx.buffer(np.array(lv, dtype="f4").tobytes())
    lvao = ctx.vertex_array(prog, [(lbuf, "3f 3f", "in_pos", "in_nrm")])
    fbo = ctx.framebuffer(color_attachments=[ctx.renderbuffer((W, H), 4, samples=4)],
                          depth_attachment=ctx.depth_renderbuffer((W, H), samples=4))
    res = ctx.framebuffer(color_attachments=[ctx.renderbuffer((W, H), 4)])
    views = (("leeward (belly side)", (0.25, 0.15, 1.0)), ("windward, ahead of the luff", (-0.8, 0.1, -0.6)),
             ("from the clew end", (1.0, 0.25, 0.15)))
    sheet = Image.new("RGB", (3 * W, H + 40), (246, 246, 243))
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), title, fill=(20, 20, 30), font=_font(20))
    for k, (name, eye) in enumerate(views):
        e = np.array(eye, dtype=np.float64)
        e = e / np.linalg.norm(e) * 3.0
        V = look_at(e, np.zeros(3), up=(0, 1, 0))
        Pm = ortho(-0.62, 0.62, -0.62, 0.62, 0.1, 10.0)
        fbo.use()
        ctx.enable(moderngl.DEPTH_TEST)
        ctx.clear(0.97, 0.97, 0.95, 1.0)
        prog["mvp"].write((Pm @ V).T.astype("f4").tobytes())
        prog["light"].value = tuple((np.array([0.3, 0.8, 0.5]) / np.linalg.norm([0.3, 0.8, 0.5])).tolist())
        prog["col"].value = (0.93, 0.62, 0.30)
        prog["eye"].value = tuple((e / np.linalg.norm(e)).tolist())
        prog["line"].value = 0
        vao.render(moderngl.TRIANGLES)
        prog["line"].value = 1
        ctx.line_width = 1.0
        lvao.render(moderngl.LINES)
        ctx.copy_framebuffer(res, fbo)
        img = Image.frombytes("RGBA", (W, H), res.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM).convert("RGB")
        sheet.paste(img, (k * W, 40))
        d.text((k * W + 10, 44), name, fill=(40, 40, 50), font=_font(16))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    return path


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(prog="python3 -m boatgen.kite_surface")
    sub = ap.add_subparsers(dest="cmd", required=True)
    a1 = sub.add_parser("ac33", help="write data/sails/ac33_asym.kite_shape.json from the IGES geometry")
    a1.add_argument("igs")
    a1.add_argument("--out", default=os.path.join(DATA_DIR, "ac33_asym.kite_shape.json"))
    a2 = sub.add_parser("render", help="draw every surface of the surface kite shape files alone")
    a2.add_argument("--out", default=os.path.normpath(os.path.join(DATA_DIR, "..", "..", "docs", "design",
                                                                   "kite_ac_2026-11-06")))
    a = ap.parse_args(argv)
    np.seterr(all="ignore")
    if a.cmd == "ac33":
        d = ac33_file(a.igs)
        with open(a.out, "w") as f:
            json.dump(d, f, separators=(",", ":"))
            f.write("\n")
        print(f"wrote {a.out}")
        return 0
    for fn in sorted(os.listdir(DATA_DIR)):
        if not fn.endswith(".kite_shape.json"):
            continue
        with open(os.path.join(DATA_DIR, fn)) as f:
            d = json.load(f)
        if not is_surface(d):
            continue
        name = fn[:-len(".kite_shape.json")]
        sh = validate(d, name)
        for k, spec in sh["surfaces"].items():
            M = surface_grid(spec)
            o = outline(M)
            cam = M[..., 2].max() / o["tack_clew"]
            title = (f"{name} / {k}: raw measured surface, no boat. leech/luff {o['leech'] / o['luff']:.2f}, "
                     f"foot/luff {o['foot'] / o['luff']:.2f}, depth/(tack-clew) {cam:.2f}")
            p = render_raw(M, os.path.join(a.out, f"raw_{name}_{k}.png"), title)
            print(f"wrote {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
