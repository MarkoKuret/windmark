"""Sails set as the game draws them, for the preview poses and kite_preview.

A port of the run-time sail shape of docs/specs/sail_visuals.md (the `up` shapes of 6.1 to 6.4, the placement of
7.1 to 7.3 and the clearance of 7.4) from the game's reference, game/scripts/sail_shape_ref.gd (the native
game/native/src/sail_shape.cpp follows the same reference). The previews therefore show the shape a boat carries
in a race rather than a shape of their own; game/tests/sail_parity_test.gd checks the two against each other on
the generated boats, from the `<id>.sets.json` file the generator writes next to the models.

Frame: the generator's internal one (x forward from the transom, y port, z up); every rotation is about an axis
through a point, so the origin does not matter. No flutter (luff shiver 0), headsails drawing (not backed), the
twist side already settled to leeward.
"""
import numpy as np

KNOT = 1852.0 / 3600.0
C_HOOK = 0.0369260386
FWD, PORT, UP = np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])

MAIN, HEADSAIL, ASYM, SYM = range(4)
BOOM, LUFF, SPRIT, POLE = range(4)

# look defaults the game falls back on (game/scripts/boat_view.gd, sail_visuals.md 4); the sidecar look block
# normally carries all of them
_KIND = {"main": MAIN, "jib": HEADSAIL, "genoa": HEADSAIL, "code_zero": HEADSAIL, "spinnaker_asym": ASYM,
         "spinnaker_sym": SYM}


def sgn(x):
    return 1.0 if x >= 0.0 else -1.0


def wrap_pi(x):
    return (x + np.pi) % (2 * np.pi) - np.pi


def fill(v, g, k):
    """sail_visuals.md 5.1"""
    x = abs(v)
    m = min(max(x ** (0.75 / k) * np.exp(-0.01 / (x + 1e-6)), 0.0), 1.0)
    return sgn(v) * 0.75 * g * m


def rot(axis, a):
    """Right-handed rotation by `a` about the unit `axis`."""
    x, y, z = axis
    c, s = np.cos(a), np.sin(a)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


class Xf:
    """Rigid transform p -> R p + t."""

    def __init__(self, R=None, t=None):
        self.R = np.eye(3) if R is None else R
        self.t = np.zeros(3) if t is None else t

    @staticmethod
    def about(p, axis, a):
        R = rot(axis, a)
        return Xf(R, p - R @ p)

    def __mul__(self, o):
        return Xf(self.R @ o.R, self.R @ o.t + self.t)

    def __call__(self, p):
        return p @ self.R.T + self.t


PUSH_SLOPE = 0.3        # 7.4 k_p: the local push falls off by this much per metre of cloth
PUSH_EASE = 3.0         # 7.4 P_e: the ease starts where the leech is deeper than this many clearances
EASE_MAX = 0.35         # 7.4 e_max: the largest ease, rad


def smoothstep01(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def smax(x, b):
    if x >= b:
        return x
    if x <= -b:
        return 0.0
    return (x + b) * (x + b) / (4 * b)


def asym_height(h):
    """6.3: the asymmetric spinnaker's camber over its largest by row height h: deepest at 0.3 of the height,
    0.8 on the foot, 0.45 at the head."""
    h = np.asarray(h, dtype=np.float64)
    lo = (0.3 - h) / 0.3
    hi = (h - 0.3) / 0.7
    return np.where(h < 0.3, 1 - 0.2 * lo * lo, 1 - 0.55 * hi * hi)


def asym_draft(h):
    """6.3: the exponent of the chordwise profile by row height: 0.8 (draft 0.42 of the chord) up to 0.55 of the
    height, 1.4 (draft 0.61) at the head."""
    h = np.asarray(h, dtype=np.float64)
    t = np.clip((h - 0.55) / 0.45, 0.0, 1.0)
    return 0.8 + 0.6 * t * t * (3 - 2 * t)


def asym_profile(uc, q):
    """6.3: the chordwise camber profile sin(pi uc^q), 0 at the luff and the leech, 1 at the draft."""
    return np.sin(np.pi * np.power(np.clip(uc, 0.0, 1.0), q))


def asym_twist(awa):
    """7.3: the share of twist_top an asymmetric spinnaker carries at the apparent wind angle awa: none to 60
    deg, all from 130 to 155 deg, none again dead downwind (180 deg), so a gybe round the bow passes untwisted."""
    t = min(max((abs(awa) - np.radians(60.0)) / np.radians(70.0), 0.0), 1.0)
    r = min(max((np.pi - abs(awa)) / np.radians(25.0), 0.0), 1.0)
    return t * t * (3 - 2 * t) * r * r * (3 - 2 * r)


class SailSet:
    """One sail: configure from the flat grid and the look, then `update` places it (mid-surface in `self.mid`)."""

    def __init__(self, P, sail_type, look, mode, rig, loa):
        self.rows, self.cols = P.shape[:2]
        rows, cols = self.rows, self.cols
        Q = P.reshape(-1, 3).astype(np.float64)
        self.kind = _KIND[sail_type]
        self.mode = mode
        self.fill_gain = float(look["fill_gain"])
        self.fill_curve = float(look["fill_curve"])
        self.twist_top = float(look["twist_top"])
        self.camber = float(look.get("camber", 0.26))
        self.cam_cap = self.camber if self.kind == HEADSAIL and "camber" in look else 0.0
        self.tack_line_max = float(look.get("tack_line_max", 0.0))
        self.boom_pivot = np.asarray(rig["boom_pivot"], dtype=np.float64)
        self.boom_axis = np.asarray(rig["boom_axis"], dtype=np.float64)
        self.mast_step = np.asarray(rig["mast_step"], dtype=np.float64)
        self.mast_head = np.asarray(rig["masthead"], dtype=np.float64)
        self.mast_axis = (self.mast_head - self.mast_step) / np.linalg.norm(self.mast_head - self.mast_step)
        self.flying = sail_type.startswith("spinnaker") or sail_type == "code_zero"
        self.clearance = 0.042 * loa if self.flying else 0.0
        self.tack = Q[0].copy()
        self.head = Q[(rows - 1) * cols].copy()
        self.lh = (self.head - self.tack) / np.linalg.norm(self.head - self.tack)
        self.nh = PORT.copy()
        ah = np.cross(self.lh, self.nh)
        self.ah = ah / np.linalg.norm(ah)
        d = Q - self.tack
        self.a, self.l = d @ self.ah, d @ self.lh
        self.a_min, self.l_min = self.a.min(), self.l.min()
        self.sa = max(self.a.max() - self.a_min, 1e-3)
        self.sl = max(self.l.max() - self.l_min, 1e-3)
        self.u = (self.a - self.a_min) / self.sa
        self.h = (self.l - self.l_min) / self.sl
        self.uc = np.tile(np.arange(cols) / (cols - 1), rows)
        R = Q.reshape(rows, cols, 3)
        self.C = np.linalg.norm(R[:, -1] - R[:, 0], axis=-1)
        A = self.a.reshape(rows, cols)
        self.amid = 0.5 * (A[:, 0] + A[:, -1])
        self.hrow = self.h.reshape(rows, cols)[:, 0].copy()
        dh = self.tack - self.head
        self.r_h = max(np.linalg.norm(dh - UP * (dh @ UP)), 1e-3)
        self.mid = Q.copy()
        self.loc = np.stack([self.a, self.l, np.zeros_like(self.a)], -1)
        self.ease = 0.0
        self.trow = np.zeros(rows)
        self.push_max = 0.0     # the largest local push of the last update (7.4), m
        self._secs = []
        # 7.4: distances between grid neighbours on the rest cloth (along a row, up a column, the two diagonals)
        E = Q.reshape(rows, cols, 3)
        self._ec = np.linalg.norm(E[:, 1:] - E[:, :-1], axis=-1)
        self._er = np.linalg.norm(E[1:] - E[:-1], axis=-1)
        self._e1 = np.linalg.norm(E[1:, 1:] - E[:-1, :-1], axis=-1)
        self._e2 = np.zeros((rows - 1, cols))
        self._e2[:, 1:] = np.linalg.norm(E[1:, :-1] - E[:-1, 1:], axis=-1)

    # ------------------------------------------------------------------ shape and placement (7, 6.1 to 6.4)

    def update(self, beta, gamma, awa, aws, obstacles=()):
        rows, cols = self.rows, self.cols
        tl = -sgn(awa)
        s_t = Xf()
        ge = 0.0
        piv, ax = self.tack, self.lh
        if self.mode == BOOM:
            piv, ax = self.boom_pivot, self.boom_axis
        elif self.mode == SPRIT:
            lim = np.arcsin(min(1.0, self.tack_line_max * self.sl / self.r_h))
            ge = sgn(gamma) * min(abs(gamma), lim)
            s_t = Xf.about(self.head, UP, ge)
        elif self.mode == POLE:
            ge = gamma
            s_t = Xf.about(self.mast_step, self.mast_axis, ge)
        if self.mode in (SPRIT, POLE):
            piv = s_t(self.tack)
            ax = s_t.R @ self.lh
            ax = ax / np.linalg.norm(ax)
        base = beta - ge
        b0 = rot(ax, base) @ s_t.R
        ap, lp, np_ = b0 @ self.ah, b0 @ self.lh, b0 @ self.nh
        a, l, u = self.a, self.l, self.u
        if self.kind == MAIN:
            b = fill(np.sin(wrap_pi(beta + awa)), self.fill_gain, self.fill_curve)
            D = sgn(b) * 4 * self.sa * b * b
            f = 1 - np.exp(-8 * self.h)
            loc = np.stack([a, l, f * D * u * (1 - u)], -1)
        elif self.kind == HEADSAIL:
            b = fill(np.sin(beta), self.fill_gain, self.fill_curve)
            D = sgn(b) * 4 * self.sa * b * b
            if self.cam_cap > 0:
                dm = self.cam_cap * self.sa / 0.2362
                D = dm * np.tanh(D / dm)
            loc = np.stack([a, l, 0.5 * D * (u ** 4 - C_HOOK * u)], -1)
        else:
            if self.kind == SYM:
                F = abs(fill(np.sin(beta), self.fill_gain, self.fill_curve))
            else:
                F = self.fill_gain * min(max(aws / KNOT, 3.0), 6.0) / 6.0
            uw = FWD * np.cos(awa) - PORT * np.sin(awa)
            w = np.array([uw @ ap * 0.5 / self.fill_curve, uw @ lp * 0.5, uw @ np_])
            w = w / np.linalg.norm(w) if w @ w > 1e-12 else np.array([0, 0, 1.0])
            fc = self.camber * min(F, 1.15)
            i = np.repeat(np.arange(rows), cols)
            if self.kind == ASYM:
                drow = fc * asym_height(self.hrow)
                prof = asym_profile(self.uc, asym_draft(self.hrow)[i])
            else:
                hh = 2 * self.hrow - 1
                drow = fc * (1 - 0.45 * hh * hh)
                prof = 4 * self.uc * (1 - self.uc)
            srow = 1 / (1 + 8 / 3 * drow * drow)
            a0 = a.reshape(rows, cols)[:, 0][i]
            s = srow[i]
            e = drow[i] * s * self.C[i] * prof
            loc = np.stack([a0 + (a - a0) * s, l, np.zeros_like(a)], -1) - e[:, None] * w[None]
        self.loc = loc
        # 7.1 to 7.3: the twist of each row toward leeward (an asymmetric spinnaker: opening with the AWA)
        # (signed, rad; the asymmetric spinnaker's on the side away from the wind at once: it is zero where awa
        # changes sign)
        if self.kind == ASYM:
            self.trow = -sgn(awa) * self.twist_top * asym_twist(awa) * np.sqrt(self.hrow)
        else:
            self.trow = tl * self.twist_top * self.hrow ** 1.5
        hd = s_t(self.head)
        clearing = self.clearance > 0
        self.ease = 0.0
        if clearing and obstacles:
            self._sections(obstacles, s_t, piv, ax, base, tl)
            self.ease = self._ease_for(beta, s_t, piv, ax, base, hd, tl)
        else:
            self._secs = []
        es = sgn(beta) * self.ease
        mid = np.empty_like(self.mid)
        rest = self.tack + loc[:, :1] * self.ah + loc[:, 1:2] * self.lh + loc[:, 2:] * self.nh
        for r in range(rows):
            th = base + self.trow[r] + es
            xr = Xf.about(piv, ax, th) * s_t
            mid[r * cols:(r + 1) * cols] = xr(rest[r * cols:(r + 1) * cols])
        self.mid = mid
        if clearing:
            self._push(awa, hd)
        return self.mid

    def grid(self):
        return self.mid.reshape(self.rows, self.cols, 3)

    # ------------------------------------------------------------------ clearance (7.4)

    def _sections(self, obstacles, s_t, piv, ax, base, tl):
        lc = self.loc[self.cols - 1]
        xr = Xf.about(piv, ax, base + self.trow[0]) * s_t
        cl = xr(self.tack + self.ah * lc[0] + self.lh * lc[1] + self.nh * lc[2])
        sk = sgn((cl - self.mast_step) @ PORT)
        bow = FWD + PORT * (0.3 * sk)
        self._secs = []
        for o in obstacles:
            M = o.grid()
            z = M[..., 2].mean(1)
            box = np.stack([M[..., 0].min(1), M[..., 0].max(1), M[..., 1].min(1), M[..., 1].max(1)], -1)
            for i in range(o.rows - 1):
                box[i, 0] = min(box[i, 0], box[i + 1, 0])
                box[i, 1] = max(box[i, 1], box[i + 1, 1])
                box[i, 2] = min(box[i, 2], box[i + 1, 2])
                box[i, 3] = max(box[i, 3], box[i + 1, 3])
            ch = M[0, -1] - M[0, 0]
            f = np.cross(UP, ch - UP * (ch @ UP))
            f = f / np.linalg.norm(f) if f @ f > 1e-12 else PORT.copy()
            self._secs.append({"M": M, "z": z, "box": box, "f": f if f @ bow >= 0 else -f})

    def _clear_x(self, o, p, reach):
        M, z, box = o["M"], o["z"], o["box"]
        rn, cn = M.shape[:2]
        pz = p[2]
        if pz < z[0] - self.clearance or pz > z[-1]:
            return np.inf, np.zeros(3)
        r = min(max(int(np.searchsorted(z, pz, side="right")) - 1, 0), rn - 2)
        if p[0] < box[r, 0] - reach or p[0] > box[r, 1] + reach or p[1] < box[r, 2] - reach \
                or p[1] > box[r, 3] + reach:
            return np.inf, np.zeros(3)
        den = z[r + 1] - z[r]
        t = min(max((pz - z[r]) / den, 0.0), 1.0) if den > 1e-6 else 0.0
        Qs = M[r] + (M[r + 1] - M[r]) * t
        Qs = Qs - UP[None] * Qs[:, 2:3]
        ph = p - UP * pz
        best, bj, bs, bq, bd, bh = np.inf, 0, 0.0, None, None, 1.0
        for j in range(cn - 1):
            q0, d = Qs[j], Qs[j + 1] - Qs[j]
            l2 = d @ d
            # the last segment runs on past the leech by 2 clearances (7.4)
            hi = 1.0 + 2 * self.clearance / np.sqrt(l2) if j == cn - 2 and l2 > 1e-12 else 1.0
            sp = min(max((ph - q0) @ d / l2, 0.0), hi) if l2 > 1e-12 else 0.0
            q = q0 + d * sp
            d2 = (ph - q) @ (ph - q)
            if d2 < best:
                best, bj, bs, bq, bd, bh = d2, j, sp, q, d, hi
        if (bj == 0 and bs <= 0) or (bj == cn - 2 and bs >= bh) or bd @ bd < 1e-12:
            v = ph - bq
            ln = np.linalg.norm(v)
            return ln, (v / ln if ln > 1e-6 else o["f"])
        g = np.cross(UP, bd)
        g = g / np.linalg.norm(g)
        if g @ o["f"] < 0:
            g = -g
        return (ph - bq) @ g, g

    def _mast_x(self, p, lee):
        d = p - self.mast_step
        axv = self.mast_head - self.mast_step
        ln = np.linalg.norm(axv)
        au = axv / ln
        tz = d @ au
        if tz < 0 or tz > ln:
            return np.inf, np.zeros(3)
        rad = d - au * tz
        x = np.linalg.norm(rad)
        return x, (rad / x if x > 1e-6 else lee)

    def _margin(self, p, hd):
        return self.clearance * smoothstep01(np.linalg.norm(p - hd) / (5 * self.clearance))

    def _ease_for(self, beta, s_t, piv, ax, base, hd, tl):
        rows, cols = self.rows, self.cols
        delta, es = 0.0, sgn(beta)
        for _ in range(4):
            worst, rr = np.inf, 1.0
            i = 0
            while True:
                lc = self.loc[i * cols + cols - 1]
                th = base + self.trow[i] + es * delta
                pt = (Xf.about(piv, ax, th) * s_t)(self.tack + self.ah * lc[0] + self.lh * lc[1] + self.nh * lc[2])
                cp = self._margin(pt, hd)
                for o in self._secs:
                    x = self._clear_x(o, pt, cp)[0] - cp
                    if x < worst:
                        worst = x
                        d = pt - piv
                        rr = np.linalg.norm(d - ax * (d @ ax))
                if i == rows - 2:
                    break
                i = min(i + 3, rows - 2)
            worst += PUSH_EASE * self.clearance
            if worst >= 0:
                break
            delta = min(delta + (-worst) / max(rr, 0.5), EASE_MAX)
        return delta

    def _spread(self, d):
        """7.4: the push depth field: the largest of d_s - PUSH_SLOPE * (distance over the cloth from s), by
        two chamfer passes over the rest grid; it may go down to -clearance so the smooth max has a base."""
        rows, cols = self.rows, self.cols
        s = PUSH_SLOPE
        D = d.reshape(rows, cols).copy()
        ec, er, e1, e2 = self._ec, self._er, self._e1, self._e2
        for i in range(rows):
            for j in range(cols):
                v = D[i, j]
                if j > 0:
                    v = max(v, D[i, j - 1] - s * ec[i, j - 1])
                if i > 0:
                    v = max(v, D[i - 1, j] - s * er[i - 1, j])
                    if j > 0:
                        v = max(v, D[i - 1, j - 1] - s * e1[i - 1, j - 1])
                    if j < cols - 1:
                        v = max(v, D[i - 1, j + 1] - s * e2[i - 1, j + 1])
                D[i, j] = v
        for i in range(rows - 1, -1, -1):
            for j in range(cols - 1, -1, -1):
                v = D[i, j]
                if j < cols - 1:
                    v = max(v, D[i, j + 1] - s * ec[i, j])
                if i < rows - 1:
                    v = max(v, D[i + 1, j] - s * er[i, j])
                    if j < cols - 1:
                        v = max(v, D[i + 1, j + 1] - s * e1[i, j])
                    if j > 0:
                        v = max(v, D[i + 1, j - 1] - s * e2[i, j])
                D[i, j] = v
        return D.reshape(-1)

    def _push(self, awa, hd):
        b = self.clearance
        lee = PORT * sgn(awa)
        n = len(self.mid)
        cp = np.array([self._margin(p, hd) for p in self.mid])
        self.push_max = 0.0
        for o in self._secs:
            X = np.full(n, np.inf)
            G = np.zeros((n, 3))
            d = np.full(n, -np.inf)
            for k in range(n):
                x, g = self._clear_x(o, self.mid[k], cp[k] + b)
                X[k], G[k] = x, g
                if x < cp[k] + b:
                    d[k] = cp[k] - x
            if np.isfinite(d).any():
                D = self._spread(d)
                w = cp / b                                      # the head fade
                push = np.array([smax(v, b) for v in D]) * w
                self.push_max = max(self.push_max, float(push.max()))
                for k in range(n):
                    if push[k] > 0:
                        self.mid[k] = self.mid[k] + o["f"] * push[k]
                        X[k], G[k] = self._clear_x(o, self.mid[k], cp[k] + b)
            for k in range(n):
                if X[k] < cp[k] + b:
                    self.mid[k] = self.mid[k] + G[k] * (cp[k] + smax(X[k] - cp[k], b) - X[k])
        for k in range(n):
            x, g = self._mast_x(self.mid[k], lee)
            if x < cp[k] + b:
                self.mid[k] = self.mid[k] + g * (cp[k] + smax(x - cp[k], b) - x)


# ---------------------------------------------------------------------------- whole boat


def rig_points(boat):
    """The rig numbers of sail_visuals.md 7 in the generator's internal frame (the sidecar's `rig`, unshifted)."""
    rig = boat.rig
    return {"boom_pivot": np.asarray(rig.gooseneck, dtype=np.float64), "boom_axis": UP,
            "mast_step": np.array([rig.x_mast, 0.0, rig.z_step]), "masthead": np.array([rig.x_mast, 0.0, rig.z_top])}


def sail_mode(boat, sail_type):
    """7.1 to 7.3: which placement a sail takes (as game/scripts/boat_view.gd picks it)."""
    rig = boat.rig
    if sail_type == "main":
        return BOOM
    if sail_type == "spinnaker_sym" or (sail_type == "spinnaker_asym" and rig.pole_flown and rig.sprit <= 0):
        return POLE
    if sail_type == "spinnaker_asym":
        return SPRIT
    return LUFF


def preview_poses(boat):
    """Every pose the previews draw on this boat: [(name, pose)]: the build's POSES whose sails the boat carries,
    and kite_preview's run and reach per flying-sail type."""
    from .kite_preview import SETS, set_pose
    kinds = {s.type for s in boat.sails.values()}
    out = [(n, p) for n, p in boat.POSES.items() if kinds & set(p["sails"]) - {"main"}]
    for t in sorted(kinds & set(SETS)):
        out += [(f"{t}_{pt}", set_pose(t, pt)) for pt in ("run", "reach")]
    return out


def write_sets(boat, path):
    """The preview poses as drawn (`<id>.sets.json`, body frame) for the game's parity test
    (game/tests/sail_visuals_test.gd): per pose the wind, and per set sail its sheet and pole angles (rad, the
    core's signs) and the placed mid-surface in grid order."""
    import json
    ox = boat.origin_x()
    sets = []
    for name, pose in preview_poses(boat):
        grids, shapes = set_sails(boat, pose)
        awa = np.radians(pose["awa"])
        side = -sgn(awa)
        sails = []
        for sid, G in grids.items():
            sails.append({"id": sid, "beta": round(side * np.radians(pose["sails"][boat.sails[sid].type]), 9),
                          "gamma": round(side * np.radians(pose.get("gamma", 0.0)), 9),
                          "ease": round(float(shapes[sid].ease), 6),
                          "mid": np.round(G.reshape(-1, 3) - [ox, 0.0, 0.0], 5).tolist()})
        sets.append({"name": name, "awa": round(float(awa), 9), "aws": float(pose.get("aws", 6.0)), "sails": sails})
    with open(path, "w") as f:
        json.dump({"schema": "windmark.boatgen.sets/1", "class_id": boat.cls["id"],
                   "frame": "body: x forward, y port, z up, m", "sets": sets}, f)
    return sets


def set_sails(boat, pose):
    """Place the sails of `pose` as the game draws them: {sail id: (rows, cols, 3) grid}.

    pose: {"awa": deg (sails to the side away from the wind), "aws": m/s, "gamma": deg (pole or tack line, to
    windward), "sails": {sail type: sheet angle deg}}; a sail whose type is not listed is down. The angles are
    magnitudes; the sign follows the wind side. The flying sails are placed last, clear of the others."""
    awa = np.radians(pose["awa"])
    side = -sgn(awa)                       # sails on the side away from the wind (beta > 0 = starboard)
    gamma = side * np.radians(pose.get("gamma", 0.0))   # the core's -sgn(awa) * pole_angle: to windward
    rp = rig_points(boat)
    L = boat.hull.L
    shapes, order = {}, []
    for sid, sail in boat.sails.items():
        if sail.type not in pose["sails"]:
            continue
        shapes[sid] = SailSet(sail.P, sail.type, sail.look(L), sail_mode(boat, sail.type), rp, L)
        order.append(sid)
    order.sort(key=lambda s: shapes[s].flying)
    for sid in order:
        sh = shapes[sid]
        beta = side * np.radians(pose["sails"][boat.sails[sid].type])
        obs = [shapes[o] for o in order if o != sid and not shapes[o].flying] if sh.flying else ()
        sh.update(beta, gamma if sh.mode in (SPRIT, POLE) else beta, awa, pose.get("aws", 6.0), obs)
    return {sid: shapes[sid].grid().copy() for sid in order}, shapes
