"""Parametric canoe bodies and large-angle hydrostatics.

Each buoyant body (main hull or float) is lofted from its class parameters:

* waterline half-breadth b(xi) and keel-line depth t(xi) along xi = x/LWL (0 at the bow): power-law entry forward
  of the maximum section, power-law run aft ending at the transom width and the rocker rise;
* sections are superellipses |y/b|^n + |z/t|^n = 1 below the waterline, n chosen so the section area coefficient
  equals the midship coefficient Cm; one exponent p for the four fore/aft curves is solved so the prismatic
  coefficient matches Cp exactly;
* straight flared topsides from the waterline to the sheer (beam at the sheer, freeboard rising forward) and a
  flat deck.

Hydrostatics integrate the heeled sections (level trim) with Green's theorem on each clipped polygon, so the
righting arm stays valid at any heel, including a multihull lifting its hulls. Everything is vectorised over
heel angles, stations and polygon edges.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List

import numpy as np
from scipy.optimize import brentq

from .boatclass import Boat, HullBody
from .constants import G

N_STATIONS = 41
N_BOTTOM = 20        # superellipse points per side, keel to waterline
N_TOP = 3            # topside points per side above the waterline


def _superellipse_n(cm: float) -> float:
    from .boatclass import superellipse_cm
    return brentq(lambda n: superellipse_cm(n) - cm, 0.55, 60.0)


def _shape(xi, xm, p, end):
    """1 at the maximum section, 0 at the bow (power p), `end` at the aft end (power 1.5 p)."""
    xi = np.asarray(xi, float)
    fwd = 1.0 - np.clip((xm - xi) / xm, 0, 1) ** p
    aft = 1.0 - (1.0 - end) * np.clip((xi - xm) / (1 - xm), 0, 1) ** (1.5 * p)
    return np.where(xi < xm, fwd, aft)


@dataclass
class Loft:
    body: HullBody
    n: float                  # section superellipse exponent
    p: float                  # fore/aft fullness exponent
    xi: np.ndarray            # station positions, fraction of LWL
    b: np.ndarray             # waterline half-breadth per station
    t: np.ndarray             # depth below the body's waterline per station
    bd: np.ndarray            # sheer half-breadth
    fb: np.ndarray            # freeboard

    def area_curve(self, xi=None):
        from .boatclass import superellipse_cm
        if xi is None:
            return 2 * self.b * self.t * superellipse_cm(self.n)
        bw = _shape(xi, self.body.max_section, self.p, self.body.transom_width / self.body.bwl) * self.body.bwl / 2
        tt = _shape(xi, self.body.max_section, self.p, 1 - self.body.rocker / self.body.draft) * self.body.draft
        return 2 * bw * tt * superellipse_cm(self.n)

    def half_breadth(self, xi, z):
        """Half-breadth at xi (fraction of LWL) and depth z <= 0 below the body's design waterline."""
        B = self.body
        bw = _shape(xi, B.max_section, self.p, B.transom_width / B.bwl) * B.bwl / 2
        tt = _shape(xi, B.max_section, self.p, 1 - B.rocker / B.draft) * B.draft
        with np.errstate(divide="ignore", invalid="ignore"):
            r = np.clip(-z / np.where(tt > 0, tt, 1), 0, 1)
            y = bw * np.clip(1 - r ** self.n, 0, 1) ** (1 / self.n)
        return np.where((tt > 0) & (-z <= tt), y, 0.0)


def loft(body: HullBody) -> Loft:
    n = _superellipse_n(body.cm)
    wt = body.transom_width / body.bwl
    te = 1.0 - body.rocker / body.draft
    xs = np.linspace(0, 1, 801)

    def cp_of(p):
        return np.trapezoid(_shape(xs, body.max_section, p, wt) * _shape(xs, body.max_section, p, te), xs)

    lo, hi = cp_of(0.2), cp_of(12.0)
    cp = float(np.clip(body.cp, lo + 1e-4, hi - 1e-4))
    p = brentq(lambda q: cp_of(q) - cp, 0.2, 12.0)
    xi = np.linspace(0, 1, N_STATIONS)
    b = _shape(xi, body.max_section, p, wt) * body.bwl / 2
    t = _shape(xi, body.max_section, p, te) * body.draft
    bd = np.maximum(b, _shape(xi, body.max_section, 0.7 * p, min(1.0, 1.25 * wt + 0.2)) * body.beam_deck / 2)
    fb = body.freeboard * (1 + 0.35 * (1 - xi) ** 2)
    return Loft(body=body, n=n, p=p, xi=xi, b=b, t=t, bd=bd, fb=fb)


def section_polygons(lf: Loft) -> np.ndarray:
    """(stations, vertices, 2) polygons in body coordinates (y starboard, z up from the body's waterline), ccw."""
    th = np.linspace(0, np.pi / 2, N_BOTTOM)
    ct = np.cos(th) ** (2 / lf.n)
    st = np.sin(th) ** (2 / lf.n)
    S = len(lf.xi)
    # starboard bottom: keel (th = pi/2) -> waterline (th = 0)
    yb = lf.b[:, None] * ct[None, ::-1]
    zb = -lf.t[:, None] * st[None, ::-1]
    f = np.linspace(0, 1, N_TOP + 1)[1:]
    yt = lf.b[:, None] + (lf.bd - lf.b)[:, None] * f[None, :]
    zt = lf.fb[:, None] * f[None, :]
    ys = np.concatenate([yb, yt], axis=1)
    zs = np.concatenate([zb, zt], axis=1)
    # port side mirrored, deck -> keel
    yp = -ys[:, ::-1]
    zp = zs[:, ::-1]
    y = np.concatenate([ys, yp], axis=1)
    z = np.concatenate([zs, zp], axis=1)
    return np.stack([y, z], axis=-1).reshape(S, -1, 2)


def _clip_integrals(P: np.ndarray, h: np.ndarray):
    """Area, first moments (y, z - h) and wetted girth of polygons P (..., M, 2) below z = h (...)."""
    y0 = P[..., 0]
    z0 = P[..., 1] - h[..., None]
    y1 = np.roll(y0, -1, axis=-1)
    z1 = np.roll(z0, -1, axis=-1)
    below0 = z0 <= 0
    below1 = z1 <= 0
    dz = z0 - z1
    with np.errstate(divide="ignore", invalid="ignore"):
        tc = np.where(np.abs(dz) > 1e-15, z0 / dz, 0.0)
    ta = np.where(below0, 0.0, tc)
    tb = np.where(below1, 1.0, tc)
    keep = below0 | below1
    dy = y1 - y0
    dzz = z1 - z0
    ya = y0 + ta * dy
    za = z0 + ta * dzz
    yb = y0 + tb * dy
    zb = z0 + tb * dzz
    Dy = np.where(keep, yb - ya, 0.0)
    za = np.where(keep, za, 0.0)
    zb = np.where(keep, zb, 0.0)
    A = -np.sum(Dy * (za + zb) / 2, axis=-1)
    My = -np.sum(Dy * (2 * ya * za + ya * zb + yb * za + 2 * yb * zb) / 6, axis=-1)
    Mz = -np.sum(Dy * (za * za + za * zb + zb * zb) / 6, axis=-1)
    girth = np.sum(np.where(keep, np.hypot(yb - ya, zb - za), 0.0), axis=-1)
    return A, My, Mz, girth


@dataclass
class Hydro:
    heel: np.ndarray            # rad
    sinkage: np.ndarray         # waterline height relative to the static waterline, m
    yb: np.ndarray              # buoyancy centre, horizontal (to leeward +), m
    zb: np.ndarray
    rm_boat: np.ndarray         # righting moment of the boat without crew, N m
    rm_crew: np.ndarray         # righting moment of the crew sitting out, N m
    body_volume: np.ndarray     # (heel, body) immersed volume, m^3
    body_wetted: np.ndarray     # (heel, body) wetted canoe-body area, m^2
    upright: Dict[str, float]   # DSYHS-style parameters of the main body

    def righting_moment(self, heel):
        heel = np.abs(heel)
        return np.interp(heel, self.heel, self.rm_boat) + np.interp(heel, self.heel, self.rm_crew)

    def rm_max(self):
        rm = self.rm_boat + self.rm_crew
        i = int(np.argmax(rm))
        return float(self.heel[i]), float(rm[i])


def hydrostatics(boat: Boat, heel_deg_max: float = 90.0, dheel_deg: float = 1.0) -> Hydro:
    lofts = [loft(b) for b in boat.bodies]
    polys, weights, xs, owner = [], [], [], []
    for k, lf in enumerate(lofts):
        B = lf.body
        P = section_polygons(lf)
        P = P + np.array([B.y, B.z])[None, None, :]
        w = np.full(len(lf.xi), lf.xi[1] - lf.xi[0]) * B.lwl
        w[0] *= 0.5
        w[-1] *= 0.5
        polys.append(P)
        weights.append(w)
        xs.append(B.x + lf.xi * B.lwl)
        owner.append(np.full(len(lf.xi), k))
    P = np.concatenate(polys)           # (S, M, 2)
    w = np.concatenate(weights)         # (S,)
    owner = np.concatenate(owner)
    V = boat.volume
    phis = np.radians(np.arange(0.0, heel_deg_max + 1e-9, dheel_deg))
    c, s = np.cos(phis), np.sin(phis)
    # heel lowers +y (leeward)
    Yr = P[None, :, :, 0] * c[:, None, None] + P[None, :, :, 1] * s[:, None, None]
    Zr = -P[None, :, :, 0] * s[:, None, None] + P[None, :, :, 1] * c[:, None, None]
    R = np.stack([Yr, Zr], axis=-1)     # (K, S, M, 2)
    K = len(phis)
    lo = np.full(K, Zr.min(axis=(1, 2)))
    hi = np.full(K, Zr.max(axis=(1, 2)))
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        A, _, _, _ = _clip_integrals(R, np.broadcast_to(mid[:, None], (K, P.shape[0])))
        vol = A @ w
        big = vol > V
        hi = np.where(big, mid, hi)
        lo = np.where(big, lo, mid)
    h = 0.5 * (lo + hi)
    A, My, Mz, girth = _clip_integrals(R, np.broadcast_to(h[:, None], (K, P.shape[0])))
    vol = A @ w
    yb = (My @ w) / vol
    zb = (Mz @ w) / vol + h
    nb = len(boat.bodies)
    bvol = np.stack([(A * (owner == k)) @ w for k in range(nb)], axis=1)
    bwet = np.stack([(girth * (owner == k)) @ w for k in range(nb)], axis=1)
    m_b, m_c = boat.mass_boat, boat.mass_crew
    zc = boat.freeboard + 0.3
    # the buoyancy couple is split by mass: each part's weight against its share of the buoyancy
    rm_boat = G * m_b * (yb - boat.vcg * s)
    rm_crew = G * m_c * (yb + boat.crew_arm * c - zc * s)

    main = lofts[boat.main_index if boat.main_index is not None else 0]
    upright = _upright(main)
    return Hydro(heel=phis, sinkage=h, yb=yb, zb=zb, rm_boat=rm_boat, rm_crew=rm_crew, body_volume=bvol,
                 body_wetted=bwet, upright=upright)


def _upright(lf: Loft) -> Dict[str, float]:
    """Canoe-body parameters of one body at its design waterline (DSYHS inputs)."""
    from .boatclass import superellipse_cm
    B = lf.body
    xs = np.linspace(0, 1, 801)
    area = lf.area_curve(xs)
    vol = np.trapezoid(area, xs) * B.lwl
    bw = _shape(xs, B.max_section, lf.p, B.transom_width / B.bwl) * B.bwl
    aw = np.trapezoid(bw, xs) * B.lwl
    lcb = np.trapezoid(area * xs, xs) / np.trapezoid(area, xs)
    lcf = np.trapezoid(bw * xs, xs) / np.trapezoid(bw, xs)
    P = section_polygons(lf)
    _, _, _, girth = _clip_integrals(P[None], np.zeros((1, P.shape[0])))
    wet = np.trapezoid(girth[0], lf.xi) * B.lwl
    amax = float(area.max())
    return {
        "volume": float(vol), "lwl": B.lwl, "bwl": B.bwl, "tc": B.draft,
        "cp": float(vol / (amax * B.lwl)), "cm": float(superellipse_cm(lf.n)),
        "aw": float(aw), "cw": float(aw / (B.lwl * B.bwl)), "lcb": float(lcb), "lcf": float(lcf),
        "wetted": float(wet), "amax": amax, "p": lf.p, "n": lf.n,
    }
