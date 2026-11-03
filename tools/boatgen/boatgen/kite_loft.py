"""The lofted flying shape of a spinnaker (docs/specs/sail_visuals.md 6.5): built once from measured flying
sections (a kite shape file, docs/specs/data_format.md 3.9) and the class's flat planform, written to the physics
sidecar as one shape per measured apparent wind angle. The game only blends and places these shapes.

Per measured AWA and per grid row (a stripe at a fraction of the luff and the leech, as the measured sections are):
the row's camber, draft, entry angle and twist come from the measured sections by height (a monotone cubic through
them; toward the head the camber and the entry go to zero, the twist runs on); the row's section is the convex
curve of those three numbers (below) with the row's flat girth as its arc length, so the cloth keeps its length
and the flying chord comes out of the camber; it hangs from the row's luff vertex, its chord along the flat row
turned by the twist about the vertical, its belly to port. Each grid vertex sits on its row's section at its own
fraction of the flat girth.

The section curve: tangent angle theta(t) over the arc fraction t, from its curvature
    kappa(t) = k * (exp(s (t - 1/2)) - exp(-s/2) w(t)) + g * w(t),   w(t) = max(0, 1 - t / CURL_W)^2
k sets the depth, s moves the draft fore and aft, g >= 0 is the luff curl (with g = 0 the curvature is zero at the
luff). Every term is >= 0 for s >= -2 / CURL_W, so the section is convex: a membrane under pressure has no hollow.
Solved for the camber, the draft and the entry angle; when the entry asked for is under what g = 0 gives, the curl
stays 0 and the entry is what the camber and the draft make (the section stays convex).
"""
import json
import math
import os

import numpy as np

SCHEMA = "windmark.kiteshape/1"
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "..", "data", "sails"))

CURL_W = 0.3        # the luff curl's reach, share of the girth (spread over a few grid columns: no crease)
N_ARC = 801         # samples along a section for the solve
S_MIN = -2.0 / CURL_W   # the draft term's lowest exponent (the section stays convex above it)
CURL_FLOOR = 0.01   # the curl's chord shortening goes to zero smoothly over +-this
HOOK_W = 0.5        # the clew hook's reach along the foot from the clew, share of the girth
HOOK_H = 0.3        # the clew hook fades out up the sail over this share of the height, (1 - h / HOOK_H)^3
HOOK_MAX = 8.0      # the largest clew hook (curvature at the clew times the girth)
LIFT_MAX = 0.3      # the largest clew lift, share of the flat foot
HOOK_GRID = 7       # the hooks tried first (0 to HOOK_MAX)
AIM_STEPS = 14      # golden-section steps of the clew's solve
TWIST_STEPS = 3     # corrections of the rows' twist to the measured one as the kite is set


class KiteShapeError(ValueError):
    pass


# ---------------------------------------------------------------------------- the data file


def load(name, data_dir=None):
    """The kite shape file `<data_dir>/<name>.kite_shape.json`, validated: shapes sorted by AWA (two or more),
    each with sections sorted by height (at least two, from h = 0)."""
    path = os.path.join(data_dir or DATA_DIR, f"{name}.kite_shape.json")
    if not os.path.exists(path):
        raise KiteShapeError(f"kite shape {name!r}: no file {path}")
    with open(path) as f:
        d = json.load(f)
    return validate(d, name)


def validate(d, where="kite shape"):
    if not isinstance(d, dict) or d.get("schema") != SCHEMA:
        raise KiteShapeError(f"{where}: schema must be {SCHEMA}")
    src = d.get("source")
    if not isinstance(src, dict) or not str(src.get("citation", "")).strip():
        raise KiteShapeError(f"{where}: source.citation is required")
    shapes = d.get("shapes")
    if not isinstance(shapes, list) or len(shapes) < 2:
        raise KiteShapeError(f"{where}: shapes needs two or more apparent wind angles")
    out = []
    for i, s in enumerate(shapes):
        w = f"{where}.shapes[{i}]"
        awa = s.get("awa_deg")
        if not isinstance(awa, (int, float)) or not 20 <= awa <= 180:
            raise KiteShapeError(f"{w}.awa_deg must be a number from 20 to 180")
        secs = s.get("sections")
        if not isinstance(secs, list) or len(secs) < 2:
            raise KiteShapeError(f"{w}.sections needs two or more sections")
        rows = []
        for j, c in enumerate(secs):
            wc = f"{w}.sections[{j}]"
            for k, lo, hi in (("h", 0.0, 0.95), ("camber", 0.0, 0.45), ("draft", 0.2, 0.8),
                              ("twist_deg", -45.0, 60.0), ("entry_deg", 0.0, 150.0)):
                v = c.get(k, 0.0 if k == "twist_deg" else None)
                if isinstance(v, bool) or not isinstance(v, (int, float)) or not lo <= v <= hi:
                    raise KiteShapeError(f"{wc}.{k} must be a number from {lo:g} to {hi:g}")
            rows.append((float(c["h"]), float(c["camber"]), float(c["draft"]), math.radians(c.get("twist_deg", 0.0)),
                         math.radians(c["entry_deg"])))
        rows.sort()
        if rows[0][0] != 0.0 or len({r[0] for r in rows}) != len(rows):
            raise KiteShapeError(f"{w}.sections must start at h = 0 with one section per height")
        out.append({"awa": math.radians(awa), "sections": np.array(rows)})
    out.sort(key=lambda s: s["awa"])
    if len({s["awa"] for s in out}) != len(out):
        raise KiteShapeError(f"{where}: one shape per apparent wind angle")
    return {"name": d.get("name", where), "source": src, "shapes": out}


# ---------------------------------------------------------------------------- the measured numbers by height


def pchip(x, y, xq):
    """Monotone cubic (Fritsch-Carlson) through (x, y) at xq: no overshoot between the measured sections."""
    x, y = np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64)
    h = np.diff(x)
    dl = np.diff(y) / h
    m = np.zeros_like(y)
    for i in range(1, len(x) - 1):
        if dl[i - 1] * dl[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])
    m[0], m[-1] = dl[0], dl[-1]
    xq = np.clip(np.asarray(xq, dtype=np.float64), x[0], x[-1])
    i = np.clip(np.searchsorted(x, xq, side="right") - 1, 0, len(x) - 2)
    t = (xq - x[i]) / h[i]
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * y[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * y[i + 1] \
        + (t3 - t2) * h[i] * m[i + 1]


def by_height(sections, h):
    """(camber, draft, twist, entry) at heights h from the measured sections (rows of h, camber, draft, twist,
    entry): a monotone cubic through them and a head point at h = 1 where the camber and the twist run on along the
    top two sections' slope (the camber toward zero, never below it: a camber forced to zero over the top sixth
    pinches the head into a waist; the depth goes to zero with the chord anyway), the draft is the top section's and
    the entry zero."""
    S = np.asarray(sections, dtype=np.float64)
    hs = S[:, 0]
    if hs[-1] < 1.0:
        run = (1.0 - hs[-1]) / (hs[-1] - hs[-2])
        cam = max(0.0, S[-1, 1] + min(S[-1, 1] - S[-2, 1], 0.0) * run)
        tw = S[-1, 3] + (S[-1, 3] - S[-2, 3]) * run
        S = np.vstack([S, [1.0, cam, S[-1, 2], tw, 0.0]])
    return tuple(pchip(S[:, 0], S[:, k], h) for k in (1, 2, 3, 4))


# ---------------------------------------------------------------------------- one section

_T = np.linspace(0.0, 1.0, N_ARC)
_W = np.clip(1.0 - _T / CURL_W, 0.0, None) ** 2
_WE = np.clip(1.0 - (1.0 - _T) / HOOK_W, 0.0, None) ** 2     # the clew hook's reach at the leech end


def _cumtrapz(f):
    return np.concatenate([[0.0], np.cumsum(0.5 * (f[1:] + f[:-1]))]) / (N_ARC - 1)


def section_curve(k, s, g, he=0.0):
    """The section of unit arc length with the curvature terms k, s, g and the hook he at the leech end: (X, Y,
    theta) at _T, its chord along +x from the origin, the belly toward +y."""
    kap = k * (np.exp(s * (_T - 0.5)) - math.exp(-0.5 * s) * _W) + g * _W + he * _WE
    th = -_cumtrapz(kap)
    x, y = _cumtrapz(np.cos(th)), _cumtrapz(np.sin(th))
    phi = math.atan2(y[-1], x[-1])
    c, sn = math.cos(phi), math.sin(phi)
    return x * c + y * sn, -x * sn + y * c, th - phi


def _measure(X, Y, th):
    ch = X[-1]
    k = min(max(int(np.argmax(Y)), 1), N_ARC - 2)
    y0, y1, y2 = Y[k - 1], Y[k], Y[k + 1]
    den = y0 - 2 * y1 + y2
    dk = 0.5 * (y0 - y2) / den if den != 0 else 0.0
    xm = np.interp(k + dk, np.arange(N_ARC), X)
    ym = y1 - 0.25 * (y0 - y2) * dk
    return np.array([ym / ch, xm / ch, th[0]])


def _solve(target, x0, free, he=0.0):
    """Newton with a line search on the free terms (indices into (k, s, g)) for the targets (camber, draft[,
    entry]); returns the terms."""
    x = np.array(x0, dtype=np.float64)
    nt = len(target)

    def F(v):
        X, Y, th = section_curve(*v, he)
        return _measure(X, Y, th)[:nt]
    for _ in range(80):
        m = F(x)
        r = m - target
        err = np.max(np.abs(r))
        if err < 1e-9:
            break
        J = np.zeros((nt, len(free)))
        for q, i in enumerate(free):
            dx = x.copy()
            dx[i] += 1e-6
            J[:, q] = (F(dx) - m) / 1e-6
        step = np.linalg.lstsq(J, -r, rcond=None)[0]
        a = 1.0
        while a > 1e-5:
            xn = x.copy()
            xn[list(free)] += a * step
            xn[1] = max(xn[1], S_MIN)
            if np.max(np.abs(F(xn) - target)) < err:
                x = xn
                break
            a *= 0.5
        else:
            break
    return x


def section(camber, draft, entry=None, chord=None, hook=0.0):
    """The convex section of unit arc length with this camber, draft and clew hook and, as near as convexity
    allows, either this entry angle or this chord (over the arc): {"X", "Y" (at _T), "chord", "entry", "exit",
    "curl" (g)}."""
    if camber < 1e-4:
        return {"X": _T.copy(), "Y": np.zeros_like(_T), "chord": 1.0, "entry": 0.0, "exit": 0.0, "curl": 0.0}
    k0 = 2.0 * 2.0 * math.atan(2.0 * camber)        # a circular arc's curvature times its length
    # no curl first (g = 0): the least entry (the longest chord) a convex section of this camber and draft has
    x = _solve(np.array([camber, draft]), [k0, 0.0, 0.0], (0, 1), hook)
    X, Y, th = section_curve(*x, hook)
    curl = th[0] < entry if chord is None else X[-1] > chord
    if curl:
        if chord is None:
            x = _solve(np.array([camber, draft, entry]), x, (0, 1, 2), hook)
        else:
            x = _solve_chord(camber, draft, chord, x, hook)
        if x[2] < 0.0:      # numerically below the floor: back to no curl
            x = _solve(np.array([camber, draft]), [x[0], x[1], 0.0], (0, 1), hook)
        X, Y, th = section_curve(*x, hook)
    return {"X": X, "Y": Y, "chord": float(X[-1]), "entry": float(th[0]), "exit": float(-th[-1]),
            "curl": float(x[2])}


def _solve_chord(camber, draft, chord, x0, he=0.0):
    """As _solve, the targets camber, draft and the chord over the arc."""
    x = np.array(x0, dtype=np.float64)
    tgt = np.array([camber, draft, chord])

    def F(v):
        X, Y, th = section_curve(*v, he)
        m = _measure(X, Y, th)
        return np.array([m[0], m[1], X[-1]])
    for _ in range(80):
        m = F(x)
        r = m - tgt
        err = np.max(np.abs(r))
        if err < 1e-9:
            break
        J = np.zeros((3, 3))
        for i in range(3):
            dx = x.copy()
            dx[i] += 1e-6
            J[:, i] = (F(dx) - m) / 1e-6
        step = np.linalg.lstsq(J, -r, rcond=None)[0]
        a = 1.0
        while a > 1e-5:
            xn = x + a * step
            xn[1] = max(xn[1], S_MIN)
            if np.max(np.abs(F(xn) - tgt)) < err:
                x = xn
                break
            a *= 0.5
        else:
            break
    return x


def draft_by_height(sections, h):
    """The draft by height: a least-squares cubic in h through the measured sections' drafts (the J/80 reach's 0.44,
    0.39, 0.44 at 1/6 to 1/2 would wave the line of deepest points, and with it the light on the cloth, from side to
    side), held from the top section to the head."""
    S = np.asarray(sections, dtype=np.float64)
    coef = np.polyfit(S[:, 0], S[:, 2], min(3, len(S) - 1))
    h = np.minimum(np.asarray(h, dtype=np.float64), S[-1, 0])
    return np.polyval(coef, h)


def twist_by_height(sections, h):
    """The twist by height: a least-squares cubic in h through the measured sections' twists, zero at the foot
    (the twist is measured from the foot's chord), run on to the head; a fair leech again (the J/80 reach's 6, 6, 3,
    4 deg up the top half would bend the leech back and forth)."""
    S = np.asarray(sections, dtype=np.float64)
    hs, tw = S[:, 0], S[:, 3]
    A = np.stack([hs, hs ** 2, hs ** 3], -1)
    coef = np.linalg.lstsq(A, tw, rcond=None)[0]
    h = np.asarray(h, dtype=np.float64)
    return coef[0] * h + coef[1] * h ** 2 + coef[2] * h ** 3


def chord_by_height(sections, h, camber=None, draft=None, hooks=None):
    """The flying chord over the girth by height: the longest chord a convex section of the row's camber and draft
    has (no luff curl), less a curl shortening that is fair in h: a least-squares cubic through the measured
    sections' own shortening (from their entry angles; zero at the head), kept >= 0 with a smooth floor. The
    measured entries scatter (50 to 129 deg) more than a fair leech allows; the leech the chords make is fair.
    Returns the chords at h and the measured sections' (h, chord)."""
    S = np.asarray(sections, dtype=np.float64)
    h = np.asarray(h, dtype=np.float64)
    if camber is None:
        camber, draft, _, _ = by_height(S, h)
    hs = np.concatenate([S[:, 0], [1.0]])
    rho = np.array([section(c, d, e)["chord"] for _, c, d, _, e in S] + [1.0])
    flo = np.array([section(c, d, 0.0)["chord"] for _, c, d, _, _ in S] + [1.0])
    w = np.ones_like(hs)
    w[-1] = 10.0
    A = np.vander(hs, 4)
    coef = np.linalg.lstsq(A * w[:, None], (flo - rho) * w, rcond=None)[0]
    b = CURL_FLOOR
    x = np.polyval(coef, h)
    short = np.where(x >= b, x, np.where(x <= -b, 0.0, (x + b) ** 2 / (4 * b)))
    hooks = np.zeros(len(h)) if hooks is None else hooks
    floor_h = np.array([section(float(c), float(d), 0.0, hook=float(he))["chord"]
                        for c, d, he in zip(camber, draft, hooks)])
    return floor_h - short, (hs, rho)


# ---------------------------------------------------------------------------- the loft


def sail_frame(P):
    """sail_visuals.md 3.2 for a flat grid (rows, cols, 3) in a frame with z up and y port: the tack T and the
    unit axes Ah (aft, square to the luff in the sail plane), Lh (tack to head), Nh (port)."""
    rows = P.shape[0]
    T = P[0, 0]
    Lh = P[rows - 1, 0] - T
    Lh = Lh / np.linalg.norm(Lh)
    Nh = np.array([0.0, 1.0, 0.0])
    Ah = np.cross(Lh, Nh)
    return T, Ah / np.linalg.norm(Ah), Lh, Nh


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def loft_one(P, sections, hook=0.0, lift=0.0, twist=None, camber=None):
    """One flying shape of the flat grid P (rows, cols, 3; z up, y port) from one AWA's measured sections with the
    clew hook `hook` (the foot's, fading up the sail) and the clew lift `lift` (share of the flat foot): (rows *
    cols, 3) local positions (a, l, n) in the sail frame of 3.2 (from the tack), the belly to port, and per row the
    numbers used: {"h", "camber", "draft", "twist", "entry", "exit", "chord" (flying chord over girth), "hook"}.
    `twist`, `camber`: the rows' twist about the vertical (rad) and camber, in place of the measured sections'."""
    rows, cols = P.shape[:2]
    T, Ah, Lh, Nh = sail_frame(P)
    hs = np.arange(rows) / (rows - 1)          # a row's stripe: its fraction of the luff and the leech
    cam, dra, tw, ent = by_height(sections, hs)
    dra = draft_by_height(sections, hs)
    if camber is not None:
        cam = np.maximum(np.asarray(camber, dtype=np.float64), 0.0)
    hooks = hook * np.clip(1.0 - hs / HOOK_H, 0.0, None) ** 3
    rho, _ = chord_by_height(sections, hs, cam, dra, hooks)
    tw = twist_by_height(sections, hs) if twist is None else np.asarray(twist, dtype=np.float64)
    out = np.zeros((rows, cols, 3))
    info = {"h": hs, "camber": cam, "draft": dra, "twist": tw, "entry": np.zeros(rows), "exit": np.zeros(rows),
            "chord": np.ones(rows), "hook": hooks}
    for i in range(rows):
        R = P[i]
        seg = np.linalg.norm(np.diff(R, axis=0), axis=-1)
        G = float(seg.sum())
        if G < 1e-6:
            Q = np.repeat(R[:1], cols, axis=0)
        else:
            t = np.concatenate([[0.0], np.cumsum(seg)]) / G       # each vertex's share of the flat girth
            sc = section(float(cam[i]), float(dra[i]), chord=float(rho[i]), hook=float(hooks[i]))
            info["entry"][i], info["exit"][i], info["chord"][i] = sc["entry"], sc["exit"], sc["chord"]
            r = (R[-1] - R[0]) / np.linalg.norm(R[-1] - R[0])
            # the twist turns the section about the vertical through its luff vertex, the leech to port
            Rz = rot_z(-float(tw[i]))
            r2, n2 = Rz @ r, Rz @ Nh
            X, Y = np.interp(t, _T, sc["X"]), np.interp(t, _T, sc["Y"])
            Q = R[0] + G * (X[:, None] * r2 + Y[:, None] * n2)
        d = Q - T
        out[i] = np.stack([d @ Ah, d @ Lh, d @ Nh], -1)
    return lifted(P, out.reshape(-1, 3), lift), info


def lifted(P, loc, lift):
    """The clew end of the low rows raised along the luff by lift * (flat foot) * (1 - h / HOOK_H)^3 * uc^2 (uc the
    vertex's place along its row): the foot and the lower leech stay fair, the luff, the tack and the head do not
    move."""
    if lift == 0.0:
        return loc
    rows, cols = P.shape[:2]
    c0 = float(np.linalg.norm(P[0, -1] - P[0, 0]))
    h = np.repeat(np.arange(rows) / (rows - 1), cols)
    uc = np.tile(np.arange(cols) / (cols - 1), rows)
    out = loc.copy()
    out[:, 1] += lift * c0 * np.clip(1.0 - h / HOOK_H, 0.0, None) ** 3 * uc * uc
    return out


def clew_angle(G, lead):
    """The angle (rad) between the sheet (from the lead through the clew) and the bisector of the clew corner (the
    foot to its third vertex from the clew, the leech to its third vertex up) of a placed grid G (rows, cols, 3)."""
    c = G[0, -1]
    f = (G[0, -3] - c) / np.linalg.norm(G[0, -3] - c)
    e = (G[2, -1] - c) / np.linalg.norm(G[2, -1] - c)
    b = (f + e) / np.linalg.norm(f + e)
    sv = (c - lead) / np.linalg.norm(c - lead)
    return float(np.arccos(np.clip(sv @ b, -1.0, 1.0)))


def row_camber(G):
    """Each row's camber of a placed grid G: its largest distance from its chord (a parabola through the deepest
    vertex and its neighbours) over the chord; 0 on a row with no chord."""
    out = np.zeros(G.shape[0])
    for i, R in enumerate(G):
        ch = R[-1] - R[0]
        cl = float(np.linalg.norm(ch))
        if cl < 1e-6:
            continue
        cu = ch / cl
        v = R - R[0]
        x = v @ cu
        d = np.linalg.norm(v - np.outer(x, cu), axis=-1)
        k = int(np.argmax(d))
        dm = d[k]
        if 0 < k < len(d) - 1:
            c2 = np.polyfit(x[k - 1:k + 2], d[k - 1:k + 2], 2)
            if c2[0] < 0:
                xv = -c2[1] / (2 * c2[0])
                if x[k - 1] < xv < x[k + 1]:
                    dm = float(np.polyval(c2, xv))
        out[i] = dm / cl
    return out


def plan_twist(G, lee, up):
    """Each row's chord's horizontal angle from the foot's (rad, to leeward `lee`) of a placed grid G."""
    aft = np.cross(up, lee)       # with lee to port and z up: aft
    ch = G[:, -1] - G[:, 0]
    a = np.arctan2(ch @ lee, ch @ aft)
    d = a - a[0]
    return (d + np.pi) % (2 * np.pi) - np.pi


def loft(P, shape, place=None):
    """Every measured AWA of `shape` (load()) lofted on the flat grid P: {"awa": [rad], "shapes": [(n, 3)],
    "rows": [info per AWA], "hook", "lift", "aim" (the sheet's angle off the clew's bisector, rad, or None): per
    AWA}. `place(awa, shape)`: the kite set alone at its nominal trim for that AWA (wind from starboard: its belly
    and leeward to port, z up): (the placed grid (rows, cols, 3), its sheet's lead block). With it the loft is
    fitted to the kite as it flies: the rows' twist and camber are corrected so their chords' horizontal angles and
    their cambers as set are the measured ones (a turn about the leaning luff alone changes the angles; the clew's
    hook and lift the low rows' camber), the clew hook (0 to HOOK_MAX) and lift (-LIFT_MAX to LIFT_MAX) are chosen
    to bring the sheet nearest the clew's bisector, and the twist and camber are corrected again."""
    P = np.asarray(P, dtype=np.float64)
    rows = P.shape[0]
    hs_rows = np.arange(rows) / (rows - 1)
    lee, up = np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0])
    res = {"awa": [], "shapes": [], "rows": [], "hook": [], "lift": [], "aim": []}
    gr = (math.sqrt(5.0) - 1.0) / 2.0

    def golden(f, a, b, n):
        c, d = b - gr * (b - a), a + gr * (b - a)
        fc, fd = f(c), f(d)
        for _ in range(n):
            if fc < fd:
                b, d, fd = d, c, fc
                c = b - gr * (b - a)
                fc = f(c)
            else:
                a, c, fc = c, d, fd
                d = a + gr * (b - a)
                fd = f(d)
        return (c, fc) if fc < fd else (d, fd)

    for s in shape["shapes"]:
        awa = float(s["awa"])
        sec = s["sections"]
        hook = lift = 0.0
        err = None
        tw = twist_by_height(sec, hs_rows)
        cam = by_height(sec, hs_rows)[0]
        if place is not None:
            tw_t, cam_t = tw.copy(), cam.copy()

            def as_flown(hk, lf, tw, cam):
                for _ in range(TWIST_STEPS):
                    G, _ = place(awa, loft_one(P, sec, hk, lf, tw, cam)[0])
                    tw = tw + (tw_t - plan_twist(G, lee, up))
                    cam = np.where(np.arange(rows) < rows - 1, cam + (cam_t - row_camber(G)), cam)
                return tw, cam
            tw, cam = as_flown(0.0, 0.0, tw, cam)
            cache = {}

            def aim(loc):
                G, lead = place(awa, loc)
                return clew_angle(G, lead)

            def best_lift(hk):
                if hk not in cache:
                    base = loft_one(P, sec, hk, twist=tw, camber=cam)[0]
                    cache[hk] = golden(lambda lf: aim(lifted(P, base, lf)), -LIFT_MAX, LIFT_MAX, AIM_STEPS)
                return cache[hk]
            hks = np.linspace(0.0, HOOK_MAX, HOOK_GRID)
            k = int(np.argmin([best_lift(float(h))[1] for h in hks]))
            lo, hi = hks[max(k - 1, 0)], hks[min(k + 1, len(hks) - 1)]
            hook, _ = golden(lambda hk: best_lift(float(hk))[1], lo, hi, AIM_STEPS // 2)
            lift, _ = best_lift(float(hook))
            tw, cam = as_flown(hook, lift, tw, cam)
            err = aim(loft_one(P, sec, hook, lift, tw, cam)[0])
        loc, info = loft_one(P, sec, hook, lift, tw, cam)
        res["awa"].append(awa)
        res["shapes"].append(loc)
        res["rows"].append(info)
        res["hook"].append(float(hook))
        res["lift"].append(float(lift))
        res["aim"].append(err)
    return res


def sidecar_block(P, name, shape=None, place=None):
    """The sidecar's `loft` block of a kite (sail_visuals.md 6.5): the shape file's name and source, the AWAs
    (rad), the clew hook of each and per AWA the local position of every grid vertex (grid order, m, in the sail
    frame of 3.2)."""
    shape = shape or load(name)
    L = loft(P, shape, place)
    return {"shape": name, "source": shape["source"].get("citation", ""),
            "clew": [{"hook": round(h, 4), "lift": round(lf, 4),
                      "sheet_off_bisector_deg": None if e is None else round(math.degrees(e), 2)}
                     for h, lf, e in zip(L["hook"], L["lift"], L["aim"])],
            "frame": "sail frame of sail_visuals.md 3.2 from the tack: a aft square to the luff, l along the luff, "
                     "n to port (the belly); grid order",
            "awa": [round(a, 6) for a in L["awa"]],
            "shapes": [np.round(s, 5).tolist() for s in L["shapes"]]}
