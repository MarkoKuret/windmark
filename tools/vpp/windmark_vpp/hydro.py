"""Hydrodynamic resistance: canoe bodies, appendages, heel and side force.

Monohull canoe body (sources in README.md, "Hydrodynamics"):

* friction: ITTC-57 line with the Reynolds number on 0.7 LWL and no form factor (the Delft convention the
  residuary regression was derived with), on the wetted area of the heeled lofted hull;
* residuary: Delft Systematic Yacht Hull Series bare-hull regression of Keuning & Katgert (2008), Fn 0.15-0.75;
  below Fn 0.15 it fades as Fn^4; a hull light enough for its length to plane (``planing_ability``) meets its
  hump stretched over a wider Froude range and holds the curve where it levels off, a hull too heavy to plane
  keeps climbing its wave wall; the upright resistance never falls with speed, so the equilibrium speed rises
  continuously with the wind;
* keel residuary and its heel increment: Keuning & Sonnenberg (1998);
* induced resistance: Fh^2 / (pi Te^2 q) with the effective draft Te of Keuning & Sonnenberg (1998);
* deck-edge immersion: a Windmark term that grows the residuary resistance quadratically once the sheer line
  is under water, so the optimiser never settles at a knocked-down heel.

Multihull bodies are slender (L/B 10-20), outside the Delft series, so their wave resistance is Michell's
thin-ship integral computed on the lofted body at a range of immersions; friction uses ITTC-57 on LWL with a
slender-body form factor. The floats' immersion and wetted area at each heel come from the hydrostatics.

Appendage friction: ITTC-57 on the mean chord with Hoerner's thickness form factors, both for foils and the
bulb (as a body of revolution).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np

from .boatclass import Boat
from .constants import G, NU_WATER, RHO_WATER
from .geometry import Hydro, Loft, loft

# Keuning & Katgert (2008) bare-hull residuary resistance, Fn 0.15 ... 0.75 step 0.05.
# Rr / (rho g V) = (a0 + a1 LCBfpp/LWL + a2 Cp + a3 V^(2/3)/Aw + a4 BWL/LWL + a5 LCBfpp/LCFfpp
#                   + a6 BWL/Tc + a7 Cm) * V^(1/3)/LWL
DSYHS_FN = np.round(np.arange(0.15, 0.7501, 0.05), 2)
DSYHS_A = np.array([
    [-0.0005, -0.0003, -0.0002, -0.0009, -0.0026, -0.0064, -0.0218, -0.0388, -0.0347, -0.0361, 0.0008, 0.0108, 0.1023],
    [0.0023, 0.0059, -0.0156, 0.0016, -0.0567, -0.4034, -0.5261, -0.5986, -0.4764, 0.0037, 0.3728, -0.1238, 0.7726],
    [-0.0086, -0.0064, 0.0031, 0.0337, 0.0446, -0.1250, -0.2945, -0.3038, -0.2361, -0.2960, -0.3667, -0.2026, 0.5040],
    [-0.0015, 0.0070, -0.0021, -0.0285, -0.1091, 0.0273, 0.2485, 0.6033, 0.8762, 0.9661, 1.3957, 1.1282, 1.7867],
    [0.0061, 0.0014, -0.0070, -0.0367, -0.0707, -0.1341, -0.2428, -0.0430, 0.4219, 0.6123, 1.0343, 1.1836, 2.1934],
    [0.0010, 0.0013, 0.0148, 0.0218, 0.0914, 0.3578, 0.6293, 0.8332, 0.8990, 0.7534, 0.3230, 0.4973, -1.5479],
    [0.0001, 0.0005, 0.0010, 0.0015, 0.0021, 0.0045, 0.0081, 0.0106, 0.0096, 0.0100, 0.0072, 0.0038, -0.0115],
    [0.0052, -0.0020, -0.0043, -0.0172, -0.0078, 0.1115, 0.2086, 0.1336, -0.2272, -0.3352, -0.4632, -0.4477, -0.0977],
])
# Parameter ranges of the series (Keuning & Katgert 2008), reported when a hull falls outside.
DSYHS_RANGE = {
    "LCBfpp/LWL": (0.500, 0.582), "Cp": (0.52, 0.60), "V^(2/3)/Aw": (0.08, 0.26), "BWL/LWL": (0.17, 0.37),
    "LCBfpp/LCFfpp": (0.93, 1.00), "BWL/Tc": (2.46, 19.4), "Cm": (0.65, 0.79), "V^(1/3)/LWL": (0.12, 0.23),
}

# Keuning & Sonnenberg (1998) keel residuary resistance, Fn 0.20 ... 0.60 step 0.05.
# Rrk / (rho g Vk) = A0 + A1 T/BWL + A2 (Tc + Zcbk)/Vk^(1/3) + A3 Vc/Vk
KEEL_FN = np.round(np.arange(0.20, 0.6001, 0.05), 2)
KEEL_A = np.array([
    [-0.00104, -0.00550, -0.01100, -0.00713, -0.03581, -0.00470, 0.00553, 0.04822, 0.01021],
    [0.00172, 0.00597, 0.01421, 0.02632, 0.08649, 0.11592, 0.07371, 0.00660, 0.14173],
    [0.00117, 0.00390, 0.00069, -0.00232, 0.00999, -0.00064, 0.05991, 0.07048, 0.06409],
    [-0.00008, -0.00009, 0.00021, 0.00039, 0.00017, 0.00035, -0.00114, -0.00035, -0.00192],
])

# Keuning & Sonnenberg (1998) effective draft of hull + appendages, heel 0/10/20/30 deg.
# Te/T = (A1 Tc/T + A2 (Tc/T)^2 + A3 BWL/Tc + A4 TR) (B0 + B1 Fn)
TE_HEEL = np.radians([0.0, 10.0, 20.0, 30.0])
TE_A = np.array([
    [3.7455, 4.4892, 3.9592, 3.4891],
    [-3.6246, -4.8454, -3.9804, -2.9577],
    [0.0589, 0.0294, 0.0283, 0.0250],
    [-0.0296, -0.0176, -0.0075, -0.0272],
])
TE_B = np.array([
    [1.2306, 1.4231, 1.5450, 1.4744],
    [-0.7256, -1.2971, -1.5622, -1.3499],
])

# Planing: a hull light for its length is lifted by its bottom and lengthened by its own bow and stern waves as it
# speeds up, so it meets its wave hump later and more gently than the towed Delft models: past HUMP_FN0 its
# residuary coefficient is the Delft curve at the effective Froude number HUMP_FN0 + HUMP_STRETCH (Fn - HUMP_FN0)
# (fitted to ORC one-design and club certificates, README "Planing"). How much of this a hull gets (its planing
# ability) is gated on its displacement-length ratio (design displacement without crew, the usual convention): 1
# up to PLANING_DLR_FULL, 0 from PLANING_DLR_NONE, smooth in between; a hull heavy for its length keeps the towed
# curve and climbs its wave wall however hard it is driven.
HUMP_FN0 = 0.35             # Froude number where the stretch starts (below it the Delft curve as is)
HUMP_STRETCH = 0.5          # rate at which the effective Froude number grows past HUMP_FN0 (fitted, README)
PLANING_DLR_FULL = 100.0    # displacement-length ratio up to which a hull planes fully (sportsboats, racers) ...
PLANING_DLR_NONE = 200.0    # ... and from which it never planes (heavy cruisers; fitted, README)
WAVE_WALL_SLOPE = (2.0, 6.0)  # bounds of the log slope d ln(Rr) / d ln(Fn) a non-planing hull keeps on its wave wall
MIN_RESISTANCE_SLOPE = 1.0  # the upright resistance grows at least in proportion to the speed (Windmark, README)
FOIL_CL_MAX = 1.1           # keel + rudder lift coefficient where the side force starts to stall
STALL_PENALTY = 12.0        # drag per unit of excess CL^2 beyond FOIL_CL_MAX (Windmark robustness term)
DECK_EDGE_GAIN = 0.8        # residuary growth per (heel beyond deck-edge immersion / that angle)^2 (Windmark)


def cf_ittc(re):
    re = np.maximum(re, 1e4)
    return 0.075 / (np.log10(re) - 2.0) ** 2


def foil_form_factor(tc):
    """Hoerner: 1 + 2 t/c + 60 (t/c)^4 for a two-dimensional section."""
    return 1 + 2 * tc + 60 * tc ** 4


def body_form_factor(d_over_l):
    """Hoerner: 1 + 1.5 (d/l)^1.5 + 7 (d/l)^3 for a streamlined body of revolution."""
    return 1 + 1.5 * d_over_l ** 1.5 + 7 * d_over_l ** 3


# ---------------------------------------------------------------------------------------------------------------
# Michell thin-ship wave resistance


def michell_rw(lf: Loft, speeds, zw: float = 0.0, nz: int = 24) -> np.ndarray:
    """Wave resistance (N) of one body at speeds (m/s), waterline zw above its design waterline.

    R = 4 rho g^2 / (pi U^2) * Int_1^inf |A(l)|^2 l^2 / sqrt(l^2 - 1) dl,
    A(l) = Int Int dY/dx exp(k0 l^2 z) exp(i k0 l x) dx dz, k0 = g/U^2  (Michell 1898; Tuck 1989).
    Integrated with l = cosh(u); the half-breadth above the design waterline is continued vertically.
    """
    B = lf.body
    speeds = np.atleast_1d(np.asarray(speeds, float))
    out = np.zeros_like(speeds)
    depth = B.draft + zw
    if depth <= 1e-4:
        return out
    L = B.lwl
    for i, U in enumerate(speeds):
        fn = U / math.sqrt(G * L)
        if fn < 0.08:
            continue
        k0 = G / U ** 2
        lam_max = min(math.sqrt(400.0 / (k0 * depth * 0.02)) + 1.0, 80.0)
        nx = int(np.clip(k0 * lam_max * L / 0.35, 200, 2400))
        # a transom stern is closed by a virtual run behind it (the separated hollow of a dry transom)
        ext = 3.0 * B.transom_wl
        x = np.linspace(0, L + ext, nx)
        zc = -(np.arange(nz) + 0.5) / nz * depth
        dzc = depth / nz
        xi = np.minimum(x / L, 1.0)
        fade = np.clip(1 - (x - L) / max(ext, 1e-9), 0, 1)
        Y = lf.half_breadth(xi[None, :], zc[:, None] + zw) * fade[None, :]   # vertical sides above the DWL
        Yx = np.gradient(Y, x, axis=1)
        u = np.linspace(0, math.acosh(lam_max), 400)
        lam = np.cosh(u)
        Ez = np.exp(k0 * lam[:, None] ** 2 * zc[None, :]) * dzc          # (nl, nz)
        F = Ez @ Yx                                                       # (nl, nx)
        ph = k0 * lam[:, None] * x[None, :]
        wx = np.full(nx, x[1] - x[0])
        wx[0] *= 0.5
        wx[-1] *= 0.5
        P = (F * np.cos(ph)) @ wx
        Q = (F * np.sin(ph)) @ wx
        integrand = (P ** 2 + Q ** 2) * lam ** 2        # l^2/sqrt(l^2-1) dl = cosh^2(u) du
        out[i] = 4 * RHO_WATER * G ** 2 / (math.pi * U ** 2) * np.trapezoid(integrand, u)
    return out


# ---------------------------------------------------------------------------------------------------------------


@dataclass
class HullModel:
    boat: Boat
    hydro: Hydro
    lofts: List[Loft]
    rr_fn: np.ndarray                     # Froude grid of the tabulated monohull residuary coefficient
    rr_coef: np.ndarray                   # Rr / (rho g V) on rr_fn
    dsyhs_params: Dict[str, float]
    notes: List[str]
    # multihull wave resistance tables per body: speed grid, immersed-volume grid, Rw(speed, volume)
    mh_speed: Optional[np.ndarray] = None
    mh_tables: Optional[List[tuple]] = None
    use_thin_ship: bool = False

    # -----------------------------------------------------------------------------------------------------------
    def upright_residuary(self, V):
        """Monohull canoe-body residuary resistance (N) at speed V (m/s), planing included."""
        up = self.hydro.upright
        fn = np.asarray(V) / math.sqrt(G * up["lwl"])
        c = np.interp(fn, self.rr_fn, self.rr_coef)
        return c * RHO_WATER * G * self.boat.volume

    def resistance(self, V, heel, side_force, parts: bool = False):
        """Total water resistance (N) at speed V, heel (rad) and hydrodynamic side force (N, heeled plane)."""
        b = self.boat
        V = np.maximum(np.asarray(V, float), 1e-3)
        heel = np.abs(np.asarray(heel, float))
        Fh = np.abs(np.asarray(side_force, float))
        q = 0.5 * RHO_WATER * V * V
        H = self.hydro
        up = H.upright
        main = b.main_index if b.main_index is not None else 0
        out = {}
        if not self.use_thin_ship:
            S = np.interp(heel, H.heel, H.body_wetted[:, main])
            out["friction"] = q * S * cf_ittc(V * 0.7 * up["lwl"] / NU_WATER)
            rr = self.upright_residuary(V)
            out["residuary"] = rr
            # deck edge immersion
            phi_d = math.atan2(2 * b.freeboard, b.beam_max)
            ex = np.maximum(heel - phi_d, 0.0) / phi_d
            out["deck_edge"] = rr * DECK_EDGE_GAIN * ex ** 2
        else:
            fr = np.zeros_like(V * heel)
            rw = np.zeros_like(fr)
            for k, lf in enumerate(self.lofts):
                vol = np.interp(heel, H.heel, H.body_volume[:, k])
                wet = np.interp(heel, H.heel, H.body_wetted[:, k])
                L = lf.body.lwl
                d_eq = math.sqrt(8 * max(np.max(lf.area_curve()), 1e-6) / math.pi)
                ff = body_form_factor(d_eq / L)
                fr = fr + q * wet * cf_ittc(V * L / NU_WATER) * ff
                spd, vols, tab = self.mh_tables[k]
                rw = rw + _interp2(spd, vols, tab, V, vol)
            out["friction"] = fr
            out["residuary"] = rw
        out.update(self.appendage_resistance(V, heel))
        out["induced"] = self.induced(V, heel, Fh)
        total = sum(out.values())
        return (total, out) if parts else total

    def appendage_resistance(self, V, heel):
        b = self.boat
        q = 0.5 * RHO_WATER * V * V
        out = {}
        R = 0.0
        for foil in (b.keel, b.rudder):
            R = R + q * foil.wetted * cf_ittc(V * foil.chord / NU_WATER) * foil_form_factor(foil.thickness)
        if b.bulb is not None:
            bl = b.bulb
            wet = 0.8 * math.pi * bl.diameter * bl.length     # spheroid-like body
            R = R + q * wet * cf_ittc(V * bl.length / NU_WATER) * body_form_factor(bl.diameter / bl.length)
        out["appendage_friction"] = R
        if b.kind == "monohull":
            up = self.hydro.upright
            fn = V / math.sqrt(G * up["lwl"])
            vk = self._keel_volume()
            T = b.draft_total
            c = (np.interp(fn, KEEL_FN, KEEL_A[0]) + np.interp(fn, KEEL_FN, KEEL_A[1]) * T / up["bwl"]
                 + np.interp(fn, KEEL_FN, KEEL_A[2]) * self._keel_cb_depth() / vk ** (1 / 3)
                 + np.interp(fn, KEEL_FN, KEEL_A[3]) * up["volume"] / vk)
            c = np.where(fn < KEEL_FN[0], c * (fn / KEEL_FN[0]) ** 4, c)
            out["keel_residuary"] = np.maximum(c, 0.0) * RHO_WATER * G * vk
            ch = (-3.5837 * up["tc"] / T - 0.0518 * up["bwl"] / up["tc"]
                  + 0.5958 * (up["tc"] / T) * (up["bwl"] / up["tc"]) + 0.2055 * up["lwl"] / up["volume"] ** (1 / 3))
            out["keel_heel"] = np.maximum(RHO_WATER * G * vk * ch * np.minimum(fn, 0.6) ** 2 * heel, 0.0)
        return out

    def _keel_cb_depth(self):
        """Depth of the fin's centre of buoyancy below the waterline (Tc + Zcbk), m."""
        return self.hydro.upright["tc"] + 0.45 * self.boat.keel.span

    def _keel_volume(self):
        """Fin volume for the keel regressions: the Delft keel series were fins; a deep bulb makes little wave
        resistance and is charged through its friction and form drag instead (calibration, README)."""
        b = self.boat
        v = b.keel.span * b.keel.chord ** 2 * b.keel.thickness * 0.68
        return max(v, 1e-4)

    def effective_draft(self, V, heel):
        b = self.boat
        up = self.hydro.upright
        if b.kind != "monohull":
            return 0.9 * (b.keel.span + 0.5 * up["tc"]) + 0.0 * V
        T = b.draft_total
        fn = np.minimum(V / math.sqrt(G * up["lwl"]), 0.6)
        h = np.clip(heel, 0, TE_HEEL[-1])
        A = [np.interp(h, TE_HEEL, TE_A[i]) for i in range(4)]
        Bc = [np.interp(h, TE_HEEL, TE_B[i]) for i in range(2)]
        r = up["tc"] / T
        te = (A[0] * r + A[1] * r * r + A[2] * up["bwl"] / up["tc"] + A[3] * b.keel.taper) * (Bc[0] + Bc[1] * fn)
        return T * np.clip(te, 0.5, 1.3)

    def induced(self, V, heel, Fh):
        b = self.boat
        q = 0.5 * RHO_WATER * V * V
        te = self.effective_draft(V, heel)
        ri = Fh ** 2 / (math.pi * te ** 2 * q)
        area = b.keel.area + b.rudder.area
        cl = Fh / (q * area)
        stall = q * area * STALL_PENALTY * np.maximum(cl - FOIL_CL_MAX, 0.0) ** 2
        return ri + stall


def _interp2(xg, yg, tab, x, y):
    """Bilinear interpolation of tab[len(xg), len(yg)] with clamping, vectorised over x, y."""
    x = np.clip(x, xg[0], xg[-1])
    y = np.clip(y, yg[0], yg[-1])
    i = np.clip(np.searchsorted(xg, x) - 1, 0, len(xg) - 2)
    j = np.clip(np.searchsorted(yg, y) - 1, 0, len(yg) - 2)
    tx = (x - xg[i]) / (xg[i + 1] - xg[i])
    ty = (y - yg[j]) / (yg[j + 1] - yg[j])
    return ((1 - tx) * (1 - ty) * tab[i, j] + tx * (1 - ty) * tab[i + 1, j]
            + (1 - tx) * ty * tab[i, j + 1] + tx * ty * tab[i + 1, j + 1])


def dsyhs_coefficient(p: Dict[str, float]) -> np.ndarray:
    """Rr/(rho g V) at DSYHS_FN for the parameter set p (keys of DSYHS_RANGE)."""
    x = np.array([1.0, p["LCBfpp/LWL"], p["Cp"], p["V^(2/3)/Aw"], p["BWL/LWL"], p["LCBfpp/LCFfpp"], p["BWL/Tc"],
                  p["Cm"]])
    return (x @ DSYHS_A) * p["V^(1/3)/LWL"]


def residuary_curve(p: Dict[str, float], ability: float = 1.0):
    """Delft residuary coefficient Rr/(rho g V) on a Froude grid 0 ... 3, made robust.

    Inside the series the regression is used as is, made monotone (it can dip when a hull sits at the edge of the
    parameter range); below Fn 0.15 it fades as Fn^4. Where the monotone curve stops rising (at the latest Fn
    0.75) a hull that can plane (ability 1) holds it; one that cannot (ability 0) keeps climbing its wave wall
    with the curve's log slope just before that point (bounded by WAVE_WALL_SLOPE); ability in between scales
    the exponent. The planing stretch is applied by ``build``.
    """
    c = np.maximum.accumulate(np.maximum(dsyhs_coefficient(p), 0.0))
    fn_lo = np.linspace(0.0, 0.14, 8)
    fn_hi = np.linspace(0.8, 3.0, 23)
    fn = np.concatenate([fn_lo, DSYHS_FN, fn_hi])
    out = np.concatenate([c[0] * (fn_lo / DSYHS_FN[0]) ** 4, c, np.full(len(fn_hi), c[-1])])
    k = max(int(np.argmax(c >= c[-1] * (1 - 1e-9))), 1)        # where the monotone regression levels off
    slope = math.log(max(c[k], 1e-9) / max(c[k - 1], 1e-9)) / math.log(DSYHS_FN[k] / DSYHS_FN[k - 1])
    slope = min(max(slope, WAVE_WALL_SLOPE[0]), WAVE_WALL_SLOPE[1]) * (1.0 - ability)
    wall = c[k] * (np.maximum(fn, DSYHS_FN[k]) / DSYHS_FN[k]) ** slope
    return fn, np.maximum(out, wall * (fn >= DSYHS_FN[k]))


def displacement_length_ratio(mass: float, lwl: float) -> float:
    """Displacement-length ratio: displacement in long tons over (0.01 LWL in feet)^3, from SI inputs."""
    return (mass / 1016.047) / (lwl / 30.48) ** 3


def planing_ability(dlr: float) -> float:
    """1 for a hull light enough for its length to plane, 0 for one that never does, smooth in between."""
    u = min(max((PLANING_DLR_NONE - dlr) / (PLANING_DLR_NONE - PLANING_DLR_FULL), 0.0), 1.0)
    return u * u * (3 - 2 * u)


def hump_froude(fn):
    """Effective Froude number of a planing hull's wave hump: Fn up to HUMP_FN0, growing at HUMP_STRETCH beyond."""
    fn = np.asarray(fn, float)
    return np.where(fn > HUMP_FN0, HUMP_FN0 + HUMP_STRETCH * (fn - HUMP_FN0), fn)


def build(boat: Boat, hydro: Hydro, thin_ship: Optional[bool] = None) -> HullModel:
    notes: List[str] = []
    lofts = [loft(b) for b in boat.bodies]
    up = hydro.upright
    V = boat.volume
    p = {
        "LCBfpp/LWL": up["lcb"], "Cp": up["cp"], "V^(2/3)/Aw": up["volume"] ** (2 / 3) / up["aw"],
        "BWL/LWL": up["bwl"] / up["lwl"], "LCBfpp/LCFfpp": up["lcb"] / up["lcf"], "BWL/Tc": up["bwl"] / up["tc"],
        "Cm": up["cm"], "V^(1/3)/LWL": up["volume"] ** (1 / 3) / up["lwl"],
    }
    use_thin = boat.kind != "monohull" if thin_ship is None else thin_ship
    if not use_thin:
        for k, (lo, hi) in DSYHS_RANGE.items():
            if not lo * 0.97 <= p[k] <= hi * 1.03:
                notes.append(f"hull {k} = {p[k]:.3f} outside the Delft series range {lo}-{hi}")
    ability = 1.0
    if not use_thin:
        dlr = displacement_length_ratio(boat.mass_boat, boat.lwl)
        ability = planing_ability(dlr)
        notes.append(f"displacement-length ratio {dlr:.0f}: planing ability {ability:.2f}")
    fn, curve = residuary_curve(p, ability)
    model = HullModel(boat=boat, hydro=hydro, lofts=lofts, rr_fn=fn, rr_coef=curve, dsyhs_params=p, notes=notes,
                      use_thin_ship=use_thin)
    if not use_thin:
        _apply_planing(model, ability)
    if use_thin:
        tables = []
        vmax = 3.2 * math.sqrt(G * max(b.lwl for b in boat.bodies))
        spd = np.concatenate([np.linspace(0.3, vmax, 48)])
        cache = {}
        for k, lf in enumerate(lofts):
            B = lf.body
            key = (B.lwl, B.bwl, B.draft, B.cp, B.cm, B.rocker_fwd, B.rocker_aft, B.transom_wl, B.max_section)
            if key not in cache:
                zws = np.linspace(-0.85 * B.draft, 0.5 * B.draft, 10)
                vols = np.array([_immersed_volume(lf, zw) for zw in zws])
                tab = np.stack([michell_rw(lf, spd, zw) for zw in zws], axis=1)
                vols = np.concatenate([[0.0], vols])
                tab = np.concatenate([np.zeros((len(spd), 1)), tab], axis=1)
                cache[key] = (spd, vols, tab)
            tables.append(cache[key])
        model.mh_speed = spd
        model.mh_tables = tables
    return model


def _apply_planing(model: HullModel, ability: float):
    """Fold the planing stretch into the residuary curve, with the upright resistance kept non-decreasing.

    A hull with planing ability a takes (1 - a) of the towed curve and a of the curve at the stretched Froude
    number (``hump_froude``). The Delft regression levels off over the hump of some hulls, and the stretched
    curve levels off where the towed one does, which alone would leave the total resistance growing more slowly
    than the speed there. The speed would then jump where the wind first drives the boat over it (the drive of a
    reaching rig grows with the boat's speed). Here the total upright resistance is made to grow at least in
    proportion to the speed (MIN_RESISTANCE_SLOPE) by lowering the residuary part ahead of such a flat stretch to
    the largest such curve under it: a planing hull's speed climbs steeply but continuously with the wind.
    """
    b = model.boat
    up = model.hydro.upright
    vs = math.sqrt(G * up["lwl"])
    fn = np.linspace(0.0, model.rr_fn[-1], 601)
    V = np.maximum(fn * vs, 1e-3)
    c = ((1 - ability) * np.interp(fn, model.rr_fn, model.rr_coef)
         + ability * np.interp(hump_froude(fn), model.rr_fn, model.rr_coef))
    wg = RHO_WATER * G * b.volume
    model.rr_fn, model.rr_coef = fn, c
    _, parts = model.resistance(V, np.zeros_like(V), np.zeros_like(V), parts=True)
    other = sum(v for k, v in parts.items() if k not in ("residuary", "deck_edge", "induced"))
    k = MIN_RESISTANCE_SLOPE
    total = np.minimum.accumulate(((c * wg + other) / V ** k)[::-1])[::-1] * V ** k
    model.rr_coef = np.maximum((total - other) / wg, 0.0)


def _immersed_volume(lf: Loft, zw: float) -> float:
    B = lf.body
    x = np.linspace(0, 1, 201)
    z = np.linspace(-(B.draft + zw), 0, 60)
    Y = lf.half_breadth(x[None, :], z[:, None] + zw)
    return float(2 * np.trapezoid(np.trapezoid(Y, z, axis=0), x) * B.lwl)
