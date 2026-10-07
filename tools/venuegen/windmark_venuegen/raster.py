"""The work raster: land mask and land height on a fine square grid, blurs, bilinear sampling, distances."""

from __future__ import annotations

import numpy as np


class Raster:
    """Cell-centre raster over box (xmin, ymin, xmax, ymax) at spacing h: value [j, i] at
    (xmin + (i + 0.5) h, ymin + (j + 0.5) h)."""

    def __init__(self, box, h):
        self.h = float(h)
        self.x0, self.y0 = float(box[0]), float(box[1])
        self.nx = int(np.ceil((box[2] - box[0]) / h))
        self.ny = int(np.ceil((box[3] - box[1]) / h))
        self.xc = self.x0 + (np.arange(self.nx) + 0.5) * h
        self.yc = self.y0 + (np.arange(self.ny) + 0.5) * h

    def rasterize(self, polygons):
        """Land mask (0/1) and land height (m, 0 on water) of the land polygons, even-odd per polygon by
        scanline at the cell centres."""
        mask = np.zeros((self.ny, self.nx), np.float64)
        height = np.zeros((self.ny, self.nx), np.float64)
        for poly in polygons:
            p = poly["points"]
            h = float(poly["height"])
            x1, y1 = p[:, 0], p[:, 1]
            x2, y2 = np.roll(x1, -1), np.roll(y1, -1)
            jlo = max(0, int(np.floor((y1.min() - self.y0) / self.h)))
            jhi = min(self.ny, int(np.ceil((y1.max() - self.y0) / self.h)) + 1)
            for j in range(jlo, jhi):
                y = self.yc[j]
                c = (y1 > y) != (y2 > y)
                if not c.any():
                    continue
                xs = np.sort(x1[c] + (y - y1[c]) * (x2[c] - x1[c]) / (y2[c] - y1[c]))
                for a, b in zip(xs[0::2], xs[1::2]):
                    i0 = max(0, int(np.ceil((a - self.x0) / self.h - 0.5)))
                    i1 = min(self.nx, int(np.floor((b - self.x0) / self.h - 0.5)) + 1)
                    if i1 > i0:
                        mask[j, i0:i1] = 1.0
                        height[j, i0:i1] = np.maximum(height[j, i0:i1], h)
        return mask, height

    def sample(self, field, x, y, outside=0.0):
        """Bilinear sample of a raster field at points (cell centres as nodes); `outside` beyond the raster."""
        u = (np.asarray(x, float) - self.x0) / self.h - 0.5
        v = (np.asarray(y, float) - self.y0) / self.h - 0.5
        out = (u < 0) | (v < 0) | (u > self.nx - 1) | (v > self.ny - 1)
        u = np.clip(u, 0, self.nx - 1.000001)
        v = np.clip(v, 0, self.ny - 1.000001)
        i = np.floor(u).astype(int)
        j = np.floor(v).astype(int)
        tu, tv = u - i, v - j
        r0 = field[j, i] * (1 - tu) + field[j, i + 1] * tu
        r1 = field[j + 1, i] * (1 - tu) + field[j + 1, i + 1] * tu
        r = r0 * (1 - tv) + r1 * tv
        return np.where(out, outside, r)


def _box_blur_axis(a, r, axis):
    """Box filter of half-width r cells along axis, with edge values extended."""
    if r <= 0:
        return a
    a = np.moveaxis(a, axis, -1)
    pad = np.concatenate([np.repeat(a[..., :1], r + 1, -1), a, np.repeat(a[..., -1:], r, -1)], -1)
    c = np.cumsum(pad, axis=-1)
    out = (c[..., 2 * r + 1:] - c[..., :-(2 * r + 1)]) / (2 * r + 1)
    return np.moveaxis(out, -1, axis)


def gaussian_blur(a, sigma_cells, axes=(0, 1)):
    """Gaussian blur approximated by three box passes per axis (sigma in cells)."""
    if sigma_cells <= 0:
        return a
    # three boxes of width w have variance 3 (w^2 - 1) / 12
    w = np.sqrt(4.0 * sigma_cells ** 2 + 1.0)
    r = max(0, int(round((w - 1) / 2)))
    out = a.astype(np.float64)
    for ax in axes:
        for _ in range(3):
            out = _box_blur_axis(out, r, ax)
    return out


def gaussian_kernel(sigma_cells):
    r = max(1, int(np.ceil(3.0 * sigma_cells)))
    x = np.arange(-r, r + 1, dtype=float)
    k = np.exp(-0.5 * (x / sigma_cells) ** 2)
    return k / k.sum()


def distance_to_edges(x, y, polygons, chunk=4096):
    """Distance (m) from each point to the nearest land polygon edge (0 if there are no polygons)."""
    x = np.asarray(x, float).ravel()
    y = np.asarray(y, float).ravel()
    if not polygons:
        return np.full(x.shape, np.inf)
    a = np.concatenate([p["points"] for p in polygons])
    b = np.concatenate([np.roll(p["points"], -1, axis=0) for p in polygons])
    d = b - a
    L2 = np.maximum(np.sum(d * d, axis=1), 1e-12)
    best = np.full(x.shape, np.inf)
    for s in range(0, len(x), chunk):
        px, py = x[s:s + chunk, None], y[s:s + chunk, None]
        for e0 in range(0, len(a), 2048):
            ax, ay = a[None, e0:e0 + 2048, 0], a[None, e0:e0 + 2048, 1]
            dx, dy = d[None, e0:e0 + 2048, 0], d[None, e0:e0 + 2048, 1]
            t = np.clip(((px - ax) * dx + (py - ay) * dy) / L2[None, e0:e0 + 2048], 0.0, 1.0)
            dist = np.hypot(px - (ax + t * dx), py - (ay + t * dy)).min(axis=1)
            best[s:s + chunk] = np.minimum(best[s:s + chunk], dist)
    return best


def points_in_land(x, y, polygons):
    """True where a point is inside any land polygon (even-odd per polygon)."""
    x = np.asarray(x, float).ravel()
    y = np.asarray(y, float).ravel()
    inside = np.zeros(x.shape, bool)
    for poly in polygons:
        p = poly["points"]
        x1, y1 = p[:, 0], p[:, 1]
        x2, y2 = np.roll(x1, -1), np.roll(y1, -1)
        c = np.zeros(x.shape, bool)
        for e in range(len(p)):
            cond = (y1[e] > y) != (y2[e] > y)
            if not cond.any():
                continue
            xi = x1[e] + (y - y1[e]) * (x2[e] - x1[e]) / ((y2[e] - y1[e]) if y2[e] != y1[e] else 1.0)
            c ^= cond & (x < xi)
        inside |= c
    return inside
