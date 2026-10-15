"""Downwind what-if runs: speeds per config at ORC-style TWS/TWA points under model variants.

Usage (from tools/vpp): .venv/bin/python analysis/downwind_variants.py [variant ...]
Variants are named patches of model constants (see VARIANTS); 'base' is the shipped model. Prints, per class and
variant, the best speed of each config (kn) and the run VMG, at TWS 6 8 10 12 16 20 kn.
"""
import inspect
import math
import textwrap
import os
import sys
from contextlib import contextmanager

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from windmark_vpp import boatclass, hydro, sails, solver  # noqa: E402
from windmark_vpp.perf import Generator, NF, NR  # noqa: E402
from windmark_vpp.solver import REEFS  # noqa: E402
from windmark_vpp.constants import DEG  # noqa: E402

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


def _forces_with_slot(types):
    """Rig.forces with the main's slot loss waived when any sail of `types` is set (instead of jib/genoa only)."""
    src = textwrap.dedent(inspect.getsource(solver.Rig.forces))
    src = src.replace('("jib", "genoa")', repr(tuple(types)))
    ns = {}
    exec(src, vars(solver), ns)
    return [(solver.Rig, "forces", ns["forces"])]


def _c0(**kw):
    return [(sails, "COEFFS", {**sails.COEFFS, "code0": sails.replace(sails.COEFFS["code0"], **kw)})]


VARIANTS = {
    "base": [],
    # kite: no flat floor, and the class heel limit instead of 21.5 deg
    "kite_free": [(solver, "KITE_FLAT_MIN", 0.1), (boatclass, "KITE_MAX_HEEL", math.radians(40))],
    "kite_heel25": [(boatclass, "KITE_MAX_HEEL", math.radians(25))],
    # planing gate: full ability to DLR 100 ... none from 140 (instead of 106)
    "plane_gate140": [(hydro, "PLANING_DLR_NONE", 140.0)],
    "plane_gate200": [(hydro, "PLANING_DLR_NONE", 200.0)],
    # one planing law for both hull sizes, a less generous planing branch
    "hull_a": [(hydro, "PLANING_DLR_NONE", 140.0), (hydro, "PLANING_DRAG_LIFT", 0.075)],
    "hull_b": [(hydro, "PLANING_DLR_NONE", 140.0), (hydro, "PLANING_START", 0.45), (hydro, "PLANING_FULL", 1.3)],
    "hull_c": [(hydro, "PLANING_DLR_NONE", 140.0), (hydro, "PLANING_DRAG_LIFT", 0.075),
               (hydro, "PLANING_START", 0.40), (hydro, "PLANING_FULL", 1.1)],
    # wave wall: a non-planing hull keeps the Delft curve flat past its peak (no extra wall)
    "wall_flat": [(hydro, "WAVE_WALL_SLOPE", (0.0, 0.0))],
    # code zero blanketed in the main's lee like the gennaker
    "c0_blanket": _c0(blanket=0.557),
    # code zero fitted to the ORC flying-headsail table (62.5 % HHW/HLP, analysis/fit_code0.py), main in its slot
    "c0_orc": _forces_with_slot(("jib", "genoa", "code_zero")) + _c0(
        alpha_luff=3.45 * DEG, alpha_stall=10.0 * DEG, cl_max=1.356, cd0=0.0048, kp=0.0055, cn_max=0.40,
        blend=51.0 * DEG, kt=0.357, blanket=0.51),
    # the main keeps its slot behind a code zero too / behind any front sail
    "slot_c0": _forces_with_slot(("jib", "genoa", "code_zero")),
    "slot_all": _forces_with_slot(("jib", "genoa", "code_zero", "spinnaker_sym", "spinnaker_asym")),
    "slot_c0_blanket": _forces_with_slot(("jib", "genoa", "code_zero")) + _c0(blanket=0.557),
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
