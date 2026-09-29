"""Quick preview for shaping a code zero or spinnaker by hand (tools/boatgen/README.md, "Shaping a kite by hand").

    python3 -m boatgen.kite_preview ../../data/classes/wm7.boat.json [--sail kite] [--out DIR]

Rebuilds only the flying sails of the boat (the hull, deck, rig and hardware are cached per class and rebuilt only
when something else in the class file or the generator changes), prints each sail's rule measurements and clew
position, and writes one sheet per sail: the flat planform with its dimensions, and the sail set on a run (from
the leeward quarter) and on a reach (abeam, from leeward), rendered headless. The previous run's sheet row sits
below the new one, and its outline is drawn dashed on the new planform.
"""
import argparse
import copy
import datetime
import glob
import hashlib
import json
import os
import pickle
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import classfile
from .classfile import FLYING_TYPES, SHAPE_KEYS

HERE = os.path.dirname(os.path.abspath(__file__))

# the sets per flying-sail type and point of sail, drawn with the game's shape (sail_set.py, sail_visuals.md 6, 7):
# apparent wind angle (deg, wind from port), apparent wind (m/s), pole or tack line to windward (deg), and the sheet
# angles (deg) of the main and the flying sail: the core's optimum from the wm7 and wm12 tables at 10 kn TWS
SETS = {
    "spinnaker_asym": {"run": {"awa": -140, "aws": 4.0, "gamma": 20, "main": 59, "fly": 64},
                       "reach": {"awa": -80, "aws": 6.0, "gamma": 2, "main": 53, "fly": 32}},
    "spinnaker_sym": {"run": {"awa": -150, "aws": 4.0, "gamma": 30, "main": 59, "fly": 75},
                      "reach": {"awa": -100, "aws": 5.0, "gamma": 5, "main": 59, "fly": 50}},
    "code_zero": {"run": {"awa": -100, "aws": 5.0, "main": 59, "fly": 55},
                  "reach": {"awa": -70, "aws": 6.0, "main": 43, "fly": 50}},
}


def set_pose(sail_type, pt):
    """The pose of sail_set.set_sails for a flying sail of `sail_type` set on `pt` (run, reach)."""
    s = SETS[sail_type][pt]
    return {"awa": s["awa"], "aws": s["aws"], "gamma": s.get("gamma", 0.0),
            "sails": {"main": s["main"], sail_type: s["fly"]}}
HEEL = {"run": 5, "reach": 10}
VIEW = {"run": ("run, from the leeward quarter", -160, 10), "reach": ("reach, abeam from leeward", -90, 5)}


def _font(size):
    for f in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default(size)


# ---------------------------------------------------------------------------- cached boat


def _cache_key(raw):
    """Hash of everything but the flying sails' own settings, plus the generator source."""
    r = copy.deepcopy(raw)
    fly = set()
    for i, s in enumerate(r.get("sails", [])):
        if s.get("type") in FLYING_TYPES:
            fly.add(s.get("id"))
            r["sails"][i] = {"id": s.get("id"), "type": s["type"]}
    vs = (r.get("visual") or {}).get("sails") or {}
    for sid in fly:
        vs.pop(sid, None)
    h = hashlib.sha256(json.dumps(r, sort_keys=True).encode())
    for f in sorted(glob.glob(os.path.join(HERE, "*.py"))):
        with open(f, "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


def load_boat(cls, cache_dir, log=print):
    """The built boat with its flying sails drawn from `cls`: from the cache when only flying-sail settings
    changed since the last build of this class."""
    from .build import Boat
    os.makedirs(cache_dir, exist_ok=True)
    key = _cache_key(cls["raw"])
    path = os.path.join(cache_dir, f"{cls['id']}.{key}.pkl")
    if os.path.exists(path):
        with open(path, "rb") as f:
            boat = pickle.load(f)
        boat.log = log
        boat.rebuild_sails(cls)
        return boat, True
    for old in glob.glob(os.path.join(cache_dir, f"{cls['id']}.*.pkl")):
        os.remove(old)
    log(f"{cls['id']}: building the hull, deck and rig (cached for the next runs)")
    boat = Boat(cls, log=lambda *a: None)
    boat.log = None
    with open(path, "wb") as f:
        pickle.dump(boat, f)
    boat.log = log
    return boat, False


# ---------------------------------------------------------------------------- report


def report(boat, sid):
    """Printable lines and a summary dict for one flying sail."""
    s = boat.sails[sid]
    spec = next(sp for sp in boat.cls["sails"] if sp["id"] == sid)
    m, L = s.measure, boat.hull.L
    clew = s.P[0, -1]
    ra = m["rule_area"]
    class_area = np.floor(ra * 2) / 2
    info = {"luff": m["luff"], "leech": m["leech"], "foot": m["foot"], "mid_girth": m["mid_girth"],
            "mid_frac": m["mid_girth"] / m["foot"], "rule_area": ra, "class_area": spec["area"],
            "clew_x": float(clew[0]), "clew_z": float(clew[2]), "loa": L, "shape": s.shape}
    rounds = ", ".join(f"{e} {s.shape[e]['round'] * 100:.1f} % at {s.shape[e]['pos']:.2f}"
                       f"{' (solved)' if s.shape[e]['solved'] else ''}" for e in ("luff", "leech", "foot"))
    keys = {k: spec["shape"][k] for k in SHAPE_KEYS if k in spec["shape"]}
    lines = [
        f"{boat.cls['id']} {sid} ({s.type}): rule area {ra:.2f} m2, class area {spec['area']:.1f} m2"
        + ("" if spec["area"] == class_area else f" (would be {class_area:.1f}: the rule area rounded down to 0.5)"),
        f"  luff {m['luff']:.2f}, leech {m['leech']:.2f}, foot {m['foot']:.2f}, mid girth {m['mid_girth']:.2f} m "
        f"({info['mid_frac']:.3f} of the foot)",
        f"  edge round (depth of the edge, where deepest): {rounds}",
        f"  clew {clew[0]:.2f} m forward of the transom ({clew[0] / L:.2f} LOA), {clew[2]:.2f} m above the DWL",
        f"  shaping keys set: {json.dumps(keys) if keys else 'none (standard proportions)'}",
    ]
    return lines, info


# ---------------------------------------------------------------------------- planform drawing


def _outline(P):
    """Boundary of the flat grid, x-z: foot (tack to clew), leech (clew to head), luff (head to tack)."""
    b = np.vstack([P[0, :], P[1:, -1], P[::-1, 0][1:]])
    return b[:, [0, 2]]


def _hull_profile(boat, n=60):
    P = np.vstack([g.P for g in boat.skin])
    L = boat.hull.L
    xs = np.linspace(0, L, n + 1)
    top, bot = [], []
    for a, b in zip(xs[:-1], xs[1:]):
        sel = P[(P[:, 0] >= a) & (P[:, 0] <= b)]
        if len(sel):
            x = 0.5 * (a + b)
            top.append((x, sel[:, 2].max()))
            bot.append((x, sel[:, 2].min()))
    return np.array([(0.0, top[0][1])] + top + [(L, top[-1][1])]), np.array([(0.0, bot[0][1])] + bot + [(L, top[-1][1])])


def _dashed(d, pts, fill, width=2, dash=10):
    pts = np.asarray(pts, dtype=float)
    for a, b in zip(pts[:-1], pts[1:]):
        seg = np.linalg.norm(b - a)
        k = max(int(seg / dash), 1)
        for i in range(0, k, 2):
            p0, p1 = a + (b - a) * i / k, a + (b - a) * min(i + 1, k) / k
            d.line([tuple(p0), tuple(p1)], fill=fill, width=width)


def _edge_mid(C):
    s = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=-1))]
    return np.array([np.interp(0.5 * s[-1], s, C[:, k]) for k in range(C.shape[1])])


def draw_planform(boat, sid, info, size, prev=None):
    W, H = size
    s = boat.sails[sid]
    P = s.P
    rig = boat.rig
    top, bot = _hull_profile(boat)
    ol = _outline(P)
    pts = [ol, top, bot, np.array([[rig.sprit_end[0], rig.sprit_end[2]], [rig.x_mast, rig.z_top]])]
    if prev is not None:
        pts.append(np.array(prev["outline"]))
    allp = np.vstack(pts)
    lo, hi = allp.min(0), allp.max(0)
    pad_l, pad_r, pad_t, pad_b = 60, 60, 150, 40
    sc = min((W - pad_l - pad_r) / (hi[0] - lo[0]), (H - pad_t - pad_b) / (hi[1] - lo[1]))
    ox = pad_l + 0.5 * (W - pad_l - pad_r - sc * (hi[0] - lo[0]))

    def T(p):
        p = np.asarray(p, dtype=float)
        return np.stack([ox + (p[..., 0] - lo[0]) * sc, H - pad_b - (p[..., 1] - lo[1]) * sc], -1)

    img = Image.new("RGB", (W, H), (250, 250, 247))
    d = ImageDraw.Draw(img)
    f, fs, fb = _font(19), _font(16), _font(22)
    ink, grey, blue, red, sailc = (25, 25, 30), (150, 150, 150), (70, 120, 190), (200, 60, 40), (225, 232, 245)
    # DWL, hull, mast, sprit
    d.line([tuple(T((lo[0], 0.0))), tuple(T((hi[0], 0.0)))], fill=(160, 190, 225), width=2)
    hull = np.vstack([top, bot[::-1]])
    d.polygon([tuple(p) for p in T(hull)], fill=(232, 232, 228), outline=(110, 110, 110))
    d.line([tuple(T((rig.x_mast, rig.z_step))), tuple(T((rig.x_mast, rig.z_top)))], fill=(90, 90, 90), width=4)
    bow = (boat.hull.L, float(top[-1][1]))
    d.line([tuple(T(bow)), tuple(T((rig.sprit_end[0], rig.sprit_end[2])))], fill=(90, 90, 90), width=3)
    tr = T((0.0, float(top[0][1])))
    d.line([tuple(tr), (tr[0], tr[1] - 30)], fill=ink, width=2)
    d.text((tr[0] + 4, tr[1] - 48), "transom", fill=ink, font=fs)
    # sail
    d.polygon([tuple(p) for p in T(ol)], fill=sailc)
    if prev is not None:
        _dashed(d, T(np.array(prev["outline"])), grey, 2)
    d.line([tuple(p) for p in T(np.vstack([ol, ol[:1]]))], fill=ink, width=3)
    tk, ck, hd = P[0, 0][[0, 2]], P[0, -1][[0, 2]], P[-1, 0][[0, 2]]
    for a, b in ((tk, ck), (ck, hd), (tk, hd)):         # straight edges: the round is the gap to these
        _dashed(d, T(np.array([a, b])), (170, 170, 190), 1, 6)
    ml, me = _edge_mid(P[:, 0][:, [0, 2]]), _edge_mid(P[:, -1][:, [0, 2]])
    _dashed(d, T(np.array([ml, me])), red, 2, 8)
    cm = T(0.5 * (ml + me))
    d.text((cm[0], cm[1] - 8), f"mid girth {info['mid_girth']:.2f} m ({info['mid_frac']:.2f} SF)", fill=red,
           font=fs, anchor="ms")
    sh = info["shape"]

    def edge_label(C, name, length, outward):
        mid = _edge_mid(C)
        q = T(mid) + outward
        txt = f"{name} {length:.2f} m\nround {sh[name]['round'] * 100:.1f} % at {sh[name]['pos']:.2f}"
        txt += " (solved)" if sh[name]["solved"] else ""
        bb = d.multiline_textbbox((0, 0), txt, font=fs)
        x = q[0] - (bb[2] if outward[0] < 0 else 0 if outward[0] > 0 else bb[2] / 2)
        d.multiline_text((x, q[1] - bb[3] / 2), txt, fill=ink, font=fs)
    edge_label(P[:, 0][:, [0, 2]], "luff", info["luff"], np.array([18, 0]))
    edge_label(P[:, -1][:, [0, 2]], "leech", info["leech"], np.array([-18, 0]))
    edge_label(P[0, :][:, [0, 2]], "foot", info["foot"], np.array([0, 30]))
    c = T(ck)
    d.ellipse([c[0] - 6, c[1] - 6, c[0] + 6, c[1] + 6], fill=red)
    d.text((c[0] - 10, c[1] - 30), f"clew {info['clew_x']:.2f} m fwd of transom ({info['clew_x'] / info['loa']:.2f} LOA)",
           fill=red, font=fs, anchor="rs")
    # header
    d.text((16, 12), f"{boat.cls['id']} {sid}: flat planform", fill=ink, font=fb)
    d.text((16, 44), f"rule area {info['rule_area']:.2f} m2 (class {info['class_area']:.1f})", fill=ink, font=f)
    if prev is not None:
        pa = prev["info"]
        d.text((16, 72), f"previous (dashed): rule area {pa['rule_area']:.2f} m2, foot {pa['foot']:.2f}, "
                         f"mid girth {pa['mid_girth']:.2f} m; change {info['rule_area'] - pa['rule_area']:+.2f} m2",
               fill=(110, 110, 110), font=fs)
    return img


# ---------------------------------------------------------------------------- set sail renders


def render_sets(boat, sid, out_dir, size, renderer):
    from .previews import heel_matrix
    from .render import orbit
    s = boat.sails[sid]
    top, L = boat.rig.z_top, boat.hull.L
    drop = tuple("sail_" + k for k, o in boat.sails.items() if k != sid and o.type != "main")
    bat = tuple("sail_" + k for k, o in boat.sails.items() if o.type == "main")
    imgs = {}
    for pt in ("run", "reach"):
        pose = set_pose(s.type, pt)
        glb = os.path.join(out_dir, f"{boat.cls['id']}_{sid}_{pt}.glb")
        boat.write_posed_glb(glb, pose, name=f"{sid}_{pt}", drop=drop)
        renderer.load(glb, transform=heel_matrix(HEEL[pt]), battened=bat)
        title, az, el = VIEW[pt]
        t = np.array([-0.12 * top, 0.44 * top, 0.08 * L])
        png = os.path.join(out_dir, f"_{pt}.png")
        renderer.render(png, eye=orbit(t, 1.95 * top, az, el), target=t, fov=40)
        im = Image.open(png).convert("RGB")
        os.remove(png)
        os.remove(glb)
        ImageDraw.Draw(im).text((16, 12), f"{sid} set on a {title}", fill=(20, 20, 30), font=_font(22))
        imgs[pt] = im
    return imgs


# ---------------------------------------------------------------------------- command line


def main(argv=None):
    ap = argparse.ArgumentParser(prog="boatgen.kite_preview",
                                 description="Preview the code zeros and spinnakers of a boat class after a hand edit")
    ap.add_argument("classfile", help="boat-class file (windmark.boatclass/1)")
    ap.add_argument("--sail", action="append", help="sail id (repeatable; default: every code zero and spinnaker)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(HERE), "out", "kite"), help="output directory")
    ap.add_argument("--size", default="900x720", help="size of each panel, WxH")
    ap.add_argument("--no-render", action="store_true", help="print the measurements only")
    a = ap.parse_args(argv)
    np.seterr(all="ignore")
    t0 = time.time()
    try:
        cls = classfile.load(a.classfile)
    except classfile.ClassFileError as e:
        print(f"{a.classfile}: {e}", file=sys.stderr)
        return 2
    flying = [s["id"] for s in cls["sails"] if s["type"] in FLYING_TYPES]
    sids = a.sail or flying
    for sid in sids:
        if sid not in flying:
            print(f"{a.classfile}: no code zero or spinnaker with id {sid!r} (have: {', '.join(flying) or 'none'})",
                  file=sys.stderr)
            return 2
    os.makedirs(a.out, exist_ok=True)
    try:
        boat, cached = load_boat(cls, os.path.join(a.out, ".cache"))
    except ValueError as e:
        print(f"{a.classfile}: {e}", file=sys.stderr)
        return 2
    size = tuple(int(v) for v in a.size.split("x"))
    renderer = None
    if not a.no_render:
        from .render import Renderer
        renderer = Renderer(*size, samples=4)
    for sid in sids:
        lines, info = report(boat, sid)
        print("\n".join(lines))
        if a.no_render:
            continue
        stem = os.path.join(a.out, f"{cls['id']}_{sid}")
        prev = None
        if os.path.exists(stem + ".last.json") and os.path.exists(stem + ".last.png"):
            with open(stem + ".last.json") as f:
                prev = json.load(f)
        plan = draw_planform(boat, sid, info, size, prev)
        sets = render_sets(boat, sid, a.out, size, renderer)
        row = Image.new("RGB", (3 * size[0], size[1]), (255, 255, 255))
        for i, im in enumerate((plan, sets["run"], sets["reach"])):
            row.paste(im, (i * size[0], 0))
        sheet = row
        if prev is not None:
            old = Image.open(stem + ".last.png").convert("RGB")
            band = 40
            sheet = Image.new("RGB", (row.width, row.height + band + old.height), (60, 60, 66))
            sheet.paste(row, (0, 0))
            ImageDraw.Draw(sheet).text((16, row.height + 8), f"previous run ({prev['time']}), below",
                                       fill=(235, 235, 235), font=_font(22))
            sheet.paste(old, (0, row.height + band))
        sheet.save(stem + ".png")
        row.save(stem + ".last.png")
        with open(stem + ".last.json", "w") as f:
            json.dump({"time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                       "outline": _outline(boat.sails[sid].P).round(4).tolist(),
                       "info": {k: v for k, v in info.items() if k != "shape"}}, f)
        print(f"  preview: {stem}.png")
    print(f"done in {time.time() - t0:.1f} s{' (hull, deck and rig from the cache)' if cached else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
