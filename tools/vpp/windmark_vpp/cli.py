"""Command line: python -m windmark_vpp <class.boat.json> [-o class.perf.json] [--plots DIR]."""

from __future__ import annotations

import argparse
import os
import json
import sys
import time

from . import boatclass
from .perf import generate, validate


def main(argv=None):
    ap = argparse.ArgumentParser(prog="windmark_vpp", description=__doc__)
    ap.add_argument("classfile", nargs="+", help="boat-class file(s), windmark.boatclass/1")
    ap.add_argument("-o", "--out", help="performance file (one class) or output directory (several)")
    ap.add_argument("--plots", help="directory for polar plots (PNG)")
    ap.add_argument("--physics", help="boat generator physics sidecar (<id>.physics.json) or its directory; its "
                    "perf_inputs block is copied into the performance file")
    ap.add_argument("--thin-ship", action="store_true", help="Michell thin-ship wave resistance for a monohull too")
    args = ap.parse_args(argv)
    for path in args.classfile:
        t0 = time.time()
        try:
            boat = boatclass.load(path)
        except boatclass.ClassFileError as e:
            print(f"{path}: {e}", file=sys.stderr)
            return 2
        physics = None
        if args.physics:
            pp = args.physics
            if os.path.isdir(pp):
                pp = os.path.join(pp, f"{boat.id}.physics.json")
            with open(pp) as f:
                physics = json.load(f)
        tables = generate(boat, thin_ship=True if args.thin_ship else None, physics=physics)
        validate(tables)
        out = args.out
        if out is None or len(args.classfile) > 1:
            d = out or os.path.dirname(os.path.abspath(path))
            os.makedirs(d, exist_ok=True)
            out = os.path.join(d, f"{boat.id}.perf.json")
        with open(out, "w") as f:
            json.dump(tables, f, separators=(",", ":"))
            f.write("\n")
        msg = f"{path} -> {out} ({time.time() - t0:.1f} s)"
        if args.plots:
            from .plots import plot_all
            os.makedirs(args.plots, exist_ok=True)
            files = plot_all(tables, args.plots)
            msg += f", {len(files)} plots"
        print(msg)
        for n in tables["vpp"]["notes"]:
            print("  note:", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
