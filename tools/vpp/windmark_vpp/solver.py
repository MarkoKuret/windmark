"""Aerodynamics of a sail configuration and the vectorised speed/heel equilibrium.

Equilibrium (2 degrees of freedom, surge and roll, as in the classic VPPs):

    drive(V, phi) = resistance(V, phi, Fh(V, phi))        surge
    Fh(V, phi) * (z_CE + z_CLR) = RM(phi)                  roll

with depowering controls flat (lift scale) and reef (area x reef^2, heights x reef) and each sail trimmed to its
best sheet angle for the effective apparent wind. Speed and heel are solved by alternating bisections, fully
vectorised over (TWS, TWA, flat, reef) so a whole boat solves in seconds.

Apparent wind (Kerwin/Jackson heeled-rig model): the rig sees the component of the apparent wind normal to the
mast, beta_e = atan2(sin(beta) cos(phi), cos(beta)), AWS_e = AWS sqrt(cos^2 beta + sin^2 beta cos^2 phi). The
true wind speed is given at 10 m and scaled to the rig's centre of effort with a logarithmic sea profile.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List

import numpy as np

from .boatclass import SPINNAKER_TYPES, Boat, Sail
from .constants import RHO_AIR, RHO_WATER, G
from .hydro import HullModel
from .sails import COEFFS, Envelope, coefficients, envelope

Z0_SEA = 2e-4            # m, sea surface roughness length of the wind profile
REF_HEIGHT = 10.0        # m, height the true wind speed is quoted at
WINDAGE_CD = 1.13        # Hazen/ORC windage coefficient on hull topsides and mast
FLATS = np.linspace(0.1, 1.0, 16)
REEFS = np.linspace(0.55, 1.0, 10)
REEFABLE = ("main", "jib", "genoa")


def wind_at(tws, z):
    return tws * np.log(np.maximum(z, 0.5) / Z0_SEA) / math.log(REF_HEIGHT / Z0_SEA)


@dataclass
class Rig:
    boat: Boat
    name: str
    sails: List[Sail]
    env: List[Envelope]
    reefable: np.ndarray        # bool per sail

    @property
    def downwind(self) -> bool:
        return any(s.type in SPINNAKER_TYPES for s in self.sails)

    def areas(self, reef):
        return [s.area * (reef ** 2 if r else 1.0) for s, r in zip(self.sails, self.reefable)]

    def ce_height(self, reef):
        fb = self.boat.freeboard
        num = 0.0
        den = 0.0
        for s, r, a in zip(self.sails, self.reefable, self.areas(reef)):
            z = fb + (s.ce_height - fb) * (reef if r else 1.0)
            num = num + a * z
            den = den + a
        return num / den

    def forces(self, fi, reef, beta_e, aws_e, eps=None):
        """Drive and heeled-plane side force (N) and per-sail sheet angles.

        fi: flat index, reef factor, effective AWA and AWS. With eps (rad, + = eased beyond the optimum, the trim
        error of the specs) every sail is sheeted eps away from its optimum, as the single manual sheet does,
        clamped to the sheet limits and the wind line.
        """
        areas = self.areas(reef)
        aref = sum(areas)
        cl = 0.0
        cd = 0.0
        deltas = []
        for s, e, a in zip(self.sails, self.env, areas):
            c_l, c_d, de = e.at(fi, beta_e)
            if eps is not None:
                de = np.minimum(np.clip(de + eps, s.sheet_min, s.sheet_max), np.maximum(beta_e, s.sheet_min))
                c_l, c_d = coefficients(COEFFS[s.coeff_type], beta_e - de, e.flat[fi], de)
            cl = cl + c_l * a
            cd = cd + c_d * a
            deltas.append(de)
        fx, fh = self._resolve(cl / aref, cd / aref, aref, reef, beta_e, aws_e)
        return fx, fh, deltas

    def _resolve(self, cl, cd, aref, reef, beta_e, aws_e):
        b = self.boat
        # induced drag: effective rig height with the deck mirror close-hauled (Hazen)
        h_close = 1.1 * b.mast_height * reef
        h_free = 1.1 * (b.mast_height - b.freeboard) * reef
        u = np.clip((beta_e - np.radians(40)) / np.radians(30), 0, 1)
        h = h_close + (h_free - h_close) * u * u * (3 - 2 * u)
        ar = h * h / aref
        cdi = cl * cl * (1.0 / (math.pi * ar) + 0.005)
        cd0 = WINDAGE_CD * (b.beam_max * b.freeboard + (b.mast_height - b.freeboard) * b.mast_chord) / aref
        cdt = cd + cdi + cd0
        q = 0.5 * RHO_AIR * aws_e * aws_e * aref
        sb, cb = np.sin(beta_e), np.cos(beta_e)
        return q * (cl * sb - cdt * cb), q * (cl * cb + cdt * sb)

    def windage_force(self, aws, awa):
        """Drag (N) of hull, rig and flogging sails along the apparent wind, sails luffing."""
        b = self.boat
        area = (WINDAGE_CD * (b.beam_max * b.freeboard + (b.mast_height - b.freeboard) * b.mast_chord)
                + sum(0.06 * s.area for s in self.sails))
        area = area + WINDAGE_CD * b.loa * b.freeboard * 0.5 * np.abs(np.sin(awa))
        return 0.5 * RHO_AIR * aws * aws * area


def make_rig(boat: Boat, name: str, sails: List[Sail]) -> Rig:
    env = [envelope(s.coeff_type, s.sheet_min, s.sheet_max, FLATS) for s in sails]
    return Rig(boat=boat, name=name, sails=sails, env=env,
               reefable=np.array([s.type in REEFABLE for s in sails]))


def apparent(tws_ce, twa, V, heel):
    ax = tws_ce * np.cos(twa) + V
    ay = tws_ce * np.sin(twa)
    aws = np.hypot(ax, ay)
    beta = np.arctan2(ay, ax)
    c = np.cos(heel)
    beta_e = np.arctan2(np.sin(beta) * c, np.cos(beta))
    aws_e = aws * np.sqrt(np.cos(beta) ** 2 + (np.sin(beta) * c) ** 2)
    return aws, beta, aws_e, beta_e


@dataclass
class State:
    V: np.ndarray
    heel: np.ndarray
    valid: np.ndarray
    aws: np.ndarray
    awa: np.ndarray
    fh: np.ndarray
    fx: np.ndarray
    deltas: list


class Solver:
    def __init__(self, boat: Boat, hull: HullModel):
        self.boat = boat
        self.hull = hull
        H = hull.hydro
        rm = H.rm_boat + H.rm_crew
        i = int(np.argmax(rm))
        self.heel_top = float(min(boat.heel_max, H.heel[i]))
        self.zclr = 0.45 * boat.draft_total

    def moment(self, rig, fi, reef, tws, twa, V, heel, eps=None):
        z = rig.ce_height(reef)
        tw = wind_at(tws, z)
        aws, beta, aws_e, beta_e = apparent(tw, twa, V, heel)
        fx, fh, deltas = rig.forces(fi, reef, beta_e, aws_e, eps)
        return fx, fh, fh * (z + self.zclr), aws, beta, deltas

    def solve_heel(self, rig, fi, reef, tws, twa, V, iters=26, eps=None):
        rm = self.hull.hydro.righting_moment
        lo = np.zeros_like(V)
        hi = np.full_like(V, self.heel_top)
        _, _, m_hi, _, _, _ = self.moment(rig, fi, reef, tws, twa, V, hi, eps)
        over = rm(hi) < m_hi
        for _ in range(iters):
            mid = 0.5 * (lo + hi)
            _, _, m, _, _, _ = self.moment(rig, fi, reef, tws, twa, V, mid, eps)
            up = rm(mid) < m
            lo = np.where(up, mid, lo)
            hi = np.where(up, hi, mid)
        heel = np.where(over, self.heel_top, 0.5 * (lo + hi))
        return heel, over

    def net_force(self, rig, fi, reef, tws, twa, V, heel, eps=None):
        fx, fh, _, _, _, _ = self.moment(rig, fi, reef, tws, twa, V, heel, eps)
        return fx - self.hull.resistance(V, heel, fh), fh

    def solve_speed(self, rig, fi, reef, tws, twa, heel, vmax, iters=28, eps=None):
        lo = np.zeros_like(heel)
        hi = np.broadcast_to(vmax, heel.shape).astype(float).copy()
        for _ in range(iters):
            mid = 0.5 * (lo + hi)
            f, _ = self.net_force(rig, fi, reef, tws, twa, mid, heel, eps)
            up = f > 0
            lo = np.where(up, mid, lo)
            hi = np.where(up, hi, mid)
        return 0.5 * (lo + hi)

    def solve(self, rig, fi, reef, tws, twa, outer=7, eps=None) -> State:
        shape = np.broadcast(fi, reef, tws, twa, 0.0 if eps is None else eps).shape
        fi = np.broadcast_to(fi, shape)
        reef = np.broadcast_to(reef, shape)
        tws = np.broadcast_to(tws, shape)
        twa = np.broadcast_to(twa, shape)
        if eps is not None:
            eps = np.broadcast_to(eps, shape)
        vmax = np.maximum(2.2 * tws, 4.0)
        heel = np.zeros(shape)
        over = np.zeros(shape, bool)
        for _ in range(outer):
            V = self.solve_speed(rig, fi, reef, tws, twa, heel, vmax, eps=eps)
            heel, over = self.solve_heel(rig, fi, reef, tws, twa, V, eps=eps)
        V = self.solve_speed(rig, fi, reef, tws, twa, heel, vmax, eps=eps)
        fx, fh, _, aws, beta, deltas = self.moment(rig, fi, reef, tws, twa, V, heel, eps)
        valid = ~over & (V < 0.98 * vmax)
        return State(V=V, heel=heel, valid=valid, aws=aws, awa=beta, fh=fh, fx=fx, deltas=deltas)

    def sternway(self, rig, tws, twa):
        """Steady drift speed (m/s, <= 0) with the sails luffing, windage pushing the boat astern."""
        tw = wind_at(tws, rig.ce_height(1.0))
        lo = np.zeros(np.broadcast(tws, twa).shape)
        hi = np.full_like(lo, -0.3 * np.max(tws) - 0.5)
        for _ in range(30):
            mid = 0.5 * (lo + hi)
            aws, beta, _, _ = apparent(tw, twa, mid, 0.0)
            push = rig.windage_force(aws, beta) * np.cos(beta)       # astern component
            drag = self.hull.resistance(-mid, 0.0 * mid, 0.0 * mid)
            back = push > drag
            lo = np.where(back, mid, lo)
            hi = np.where(back, hi, mid)
        return 0.5 * (lo + hi)


def added_mass_coefficient(lwl: float, amax: float) -> float:
    """Surge added-mass coefficient of the canoe body as a prolate spheroid (Lamb 1932).

    The underwater body and its mirror image form a spheroid of length LWL and diameter sqrt(8 Amax / pi).
    """
    d = math.sqrt(8 * amax / math.pi)
    e = math.sqrt(max(1 - (d / lwl) ** 2, 1e-6))
    a0 = 2 * (1 - e * e) / e ** 3 * (0.5 * math.log((1 + e) / (1 - e)) - e)
    return a0 / (2 - a0)
