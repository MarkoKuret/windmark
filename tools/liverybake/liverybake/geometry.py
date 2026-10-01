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

import numpy as np

from .common import BOATGEN, CLASSES, HERE

CACHE = HERE / ".cache"
VERSION = 3


def _key(class_id):
    h = hashlib.sha256()
    h.update(str(VERSION).encode())
    h.update((CLASSES / f"{class_id}.boat.json").read_bytes())
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
    # the deck seen from above: triangles (x, y) by slot
    dk = boat.parts["deck"].merged()
    geo["deck_tris"] = {m: np.stack([g.P[:, 0], g.P[:, 1]], -1)[g.I] for m, g in dk.items()
                        if m in ("gelcoat", "nonslip")}
    geo["deck_min"] = np.vstack([g.P for g in dk.values()]).min(0).tolist()
    geo["deck_max"] = np.vstack([g.P for g in dk.values()]).max(0).tolist()
    # flat sails (x, z in the centreline plane): grid, type and corners
    geo["sails"] = []
    for spec in cls["sails"]:
        s = boat.sails[spec["id"]]
        geo["sails"].append({"id": spec["id"], "type": s.type, "P": np.asarray(s.P, dtype=np.float64),
                             "corners": {k: list(v) for k, v in s.corners.items()}})
    return geo


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
        "patch": (0.045 if kind == 2 else 0.06) * luff_len,
        "battens": 4 if kind == 0 else 0,
        "telltales": t in ("jib", "genoa"),
        "outline": np.vstack([plan[:, 0], plan[-1, 1:], plan[::-1, -1][1:], plan[0, ::-1][1:-1]]),
        "luff_line": plan[:, 0].copy(), "leech_line": plan[:, -1].copy(), "foot_line": plan[0, :].copy(),
        "head_line": plan[-1, :].copy(),
    }
