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
JIB_CAMBER = 0.135      # 6.2 k_j: a jib's or genoa's largest camber over chord, eased
JIB_FILL = 0.15         # 6.2 b_j: the fill at which it reaches tanh(1) of that
JIB_PROFILE_MAX = 2 * np.sqrt(3) / 9    # 6.2: the largest of x (1 - x) (2 - x), at x = 1 - 1/sqrt(3)
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


STOP_SCAN = 24          # 7.6: steps of the main's angle scanned out from the centreline
STOP_STEPS = 10         # 7.6: bisection steps of the main's stop
RUN_ON = 6.0            # 7.4: the last segment of an obstacle section runs on past its leech by this many clearances
PUSH_SLOPE = 0.3        # 7.4 k_p: the local push falls off by this much per metre of cloth
PUSH_EASE = 2.0         # 7.4 P_e: the ease starts where the leech is deeper than this many clearances
EASE_MAX = 0.35         # 7.4 e_max: the largest ease, rad
STAY_CLEAR = 0.25       # 7.4 c_s: margin forward of the forestay for a kite on a pole, of the foretriangle base
SYM_SAG = 0.35          # 6.4: the belly of a symmetric spinnaker's foot sags down by this share of its depth ...
SYM_SAG_H = 0.35        # ... fading out over this lower share of the height
SYM_ENDS = 0.3          # 6.4: a symmetric spinnaker keeps its full camber from the foot to mid height, 1 - this at the head
STAY_HEAD = 0.3         # 7.4: the stay's shift fades to none over this top fraction of the height
STAY_LEECH = 0.3        # 7.4: ... and fades to 1 - this of it at the leech (the clew stays nearer its sheet)
STAY_LUFF = 0.5         # 7.4: the stay's shift is taken in full from this chord fraction aft of the luff
STAY_WIDTH = 0.6        # 7.4 w_s: half width of the forestay's wall for a kite on a pole, of the foretriangle base
CLEW_REACH = 2          # 7.7: the grid steps from the clew that give the foot and leech directions
CLEW_H = 0.3            # 7.7: the clew's draw-in and draw-down fade out at this share of the height
CLEW_KD = (-0.1, 0.25)  # 7.7: bounds of the draw-in k_d (share of the row's chord)
CLEW_KL = (-0.1, 0.3)   # 7.7: bounds of the draw-down k_l (share of the foot's chord)
CLEW_STEP = 0.01        # 7.7: the difference step of the solve
CLEW_ITER = 2           # 7.7: Newton steps of the solve
CLEW_FADE = (np.radians(75.0), np.radians(105.0))  # 7.7: the clew set fades out as |beta| goes round the bow
CLEW_AWA = (np.radians(45.0), np.radians(65.0))    # 7.7: and in with the AWA, over the kite's lowest angles
CURL_BAND = 0.25        # 4.1: the luff and leech curl reach this share of the chord in from the edge
HOLD = 0.35             # 4.1: `forward` holds the corners over this share of Sl
TACK_REACH = 0.5        # 4.1: `tack_rise` fades out over this share of Sl from the tack
LOFT_SIDE = 0.1         # 6.5: the lofted belly crosses to the other side as sin(beta + awa) passes +-this
LOFT_EASE_MAX = 0.5     # 6.5: the largest turn of a lofted kite off the main, the jib and the mast, rad
LOFT_STAY_MAX = 1.8     # 6.5: ... of a lofted kite on a pole, which also keeps ahead of the forestay, rad
LOFT_STAY_CLEAR = 0.04  # 6.5: ... by this share of the foretriangle base (the hard rule)
LOFT_EASE_STEPS = 12     # 6.5: steps of that turn's solve
LOFT_FADE = (0.1, np.radians(100.0), np.radians(60.0))  # 6.5: |beta| over which the turn fades in from the
#                         centreline, and from where and over how much it fades out round the bow
LOFT_MARGIN = 1.2       # 6.5: the turn keeps this many margins (horizontal) so the true distance keeps one
LOFT_NEAR = 2.0         # 6.5: after its first step, the solve looks only at vertices this many clearances near the worst

# 4.1: the kite set parameters (visual.sails.<id>.set) by kite type: the shape constants of 6.3, 6.4, 7.3, 7.4, 7.7
_SET_COMMON = {"draft_from_h": 0.55, "belly_aft": 0.5, "belly_up": 0.5, "twist_awa_lo": float(np.radians(60.0)),
               "twist_awa_hi": float(np.radians(130.0)), "twist_run": float(np.radians(25.0)), "foot_sag_h": 0.35,
               "girth_foot": 1.0, "girth_mid": 1.0, "girth_head": 1.0, "luff_curl": 0.0, "leech_curl": 0.0,
               "head_drop": 0.0, "clew_lift": 0.0, "clew_out": 0.0, "clew_h": 0.3, "forward": 0.0, "tack_rise": 0.0,
               "stay_clear": 0.25, "stay_width": 0.6, "stay_head": 0.3, "stay_luff": 0.5, "stay_leech": 0.3,
               "loft_depth": 1.0, "loft_trim": 0.0}
# 4.1, 6.5: the kite's shape model (`hinge`: the shapes of 6.3, 6.4 placed by 7.3 to 7.7; `loft`: the lofted
# shapes of 6.5) and, for a loft, the kite shape file it is lofted from; strings, not numbers
SET_STRINGS = {"model": "hinge", "shape": ""}
SET_DEFAULTS = {
    "spinnaker_asym": dict(_SET_COMMON, depth_peak_h=0.3, depth_foot=0.8, depth_head=0.45,
                           draft_low=0.5 ** (1 / 0.8), draft_head=0.5 ** (1 / 1.4), twist_exp=2.5, foot_sag=0.0),
    "spinnaker_sym": dict(_SET_COMMON, depth_peak_h=0.5, depth_foot=1.0, depth_head=0.7, draft_low=0.5,
                          draft_head=0.5, twist_exp=1.5, foot_sag=0.35),
}


def set_params(sail_type, given=None):
    """4.1: the kite's set parameters, `given` over the defaults of its type ({} for any other sail)."""
    if sail_type not in SET_DEFAULTS:
        return {}
    d = dict(SET_DEFAULTS[sail_type], **SET_STRINGS)
    d.update({k: (str(v) if k in SET_STRINGS else float(v)) for k, v in (given or {}).items()})
    return d


def smoothstep01(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def smoothstep_v(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def smax(x, b):
    if x >= b:
        return x
    if x <= -b:
        return 0.0
    return (x + b) * (x + b) / (4 * b)


def asym_height(h, peak=0.3, foot=0.8, head=0.45):
    """6.3, 4.1: a kite's camber over its largest by row height h: deepest at `peak` of the height, `foot` on the
    foot, `head` at the head (asymmetric defaults: 0.3, 0.8, 0.45)."""
    h = np.asarray(h, dtype=np.float64)
    lo = (peak - h) / peak
    hi = (h - peak) / (1 - peak)
    return np.where(h < peak, 1 - (1 - foot) * lo * lo, 1 - (1 - head) * hi * hi)


def asym_draft(h, low=0.5 ** (1 / 0.8), head=0.5 ** (1 / 1.4), from_h=0.55):
    """6.3, 4.1: the exponent of the chordwise profile by row height: the draft at `low` of the chord up to
    `from_h` of the height, moving to `head` at the head (asymmetric defaults: exponents 0.8 and 1.4, drafts 0.42
    and 0.61, from 0.55)."""
    h = np.asarray(h, dtype=np.float64)
    ql, qh = np.log(0.5) / np.log(low), np.log(0.5) / np.log(head)
    t = np.clip((h - from_h) / (1 - from_h), 0.0, 1.0)
    return ql + (qh - ql) * t * t * (3 - 2 * t)


def asym_profile(uc, q):
    """6.3: the chordwise camber profile sin(pi uc^q), 0 at the luff and the leech, 1 at the draft."""
    return np.sin(np.pi * np.power(np.clip(uc, 0.0, 1.0), q))


def asym_twist_h(h):
    """7.3: the asymmetric spinnaker's twist over its largest by row height h: 1 - (1 - h)^2.5 (a finite slope at
    the foot, 0.37 at a sixth of the height, 0.82 at half, 0.99 at five sixths)."""
    return 1.0 - np.power(1.0 - np.clip(np.asarray(h, dtype=np.float64), 0.0, 1.0), 2.5)


def asym_twist(awa, lo=np.radians(60.0), hi=np.radians(130.0), run=np.radians(25.0)):
    """7.3, 4.1: the share of twist_top an asymmetric spinnaker carries at the apparent wind angle awa: none to
    `lo` (60 deg), all from `hi` (130 deg) to `run` (25 deg) short of a run, none again dead downwind (180 deg), so a
    gybe round the bow passes untwisted."""
    t = min(max((abs(awa) - lo) / (hi - lo), 0.0), 1.0)
    r = min(max((np.pi - abs(awa)) / run, 0.0), 1.0)
    return t * t * (3 - 2 * t) * r * r * (3 - 2 * r)


class SailSet:
    """One sail: configure from the flat grid and the look, then `update` places it (mid-surface in `self.mid`)."""

    def __init__(self, P, sail_type, look, mode, rig, loa, kset=None, loft=None):
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
        # 4.1: the kite's set parameters (the defaults of its type for any key not given)
        self.ks = ks = set_params(sail_type, kset)
        self.crow = np.clip(1.0 - self.hrow / ks.get("clew_h", CLEW_H), 0.0, 1.0) ** 3  # 7.7: the clew set's fade
        if ks:
            hr = self.hrow
            gm = ks["girth_mid"]
            self.grow = np.where(hr < 0.5, gm + (ks["girth_foot"] - gm) * (1 - 2 * hr) ** 2,
                                 gm + (ks["girth_head"] - gm) * (2 * hr - 1) ** 2)
            dT = np.linalg.norm(Q - Q[0], axis=-1)
            dH = np.linalg.norm(Q - Q[(rows - 1) * cols], axis=-1)
            dC = np.linalg.norm(Q - Q[cols - 1], axis=-1)
            R = HOLD * self.sl
            self.hold = smoothstep_v(dT / R) * smoothstep_v(dH / R) * smoothstep_v(dC / R)
            self.rise_w = (1.0 - np.minimum(dT / (TACK_REACH * self.sl), 1.0)) ** 2
        else:
            self.grow = np.ones(rows)
        self.kd = self.kl = 0.0
        dh = self.tack - self.head
        self.r_h = max(np.linalg.norm(dh - UP * (dh @ UP)), 1e-3)
        self.mid = Q.copy()
        self.loc = np.stack([self.a, self.l, np.zeros_like(self.a)], -1)
        self.ease = 0.0
        self.trow = np.zeros(rows)
        self.push_max = 0.0     # the largest local push of the last update (7.4), m
        self.rest_q = Q.copy()
        self.lead = None if rig.get("flying_lead") is None else np.asarray(rig["flying_lead"], dtype=np.float64)
        # 7.4: a flying sail on a pole also keeps forward of the forestay (tack fitting to hounds)
        self.stay = None
        if self.flying and mode == POLE and rig.get("forestay_tack") is not None:
            f0 = np.asarray(rig["forestay_tack"], dtype=np.float64)
            f1 = np.asarray(rig["hounds"], dtype=np.float64)
            dm = f0 - self.mast_step
            jb = np.linalg.norm(dm - self.mast_axis * (dm @ self.mast_axis))   # the foretriangle base
            self.stay = (f0, f1, ks.get("stay_width", STAY_WIDTH) * jb,
                         max(ks.get("stay_clear", STAY_CLEAR) * jb, self.clearance))
        # 6.5: a lofted kite, on a pole or a sprit, keeps ahead of the forestay (the hard rule): (tack fitting, hounds,
        # margin)
        self.loft_stay = None
        self.stay_on = True
        if self.flying and self.clearance > 0 and rig.get("forestay_tack") is not None and rig.get("hounds") is not None:
            f0 = np.asarray(rig["forestay_tack"], dtype=np.float64)
            f1 = np.asarray(rig["hounds"], dtype=np.float64)
            dm = f0 - self.mast_step
            self.loft_stay = (f0, f1, LOFT_STAY_CLEAR * np.linalg.norm(dm - self.mast_axis * (dm @ self.mast_axis)))
        self.tack_at = self.tack.copy()
        self._secs = []
        # 7.4: distances between grid neighbours on the rest cloth (along a row, up a column, the two diagonals)
        E = Q.reshape(rows, cols, 3)
        self._ec = np.linalg.norm(E[:, 1:] - E[:, :-1], axis=-1)
        self._er = np.linalg.norm(E[1:] - E[:-1], axis=-1)
        self._e1 = np.linalg.norm(E[1:, 1:] - E[:-1, :-1], axis=-1)
        self._e2 = np.zeros((rows - 1, cols))
        self._e2[:, 1:] = np.linalg.norm(E[1:, :-1] - E[:-1, 1:], axis=-1)
        # 6.5: a lofted kite's shapes by AWA (the sidecar's `loft` block), when its set block picks the loft
        self.loft_awa = self.loft_shapes = None
        if ks and ks.get("model") == "loft" and loft is not None:
            self.loft_awa = np.asarray(loft["awa"], dtype=np.float64)
            self.loft_shapes = np.asarray(loft["shapes"], dtype=np.float64).reshape(len(self.loft_awa), -1, 3)
        self.turn = 0.0

    # ------------------------------------------------------------------ shape and placement (7, 6.1 to 6.4)

    def update(self, beta, gamma, awa, aws, obstacles=()):
        rows, cols = self.rows, self.cols
        self.beta = beta
        if self.loft_awa is not None:
            return self._loft_update(beta, gamma, awa, aws, obstacles)
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
            loc = np.stack([a, l, self._head_n(u, D)], -1)
        else:
            if self.kind == SYM:
                F = abs(fill(np.sin(beta), self.fill_gain, self.fill_curve))
            else:
                F = self.fill_gain * min(max(aws / KNOT, 3.0), 6.0) / 6.0
            uw = FWD * np.cos(awa) - PORT * np.sin(awa)
            ks = self.ks
            w = np.array([uw @ ap * ks["belly_aft"] / self.fill_curve, uw @ lp * ks["belly_up"], uw @ np_])
            w = w / np.linalg.norm(w) if w @ w > 1e-12 else np.array([0, 0, 1.0])
            fc = self.camber * min(F, 1.15)
            i = np.repeat(np.arange(rows), cols)
            # 6.3, 6.4, 4.1: the camber by height (the symmetric defaults: full depth from the foot to mid height)
            drow = fc * asym_height(self.hrow, ks["depth_peak_h"], ks["depth_foot"], ks["depth_head"])
            q = asym_draft(self.hrow, ks["draft_low"], ks["draft_head"], ks["draft_from_h"])[i]
            if self.kind == ASYM:
                prof = asym_profile(self.uc, q)
            else:
                x = np.power(self.uc, q)
                prof = 4 * x * (1 - x)
            fh = 4 * self.hrow[i] * (1 - self.hrow[i])         # 4.1: the edge curls, none at the corners
            prof = prof + ks["luff_curl"] * np.clip(1 - self.uc / CURL_BAND, 0.0, 1.0) ** 2 * fh \
                + ks["leech_curl"] * np.clip(1 - (1 - self.uc) / CURL_BAND, 0.0, 1.0) ** 2 * fh
            a0 = a.reshape(rows, cols)[:, 0][i]
            self._fly_args = (drow, prof, w, a0, i)
            loc = self._fly(0.0, 0.0)
        # 7.1 to 7.3: the twist of each row toward leeward (an asymmetric spinnaker: opening with the AWA)
        # (signed, rad; the asymmetric spinnaker's on the side away from the wind at once: it is zero where awa
        # changes sign)
        if self.kind == ASYM:
            ks = self.ks
            self.trow = -sgn(awa) * self.twist_top * asym_twist(awa, ks["twist_awa_lo"], ks["twist_awa_hi"],
                                                                ks["twist_run"]) * \
                (1.0 - np.power(1.0 - np.clip(self.hrow, 0.0, 1.0), ks["twist_exp"]))
        else:
            self.trow = tl * self.twist_top * self.hrow ** (self.ks["twist_exp"] if self.kind == SYM else 1.5)
        self.loc = loc
        ks = self.ks
        hd = s_t(self.head - self.lh * (ks.get("head_drop", 0.0) * self.sl))   # 4.1: the head as dropped
        self.tack_at = s_t(self.tack)           # 7.4: the margin fades out at the tack as at the head
        clearing = self.clearance > 0
        self.ease = 0.0
        if clearing and obstacles:
            self._sections(obstacles, s_t, piv, ax, base, tl)
            self.ease = self._ease_for(beta, s_t, piv, ax, base, hd, tl)
        else:
            self._secs = []
        es = sgn(beta) * self.ease
        # 7.7: the clew set by its sheet (with the sail as eased)
        self.kd = self.kl = 0.0
        if self.kind == ASYM and self.lead is not None:
            g = (1.0 - smoothstep01((abs(wrap_pi(beta)) - CLEW_FADE[0]) / (CLEW_FADE[1] - CLEW_FADE[0]))) * \
                smoothstep01((abs(awa) - CLEW_AWA[0]) / (CLEW_AWA[1] - CLEW_AWA[0]))
            if g > 0.0:
                kd, kl = self._clew_set(beta, base + es, piv, ax, s_t)
                self.kd, self.kl = g * kd, g * kl
            self.loc = loc = self._fly(self.kd, self.kl)
        mid = np.empty_like(self.mid)
        rest = self.tack + loc[:, :1] * self.ah + loc[:, 1:2] * self.lh + loc[:, 2:] * self.nh
        for r in range(rows):
            th = base + self.trow[r] + es
            xr = Xf.about(piv, ax, th) * s_t
            mid[r * cols:(r + 1) * cols] = xr(rest[r * cols:(r + 1) * cols])
        self.mid = mid
        self.clew0 = mid[cols - 1].copy()      # 7.6: the clew as placed, before the clearance push
        if ks and ks["forward"] != 0.0:         # 4.1: projected forward, the corners held
            self.mid = self.mid + FWD[None] * (ks["forward"] * self.sl * self.hold)[:, None]
        if ks and ks["tack_rise"] != 0.0:       # 4.1: the tack raised
            r = ks["tack_rise"] * self.sl
            self.mid = self.mid + UP[None] * (r * self.rise_w)[:, None]
            self.tack_at = self.tack_at + UP * r
        if self.stay is not None:
            self._stay()
        if clearing:
            self._push(awa, hd)
        return self.mid

    # ------------------------------------------------------------------ the lofted kite (6.5)

    def loft_local(self, awa, aws, beta):
        """6.5: the lofted shape's local position of every vertex (a, l, n in the sail frame, up, no flutter): the
        measured shapes blended by the AWA, the depth by the fill and `loft_depth`, the belly on the side the wind
        blows it to."""
        A, S = self.loft_awa, self.loft_shapes
        x = abs(wrap_pi(awa))
        if x <= A[0]:
            L = S[0]
        elif x >= A[-1]:
            L = S[-1]
        else:
            m = int(np.searchsorted(A, x, side="right")) - 1
            t = smoothstep01((x - A[m]) / (A[m + 1] - A[m]))
            L = S[m] + (S[m + 1] - S[m]) * t
        F = min(self.fill_gain * min(max(aws / KNOT, 3.0), 6.0) / 6.0, 1.0)
        D = F * self.ks["loft_depth"]
        sd = min(max(np.sin(wrap_pi(beta + awa)) / LOFT_SIDE, -1.0), 1.0)
        side = sd * (3.0 - sd * sd) / 2.0
        flat = np.stack([self.a, self.l, np.zeros_like(self.a)], -1)
        loc = flat + (L - flat) * D
        loc[:, 2] *= side
        return loc

    def _loft_update(self, beta, gamma, awa, aws, obstacles):
        rows, cols = self.rows, self.cols
        s_t = Xf()
        ge = 0.0
        if self.mode == SPRIT:
            lim = np.arcsin(min(1.0, self.tack_line_max * self.sl / self.r_h))
            ge = sgn(gamma) * min(abs(gamma), lim)
            s_t = Xf.about(self.head, UP, ge)
        elif self.mode == POLE:
            ge = gamma
            s_t = Xf.about(self.mast_step, self.mast_axis, ge)
        piv = s_t(self.tack)
        ax = s_t.R @ self.lh
        ax = ax / np.linalg.norm(ax)
        loc = self.loft_local(awa, aws, beta)
        self.loc = loc
        wb = abs(wrap_pi(beta))     # the trim and the turn off the obstacles fade out where sgn(beta) flips
        es = sgn(beta) * smoothstep01(wb / LOFT_FADE[0]) * (1.0 - smoothstep01((wb - LOFT_FADE[1]) / LOFT_FADE[2]))
        th = beta - ge + es * self.ks["loft_trim"]
        self.turn = th
        self.trow = np.zeros(rows)
        self.kd = self.kl = 0.0
        hd = s_t(self.head)
        self.tack_at = piv.copy()
        rest = self.tack + loc[:, :1] * self.ah + loc[:, 1:2] * self.lh + loc[:, 2:] * self.nh
        self.ease = 0.0
        self.push_max = 0.0
        if self.clearance > 0:
            if obstacles:
                self._sections(obstacles, s_t, piv, ax, th, -sgn(awa))
            else:
                self._secs = []
            self.stay_on = wb <= LOFT_FADE[1]     # not while an asymmetric goes round the bow in a gybe
            self.ease = self._loft_ease(es, s_t, piv, ax, th, hd, rest, -sgn(awa))
        self.mid = (Xf.about(piv, ax, th + es * self.ease) * s_t)(rest)
        self.clew0 = self.mid[cols - 1].copy()
        return self.mid

    def loft_clear(self, pts, hd, lee, idx):
        """6.5: the clearance over its margin of each of the points `idx` (the obstacles' sections and the mast; inf
        when none is near)."""
        out = np.full(len(idx), np.inf)
        for q, k in enumerate(idx):
            p = pts[k]
            cp = LOFT_MARGIN * self._margin(p, hd)
            x = self._mast_x(p, lee)[0] - cp
            for o in self._secs:
                x = min(x, self._clear_x(o, p, cp)[0] - cp)
            if self.loft_stay is not None and self.stay_on:
                x = min(x, self._stay_x(p) - self.loft_stay[2])
            out[q] = x
        return out

    def _stay_x(self, p):
        """6.5: how far the point p lies ahead of the forestay (a wall of the stay's half width either side of it,
        between its tack fitting and the hounds; inf beside or above it)."""
        f0, f1 = self.loft_stay[0], self.loft_stay[1]
        w = LOFT_NEAR * self.clearance
        z0, z1 = f0[2], f1[2]
        if not z0 <= p[2] <= z1:
            return np.inf
        q = f0 + (f1 - f0) * ((p[2] - z0) / (z1 - z0))
        if abs((p - q) @ PORT) > w:
            return np.inf
        return float((p - q) @ FWD)

    def _loft_ease(self, es_f, s_t, piv, ax, th, hd, rest, tl):
        """6.5: the kite turned as a whole about its luff, away from the centreline, just far enough that no vertex
        is inside the clearance margin of the main, the jib or the mast, or behind the forestay (at most
        LOFT_EASE_MAX, LOFT_STAY_MAX with the forestay), solved as it is drawn: es_f, the out side times the fade
        where sgn(beta) flips."""
        return self._loft_turn(1.0, es_f, s_t(rest), piv, ax, th, hd, tl)[0]

    def _loft_turn(self, dirn, es_f, q, piv, ax, th, hd, tl):
        """6.5: the turn's solve one way (dirn +1 out): (the turn, rad, >= 0; the worst clearance over its margin
        there, >= 0 when clear). After the first step only the vertices then within LOFT_NEAR clearances of the
        worst are looked at again, but with the forestay every vertex (the whole kite may come round it)."""
        es, delta = es_f * dirn, 0.0
        if abs(es_f) < 0.05:
            return 0.0, 0.0
        lee = -PORT * tl
        cap = LOFT_EASE_MAX if self.loft_stay is None else LOFT_STAY_MAX
        idx = np.arange(len(q))
        left = np.inf
        for it in range(LOFT_EASE_STEPS + 1):
            pts = Xf.about(piv, ax, th + es * delta)(q)
            x = self.loft_clear(pts, hd, lee, idx)
            j = int(np.argmin(x))
            worst = float(x[j])
            left = worst
            if not worst < 0.0 or it == LOFT_EASE_STEPS or delta >= cap:
                break
            at = idx[j]
            if it == 0 and self.loft_stay is None:
                idx = idx[x < worst + LOFT_NEAR * self.clearance]
            d = pts[at] - piv
            r = np.linalg.norm(d - ax * (d @ ax))
            delta = min(delta + (-worst) / (max(r, 0.5) * abs(es)), cap)
        return delta, left

    def _fly(self, kd, kl, k=None):
        """6.3, 6.4 (up, no flutter) with the clew set of 7.7 (draw-in kd, draw-down kl; 0 for none): the local
        position of every vertex, or of the vertices `k`."""
        drow, prof, w, a0, i = self._fly_args
        a, l, uc = self.a, self.l, self.uc
        if k is not None:
            a, l, uc, prof, a0, i = a[k], l[k], uc[k], prof[k], a0[k], i[k]
        ks = self.ks
        h = self.h if k is None else self.h[k]
        srow = 1 / (1 + 8 / 3 * drow * drow)
        if kd != 0.0 or kl != 0.0:
            srow = np.minimum(srow * (1 - kd * self.crow), 1.0)
            drow = np.sqrt(np.maximum(1 / srow - 1, 0.0) * 3 / 8)       # the cloth keeps its length
        cu = self.C[0] * self.crow[i] * uc * uc
        l = l - (kl - ks["clew_lift"]) * cu - ks["head_drop"] * self.sl * h      # 7.7 draw-down, 4.1 clew and head
        s = srow[i]
        g = self.grow[i]
        e = drow[i] * s * g * self.C[i] * prof
        # 6.4, 4.1: the lower panels' belly sags, so the foot curves round and down
        l = l - ks["foot_sag"] * e * np.clip(1.0 - self.hrow[i] / ks["foot_sag_h"], 0.0, 1.0) ** 2
        a_s = a0 + (a - a0) * s * g + ks["clew_out"] * cu
        return np.stack([a_s, l, np.zeros_like(a)], -1) - e[:, None] * w[None]

    def _clew_set(self, beta, base, piv, ax, s_t):
        """7.7: the draw-in and draw-down (kd, kl) that lay the clew's bisector on the sheet: two Newton steps from
        (0, 0) with difference derivatives, each clamped to its bounds."""
        cols = self.cols
        idx = np.array([cols - 1, cols - 1 - CLEW_REACH, CLEW_REACH * cols + cols - 1])
        xr = [Xf.about(piv, ax, base + self.trow[r]) * s_t for r in (0, 0, CLEW_REACH)]
        B = np.array([self.lead[0], -sgn(beta) * abs(self.lead[1]), self.lead[2]])

        def corner(kd, kl):
            lc = self._fly(kd, kl, idx)
            C, F, E = (x(self.tack + self.ah * q[0] + self.lh * q[1] + self.nh * q[2]) for x, q in zip(xr, lc))
            f, e = F - C, E - C
            b = f / np.linalg.norm(f) + e / np.linalg.norm(e)
            return b / np.linalg.norm(b), (C - B) / np.linalg.norm(C - B)

        b, s = corner(0.0, 0.0)
        u1 = np.cross(s, UP)
        if u1 @ u1 < 1e-12:
            u1 = np.cross(s, FWD)
        u1 = u1 / np.linalg.norm(u1)
        u2 = np.cross(u1, s)

        def res(kd, kl):
            b, s = corner(kd, kl)
            return np.array([(b - s) @ u1, (b - s) @ u2])
        kd = kl = 0.0
        h = CLEW_STEP
        for _ in range(CLEW_ITER):
            r0 = res(kd, kl)
            j0, j1 = (res(kd + h, kl) - r0) / h, (res(kd, kl + h) - r0) / h
            det = j0[0] * j1[1] - j1[0] * j0[1]
            if abs(det) < 1e-9:
                break
            kd = min(max(kd - (j1[1] * r0[0] - j1[0] * r0[1]) / det, CLEW_KD[0]), CLEW_KD[1])
            kl = min(max(kl - (-j0[1] * r0[0] + j0[0] * r0[1]) / det, CLEW_KL[0]), CLEW_KL[1])
        return kd, kl

    def sheet_line(self, beta):
        """7.6: the working sheet as a straight line: (the placed clew, the lead on the side of beta)."""
        return self.clew0.copy(), np.array([self.lead[0], -sgn(beta) * abs(self.lead[1]), self.lead[2]])

    def grid(self):
        return self.mid.reshape(self.rows, self.cols, 3)

    def _head_n(self, u, D):
        """6.2: the headsail's offset off its rest plane (up shape, no flutter); u per vertex."""
        if self.cam_cap > 0:
            return 0.5 * D * (u ** 4 - C_HOOK * u)
        rows, cols = self.rows, self.cols
        U = u.reshape(rows, cols)
        u0, ul = U[:, :1], U[:, -1:]
        x = np.clip((U - u0) / np.maximum(ul - u0, 1e-3), 0.0, 1.0)
        nl = 0.5 * D * (ul ** 4 - C_HOOK * ul)
        b = np.sqrt(abs(D) / (4 * self.sa))
        m = sgn(D) * JIB_CAMBER * np.tanh(b / JIB_FILL)
        hh = 2 * self.hrow[:, None] - 1
        p = 1 - 0.15 * hh * hh
        g = x * (1 - x) * (2 - x) / JIB_PROFILE_MAX
        return (nl * x - m * p * self.C[:, None] * g).reshape(-1)

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
        reach = reach + RUN_ON * self.clearance     # the bounds cover the leech's run-on (7.4)
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
            # the last segment runs on past the leech by RUN_ON clearances (7.4)
            hi = 1.0 + RUN_ON * self.clearance / np.sqrt(l2) if j == cn - 2 and l2 > 1e-12 else 1.0
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

    def _stay(self):
        """7.4: a flying sail on a pole flies forward of the forestay: per row the shift forward that brings its
        cloth within the stay's half width at least c_s ahead of the stay, the largest of its own and the rows'
        above (so it grows down to the foot), faded out over the top STAY_HEAD of the height, and taken in full at the middle of the chord, fading to none at the luff
        and to 1 - STAY_LEECH of it at the leech; the head row stays at the halyard."""
        f0, f1, w, cs = self.stay
        rows, cols = self.rows, self.cols
        M = self.mid.reshape(rows, cols, 3)
        uc = self.uc.reshape(rows, cols)
        ks = self.ks
        sl, sle, shd = ks.get("stay_luff", STAY_LUFF), ks.get("stay_leech", STAY_LEECH), ks.get("stay_head", STAY_HEAD)
        sw = smoothstep_v(uc / sl) * (1.0 - sle * smoothstep_v((uc - sl) / (1.0 - sl)))
        D = np.zeros(rows)
        for i in range(rows - 1):
            for j in range(cols):
                p = M[i, j]
                if p[2] < f0[2] or p[2] > f1[2] or sw[i, j] < 0.25:
                    continue
                q = f0 + (f1 - f0) * ((p[2] - f0[2]) / (f1[2] - f0[2]))
                dy = abs((p - q) @ PORT)
                k = 1.0 - smoothstep01((dy - w) / cs)
                d = (cs - (p - q) @ FWD) * k
                if d > 0:
                    D[i] = max(D[i], d / max(sw[i, j], 0.5))
        S = D.copy()            # never less than a row above needs: the shift grows down to the foot
        for i in range(rows - 2, -1, -1):
            S[i] = max(S[i], S[i + 1])
        S = S * smoothstep_v((1.0 - self.hrow) / shd)           # the head stays at the halyard
        self.stay_max = float(S.max())
        M += FWD[None, None] * (S[:, None] * sw)[..., None]
        self.mid = M.reshape(-1, 3)

    def _margin(self, p, hd):
        return self.clearance * smoothstep01(np.linalg.norm(p - hd) / (5 * self.clearance)) * \
            smoothstep01(np.linalg.norm(p - self.tack_at) / (5 * self.clearance))

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
    from .running import sheet_leads
    return {"boom_pivot": np.asarray(rig.gooseneck, dtype=np.float64), "boom_axis": UP,
            "mast_step": np.array([rig.x_mast, 0.0, rig.z_step]), "masthead": np.array([rig.x_mast, 0.0, rig.z_top]),
            "flying_lead": sheet_leads(boat)["flying"]["lead"],
            "forestay_tack": np.array([rig.x_tack, 0.0, rig.z_tack]),
            "hounds": np.array([rig.x_mast + rig.chord / 2, 0.0, rig.z_hounds])}


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


def nominal_pole_angle(boat, sail_id, awa):
    """6.5: the pole's angle (rad, a magnitude) at the AWA awa: the sail's pole angle table at 12 kn true wind from the
    class's performance file, else the nominal sheet angle (the core's pole follows the sheet without a table)."""
    import json
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "data", "perf",
                        f"{boat.cls['id']}.perf.json")
    try:
        with open(path) as f:
            t = json.load(f)["sails"][sail_id]["pole_angle"]
        tws, aw = (np.asarray(x["points"], dtype=np.float64) for x in t["axes"])
        v = np.asarray(t["values"], dtype=np.float64).reshape(len(tws), len(aw))
        col = np.array([np.interp(12.0 * KNOT, tws, v[:, k]) for k in range(len(aw))])
        return float(np.interp(abs(awa), aw, col))
    except (OSError, KeyError, ValueError):
        return nominal_kite_angle(boat, sail_id, awa)


def nominal_kite_angle(boat, sail_id, awa):
    """6.5: the kite's sheet angle (rad, a magnitude) at the apparent wind angle awa that the loft's clew hook is
    solved for: the class's optimum at 12 kn true wind from its performance file (data/perf/<id>.perf.json, the
    configuration with this sail in front), else |awa| - 48 deg within 15 to 64 deg."""
    import json
    import os
    a = abs(awa)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "data", "perf",
                        f"{boat.cls['id']}.perf.json")
    try:
        with open(path) as f:
            perf = json.load(f)
        cfg = next(c for c in perf["configs"] if c.get("front_sail") == sail_id)
        t = cfg["optimal_angle"][sail_id]
        tws, aw = (np.asarray(x["points"], dtype=np.float64) for x in t["axes"])
        v = np.asarray(t["values"], dtype=np.float64).reshape(len(tws), len(aw))
        w = 12.0 * KNOT
        col = np.array([np.interp(w, tws, v[:, k]) for k in range(len(aw))])
        return float(np.interp(a, aw, col))
    except (OSError, StopIteration, KeyError, ValueError):
        return float(min(max(a - np.radians(48.0), np.radians(15.0)), np.radians(64.0)))


def loft_place(boat, sail):
    """6.5: for kite_loft.loft, the kite lofted as `loc` set alone at its nominal trim for the AWA (wind from
    starboard, full, no flutter): (its placed grid (rows, cols, 3), the working lead block of its sheet)."""
    rp = rig_points(boat)
    L = boat.hull.L
    sid = next(k for k, v in boat.sails.items() if v is sail)
    lead = rp["flying_lead"]

    mode = sail_mode(boat, sail.type)

    def place(awa, loc):
        beta = -nominal_kite_angle(boat, sid, awa)
        gamma = -nominal_pole_angle(boat, sid, awa) if mode == POLE else 0.0
        sh = SailSet(sail.P, sail.type, sail.look(L), mode, rp, L,
                     dict(sail.set_override, model="loft"), {"awa": [awa], "shapes": [loc]})
        sh.update(beta, gamma, awa, 8.0, ())
        return sh.grid().copy(), np.array([lead[0], -sgn(beta) * abs(lead[1]), lead[2]])
    return place


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
        shapes[sid] = SailSet(sail.P, sail.type, sail.look(L), sail_mode(boat, sail.type), rp, L,
                              sail.set_override, sail.loft_block(boat))
        order.append(sid)
    order.sort(key=lambda s: shapes[s].flying)
    aws = pose.get("aws", 6.0)
    betas = {sid: side * np.radians(pose["sails"][boat.sails[sid].type]) for sid in order}

    def place(sid):
        sh = shapes[sid]
        obs = [shapes[o] for o in order if o != sid and not shapes[o].flying] if sh.flying else ()
        sh.update(betas[sid], gamma if sh.mode in (SPRIT, POLE) else betas[sid], awa, aws, obs)
    for sid in order:
        place(sid)
    # 7.6: the main stops on a flying sail's sheet (its clew as placed); then the flying sails again round it
    main = next((o for o in order if shapes[o].kind == MAIN), None)
    fly = next((o for o in order if shapes[o].kind in (ASYM, SYM)), None)
    if main is not None and fly is not None and shapes[fly].lead is not None:
        core = betas[main]
        for _ in range(3):      # the game reads the clew as last placed: a few updates settle it
            betas[main] = main_stop(shapes[main], core, shapes[fly].sheet_line(betas[fly]), shapes[fly].clearance)
            for sid in order:
                place(sid)
    return {sid: shapes[sid].grid().copy() for sid in order}, shapes


def main_stop(main, beta, sheet, c, w=1.0):
    """7.6: the main's drawn angle with a flying sail's sheet (clew, lead) set: eased out from the centreline, the
    main stops where its region first comes within c of the straight sheet (at most |beta|); w (0..1) blends it in."""
    clew, lead = sheet
    if w <= 0 or c <= 0:
        return beta
    g = main.boom_pivot
    up = main.boom_axis / np.linalg.norm(main.boom_axis)
    rest = main.rest_q
    d = rest - g
    d = d - np.outer(d @ up, up)
    foot = d[main.cols - 1]
    aft = foot / max(float(np.linalg.norm(foot)), 1e-6)
    span = float((d @ aft).max())                       # the farthest the rest sail reaches aft (the roach)
    z1 = float((rest[(main.rows - 1) * main.cols] - g) @ up)
    z0 = -float((rest[0] - g) @ up)                     # the boom's underside
    sb = sgn(beta)
    b = abs(beta)

    def gap(th):
        return rect_gap(clew - g, lead - g, rot(up, sb * th) @ aft, up, span, z0, z1)
    lo = hi = None
    for k in range(1, STOP_SCAN + 1):
        th = b * k / STOP_SCAN
        if gap(th) < c:
            lo, hi = b * (k - 1) / STOP_SCAN, th
            break
    if lo is None:
        return beta
    for _ in range(STOP_STEPS):
        m = 0.5 * (lo + hi)
        if gap(m) >= c:
            lo = m
        else:
            hi = m
    return sb * (b - w * (b - lo))


def seg_seg(p0, p1, q0, q1):
    """Distance between the segments p0-p1 and q0-q1."""
    d1, d2, r = p1 - p0, q1 - q0, p0 - q0
    a, e, f = d1 @ d1, d2 @ d2, d2 @ r
    if a <= 1e-12 and e <= 1e-12:
        return float(np.linalg.norm(r))
    if a <= 1e-12:
        s, t = 0.0, min(max(f / e, 0.0), 1.0)
    else:
        cc = d1 @ r
        if e <= 1e-12:
            t, s = 0.0, min(max(-cc / a, 0.0), 1.0)
        else:
            bb = d1 @ d2
            den = a * e - bb * bb
            s = min(max((bb * f - cc * e) / den, 0.0), 1.0) if den > 1e-12 else 0.0
            t = (bb * s + f) / e
            if t < 0:
                t, s = 0.0, min(max(-cc / a, 0.0), 1.0)
            elif t > 1:
                t, s = 1.0, min(max((bb - cc) / a, 0.0), 1.0)
    return float(np.linalg.norm(p0 + d1 * s - (q0 + d2 * t)))


def rect_gap(p0, p1, u, up, span, z0, z1):
    """7.6: the distance of the segment p0-p1 (relative to the gooseneck) from the vertical rectangle along u, 0 to
    span long and z0 to z1 high; 0 when the segment passes through it."""
    nv = np.cross(up, u)
    n0, n1 = p0 @ nv, p1 @ nv
    if n0 * n1 <= 0 and n0 != n1:
        q = p0 + (p1 - p0) * (n0 / (n0 - n1))
        if 0 <= q @ u <= span and z0 <= q @ up <= z1:
            return 0.0

    def pt(p):
        s_, z_, n_ = p @ u, p @ up, p @ nv
        ds = max(0.0, -s_, s_ - span)
        dz = max(0.0, z0 - z_, z_ - z1)
        return float(np.sqrt(n_ * n_ + ds * ds + dz * dz))
    c00, c10, c11, c01 = up * z0, u * span + up * z0, u * span + up * z1, up * z1
    return min(pt(p0), pt(p1), seg_seg(p0, p1, c00, c10), seg_seg(p0, p1, c10, c11), seg_seg(p0, p1, c11, c01),
               seg_seg(p0, p1, c01, c00))
