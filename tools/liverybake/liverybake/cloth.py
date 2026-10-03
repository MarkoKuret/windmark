"""Tiling cloth detail of the baked sails (sail_visuals.md §11.2): the millimetre structure no sail image can hold,
one 512 x 512 tile per cloth, 0.125 m across, seamless.

RGB = relief (red, green: the normal's x and y, 0.5 = flat) and brightness (blue: albedo factor / 2, so 0.5 = x1).
Made here, procedurally; written by the staging step into game/generated/liveries/_cloth/ (not hand-owned).
"""
import numpy as np

from .common import F32, Rng

SIZE = 512
TILE_M = 0.125


def _periodic_noise(rng, n, cycles_max, count=24):
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(F32)
    out = np.zeros((SIZE, SIZE), F32)
    for _ in range(count):
        fu, fv = rng.integers(-cycles_max, cycles_max + 1, 2)
        if fu == 0 and fv == 0:
            continue
        out += np.cos(2 * np.pi * (fu * u + fv * v) / SIZE + rng.uniform(0, 2 * np.pi)).astype(F32)
    return out / np.sqrt(count * 0.5)


def detail(cloth):
    """(SIZE, SIZE, 3) float in [0, 1] of the cloth's detail tile."""
    rng = Rng("cloth", cloth)
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(F32)
    px = TILE_M / SIZE
    if cloth == "dacron":
        # plain weave, threads about 1 mm apart, warp and weft over and under, with uneven threads
        p = 4.0
        a = np.cos(np.pi * u / p)
        b = np.cos(np.pi * v / p)
        warp = 0.5 + 0.5 * a * np.sign(np.cos(np.pi * (v / p + 0.5)))
        weft = 0.5 + 0.5 * b * np.sign(np.cos(np.pi * (u / p + 0.5)))
        h = np.maximum(warp, weft) * 0.00008
        slub = _periodic_noise(rng, SIZE, 24) * 0.25 + _periodic_noise(rng, SIZE, 3) * 0.6
        h += slub * 0.00002
        bright = 1.0 + 0.05 * (np.maximum(warp, weft) - 0.5) + 0.02 * slub
    elif cloth == "laminate":
        # smooth film over a fine scrim (light threads every 4 mm) with crinkles from handling
        p = 16.0
        grid = np.maximum(np.exp(-((u % p) - p / 2) ** 2 / 1.2), np.exp(-((v % p) - p / 2) ** 2 / 1.2))
        crinkle = np.zeros((SIZE, SIZE), F32)
        for _ in range(60):
            fu, fv = rng.integers(-6, 7, 2)
            if fu == 0 and fv == 0:
                continue
            ph = 2 * np.pi * (fu * u + fv * v) / SIZE + rng.uniform(0, 2 * np.pi)
            crinkle += np.abs(np.sin(ph)).astype(F32) ** 8
        crinkle /= crinkle.max()
        h = 0.00003 * grid + 0.00006 * crinkle + 0.00001 * _periodic_noise(rng, SIZE, 40)
        bright = 1.0 + 0.04 * grid + 0.05 * crinkle
    else:
        # nylon ripstop: a fine plain weave with a doubled thread every 6 mm both ways
        p = 2.0
        fine = np.cos(np.pi * u / p) * np.cos(np.pi * v / p)
        rp = SIZE / round(TILE_M / 0.006)
        rip = np.maximum(np.exp(-(((u + 0.5 * rp) % rp) - rp / 2) ** 2 / 2.0),
                         np.exp(-(((v + 0.5 * rp) % rp) - rp / 2) ** 2 / 2.0))
        h = 0.00002 * fine + 0.00006 * rip + 0.00001 * _periodic_noise(rng, SIZE, 30)
        bright = 1.0 + 0.02 * fine - 0.06 * rip
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * px)
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2 * px)
    n = np.stack([-gx, gy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    out = np.stack([n[..., 0] * 0.5 + 0.5, n[..., 1] * 0.5 + 0.5, np.clip(bright, 0, 2) * 0.5], -1)
    return out.astype(F32)
