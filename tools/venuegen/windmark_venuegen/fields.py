"""The generated grids of data_format.md §6.2 to §6.4: wind field (8 sectors), current field, exposure.

The model is in docs/specs/venues.md §5.3 to §5.5; every constant there has its default in DEFAULTS and can be
overridden per venue in the source file (`wind`, `current`, `exposure` blocks)."""

from __future__ import annotations

import math

import numpy as np

from .raster import Raster, distance_to_edges, gaussian_blur, gaussian_kernel, points_in_land

WIND_DEFAULTS = {
    "work_resolution": 25.0,  # m, the fine raster the fields are computed on
    "shadow_max": 0.5,        # deficit right behind land of great height
    "shadow_h_ref": 15.0,     # m: the deficit behind land of height h is shadow_max * h / (h + shadow_h_ref)
    "wake_per_height": 30.0,  # wake recovery length = this * land height (m), clamped below
    "wake_min": 400.0,
    "wake_max": 6000.0,
    "wake_diffusivity": 45.0,  # m: lateral wake spread, sigma(s) = sqrt(2 K s)
    "bend_per_height": 6.0,    # bending reach (blur sigma) = this * typical land height, clamped below
    "bend_min": 150.0,
    "bend_max": 1000.0,
    "onshore_block": 0.5,      # share of the onshore (toward land) wind component removed at a high shore
    "offshore_turn": 0.5,      # share of the along-shore component removed where the wind leaves the shore
    "max_bend": 0.5,           # rad, the largest direction offset written
    "coriolis": 0.08,          # speed change in the coastal convergence band (land on the right, N hemisphere)
    "coriolis_length": 1500.0,  # m, the width (blur sigma) of that band
    "taper": 500.0,            # m, the deviation fades to (1, 0) over this distance inside the grid edge
    "f_max": 1.5,
}

CURRENT_DEFAULTS = {
    "shore_length": 400.0,  # m, the stream recovers from the shore over this distance
    "shore_floor": 0.2,     # stream speed at the shore as a share of the open-water speed
    "bank_blur": 100.0,     # m, edge softening of the bank polygons
}

EXPOSURE_DEFAULTS = {
    "fade_length": 100.0,  # m, the sea fades out over this distance from the shore
    "spread": 1.5708,      # rad, the half-width of the wave directions averaged around the typical wind
    "directions": 61,      # rays in the fetch average (3 degrees apart over +-90)
}


def grid_nodes(g):
    x = float(g["x0"]) + np.arange(g["nx"], dtype=float) * float(g["dx"])
    y = float(g["y0"]) + np.arange(g["ny"], dtype=float) * float(g["dy"])
    X, Y = np.meshgrid(x, y)  # row j (y) major, i fastest
    return X.ravel(), Y.ravel()


class Rotated:
    """A raster aligned with a direction: rows advance along unit vector `u` (downwind), columns along its
    right-hand side `r`. Used to march wakes and fetches row by row."""

    def __init__(self, R: Raster, u):
        self.R = R
        self.u = np.array(u, float)
        self.r = np.array([self.u[1], -self.u[0]])
        cx = R.x0 + R.nx * R.h / 2
        cy = R.y0 + R.ny * R.h / 2
        self.c = np.array([cx, cy])
        half = 0.5 * math.hypot(R.nx * R.h, R.ny * R.h)
        self.ds = R.h
        self.n = int(np.ceil(2 * half / self.ds)) + 1
        self.a = -half + np.arange(self.n) * self.ds
        A, C = np.meshgrid(self.a, self.a, indexing="ij")  # [row (along u), col (along r)]
        self.X = self.c[0] + A * self.u[0] + C * self.r[0]
        self.Y = self.c[1] + A * self.u[1] + C * self.r[1]

    def take(self, field, outside=0.0):
        return self.R.sample(field, self.X, self.Y, outside)

    def sample(self, rot_field, x, y):
        dx, dy = np.asarray(x) - self.c[0], np.asarray(y) - self.c[1]
        a = dx * self.u[0] + dy * self.u[1]
        c = dx * self.r[0] + dy * self.r[1]
        fa = (a - self.a[0]) / self.ds
        fc = (c - self.a[0]) / self.ds
        fa = np.clip(fa, 0, self.n - 1.000001)
        fc = np.clip(fc, 0, self.n - 1.000001)
        i, j = np.floor(fa).astype(int), np.floor(fc).astype(int)
        ta, tc = fa - i, fc - j
        r0 = rot_field[i, j] * (1 - tc) + rot_field[i, j + 1] * tc
        r1 = rot_field[i + 1, j] * (1 - tc) + rot_field[i + 1, j + 1] * tc
        return r0 * (1 - ta) + r1 * ta


def _shore_normals(R, mask, sigma, x, y):
    """Seaward unit normal and shore strength b in [0, 1] (1 at a long straight shore, fading over sigma)."""
    phi = gaussian_blur(mask, sigma / R.h)
    gy, gx = np.gradient(phi, R.h)
    sx, sy = R.sample(gx, x, y), R.sample(gy, x, y)
    g = np.hypot(sx, sy)
    b = np.clip(g * sigma * math.sqrt(2 * math.pi), 0.0, 1.0)
    with np.errstate(invalid="ignore", divide="ignore"):
        nx = np.where(g > 1e-12, -sx / g, 0.0)
        ny = np.where(g > 1e-12, -sy / g, 0.0)
    return nx, ny, b


def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def _taper(g, x, y, length):
    xmax = g["x0"] + (g["nx"] - 1) * g["dx"]
    ymax = g["y0"] + (g["ny"] - 1) * g["dy"]
    d = np.minimum.reduce([x - g["x0"], xmax - x, y - g["y0"], ymax - y])
    t = np.clip(d / max(length, 1e-9), 0.0, 1.0)
    w = t * t * (3 - 2 * t)
    border = (np.isclose(x, g["x0"]) | np.isclose(x, xmax) | np.isclose(y, g["y0"]) | np.isclose(y, ymax))
    return np.where(border, 0.0, w)


def wind_field(grid, R, mask, height, hemisphere, p):
    """8 sectors of (f, d) on the grid nodes."""
    x, y = grid_nodes(grid)
    land_h = height[mask > 0.5]
    h_typ = float(np.mean(land_h)) if land_h.size else 0.0
    sigma_b = float(np.clip(p["bend_per_height"] * h_typ, p["bend_min"], p["bend_max"]))
    nx_, ny_, b = _shore_normals(R, mask, sigma_b, x, y)
    nxc, nyc, bc = _shore_normals(R, mask, p["coriolis_length"], x, y)
    m_blur = gaussian_blur(mask, sigma_b / R.h)
    h_blur = gaussian_blur(height, sigma_b / R.h)
    hbar = R.sample(np.where(m_blur > 1e-6, h_blur / np.maximum(m_blur, 1e-6), 0.0), x, y)
    taper = _taper(grid, x, y, p["taper"])
    sectors = []
    for k in range(8):
        th = k * math.pi / 4
        u = np.array([-math.sin(th), -math.cos(th)])  # downwind
        shadow = _wake(R, mask, height, u, p, x, y)
        # bending at the shore
        un = u[0] * nx_ + u[1] * ny_
        k_on = p["onshore_block"] * b * hbar / (hbar + p["shadow_h_ref"])
        k_off = p["offshore_turn"] * b
        tx, ty = u[0] - un * nx_, u[1] - un * ny_  # along-shore part
        on = un < 0
        vx = np.where(on, u[0] - k_on * un * nx_, un * nx_ + (1 - k_off) * tx)
        vy = np.where(on, u[1] - k_on * un * ny_, un * ny_ + (1 - k_off) * ty)
        vn = np.hypot(vx, vy)
        # blocking slows the wind only close to the shore (b squared: about half the bending reach)
        bx, by = u[0] - k_on * b * un * nx_, u[1] - k_on * b * un * ny_
        block = np.where(on, np.hypot(bx, by), 1.0)
        d = _wrap(np.arctan2(vx, vy) - math.atan2(u[0], u[1]))
        d = np.where(vn > 1e-9, d, 0.0)
        d = np.clip(d, -p["max_bend"], p["max_bend"])
        # coastal convergence: land on the right looking downwind (northern hemisphere) strengthens the wind
        side = -(nxc * u[1] - nyc * u[0])  # (-n) . right(u), right(u) = (u_y, -u_x)
        cor = 1.0 + p["coriolis"] * hemisphere * side * bc
        f = (1.0 - shadow) * block * cor
        f = np.clip(f, 0.0, p["f_max"])
        f = 1.0 + taper * (f - 1.0)
        d = taper * d
        sectors.append((f, d))
    return sectors


def _wake(R, mask, height, u, p, x, y):
    """Shadow deficit marched downwind: land sets the deficit, which decays with distance (recovery length
    from the land height) and spreads sideways like a plane wake (diffusion)."""
    rot = Rotated(R, u)
    m = rot.take(mask)
    h = rot.take(height)
    ds = rot.ds
    k = gaussian_kernel(math.sqrt(2.0 * p["wake_diffusivity"] * ds) / ds)
    S = np.zeros(rot.n)
    SH = np.zeros(rot.n)
    out = np.empty((rot.n, rot.n))
    with np.errstate(invalid="ignore", divide="ignore"):
        for row in range(rot.n):
            H = np.where(S > 1e-9, SH / S, 0.0)
            L = np.clip(p["wake_per_height"] * H, p["wake_min"], p["wake_max"])
            decay = np.exp(-ds / L)
            S = np.convolve(S * decay, k, mode="same")
            SH = np.convolve(SH * decay, k, mode="same")
            hl = np.where(m[row] > 1e-6, h[row] / np.maximum(m[row], 1e-6), 0.0)
            D = m[row] * p["shadow_max"] * hl / (hl + p["shadow_h_ref"])
            up = D > S
            S = np.where(up, D, S)
            SH = np.where(up, D * hl, SH)
            out[row] = S
    return rot.sample(out, x, y)


def current_field(grid, R, mask, polygons, desc, banks, p):
    """Stream of speed `speed` toward `to` (rad), steered along the shore, slowed near it and over banks."""
    x, y = grid_nodes(grid)
    to = float(desc["to"])
    speed = float(desc["speed"])
    ux, uy = math.sin(to), math.cos(to)
    d = distance_to_edges(x, y, polygons)
    on_land = points_in_land(x, y, polygons)
    L = p["shore_length"]
    sf = p["shore_floor"] + (1 - p["shore_floor"]) * (1 - np.exp(-d / L))
    nx_, ny_, b = _shore_normals(R, mask, L, x, y)
    un = ux * nx_ + uy * ny_
    vx = ux - b * un * nx_
    vy = uy - b * un * ny_
    bank = np.ones_like(x)
    for bk in banks:
        bm, _ = R.rasterize([{"points": np.asarray(bk["points"], float), "height": 0.0}])
        bm = gaussian_blur(bm, p["bank_blur"] / R.h)
        bank -= (1.0 - float(bk["factor"])) * R.sample(bm, x, y)
    bank = np.clip(bank, 0.0, 1.0)
    s = speed * sf * bank
    vx = np.where(on_land, 0.0, s * vx)
    vy = np.where(on_land, 0.0, s * vy)
    return vx, vy


def ref_speed(grid, vx, vy, bounds, polygons):
    """90th percentile (linear between ranks) of |v| over the nodes inside bounds that are on water."""
    x, y = grid_nodes(grid)
    vx = np.asarray(vx, np.float32).astype(np.float64)
    vy = np.asarray(vy, np.float32).astype(np.float64)
    inside = (x >= bounds[0]) & (x <= bounds[2]) & (y >= bounds[1]) & (y <= bounds[3])
    sel = inside & ~points_in_land(x, y, polygons)
    if not sel.any():
        return 0.0
    return float(np.percentile(np.hypot(vx[sel], vy[sel]), 90))


def exposure(grid, R, mask, polygons, wind_from, fetch, p):
    """Sea height factor: the open-water fetch averaged over the wave directions around the typical wind
    (square root, as the wind-sea height grows), faded out near the shore, 0 on land."""
    x, y = grid_nodes(grid)
    nd = int(p["directions"])
    deltas = np.linspace(-p["spread"], p["spread"], nd)
    w = np.cos(deltas) ** 2
    acc = np.zeros_like(x)
    for dl, wt in zip(deltas, w):
        th = wind_from + dl
        u = np.array([-math.sin(th), -math.cos(th)])
        rot = Rotated(R, u)
        m = rot.take(mask)
        F = np.empty_like(m)
        run = np.full(rot.n, float(fetch))  # beyond the raster upwind: open water
        for row in range(rot.n):
            run = np.where(m[row] > 0.5, 0.0, np.minimum(run + rot.ds, fetch))
            F[row] = run
        Fn = rot.sample(F, x, y)
        acc += wt * np.sqrt(np.clip(Fn, 0.0, fetch) / fetch)
    e = acc / w.sum()
    d = distance_to_edges(x, y, polygons)
    e *= 1.0 - np.exp(-d / p["fade_length"])
    e = np.where(points_in_land(x, y, polygons), 0.0, e)
    return np.clip(e, 0.0, 1.0)
