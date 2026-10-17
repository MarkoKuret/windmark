"""Downwind summary of a performance file: speed per config at ORC-style TWA rows, run VMG.

Usage: python downwind_table.py ../../../data/perf/wm12.perf.json
Speeds in knots, TWS columns 6 8 10 12 14 16 20 kn (interpolated linearly in TWS, TWA on a 1 deg grid).
"""
import json
import sys

import numpy as np

KN = 0.514444
TWS_KN = [6, 8, 10, 12, 14, 16, 20]
ROWS = [52, 60, 75, 90, 110, 120, 135, 150, 165, 180]


def table_kn(tab, tws_kn, fine, scale=1.0):
    """Resample a (tws, twa) table onto tws_kn rows and the fine TWA grid (deg)."""
    tws = np.array(tab["axes"][0]["points"])
    twa = np.degrees(np.array(tab["axes"][1]["points"]))
    v = np.array(tab["values"], dtype=float).reshape(len(tws), len(twa))
    keep = np.r_[np.diff(twa) > 1e-9, True]
    twa, v = twa[keep], v[:, keep]
    out = []
    for k in tws_kn:
        row = np.array([np.interp(k * KN, tws, v[:, j]) for j in range(len(twa))])
        out.append(np.interp(fine, twa, row, left=row[0], right=row[-1]) * scale)
    return np.array(out)


def grid(cfg):
    fine = np.arange(0, 181, 1.0)
    s = table_kn(cfg["polar"], TWS_KN, fine, 1 / KN)
    b = table_kn(cfg["vpp"]["broached"], TWS_KN, fine) if "broached" in cfg["vpp"] else np.zeros_like(s)
    return fine, s, b


def main(path):
    d = json.load(open(path))
    cfgs = {(c["front_sail"] or "main"): grid(c) for c in d["configs"]}
    print(f"# {d['class_id']}  speeds kn; '*' = broached cell")
    print("TWA   cfg    " + " ".join(f"{k:>6}" for k in TWS_KN))
    for a in ROWS:
        for name, (fine, s, b) in cfgs.items():
            i = int(a)
            print(f"{a:>3}  {name:>6}  " + " ".join(f"{s[j, i]:6.2f}{'*' if b[j, i] > 0.5 else ' '}" for j in range(len(TWS_KN))))
        print()
    print("run VMG (best TWA 90-180): angle / speed / VMG")
    for name, (fine, s, b) in cfgs.items():
        cells = []
        for j in range(len(TWS_KN)):
            m = (fine >= 90) & (b[j] < 0.5)
            vmg = -s[j] * np.cos(np.radians(fine))
            vmg = np.where(m, vmg, -1)
            i = int(np.argmax(vmg))
            cells.append(f"{fine[i]:4.0f}/{s[j, i]:5.2f}/{vmg[i]:5.2f}")
        print(f"{name:>6}  " + "  ".join(cells))
    print("beat VMG: angle / speed / VMG")
    for name, (fine, s, b) in cfgs.items():
        cells = []
        for j in range(len(TWS_KN)):
            m = (fine <= 90) & (b[j] < 0.5) & (s[j] > 0)
            vmg = np.where(m, s[j] * np.cos(np.radians(fine)), -1)
            i = int(np.argmax(vmg))
            cells.append(f"{fine[i]:4.0f}/{s[j, i]:5.2f}/{vmg[i]:5.2f}")
        print(f"{name:>6}  " + "  ".join(cells))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
