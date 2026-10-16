"""Downwind what-if runs: speeds per config at ORC-style TWS/TWA points under model variants.

Usage (from tools/vpp): .venv/bin/python analysis/downwind_variants.py [variant ...]
Variants are named patches of model constants (see VARIANTS); 'base' is the shipped model. The variants of the
first study (hull_a, c0_orc, slot_all, ...) went into the shipped model in 2026-10 (downwind_2026-10.md).
Prints, per class and variant, the best speed of each config (kn) and the run VMG, at TWS 6 8 10 12 16 20 kn.
"""
import math
import os
import sys
from contextlib import contextmanager

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from windmark_vpp import boatclass, hydro, solver  # noqa: E402
from windmark_vpp.perf import Generator, NF, NR  # noqa: E402
from windmark_vpp.solver import REEFS  # noqa: E402

KN = 0.514444
CLASSES = os.path.join(HERE, "..", "..", "..", "data", "classes")
TWS_KN = np.array([6, 8, 10, 12, 16, 20.0])
TWA = np.array([52, 60, 75, 90, 110, 120, 135, 150, 165, 180.0])
RUN = np.arange(130, 180.1, 2.5)


@contextmanager
def patched(pairs):
    old = []
    for obj, name, val in pairs:
        old.append((obj, name, getattr(obj, name)))
        setattr(obj, name, val)
    try:
        yield
    finally:
        for obj, name, val in reversed(old):
            setattr(obj, name, val)


VARIANTS = {
    "base": [],
    # kite: no flat floor, and the class heel limit instead of 21.5 deg
    "kite_free": [(solver, "KITE_FLAT_MIN", 0.1), (boatclass, "KITE_MAX_HEEL", math.radians(40))],
    "kite_heel25": [(boatclass, "KITE_MAX_HEEL", math.radians(25))],
    # planing (2026-10 law: the Delft hump stretched past Fn 0.35, gated from DLR 100 to 200)
    "towed": [(hydro, "HUMP_STRETCH", 1.0)],                                  # no stretch: the towed Delft curve
    "gate_narrow": [(hydro, "PLANING_DLR_NONE", 106.0)],                      # the old gate (wm12 does not plane)
    "stretch_045": [(hydro, "HUMP_STRETCH", 0.45)],
    "stretch_055": [(hydro, "HUMP_STRETCH", 0.55)],
    # wave wall: a non-planing hull keeps the Delft curve flat past its peak (no extra wall)
    "wall_flat": [(hydro, "WAVE_WALL_SLOPE", (0.0, 0.0))],
    # code zero sheeted as close as before the 2026-10 fit
    "c0_sheet12": [(boatclass, "SHEET_LIMITS", {**boatclass.SHEET_LIMITS,
                                                "code_zero": (math.radians(12.0), math.radians(55.0))})],
}


def run(cls, variant):
    with patched(VARIANTS[variant]):
        boat = boatclass.load(os.path.join(CLASSES, f"{cls}.boat.json"))
        g = Generator(boat)
        out = {}
        for front, rig in g.rigs:
            name = front or "main"
            twa = np.concatenate([TWA, RUN]) * math.pi / 180
            T, A = len(TWS_KN), len(twa)
            fi = np.repeat(np.arange(NF), NR)[None, None, :]
            rf = np.tile(REEFS, NF)[None, None, :]
            st = g.solver.solve(rig, fi, rf, (TWS_KN * KN)[:, None, None], twa[None, :, None])
            V = np.where(st.valid & (st.V > 0.02), st.V, 0.0).reshape(T, A, -1).max(axis=-1) / KN
            out[name] = V
        return out, np.concatenate([TWA, RUN])


def report(cls, variant, res, twa):
    print(f"\n## {cls} / {variant}   (kn; TWS " + " ".join(f"{t:g}" for t in TWS_KN) + ")")
    for a in TWA:
        j = int(np.where(twa == a)[0][0])
        print(f"{a:5.0f} " + " | ".join(f"{n:>5} " + " ".join(f"{res[n][i, j]:5.2f}" for i in range(len(TWS_KN)))
                                      for n in res))
    print("run VMG (angle/speed/vmg):")
    for n, V in res.items():
        vmg = V * -np.cos(np.radians(twa))[None, :]
        vmg[:, twa < 90] = -1
        k = np.argmax(vmg, axis=1)
        print(f"  {n:>5} " + "  ".join(f"{twa[k[i]]:5.1f}/{V[i, k[i]]:5.2f}/{vmg[i, k[i]]:5.2f}"
                                       for i in range(len(TWS_KN))))


if __name__ == "__main__":
    names = sys.argv[1:] or ["base"]
    for cls in ("wm7", "wm12"):
        for v in names:
            res, twa = run(cls, v)
            report(cls, v, res, twa)
