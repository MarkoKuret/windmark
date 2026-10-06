"""Command line: python -m windmark_venuegen <id>.venuesrc.json [-o <id>.venue.json | -o DIR] [--check].

--check validates venue files (and <id>.terrain.json files with their binary)."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time

from .build import SourceError, build_file
from .geo import InputError
from .terrain import check_terrain
from .validate import validate


def main(argv=None):
    ap = argparse.ArgumentParser(prog="windmark_venuegen", description=__doc__)
    ap.add_argument("source", nargs="+", help="venue source file(s), windmark.venuesrc/1 (or venue files with --check)")
    ap.add_argument("-o", "--out", help="venue file (one source) or output directory")
    ap.add_argument("--check", action="store_true", help="only validate the given venue files (windmark.venue/1)")
    args = ap.parse_args(argv)
    if args.check:
        bad = 0
        for path in args.source:
            with open(path) as f:
                text = f.read()
            if path.endswith(".terrain.json"):
                t = json.loads(text)
                binp = os.path.join(os.path.dirname(path), t.get("bin", ""))
                problems = check_terrain(t, os.path.getsize(binp) if os.path.isfile(binp) else None)
            else:
                problems = validate(json.loads(text), text)
            print(f"{path}: {'ok' if not problems else str(len(problems)) + ' problems'}")
            for p in problems:
                print("  ", p)
            bad += bool(problems)
        return 1 if bad else 0
    for path in args.source:
        t0 = time.time()
        out = args.out
        if out is None or len(args.source) > 1 or os.path.isdir(out):
            d = out or os.path.dirname(os.path.abspath(path))
            os.makedirs(d, exist_ok=True)
            with open(path) as f:
                vid = json.load(f).get("id", "venue")
            out = os.path.join(d, f"{vid}.venue.json")
        try:
            _, text, notes, _terrain = build_file(path, out)
        except (SourceError, InputError) as e:
            print(f"{path}: {e}", file=sys.stderr)
            return 2
        print(f"{path} -> {out} ({len(text) / 1024:.0f} KB, {time.time() - t0:.1f} s)")
        for n in notes:
            print("  note:", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
