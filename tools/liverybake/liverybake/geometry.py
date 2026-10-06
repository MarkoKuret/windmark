"""The class geometry the textures are laid out on, from the boat generator (tools/boatgen): the hull skin and its
uv1 atlas, the generator's livery panels, the keel in side view, the deck seen from above and the flat sails with
their cloth plan (sail_visuals.md §11.1).

Building a boat takes about 15 s, so the few arrays the bake needs are cached per class file in
tools/liverybake/.cache (keyed by the class file and the generator sources).
"""
import hashlib
import json
import pickle
import sys
from pathlib import Path

import numpy as np

from .common import BOATGEN, CLASSES, HERE

CACHE = HERE / ".cache"
VERSION = 10


def _key(class_id):
    h = hashlib.sha256()
    h.update(str(VERSION).encode())
    h.update((CLASSES / f"{class_id}.boat.json").read_bytes())
    h.update(Path(__file__).read_bytes())
    for p in sorted((BOATGEN / "boatgen").glob("*.py")):
        h.update(p.read_bytes())
    return h.hexdigest()[:16]


def load(class_id, class_path=None):
    """The class geometry as a dict (see build()); cached."""
    path = class_path or CLASSES / f"{class_id}.boat.json"
    key = _key(class_id) if class_path is None else hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]
    f = CACHE / f"{class_id}-{key}.pkl"
    if f.exists():
        return pickle.loads(f.read_bytes())
    geo = build(path)
    CACHE.mkdir(exist_ok=True)
    for old in CACHE.glob(f"{class_id}-*.pkl"):
        old.unlink()
    f.write_bytes(pickle.dumps(geo))
    return geo


def build(path):
    if str(BOATGEN) not in sys.path:
        sys.path.insert(0, str(BOATGEN))
    np.seterr(all="ignore")
    from boatgen import classfile
    from boatgen.build import Boat
    cls = classfile.load(str(path))
    boat = Boat(cls, log=lambda *a: None)
    h = boat.hull
    app = boat.app
    geo = {
        "id": cls["id"],
        "loa": float(cls["hull"]["loa"]),
        "L": float(h.L),
        "origin_x": float(boat.origin_x()),
        "boot_top": [float(v) for v in cls["hull"]["boot_top"]],
        "freeboard": {"mid": float(h.zs(np.array([0.5 * h.L]))[0])},
        # hull skin: stations x from the transom, rows from the keel (j = 0) to the sheer; y >= 0 half-breadths
        "skin_xs": np.asarray(h.skin_xs, dtype=np.float64),
        "skin": np.asarray(h.skin_grid, dtype=np.float64),
        "girth": np.asarray(h.girth, dtype=np.float64),
        "girth_max": float(h.girth_max),
        "panels": json.loads(json.dumps(boat.livery_panels(), default=float)),
    }
    # keel in side view (body x, z), fin leading edge and bulb
    kp = boat.parts["keel"].merged()
    P = np.vstack([g.P for g in kp.values()])
    keel = {"min": P.min(0).tolist(), "max": P.max(0).tolist(),
            "le_root": app.fin_le_root.tolist(), "le_tip": app.fin_le_tip.tolist(),
            "cr": float(app.fin_cr), "ct": float(app.fin_ct), "bulb": None}
    if app.has_bulb:
        s = np.linspace(0, 1, 200)
        from boatgen.appendages import _bulb_profile
        prof = np.maximum(_bulb_profile(s), 0) * app.bulb_R
        keel["bulb"] = {"nose_x": float(app.bulb_nose_x), "len": float(app.bulb_len), "zc": float(app.bulb_zc),
                        "s": s.tolist(), "half_h": (prof / np.sqrt(app.bulb_flat)).tolist()}
    geo["keel"] = keel
    # the keel's mesh triangles in side view (x, z), for the coverage mask
    keel_tris = []
    for g in kp.values():
        keel_tris.append(np.stack([g.P[:, 0], g.P[:, 2]], -1)[g.I])
    geo["keel_tris"] = np.vstack(keel_tris)
    # the deck seen from above: triangles (x, y) by slot, its uv1 frame and what the deck bake lays out on it
    dk = boat.parts["deck"].merged()
    geo["deck_tris"] = {m: np.stack([g.P[:, 0], g.P[:, 1]], -1)[g.I] for m, g in dk.items()
                        if m in ("gelcoat", "nonslip", "glass")}
    geo["deck_min"] = np.vstack([g.P for g in dk.values()]).min(0).tolist()
    geo["deck_max"] = np.vstack([g.P for g in dk.values()]).max(0).tolist()
    geo["deck"] = deck_info(boat)
    geo["footprints"] = footprints(boat)
    geo["deck_plan"] = [float(v) for v in d_plan(boat)]
    geo["painted"] = painted(boat)
    geo["face"] = face_info(boat)
    geo["ao"] = ao_heights(boat, geo["deck"]["plan"])
    # the transom seen from astern: its uv1 frame, outline (y, z), top edge, name panel and the fittings on it
    d = boat.deck
    tr = boat.livery_transom()
    P = d.transom_outline(skin=(60, 40))
    geo["transom"] = {
        "rect": tr["rect"], "panel": tr["panel"], "outline": np.stack([P[:, 1], P[:, 2]], -1),
        "open": bool(d.open_transom), "yc": float(d.yc(0.0)) if d.open_transom else 0.0,
        "floor_z": float(d.floor_z(0.0)), "bs": float(h.bs(np.array([0.0]))[0]),
        "top_y": np.linspace(0.0, float(h.bs(np.array([0.0]))[0]), 64),
    }
    geo["transom"]["top_z"] = np.array([float(d.deck_z(0.0, y)) for y in geo["transom"]["top_y"]])
    geo["transom_fittings"] = transom_fittings(boat)
    # flat sails (x, z in the centreline plane): grid, type and corners
    geo["sails"] = []
    for spec in cls["sails"]:
        s = boat.sails[spec["id"]]
        geo["sails"].append({"id": spec["id"], "type": s.type, "P": np.asarray(s.P, dtype=np.float64),
                             "corners": {k: list(v) for k, v in s.corners.items()}})
    return geo


def d_plan(boat):
    return boat.deck.plan_rect()


# a line more than this above the walking surface under it is not painted (m): there the game model keeps it as
# geometry (boatgen hardware.ROPE_LIFT_MAX)
ROPE_LIFT_MAX = 0.035


def painted(boat):
    """The fittings the game paints into the deck maps instead of modelling them (boatgen Boat.painted_part):
    [{tag, slot, P (n, 3) boat frame, I (m, 3), N (n, 3), H (n,) height above the walking surface}] per tag and
    slot."""
    if not hasattr(boat, "painted_part"):
        return []
    d = boat.deck
    by = {}
    for slot, gs in boat.painted_part().slots.items():
        for g in gs:
            by.setdefault((g.tag or "", slot), []).append(g)
    out = []
    for (tag, slot), gs in sorted(by.items()):
        off, Ps, Is, Ns = 0, [], [], []
        for g in gs:
            Ps.append(g.P)
            Ns.append(g.N)
            Is.append(g.I + off)
            off += len(g.P)
        P = np.vstack(Ps).astype(np.float64)
        Hs = P[:, 2] - np.asarray(d.surface_z(P[:, 0], P[:, 1]), dtype=np.float64)
        I = np.vstack(Is).astype(np.int64)
        N = np.vstack(Ns).astype(np.float64)
        if slot.startswith("rope"):
            # a line is painted where it lies on the walking surface, and down the coachroof's aft face on the
            # face's own rectangle of the plan (boatgen Deck.face_frame); where it hangs in the air the game model
            # keeps it as geometry
            face = boat.line_on_face(P) if hasattr(boat, "line_on_face") else np.zeros(len(P), bool)
            on = I[(Hs[I] < ROPE_LIFT_MAX).all(1) & ~face[I].all(1)]
            if len(on):
                out.append({"tag": tag, "slot": slot, "P": P, "I": on, "N": N, "H": Hs, "rope": True})
            fi = I[face[I].all(1)]
            if len(fi):
                f = d.face_frame()
                xy = d.face_plan(P)
                out_d = f["x"] - P[:, 0]                       # out of the face, toward the cockpit
                Pf = np.stack([xy[:, 0], xy[:, 1], out_d], -1)
                Nf = np.stack([N[:, 1], N[:, 2], -N[:, 0]], -1)
                out.append({"tag": tag + "_face", "slot": slot, "P": Pf, "I": fi, "N": Nf, "H": out_d, "rope": True,
                            "zbuf": "own"})
            continue
        out.append({"tag": tag, "slot": slot, "P": P, "I": I, "N": N, "H": Hs})
    return out


# the ambient-occlusion height field: grid step (m), occluders counted up to this height above the walking surface
# and only from triangles wholly within reach of it (the boom, the vang rod and the upper rig cast nothing here) (m)
AO_STEP = 0.01
AO_CAP = 0.3
AO_REACH = 0.4


def ao_heights(boat, plan):
    from boatgen.mesh import Part
    """The top of everything on the deck, seen from above, for the atlas's baked occlusion and wear (atlas.py): {"Z"
    (H, W) the walking surface plus what stands on it (the deck mesh with its toe rail, coamings and hatches, the
    game model's hardware, the mast foot, the vang), capped at AO_CAP above the surface; "floor" (H, W) the cockpit
    floor; "wear" [(x, y)] traffic spots (winches, the mast foot); "plan", "step"}."""
    from . import painted as pt
    d = boat.deck
    x0, yt, w, h = plan
    W, H = int(round(w / AO_STEP)), int(round(h / AO_STEP))
    xs = x0 + (np.arange(W) + 0.5) * w / W
    ys = yt - (np.arange(H) + 0.5) * h / H
    X, Y = np.meshgrid(xs, ys)
    S = np.asarray(d.surface_z(X, Y), dtype=np.float64)
    pieces = []
    gp = boat.game_parts() if hasattr(boat, "game_parts") else {"body": Part()}
    wear = []
    for mat, gs in gp["body"].slots.items():
        part = mat.split(":")[0]
        if part not in ("deck", "hardware", "mast"):
            continue
        for g in gs:
            Hv = g.P[:, 2] - np.asarray(d.surface_z(g.P[:, 0], g.P[:, 1]), dtype=np.float64)
            I = g.I[Hv[g.I].max(1) < AO_REACH]
            if len(I):
                pieces.append({"slot": "x", "P": g.P, "I": I, "N": g.N, "H": Hv})
            if (g.tag or "").startswith("winch"):
                c = g.P.mean(0)
                wear.append((float(c[0]), float(c[1])))
    for gs in gp["boom"].slots.values():
        for g in gs:
            if (g.tag or "").startswith("vang"):
                Hv = g.P[:, 2] - np.asarray(d.surface_z(g.P[:, 0], g.P[:, 1]), dtype=np.float64)
                I = g.I[Hv[g.I].max(1) < AO_REACH]
                if len(I):
                    pieces.append({"slot": "x", "P": g.P, "I": I, "N": g.N, "H": Hv})
    sid, _, hgt, _ = pt.rasterize(pieces, plan, W, H, ss=1)
    Z = S + np.where(sid >= 0, np.clip(hgt, 0.0, AO_CAP), 0.0)
    wear.append((float(boat.rig.x_mast), 0.0))
    floor = np.asarray(d.surface_z(X, Y)) < np.asarray(d.deck_z(X, np.abs(Y))) - 0.08
    return {"Z": Z.astype(np.float32), "floor": floor, "wear": sorted(set(wear)), "plan": list(plan), "step": AO_STEP}


def face_info(boat):
    """The coachroof's aft face rectangle on the deck plan (boatgen Deck.face_frame): {"x0", "y_top", "w", "h"} in
    plan metres, or None."""
    d = boat.deck
    f = d.face_frame() if hasattr(d, "face_frame") else None
    if f is None:
        return None
    w = (f["y"][1] - f["y"][0]) * f["scale"]
    h = (f["z"][1] - f["z"][0]) * f["scale"]
    return {"x0": float(f["plan"][0]), "y_top": float(f["plan"][1]), "w": float(w), "h": float(h)}


# ----------------------------------------------------------------------------------------------------------------
# deck layout for the deck bake (boat frame: x from the transom, y to port)

def deck_info(boat):
    """The deck's plan rectangle (its uv1 frame) and, per 1 cm along the hull, the sheer half-breadth, the cockpit
    and cabin outlines; the cockpit, cabin, companionway, mast and toe rail."""
    d, h = boat.deck, boat.hull
    L = float(h.L)
    xs = np.linspace(0.0, L, int(round(L / 0.01)) + 1)
    yk = np.asarray(d.yk(xs), dtype=np.float64) if d.has_cabin else np.zeros_like(xs)
    # the coachroof's top: inside the edge radius, where it stands at least 2 cm proud (forward of that it fairs
    # into the deck and is laid out as deck)
    top = (np.asarray(d.cab_height(xs)) > 0.02) if d.has_cabin else np.zeros_like(xs, bool)
    yk_roof = np.where(top, np.asarray(d.yk_roof(xs), dtype=np.float64), 0.0) if d.has_cabin else np.zeros_like(xs)
    in_ck = (xs >= d.xc0) & (xs <= d.xc1)
    out = {
        "plan": list(d.plan_rect()), "xs": xs, "bs": np.asarray(h.bs(xs), dtype=np.float64),
        "yc": np.where(in_ck, np.asarray(d.yc(xs), dtype=np.float64), 0.0),
        "yk": np.where((xs >= d.xk0) & (xs <= d.xk1), yk, 0.0),
        "xc0": float(d.xc0), "xc1": float(d.xc1), "xk0": float(d.xk0), "xk1": float(d.xk1),
        "yk_roof": np.where((xs >= d.xk0) & (xs <= d.xk1), yk_roof, 0.0),
        "has_cabin": bool(d.has_cabin), "open_transom": bool(d.open_transom),
        "margin": float(d.margin), "toe_rail": float(d.cls["deck"]["toe_rail"]),
        "companion": getattr(d, "companion", None),
        "mast": {"x": float(boat.rig.x_mast), "chord": float(getattr(boat.rig, "chord", 0.12)),
                 "width": float(getattr(boat.rig, "width", 0.08))},
    }
    return out


# hardware tags that are not fastened to the deck (lines, coils, rails, cars) and kinds by tag prefix
_SKIP = ("halyard_", "mainsheet_tail", "mainsheet_coil", "mainsheet_lower", "traveller_line", "traveller_car",
         "lifeline", "jib_car", "halyard_coil", "wheel", "binnacle", "tiller")
_KINDS = (("winch", "winch"), ("clutch", "clutch"), ("organiser", "organiser"), ("mast_block", "block"),
          ("traveller_block", "block"), ("cam_cleat", "cleat"), ("traveller_cleat", "cleat"), ("horn_cleat", "cleat"),
          ("jib_track", "track"), ("traveller", "track"), ("hatch", "hatch"), ("stanchion", "stanchion"),
          ("pulpit_leg", "stanchion"), ("pushpit_leg", "stanchion"), ("chainplate", "chainplate"),
          ("mast", "mast"), ("pedestal", "pedestal"), ("rudder_bearing", "pedestal"), ("stemhead", "stemhead"),
          ("backstay", "chainplate"))


def _groups(boat, names=("hardware", "rigging", "mast")):
    by = {}
    for n in names:
        if n not in boat.parts:
            continue
        for gs in boat.parts[n].slots.values():
            for g in gs:
                if g.tag:
                    by.setdefault(g.tag, []).append(g.P)
    return {t: np.vstack(ps) for t, ps in by.items()}


def footprints(boat):
    """[{tag, kind, poly (n, 2) plan outline of the base, surface}] of every fitting fastened to the deck, cabin
    roof or cockpit sole: the convex hull of its points within 12 mm of its lowest point, when that point lies on
    the surface there (within 25 mm)."""
    from scipy.spatial import ConvexHull
    d = boat.deck
    out = []
    for tag, P in sorted(_groups(boat).items()):
        if tag.startswith(_SKIP) or (tag.startswith(("pulpit", "pushpit")) and "leg" not in tag):
            continue
        if P[:, 0].min() < 0.02:          # on the transom (transom_fittings)
            continue
        # the points within 12 mm of the surface under them (a long track on a sloping deck touches all along)
        low = P[P[:, 2] < P[:, 2].min() + 0.25]
        low = np.unique(np.round(low, 4), axis=0)
        if len(low) > 4000:
            low = low[np.random.default_rng(0).choice(len(low), 4000, replace=False)]
        gap = np.array([p[2] - d.surface(float(p[0]), float(p[1]))[0] for p in low])
        base = low[(gap < 0.012) & (gap > -0.03)]
        if len(base) < 3:
            continue
        c = base.mean(0)
        kind_s = d.surface(float(c[0]), float(c[1]))[2]
        q = np.unique(np.round(base[:, :2], 4), axis=0)
        if len(q) < 3:
            continue
        try:
            poly = q[ConvexHull(q).vertices]
        except Exception:  # noqa: BLE001 - collinear points
            continue
        kind = next((k for p, k in _KINDS if tag.startswith(p)), "fitting")
        out.append({"tag": tag, "kind": kind, "poly": poly, "surface": kind_s})
    return out


def transom_fittings(boat):
    """[{tag, poly (n, 2) outline (y, z)}] of the fittings bolted to the transom face (gudgeon plates)."""
    from scipy.spatial import ConvexHull
    out = []
    for tag, P in sorted(_groups(boat, ("hardware",)).items()):
        if not tag.startswith("gudgeon_plate"):
            continue
        base = P[P[:, 0] > -0.006][:, 1:3] if (P[:, 0] > -0.006).sum() >= 3 else P[:, 1:3]
        q = np.unique(np.round(base, 4), axis=0)
        if len(q) >= 3:
            out.append({"tag": tag, "poly": q[ConvexHull(q).vertices]})
    return out


# ----------------------------------------------------------------------------------------------------------------
# sail cloth plan (sail_visuals.md §11.1, BoatMaterials.cloth_params): uv0 of the generator and the flat plan

def sail_uv0(P):
    """The generator's metric uv0 of a flat grid P (rows from the foot, cols from the luff): distance along each row
    from the luff, height as the summed mean row spacing (boatgen/sails.py Sail.part)."""
    nv, nu = P.shape[:2]
    d = np.zeros((nv, nu))
    d[:, 1:] = np.cumsum(np.linalg.norm(np.diff(P, axis=1), axis=-1), axis=1)
    h = np.zeros((nv, nu))
    h[1:] = np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=-1).mean(1))[:, None]
    return np.stack([d, h], -1)


def sail_plan(sail, loa):
    """The cloth plan of a sail: shear (cos, sin of the luff-to-row angle), the plan of every grid point, the
    corners and the cloth constants of sail_visuals.md §11.1, exactly as the game computes them at load."""
    P = sail["P"]
    rows, cols = P.shape[:2]
    uv = sail_uv0(P)
    luff = P[-1, 0] - P[0, 0]
    luff /= np.linalg.norm(luff)
    cs = 0.0
    wsum = 0.0
    for i in range(rows - 1):
        r = P[i, -1] - P[i, 0]
        ln = np.linalg.norm(r)
        if ln < 0.2:
            continue
        cs += float(np.dot(luff, r / ln)) * ln
        wsum += ln
    cs = float(np.clip(cs / wsum if wsum > 0 else 0.0, -0.9, 0.9))
    sn = float(np.sqrt(1 - cs * cs))
    plan = np.stack([uv[..., 0] * sn, uv[..., 1] + uv[..., 0] * cs], -1)
    t = sail["type"]
    kind = 0 if t == "main" else (2 if t.startswith("spinnaker") else 1)
    style = 2 if kind == 2 else (1 if t == "code_zero" or loa >= 10.0 else 0)
    luff_len = float(uv[-1, 0, 1])
    head = plan[-1, 0]
    head_aft = plan[-1, -1]
    return {
        "rows": rows, "cols": cols, "uv0": uv, "plan": plan, "shear": (cs, sn),
        "tack": plan[0, 0].copy(), "clew": plan[0, -1].copy(), "head": head.copy(), "head_aft": head_aft.copy(),
        "square_top": bool(np.linalg.norm(head_aft - head) > 0.05),
        "kind": kind, "style": style, "type": t, "luff_len": luff_len,
        "panel": [0.9, 1.1, 0.9 + 0.03 * float(np.clip(loa - 7.0, 0.0, 10.0))][style],
        "patch": (0.03 if kind == 2 else 0.05) * luff_len,
        "battens": (5 if loa >= 10.0 else 4) if kind == 0 else 0,
        "battens_full": (3 if loa >= 10.0 else 2) if kind == 0 else 0,
        "telltales": t in ("jib", "genoa"),
        "outline": np.vstack([plan[:, 0], plan[-1, 1:], plan[::-1, -1][1:], plan[0, ::-1][1:-1]]),
        "luff_line": plan[:, 0].copy(), "leech_line": plan[:, -1].copy(), "foot_line": plan[0, :].copy(),
        "head_line": plan[-1, :].copy(),
    }
