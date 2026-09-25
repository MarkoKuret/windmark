"""Sail force coefficients with an explicit sheet angle.

Classic VPPs (Hazen 1980; the ORC VPP) tabulate each sail's lift and parasitic drag against the apparent wind
angle, with the trim folded in. The game also needs the trim itself (the optimal sheet angle and what a trim error
costs), so Windmark models each sail's coefficients against its angle of attack alpha = beta - delta, where beta is
the effective apparent wind angle and delta the sheet angle (chord from the centreline, limited by the deck
layout):

* luffing below alpha_luff: no lift, flogging drag;
* attached flow up to alpha_stall: lift rises as a quarter sine to cl_max, profile drag cd0 + kp Cl^2;
* stalled beyond: blended over `blend` into a stalled plate whose normal force coefficient saturates at cn_max,
  Cl = Cn cos(alpha), Cd = Cn sin(alpha) + cd0.

The `flat` depowering control scales the attached-flow lift (Hazen's flattening). For each beta and flat the best
sheet angle is the one that maximises the drive coefficient Cl sin(beta) - Cd cos(beta); the envelope of these
optima is the per-sail coefficient curve a classic VPP would use. The per-type parameters below were fitted so
the envelopes follow the ORC (2023) per-sail coefficient tables (Hazen's method as published in the ORC VPP
documentation) with Windmark's sheeting limits (see README.md).
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Dict

import numpy as np

from .constants import DEG


@dataclass(frozen=True)
class SailCoeffs:
    alpha_luff: float   # rad, below this the sail luffs
    alpha_stall: float  # rad, maximum attached lift
    cl_max: float
    cd0: float          # profile drag at zero lift
    kp: float           # profile drag growth with Cl^2
    cn_max: float       # stalled normal force coefficient
    blend: float        # rad, width of the attached-to-stalled blend
    kt: float = 0.0     # twist drag: eased sheets open the leech, parasitic drag grows as kt delta^2
    cd_luff: float = 0.06   # luffing drag (sail on the wind line with its sheet in; solver.CD_LUFF)
    blanket: float = 0.0    # share of a front sail's force lost in the mainsail's lee dead downwind (110-180 deg)


# Per sail type, fitted to the ORC (2023) per-sail envelopes with the sheet limits in boatclass.SHEET_LIMITS_DEG
# (tests/test_sails.py re-checks the fit). Code 0 has no published table: a flat, high-clewed reacher between the
# jib and the gennaker, set by the calibration runs.
COEFFS: Dict[str, SailCoeffs] = {
    "main": SailCoeffs(alpha_luff=3.0 * DEG, alpha_stall=12.1 * DEG, cl_max=1.39, cd0=0.006, kp=0.005,
                       cn_max=1.23, blend=25.6 * DEG, kt=0.131),
    "jib": SailCoeffs(alpha_luff=4.0 * DEG, alpha_stall=12.1 * DEG, cl_max=1.46, cd0=0.005, kp=0.005,
                      cn_max=0.51, blend=37.7 * DEG, kt=0.308),
    "code0": SailCoeffs(alpha_luff=4.0 * DEG, alpha_stall=20.0 * DEG, cl_max=1.25, cd0=0.020, kp=0.05,
                        cn_max=0.60, blend=30.0 * DEG, kt=0.20),
    "spinnaker": SailCoeffs(alpha_luff=5.3 * DEG, alpha_stall=38.8 * DEG, cl_max=0.96, cd0=0.123, kp=0.290,
                            cn_max=0.45, blend=43.3 * DEG, kt=0.072),
    "gennaker": SailCoeffs(alpha_luff=6.0 * DEG, alpha_stall=47.6 * DEG, cl_max=1.02, cd0=0.194, kp=0.155,
                           cn_max=0.386, blend=30.4 * DEG, kt=0.037, blanket=0.557),
}
COEFFS["genoa"] = COEFFS["jib"]
COEFFS["staysail"] = replace(COEFFS["jib"], cl_max=1.40)

# ORC (2023) per-sail coefficient tables the parameters above were fitted to: AWA (deg), Cl, parasitic Cd.
# ("high lift" main and jib; symmetric spinnaker; asymmetric spinnaker tacked on the centreline.)
ORC_REFERENCE = {
    "main": ([0, 7, 9, 12, 28, 60, 90, 120, 150, 180],
             [0.000, 0.948, 1.138, 1.250, 1.427, 1.383, 1.267, 0.931, 0.388, -0.112],
             [0.034, 0.017, 0.015, 0.015, 0.026, 0.113, 0.383, 0.969, 1.316, 1.345]),
    "jib": ([7, 9, 12, 28, 60, 90, 120, 150, 180],
            [0.000, 1.100, 1.475, 1.500, 1.450, 1.250, 0.400, 0.000, -0.100],
            [0.050, 0.032, 0.031, 0.037, 0.250, 0.350, 0.730, 0.950, 0.900]),
    "spinnaker": ([28, 41, 50, 60, 67, 75, 100, 115, 130, 150, 170, 180],
                  [-0.024, 0.660, 0.861, 0.992, 1.026, 1.026, 0.920, 0.805, 0.635, 0.360, 0.110, 0.000],
                  [0.182, 0.267, 0.337, 0.417, 0.465, 0.506, 0.588, 0.615, 0.636, 0.650, 0.650, 0.640]),
    "gennaker": ([28, 41, 50, 60, 67, 75, 100, 115, 130, 150, 170, 180],
                 [0.017, 0.698, 0.899, 1.040, 1.072, 1.075, 0.985, 0.805, 0.372, 0.100, 0.020, 0.000],
                 [0.154, 0.239, 0.309, 0.389, 0.436, 0.477, 0.545, 0.566, 0.475, 0.352, 0.290, 0.262]),
}


def coefficients(c: SailCoeffs, alpha, flat=1.0, delta=0.0):
    """(Cl, Cd) of one sail at angle of attack alpha (rad), flattening factor flat and sheet angle delta."""
    alpha = np.asarray(alpha, float)
    a = np.abs(alpha)
    s = np.clip((a - c.alpha_luff) / (c.alpha_stall - c.alpha_luff), 0.0, 1.0)
    cl_att = flat * c.cl_max * np.sin(0.5 * np.pi * s)
    cd_att = c.cd0 + c.kp * cl_att ** 2
    u = np.clip((a - c.alpha_stall) / c.blend, 0.0, 1.0)
    w = u * u * (3 - 2 * u)
    cn = c.cn_max * (1.0 - np.exp(-a / 0.35))
    cl_st = cn * np.cos(a)
    cd_st = cn * np.sin(a) + c.cd0
    cl = (1 - w) * cl_att + w * cl_st
    cd = (1 - w) * cd_att + w * cd_st
    cd = cd + c.kt * np.asarray(delta) ** 2
    luff = a < c.alpha_luff
    cl = np.where(luff, 0.0, cl)
    cd = np.where(luff, c.cd_luff + c.kt * np.asarray(delta) ** 2, cd)
    # a sail backed past the centreline makes negative lift
    return np.sign(alpha) * cl, cd


@dataclass
class Envelope:
    """Best-trim coefficients of one sail on a (flat, beta) grid."""
    beta: np.ndarray          # effective apparent wind angle grid, rad
    flat: np.ndarray
    cl: np.ndarray            # (flat, beta)
    cd: np.ndarray
    delta: np.ndarray         # optimal sheet angle, rad

    def at(self, fi, beta):
        """Coefficients at flat index fi (int array) and beta (array), linear in beta."""
        b = np.clip(beta, self.beta[0], self.beta[-1])
        x = b / (self.beta[1] - self.beta[0])
        i = np.minimum(x.astype(int), len(self.beta) - 2)
        t = x - i
        cl = self.cl[fi, i] * (1 - t) + self.cl[fi, i + 1] * t
        cd = self.cd[fi, i] * (1 - t) + self.cd[fi, i + 1] * t
        de = self.delta[fi, i] * (1 - t) + self.delta[fi, i + 1] * t
        return cl, cd, de


def envelope(sail_type: str, sheet_min: float, sheet_max: float, flats, dbeta: float = 0.25 * DEG,
             coeffs: SailCoeffs = None) -> Envelope:
    c = coeffs or COEFFS[sail_type]
    beta = np.arange(0.0, np.pi + 1e-9, dbeta)
    deltas = np.linspace(sheet_min, sheet_max, 241)
    flats = np.asarray(flats, float)
    alpha = beta[None, :, None] - deltas[None, None, :]
    cl, cd = coefficients(c, alpha, flats[:, None, None], deltas[None, None, :])
    cx = cl * np.sin(beta)[None, :, None] - cd * np.cos(beta)[None, :, None]
    k = np.argmax(cx, axis=2)
    take = lambda a: np.take_along_axis(a, k[..., None], axis=2)[..., 0]
    u = np.clip((beta - np.radians(110)) / np.radians(70), 0, 1)
    keep = 1 - c.blanket * u * u * (3 - 2 * u)
    return Envelope(beta=beta, flat=flats, cl=take(cl) * keep[None, :], cd=take(cd) * keep[None, :],
                    delta=deltas[k])
