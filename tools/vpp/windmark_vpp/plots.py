"""Plots of a generated table set (PNG, headless)."""

from __future__ import annotations

import os
from typing import List

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.colors import ListedColormap  # noqa: E402

from .constants import DEG, KNOT  # noqa: E402

CATEGORICAL = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
INK = "#2b2b29"
MUTED = "#8a8980"
GRID = "#e4e3dc"
SHOW_TWS = [6, 10, 14, 19, 27]


def _seq(n):
    """Single-hue sequential blues, light to dark (magnitude = wind speed)."""
    return [plt.cm.Blues(0.35 + 0.6 * i / max(n - 1, 1)) for i in range(n)]


def _style(ax):
    ax.tick_params(colors=MUTED, labelsize=8)
    for s in ax.spines.values():
        s.set_color(GRID)
    ax.grid(color=GRID, lw=0.6)
    ax.title.set_color(INK)


def _t2(t):
    """(axis0, axis1, values 2-D) of a Table2D."""
    a0 = np.array(t["axes"][0]["points"])
    a1 = np.array(t["axes"][1]["points"])
    return a0, a1, np.array(t["values"]).reshape(len(a0), len(a1))


def _label(cfg):
    return "main" if cfg["front_sail"] is None else f"main + {cfg['front_sail']}"


def plot_all(perf: dict, outdir: str) -> List[str]:
    cid = perf["class_id"]
    cfgs = perf["configs"]
    twa = np.concatenate([np.arange(20, 60, 2), np.arange(60, 180.01, 5)])
    tws_all = np.array(cfgs[0]["polar"]["axes"][0]["points"])
    rows = [int(np.argmin(abs(tws_all / KNOT - t))) for t in SHOW_TWS]
    cols = _seq(len(rows))
    n = len(cfgs)

    def on_grid(tab):
        a0, a1, v = _t2(tab)
        return np.stack([np.interp(twa * DEG, a1, row) for row in v])

    speeds = np.stack([on_grid(c["polar"]) / KNOT for c in cfgs])
    heels = np.stack([on_grid(c["heel"]) / DEG for c in cfgs])
    best_i = np.argmax(speeds, axis=0)
    best = speeds.max(axis=0)
    heel = np.take_along_axis(heels, best_i[None], 0)[0]
    files = []

    # 1. polar of the best configuration with VMG optima
    fig = plt.figure(figsize=(6.4, 6.4))
    ax = fig.add_subplot(projection="polar")
    ax.set_theta_zero_location("N")
    ax.set_theta_direction(-1)
    ax.set_thetamin(0)
    ax.set_thetamax(180)
    vmg = perf["vpp"]["vmg"]
    for c, i in zip(cols, rows):
        ax.plot(np.radians(twa), best[i], color=c, lw=2, label=f"{tws_all[i] / KNOT:.0f} kn")
        for side in ("upwind", "downwind"):
            v = vmg[i - 1][side]
            ax.plot([v["twa"]], [v["speed"] / KNOT], "o", ms=8, color=c, mec="white", mew=1.5)
    ax.set_title(f"{cid}: boat speed (kn), fastest sail; dots = VMG optima", fontsize=10, pad=14)
    ax.legend(loc="lower left", bbox_to_anchor=(0.0, 0.0), fontsize=8, frameon=False, title="TWS")
    _style(ax)
    files.append(_save(fig, outdir, f"{cid}_polar.png"))

    # 2. speed per configuration (small multiples, shared y)
    fig, axs = plt.subplots(1, n, figsize=(3.2 * n, 3.4), sharey=True, squeeze=False)
    for ax, cfg, V in zip(axs[0], cfgs, speeds):
        for c, i in zip(cols, rows):
            ax.plot(twa, V[i], color=c, lw=2, label=f"{tws_all[i] / KNOT:.0f} kn")
        ax.set_title(_label(cfg), fontsize=9)
        ax.set_xlabel("TWA (deg)", fontsize=8, color=MUTED)
        ax.set_xlim(20, 180)
        _style(ax)
    axs[0][0].set_ylabel("boat speed (kn)", fontsize=8, color=MUTED)
    axs[0][-1].legend(fontsize=7, frameon=False, title="TWS", title_fontsize=7)
    fig.tight_layout()
    files.append(_save(fig, outdir, f"{cid}_configs.png"))

    # 3. sail crossover chart: fastest configuration per (TWS, TWA)
    fig, ax = plt.subplots(figsize=(7.5, 3.6))
    cmap = ListedColormap(CATEGORICAL[:n])
    ax.pcolormesh(_edges(twa), _edges(tws_all / KNOT), np.where(best > 0.1, best_i, np.nan), cmap=cmap,
                  vmin=-0.5, vmax=n - 0.5, edgecolors="white", linewidth=0.5)
    for j, cfg in enumerate(cfgs):
        ax.plot([], [], "s", color=CATEGORICAL[j], ms=9, label=_label(cfg))
    ax.legend(fontsize=7, frameon=False, loc="upper left", bbox_to_anchor=(1.0, 1.0))
    ax.set_xlabel("TWA (deg)", fontsize=8, color=MUTED)
    ax.set_ylabel("TWS (kn)", fontsize=8, color=MUTED)
    ax.set_title("Fastest sail configuration", fontsize=10)
    _style(ax)
    ax.grid(False)
    fig.tight_layout()
    files.append(_save(fig, outdir, f"{cid}_crossover.png"))

    # 4. heel of the fastest configuration, and the optimal sheet angles at 12 kn TWS
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(9.5, 3.6))
    for c, i in zip(cols, rows):
        a1.plot(twa, heel[i], color=c, lw=2, label=f"{tws_all[i] / KNOT:.0f} kn")
    a1.set_xlim(20, 180)
    a1.set_xlabel("TWA (deg)", fontsize=8, color=MUTED)
    a1.set_ylabel("heel (deg), fastest sail", fontsize=8, color=MUTED)
    a1.legend(fontsize=7, frameon=False, title="TWS", title_fontsize=7)
    a1.set_title("Heel", fontsize=10)
    _style(a1)
    k = 0
    for cfg in cfgs:
        for sid, tab in cfg["optimal_angle"].items():
            if sid == "main" and cfg["front_sail"] is not None:
                continue
            a0, aw, v = _t2(tab)
            i12 = int(np.argmin(abs(a0 / KNOT - 12)))
            a2.plot(aw / DEG, v[i12] / DEG, color=CATEGORICAL[k % 8], lw=2,
                    label=sid if cfg["front_sail"] else "main (alone)")
            k += 1
    a2.set_xlabel("AWA (deg)", fontsize=8, color=MUTED)
    a2.set_ylabel("optimal sheet angle (deg)", fontsize=8, color=MUTED)
    a2.set_title("Trim at 12 kn TWS", fontsize=10)
    a2.legend(fontsize=7, frameon=False)
    _style(a2)
    fig.tight_layout()
    files.append(_save(fig, outdir, f"{cid}_heel_trim.png"))
    return files


def _edges(c):
    c = np.asarray(c, float)
    m = (c[1:] + c[:-1]) / 2
    return np.concatenate([[c[0] - (m[0] - c[0])], m, [c[-1] + (c[-1] - m[-1])]])


def _save(fig, outdir, name):
    p = os.path.join(outdir, name)
    fig.savefig(p, dpi=110, facecolor="white")
    plt.close(fig)
    return p
