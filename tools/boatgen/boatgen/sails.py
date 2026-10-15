"""Sails as flat two-layer grids in their standard hoisted position.

Each sail is a Coons patch over its four edges (foot, leech, head, luff), sampled on a regular (chord x height)
grid so the simulation can deform it at run time; corner indices and grid size go into the physics sidecar.
Mainsail roach and headsail leech round are sized so the flat outline area matches the class area; code zeros and
spinnakers are drawn from the rig with standard proportions (docs/specs/data_format.md 3.5) and report their rule
area instead.

Two layers: the port-facing layer sits 1 mm to port, the starboard one 1 mm to starboard, each with its own
outward normal. uv0 is metric (chord metres, height metres) for tiling cloth; uv1 is (chord fraction, 1 - height
fraction) with the starboard layer mirrored in u, so decals read correctly from both sides.

The preview poses set the sails with the game's shape and placement (sail_set.py).
"""
import numpy as np

from .classfile import LOOK_KEYS, ROUND_RANGE
from .mesh import Geom, Part, grid, normalize


def coons(foot, leech, head, luff, nu, nv):
    """foot(u), head(u) run luff->leech; luff(v), leech(v) run foot->head. Returns (nv, nu, 3)."""
    u = np.linspace(0, 1, nu)
    v = np.linspace(0, 1, nv)
    F, Hd = foot(u), head(u)                       # (nu, 3)
    Lf, Le = luff(v), leech(v)                     # (nv, 3)
    P00, P10, P01, P11 = F[0], F[-1], Hd[0], Hd[-1]
    U, V = u[None, :, None], v[:, None, None]
    P = ((1 - V) * F[None] + V * Hd[None] + (1 - U) * Lf[:, None] + U * Le[:, None]
         - ((1 - U) * (1 - V) * P00 + U * (1 - V) * P10 + (1 - U) * V * P01 + U * V * P11))
    return P


def _line(a, b):
    a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    return lambda t: a[None] + np.asarray(t)[:, None] * (b - a)[None]


def _curve(a, b, bulge, power=1.0, peak=0.5):
    """Edge from a to b bowed sideways in the x-z plane by `bulge` metres, along n = d rotated -90 degrees
    about +y: an upward edge bows forward, an aft-running edge bows up; negative bulges the other way."""
    a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    d = b - a
    n = normalize(np.array([d[2], 0.0, -d[0]]))

    def f(t):
        t = np.asarray(t)
        # asymmetric bump with its maximum at `peak`
        s = np.where(t < peak, t / peak, (1 - t) / (1 - peak))
        shape = np.sin(0.5 * np.pi * np.clip(s, 0, 1)) ** power
        return a[None] + t[:, None] * d[None] + (bulge * shape)[:, None] * n[None]
    return f


def poly_area(P):
    """Area of a flat grid outline in the x-z plane (shoelace over the boundary)."""
    b = np.vstack([P[0, :], P[1:, -1], P[-1, ::-1][1:], P[::-1, 0][1:]])
    x, z = b[:, 0], b[:, 2]
    return 0.5 * abs(np.sum(x * np.roll(z, -1) - np.roll(x, -1) * z))


# look defaults per sail type (docs/specs/sail_visuals.md 4); flutter_rate, flutter_rate_max and furl_radius
# follow the size rules in Sail.look()
LOOK_DEFAULTS = {
    "main": {"fill_gain": 0.6, "fill_curve": 4.0, "flutter_amp": 0.15, "twist_top": 0.070},
    "jib": {"fill_gain": 0.75, "fill_curve": 1.2, "flutter_amp": 0.07, "twist_top": 0.175},
    "genoa": {"fill_gain": 0.75, "fill_curve": 1.2, "flutter_amp": 0.07, "twist_top": 0.175},
    "code_zero": {"fill_gain": 0.7, "fill_curve": 1.3, "flutter_amp": 0.08, "twist_top": 0.140, "camber": 0.12},
    "spinnaker_asym": {"fill_gain": 1.0, "fill_curve": 1.0, "flutter_amp": 1.0, "twist_top": 0.45, "camber": 0.27,
                       "tack_line_max": 0.0},
    "spinnaker_sym": {"fill_gain": 1.5, "fill_curve": 1.5, "flutter_amp": 1.0, "twist_top": 0.0, "camber": 0.26},
}


class Sail:
    def __init__(self, name, P, corners):
        self.name, self.P, self.corners = name, P, corners  # P: (nv, nu, 3) in the centreline plane
        self.look_override = {}
        self.measure = None        # flying sails: rule measurements (flying_measure)
        self.shape = None          # flying sails: edge rounds as drawn (_flying)

    @property
    def area(self):
        return poly_area(self.P)

    def centroid(self):
        # area-weighted centre of the grid cells
        P = self.P
        c = 0.25 * (P[:-1, :-1] + P[1:, :-1] + P[:-1, 1:] + P[1:, 1:])
        a = np.linalg.norm(np.cross(P[1:, 1:] - P[:-1, :-1], P[:-1, 1:] - P[1:, :-1]), axis=-1) * 0.5
        return (c * a[..., None]).sum((0, 1)) / a.sum()

    def chord_extent(self):
        """Sa of docs/specs/sail_visuals.md 3.2: extent of the flat sail perpendicular to its luff line (tack to
        head), in the sail plane."""
        P = self.P
        T = P[0, 0]
        Lh = normalize(P[-1, 0] - T)
        Ah = np.cross(Lh, np.array([0.0, 1.0, 0.0]))
        a = (P - T) @ Ah
        return float(a.max() - a.min())

    def look(self, loa):
        """The sidecar `look` block (sail_visuals.md 4): the class file's visual.sails.<id>.look, with every
        missing key filled from the defaults of the sail's type and the size rules. An old `depth` key is dropped
        (sail_visuals.md 4: `camber` replaced it)."""
        d = dict(LOOK_DEFAULTS[self.type])
        d["flutter_rate"] = 0.6 + 2.4 * min(max((12.0 - loa) / 5.0, 0.0), 1.0)
        d["flutter_rate_max"] = 9.0 + min(max((loa - 7.0) / 5.0, 0.0), 1.0)
        if self.type in ("jib", "genoa", "code_zero"):
            d["furl_radius"] = 0.02 + 0.006 * self.chord_extent()
        d = {k: round(float(v), 6) for k, v in d.items()}
        d.update({k: v for k, v in self.look_override.items() if k != "depth"})
        return {k: d[k] for k in LOOK_KEYS if k in d}

    def part(self, P=None, gap=0.001):
        P = self.P if P is None else P
        nv, nu = P.shape[:2]
        # metric uv: distance along each row from the luff, height above the tack
        d = np.zeros((nv, nu))
        d[:, 1:] = np.cumsum(np.linalg.norm(np.diff(P, axis=1), axis=-1), axis=1)
        h = np.zeros((nv, nu))
        h[1:] = np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=-1).mean(1))[:, None]
        uv0 = np.stack([d, h], -1)
        u = np.broadcast_to(np.linspace(0, 1, nu)[None], (nv, nu))
        v = np.broadcast_to(np.linspace(0, 1, nv)[:, None], (nv, nu))
        # row-major grid: vertex (row i from the foot, col j from the luff) has index i * cols + j
        # Full topology: two triangles per cell per layer, zero-area ones at a collapsed head included, so every
        # grid vertex is referenced and survives an engine's re-indexing (docs/specs/sail_visuals.md 3.1).
        g0 = grid(P, uv0, np.stack([u, 1 - v], -1), keep_degenerate=True)
        # layer normals: the surface normal and its opposite, each layer offset along its own normal
        N = _fill_normals(g0.N.reshape(nv, nu, 3)).reshape(-1, 3)
        port_sign = 1.0 if np.mean(N[:, 1]) >= 0 else -1.0
        Np = N * port_sign
        pa = Geom(g0.P + Np * gap, g0.I if port_sign > 0 else g0.I[:, ::-1], Np, g0.uv0, g0.uv1)
        uv1s = g0.uv1.copy()
        uv1s[:, 0] = 1 - uv1s[:, 0]
        sb = Geom(g0.P - Np * gap, g0.I[:, ::-1] if port_sign > 0 else g0.I, -Np, g0.uv0, uv1s)
        part = Part()
        part.add("sailcloth", pa)
        part.add("sailcloth", sb)
        return part


def _fill_normals(N):
    """Grid normals (rows, cols, 3) with every zero normal (a collapsed head vertex that no triangle with area
    touches) replaced by the one below it in its column, rows from the foot up (sail_visuals.md 9)."""
    N = N.copy()
    ok = np.linalg.norm(N, axis=-1) > 0.5
    for i in range(len(N)):
        for j in np.nonzero(~ok[i])[0]:
            if i > 0:
                N[i, j] = N[i - 1, j]
            else:
                good = N[ok]
                N[i, j] = normalize(good.mean(0)) if len(good) else (0.0, 1.0, 0.0)
    return N


def _solve_bulge(make, target, lo, hi, iters=30):
    for _ in range(iters):
        mid = 0.5 * (lo + hi)
        if poly_area(make(mid)) < target:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def build_sails(cls, rig, deck):
    """One Sail per class sail entry, keyed by sail id."""
    out = {}
    for spec in cls["sails"]:
        t = spec["type"]
        if t == "main":
            sail = _main(spec, rig)
        elif t in ("jib", "genoa"):
            sail = _headsail(spec, cls, rig, deck)
        else:
            sail = _flying(spec, cls, rig, deck)
        sail.type = t
        sail.look_override = dict(spec["visual"].get("look") or {})
        out[spec["id"]] = sail
    return out


def _main(spec, rig):
    v = spec["visual"]
    tack = np.array([rig.x_mast_aft - 0.01, 0, rig.z_boom + 0.07])
    head = np.array([rig.x_mast_aft - 0.01, 0, rig.z_head])
    if spec.get("luff"):
        head[2] = min(tack[2] + float(spec["luff"]), rig.z_top - 0.08)
    clew = np.array([rig.x_mast_aft - rig.E, 0, rig.z_boom + 0.09])
    head_aft = head + [-float(v.get("head_width", 0.28)) * rig.E, 0, -0.03]
    nu, nv = 14, 26

    def make(roach):
        return coons(_line(tack, clew), _curve(clew, head_aft, -roach, 0.9, 0.55), _line(head, head_aft),
                     _line(tack, head), nu, nv)
    roach = _solve_bulge(make, spec["area"], 0.0, 0.3 * rig.E)
    return Sail(spec["id"], make(roach), {"tack": (0, 0), "clew": (0, nu - 1), "head": (nv - 1, 0),
                                          "head_aft": (nv - 1, nu - 1)})


def _headsail(spec, cls, rig, deck):
    """Jib or genoa hanked on the forestay; the clew placed so the area comes out at the class value."""
    v = spec["visual"]
    L = cls["hull"]["loa"]
    ts = np.array([rig.x_tack, 0, rig.z_tack])
    if spec.get("tack_x") is not None:
        ts = np.array([spec["tack_x"], 0, float(deck.surface(spec["tack_x"], 0.0)[0]) + 0.04])
    hs = np.array([rig.x_mast + rig.chord / 2, 0, rig.z_hounds])
    d = normalize(hs - ts)
    jt = ts + d * 0.12
    luff = float(spec["luff"]) if spec.get("luff") else np.linalg.norm(hs - ts) * float(v.get("luff_frac", 0.96)) - 0.12
    jh = jt + d * luff
    lp = 2 * spec["area"] / luff / 1.04       # leech slightly rounded
    n_aft = np.array([d[2], 0, -d[0]])
    if n_aft[0] > 0:
        n_aft = -n_aft
    clew_h = float(v.get("clew_height", (0.35 if spec["type"] == "jib" else 0.25) * (L / 12) ** 0.5))
    x_guess = rig.x_tack - cls["rig"]["J"]
    z_c = float(deck.deck_z(x_guess, 0.0)) + clew_h
    sj = (z_c - jt[2] - lp * n_aft[2]) / d[2]
    jc = jt + sj * d + lp * n_aft
    nu, nv = 12, 22

    def make(b):
        return coons(_curve(jt, jc, -0.02 * lp), _curve(jc, jh, -b, 1.0, 0.45), _line(jh, jh), _line(jt, jh), nu, nv)
    b = _solve_bulge(make, spec["area"], -0.02 * luff, 0.08 * luff)
    return Sail(spec["id"], make(b), {"tack": (0, 0), "clew": (0, nu - 1), "head": (nv - 1, 0)})


# flying-sail planform (docs/specs/data_format.md 3.5): leech / luff, foot / luff, mid girth / foot, then the
# drawing: foot round (fraction of the foot), the luff's share of the edge round, clew grid (cols, rows)
FLYING = {
    "spinnaker_asym": {"leech": 0.82, "foot": 0.57, "mid": 0.95, "foot_round": 0.08, "luff_share": 0.45, "grid": (16, 26),
                       "round_pos": 0.55},
    "spinnaker_sym": {"leech": 1.00, "foot": None, "mid": 0.95, "foot_round": 0.10, "luff_share": 0.50, "grid": (16, 26)},
    "code_zero": {"leech": 0.90, "foot": 0.46, "mid": 0.56, "foot_round": 0.02, "luff_share": 0.20, "grid": (12, 24)},
}
ROUND_POS = {"luff": 0.45, "leech": 0.45, "foot": 0.5}    # where each edge round is deepest, from its lower corner
SYM_FOOT_POLE = 1.75      # symmetric spinnaker foot / pole length
SYM_FOOT_MAX = 0.60       # ... at most this share of the luff


def _edge_len(C):
    return float(np.sum(np.linalg.norm(np.diff(C, axis=0), axis=-1)))


def _edge_mid(C):
    """Point half way along a polyline edge."""
    s = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=-1))]
    return np.array([np.interp(0.5 * s[-1], s, C[:, k]) for k in range(3)])


def flying_measure(P):
    """Rule measurements of a flat code zero or spinnaker grid: luff, leech and foot along the edges, mid girth
    between the mid points of the luff and leech edges, and the rule area (SLU + SLE) / 2 * (SF + 4 SHW) / 6."""
    luff, leech, foot = _edge_len(P[:, 0]), _edge_len(P[:, -1]), _edge_len(P[0, :])
    mid = float(np.linalg.norm(_edge_mid(P[:, 0]) - _edge_mid(P[:, -1])))
    return {"luff": luff, "leech": leech, "foot": foot, "mid_girth": mid,
            "rule_area": 0.5 * (luff + leech) * (foot + 4 * mid) / 6}


def _flying(spec, cls, rig, deck):
    """Code zero and spinnakers, flat in the centreline plane: tacked at the sprit end (asymmetric, code zero) or
    at the pole end (symmetric, or asymmetric on a class with a pole and no sprit), hoisted to the masthead. The
    planform follows the standard proportions of docs/specs/data_format.md 3.5 from the rig; the class area is
    not imposed (it should be the rule area this gives, which the sidecar reports)."""
    t = spec["type"]
    if t.startswith("spinnaker") and rig.pole_flown:
        tk = rig.pole_end.copy()
    elif rig.sprit > 0:
        tk = rig.sprit_end.copy()            # on the tack fitting at the sprit end
    else:
        tk = np.array([rig.x_tack, 0, rig.z_tack + 0.1])
    if spec.get("tack_x") is not None:
        tk[0] = spec["tack_x"]
    pf = FLYING[t]
    nu, nv = pf["grid"]
    hd = np.array([rig.x_mast + rig.chord / 2 + 0.02, 0, rig.z_top - 0.12])
    if spec.get("luff"):
        hd = tk + normalize(hd - tk) * float(spec["luff"])
    dl = hd - tk
    luff = float(np.linalg.norm(dl))
    dd = dl / luff
    n_aft = np.array([dd[2], 0, -dd[0]])
    if n_aft[0] > 0:
        n_aft = -n_aft
    if pf["foot"] is None:
        foot = min(SYM_FOOT_POLE * rig.pole_len, SYM_FOOT_MAX * luff) if rig.pole_len > 0 else SYM_FOOT_MAX * luff
    else:
        foot = pf["foot"] * luff
    foot = float(spec.get("foot") or foot)
    leech = float(spec.get("leech") or pf["leech"] * luff)
    # clew: foot from the tack, leech from the head, aft of the luff line
    a = (foot * foot - leech * leech + luff * luff) / (2 * luff)
    if foot * foot - a * a <= 0:
        raise ValueError(f"sail {spec['id']}: luff {luff:.2f}, leech {leech:.2f} and foot {foot:.2f} make no triangle")
    ck = tk + a * dd + np.sqrt(foot * foot - a * a) * n_aft
    lengths = {"luff": luff, "leech": leech, "foot": foot}     # straight edges
    sh = spec.get("shape") or {}
    rp = dict(ROUND_POS, luff=pf.get("round_pos", ROUND_POS["luff"]), leech=pf.get("round_pos", ROUND_POS["leech"]))
    pos = {e: sh.get(e + "_round_pos", rp[e]) for e in lengths}
    foot_b = sh.get("foot_round", pf["foot_round"]) * foot
    share = pf["luff_share"]

    def outline(bl, be):
        # bl, be: luff and leech round in metres (outward); the foot round is fixed
        return coons(_curve(tk, ck, -foot_b, 1.0, pos["foot"]), _curve(ck, hd, -be, 1.0, pos["leech"]),
                     _line(hd, hd), _curve(tk, hd, bl, 1.0, pos["luff"]), nu, nv)
    fixed = {e: sh[e + "_round"] * lengths[e] for e in ("luff", "leech") if e + "_round" in sh}
    if len(fixed) == 2:
        bl, be = fixed["luff"], fixed["leech"]
        solved = ()
    else:
        if "luff" in fixed:
            split, solved = (lambda r: (fixed["luff"], r)), ("leech",)
        elif "leech" in fixed:
            split, solved = (lambda r: (r, fixed["leech"])), ("luff",)
        else:
            # r: extra mid girth over the straight triangle's foot / 2, split between luff and leech round
            split, solved = (lambda r: (share * r, (1 - share) * r)), ("luff", "leech")
        sf = flying_measure(outline(*split(0.0)))["foot"]      # SF along the rounded foot
        if "mid_girth" in sh:
            target = sh["mid_girth"]
        else:
            target = sh.get("mid_girth_frac", pf["mid"]) * sf
        lo, hi = 0.0, 1.5 * foot
        if flying_measure(outline(*split(0.0)))["mid_girth"] > target:
            lo = -0.5 * foot        # narrower than the straight triangle: hollow edges
        for _ in range(40):
            r = 0.5 * (lo + hi)
            if flying_measure(outline(*split(r)))["mid_girth"] < target:
                lo = r
            else:
                hi = r
        bl, be = split(0.5 * (lo + hi))
    P = outline(bl, be)
    rounds = {"luff": bl / luff, "leech": be / leech, "foot": foot_b / foot}
    where = f"sail {spec['id']}"
    if solved:
        got = flying_measure(P)["mid_girth"]
        bad = [e for e in solved if not ROUND_RANGE[0] <= rounds[e] <= ROUND_RANGE[1]]
        if abs(got - target) > 0.005 or bad:
            raise ValueError(f"{where}: mid girth {target:.2f} m is out of reach: it needs a "
                             + ", ".join(f"{e} round of {rounds[e]:.3f}" for e in solved)
                             + f" (allowed {ROUND_RANGE[0]} to {ROUND_RANGE[1]} of the edge)")
    sail = Sail(spec["id"], P, {"tack": (0, 0), "clew": (0, nu - 1), "head": (nv - 1, 0)})
    sail.measure = flying_measure(sail.P)
    # the shape as drawn: round depth (fraction of the straight edge), its position, and whether it was solved
    sail.shape = {e: {"round": rounds[e], "pos": pos[e], "solved": e in solved} for e in ("luff", "leech", "foot")}
    return sail
