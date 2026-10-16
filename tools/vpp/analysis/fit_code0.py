"""Fit the code zero's sail parameters to the ORC (2023) flying-headsail table (VPP Documentation Table 5.9).

Usage (from tools/vpp): .venv/bin/python analysis/fit_code0.py [column] [sheet_max_deg] [sheet_min_deg]
column: 62.5 (default) or 73, the HHW/HLP ratio of the ORC coefficient set; the sheet limits default to
boatclass.SHEET_LIMITS["code_zero"]. Prints the fitted SailCoeffs and the
envelope against the table (drive cx and side cy coefficients at best trim, flat 1).
"""
import os
import sys

import numpy as np
from scipy.optimize import minimize

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from windmark_vpp import sails  # noqa: E402
from windmark_vpp.boatclass import SHEET_LIMITS  # noqa: E402
from windmark_vpp.constants import DEG  # noqa: E402

AWA = [27, 35, 41, 45, 50, 60, 67, 75, 80, 90, 100, 115, 120, 130, 150, 170, 180]
ORC_FHS = {   # HHW/HLP: (CL, CD0) at AWA
    62.5: ([1.315, 1.440, 1.475, 1.480, 1.460, 1.400, 1.265, 1.090, 0.995, 0.800, 0.608, 0.357, 0.291, 0.176, 0.024,
            -0.012, -0.022],
           [0.060, 0.095, 0.135, 0.165, 0.205, 0.295, 0.355, 0.415, 0.455, 0.500, 0.522, 0.510, 0.504, 0.486, 0.451,
            0.392, 0.370]),
    73.0: ([0.980, 1.150, 1.220, 1.265, 1.300, 1.300, 1.270, 1.222, 1.140, 0.960, 0.741, 0.451, 0.357, 0.200, 0.032,
            -0.006, -0.011],
           [0.077, 0.130, 0.170, 0.200, 0.240, 0.320, 0.385, 0.450, 0.475, 0.510, 0.525, 0.520, 0.510, 0.480, 0.422,
            0.352, 0.322]),
}
NAMES = ["alpha_luff", "alpha_stall", "cl_max", "cd0", "kp", "cn_max", "blend", "kt", "blanket"]


def make(x):
    al, ast, clm, cd0, kp, cnm, bl, kt, bk = x
    return sails.SailCoeffs(alpha_luff=al * DEG, alpha_stall=ast * DEG, cl_max=clm, cd0=cd0, kp=kp, cn_max=cnm,
                            blend=bl * DEG, kt=kt, blanket=bk)


def env(c, lo, hi):
    e = sails.envelope("code0", lo, hi, [1.0], coeffs=c, dbeta=0.5 * DEG, n_delta=121)
    b = np.array(AWA) * DEG
    cl, cd, de = e.at(np.zeros(len(b), int), b)
    return b, cl, cd, de


def err(x, ref, lo, hi):
    # physical bounds: luffing from 3 deg, attached flow to at least 10 deg, a stalled plate of at least 0.4
    if x[0] < 3 or x[1] < 10 or x[1] > 30 or min(x[2:]) < 0 or x[5] < 0.4 or x[8] > 0.9:
        return 1e3
    b, cl, cd, _ = env(make(x), lo, hi)
    rl, rd = map(np.array, ref)
    cx = cl * np.sin(b) - cd * np.cos(b)
    cy = cl * np.cos(b) + cd * np.sin(b)
    rx = rl * np.sin(b) - rd * np.cos(b)
    ry = rl * np.cos(b) + rd * np.sin(b)
    return np.mean((cx - rx) ** 2) + 0.5 * np.mean((cy - ry) ** 2)


if __name__ == "__main__":
    col = float(sys.argv[1]) if len(sys.argv) > 1 else 62.5
    hi = float(sys.argv[2]) * DEG if len(sys.argv) > 2 else SHEET_LIMITS["code_zero"][1]
    lo = float(sys.argv[3]) * DEG if len(sys.argv) > 3 else SHEET_LIMITS["code_zero"][0]
    ref = ORC_FHS[col]
    c0 = sails.COEFFS["code0"]
    x0 = [c0.alpha_luff / DEG, c0.alpha_stall / DEG, c0.cl_max, c0.cd0, c0.kp, c0.cn_max, c0.blend / DEG, c0.kt,
          c0.blanket]
    print("shipped code0, error", err(x0, ref, lo, hi))
    best = None
    for start in (x0, [4, 14, 1.45, 0.01, 0.02, 0.6, 30, 0.1, 0.4], [4, 12, 1.5, 0.005, 0.005, 0.5, 38, 0.3, 0.5]):
        r = minimize(err, start, args=(ref, lo, hi), method="Nelder-Mead",
                     options={"maxiter": 4000, "xatol": 1e-4, "fatol": 1e-7})
        if best is None or r.fun < best.fun:
            best = r
    print(f"fit to ORC {col}% (sheet {lo / DEG:.0f}-{hi / DEG:.0f} deg): error {best.fun:.5f}")
    print("  " + ", ".join(f"{n}={v:.4g}" for n, v in zip(NAMES, best.x)))
    b, cl, cd, de = env(make(best.x), lo, hi)
    bs, cls, cds, _ = env(c0, lo, hi)
    rl, rd = map(np.array, ref)
    print("  AWA   ORC cx  fit cx  shipped cx | ORC cy  fit cy | sheet")
    for i, a in enumerate(AWA):
        s, k = np.sin(b[i]), np.cos(b[i])
        print(f"  {a:3d}  {rl[i] * s - rd[i] * k:6.3f}  {cl[i] * s - cd[i] * k:6.3f}  {cls[i] * s - cds[i] * k:6.3f}"
              f"     | {rl[i] * k + rd[i] * s:6.3f}  {cl[i] * k + cd[i] * s:6.3f} | {de[i] / DEG:5.1f}")
