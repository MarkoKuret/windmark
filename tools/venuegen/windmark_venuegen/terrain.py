"""Terrain from an elevation model (venues.md §5.7): land heights for the wind model and the drawn terrain file
(`windmark.terrain/1`, data_format.md §6.10) the front end draws the land from.

The drawn height is the DEM above the water level, shaped near the coastline so the waterline follows the
coastline (the physics land inside the land margin, the drawn coastline beyond): under water it slopes down to
`depth`, on land a low shore ramp blends into the DEM over `shore_band`. The mesh is an adaptive quadtree: cells
split while they hold the shoreline or miss the height by more than a tolerance, down to 5 m near the racing area,
20 m to 5 km and 80 m beyond (the distance is measured from `bounds`, where the cameras are); a 2:1 balance and
fans at the T-junctions keep it crack-free. A horizon ridge of the far mountains, a coarse grid, goes around it."""

from __future__ import annotations

import gzip
import math
import os

import numpy as np

from .clip import clip_to_box
from .dem import Dem
from .geo import InputError, load_entry, signed_area
from .raster import Raster
from .simplify import simplify_ring

TERRAIN_DEFAULTS = {
    "water_level": 0.0,        # m, DEM height of the still water (a lake's level, 0 at sea)
    "wind_height_min": 2.0,    # m, the least land height the wind model sees on a land cell
    "wind_height_max": 3000.0,
    "hill_width": 400.0,       # m, without an elevation model the land reaches its polygon height this far inland  # m, the most (a venue may cap mountains whose wakes the model overstates)
    "draw": True,              # write the drawn terrain file
    "margin": 6000.0,          # m, the terrain mesh covers bounds grown by this
    "ridge": 22000.0,          # m, the horizon ridge reaches this far from the centre of bounds
    "ridge_triangles": 10000,
    "shore_fine": 500.0,       # m from the racing water: 5 m cells at the shore
    "near": 1500.0,            # m from the racing water: 10 m cells at the shore (LOD0)
    "mid": 5000.0,             # m from the racing water: 20 m cells (LOD1); 80 m beyond (LOD2)
    "tolerance": 1.0,          # m, height error allowed at the racing water
    "tolerance_per_km": 8.0,   # m per km away from it (about 0.45 degrees seen from the water)
    "triangles": 110000,       # terrain chunk triangles at most; the tolerance is raised until it fits
    "shore_band": 80.0,        # m, the shore ramp blends into the DEM over this
    "shore_slope": 0.12,       # rise of the shore ramp (1 in 8)
    "shore_cap": 2.5,          # m, the ramp's height at most
    "under_slope": 0.35,       # fall of the bottom from the waterline
    "depth": 8.0,              # m, the bottom of the drawn shore under water
    "coast_mid": 10.0,         # m, drawn coastline tolerance beyond the land margin to `mid`
    "coast_far": 50.0,         # m, beyond
    "ground_spacing": 10.0,    # m, the ground height grid (camera land avoidance) over bounds + `near`
    "skirt": 30.0,             # m, the skirt hung from the terrain's outer edge
}
CELL_NEAR, CELL_MID, CELL_FAR = 5.0, 20.0, 80.0
SMAX = 200.0  # m, the signed shore distance is exact within this, clamped beyond
CAPS = {"triangles": 120000, "ridge_triangles": 10000, "coast_vertices": 20000, "chunks": 4,
        "bytes": 8 * 1024 * 1024}


# --- signed distance to the coastline -------------------------------------------------------------------------

class Shore:
    """Signed distance (m, positive on land) to the edges of counter-clockwise land rings, exact within SMAX,
    the sign from the nearest edge (pseudo-normals at the vertices); edges lying on `box` are not shore."""

    def __init__(self, rings, box, mask_raster):
        a, b, na, nb, ne = [], [], [], [], []
        for r in rings:
            p = np.asarray(r, float)
            q = np.roll(p, -1, 0)
            d = q - p
            L = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-12)
            n = np.stack([d[:, 1] / L, -d[:, 0] / L], 1)  # outward (water side): right of a CCW land ring
            nv = n + np.roll(n, 1, 0)  # pseudo-normal at vertex k: edges k-1 and k
            on = _on_box_edge(p, q, box)
            keep = ~on
            a.append(p[keep])
            b.append(q[keep])
            ne.append(n[keep])
            na.append(nv[keep])
            nb.append(np.roll(nv, -1, 0)[keep])
        self.a = np.concatenate(a) if a else np.zeros((0, 2))
        self.b = np.concatenate(b) if b else np.zeros((0, 2))
        self.ne, self.na, self.nb = [np.concatenate(v) if v else np.zeros((0, 2)) for v in (ne, na, nb)]
        self.R, self.mask = mask_raster
        self.T = SMAX
        self.x0, self.y0 = box[0] - SMAX, box[1] - SMAX
        self.tiles = {}
        lo = np.minimum(self.a, self.b) - SMAX
        hi = np.maximum(self.a, self.b) + SMAX
        i0 = np.floor((lo[:, 0] - self.x0) / self.T).astype(int)
        i1 = np.floor((hi[:, 0] - self.x0) / self.T).astype(int)
        j0 = np.floor((lo[:, 1] - self.y0) / self.T).astype(int)
        j1 = np.floor((hi[:, 1] - self.y0) / self.T).astype(int)
        for e in range(len(self.a)):
            for i in range(i0[e], i1[e] + 1):
                for j in range(j0[e], j1[e] + 1):
                    self.tiles.setdefault((i, j), []).append(e)
        self.tiles = {k: np.array(v) for k, v in self.tiles.items()}

    def signed(self, x, y):
        x = np.asarray(x, float).ravel()
        y = np.asarray(y, float).ravel()
        out = np.full(x.shape, SMAX)
        inside = self.R.sample(self.mask, x, y, 0.0) > 0.5
        out = np.where(inside, SMAX, -SMAX)
        ti = np.floor((x - self.x0) / self.T).astype(int)
        tj = np.floor((y - self.y0) / self.T).astype(int)
        key = ti * 100003 + tj
        order = np.argsort(key, kind="stable")
        ks = key[order]
        starts = np.flatnonzero(np.r_[True, ks[1:] != ks[:-1]])
        ends = np.r_[starts[1:], len(ks)]
        for s0, s1 in zip(starts, ends):
            idx = order[s0:s1]
            e = self.tiles.get((int(ti[idx[0]]), int(tj[idx[0]])))
            if e is None:
                continue
            for c0 in range(0, len(idx), 2048):
                ii = idx[c0:c0 + 2048]
                px, py = x[ii, None], y[ii, None]
                ax, ay = self.a[None, e, 0], self.a[None, e, 1]
                dx, dy = self.b[None, e, 0] - ax, self.b[None, e, 1] - ay
                L2 = np.maximum(dx * dx + dy * dy, 1e-12)
                t = np.clip(((px - ax) * dx + (py - ay) * dy) / L2, 0.0, 1.0)
                qx, qy = ax + t * dx, ay + t * dy
                d = np.hypot(px - qx, py - qy)
                k = np.argmin(d, axis=1)
                r = np.arange(len(ii))
                dk = d[r, k]
                tk = t[r, k]
                ek = e[k]
                n = np.where((tk <= 0.0)[:, None], self.na[ek], np.where((tk >= 1.0)[:, None], self.nb[ek],
                                                                       self.ne[ek]))
                side = (px[:, 0] - qx[r, k]) * n[:, 0] + (py[:, 0] - qy[r, k]) * n[:, 1]
                sgn = np.where(side > 0.0, -1.0, 1.0)  # on the outward side: water
                near = dk < SMAX
                out[ii[near]] = (sgn * dk)[near]
        return out


def _on_box_edge(p, q, box, eps=0.05):
    def on(v, lim):
        return np.abs(v - lim) < eps
    return ((on(p[:, 0], box[0]) & on(q[:, 0], box[0])) | (on(p[:, 0], box[2]) & on(q[:, 0], box[2])) |
            (on(p[:, 1], box[1]) & on(q[:, 1], box[1])) | (on(p[:, 1], box[3]) & on(q[:, 1], box[3])))


def _smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _box_distance(x, y, b):
    dx = np.maximum.reduce([b[0] - x, x - b[2], np.zeros_like(x)])
    dy = np.maximum.reduce([b[1] - y, y - b[3], np.zeros_like(y)])
    return np.hypot(dx, dy)


# --- the terrain model ----------------------------------------------------------------------------------------

class TerrainModel:
    def __init__(self, dem, origin, p, bounds, land_box, land, paths, notes):
        self.dem, self.origin, self.p = dem, origin, p
        self.bounds = bounds
        self.land_box = land_box
        g = p["margin"]
        self.box = (bounds[0] - g, bounds[1] - g, bounds[2] + g, bounds[3] + g)
        # the drawn coastline beyond the land margin, simplified by distance from bounds
        rings = clip_to_box(paths, self.box)
        far, far_h = [], []
        for r in rings:
            q = r["points"]
            d = _box_distance(q[:, 0], q[:, 1], bounds)
            tol = np.where(d <= p["mid"], p["coast_mid"], p["coast_far"])
            fixed = _on_box(q, self.box)
            k = simplify_ring(q, tol, fixed)
            if len(k) >= 3 and signed_area(k) > 0:
                far.append(k)
                far_h.append(float(r.get("height") or 20.0))
        inner = [np.asarray(l["points"], float) for l in land]
        self.coast_vertices = sum(len(r) for r in inner) + sum(
            int(np.count_nonzero(_box_distance(r[:, 0], r[:, 1], land_box) > 0)) for r in far)
        Rm = Raster(self.box, 25.0)
        mask, self.poly_h = Rm.rasterize([{"points": r, "height": h} for r, h in zip(far, far_h)])
        self.Rm = Rm
        self.far = Shore(far, self.box, (Rm, mask))
        self.inner = Shore(inner, land_box, (Rm, mask)) if inner else None
        self.water = p["water_level"]

    def view_distance_raster(self):
        """Distance (m) from the racing water (the water inside bounds) on a 100 m raster over the terrain box:
        where the cameras are, so the mesh is finest near it."""
        b = self.bounds
        gx, gy = np.meshgrid(np.arange(b[0], b[2] + 1, 100.0), np.arange(b[1], b[3] + 1, 100.0))
        h, _ = self.height(gx.ravel(), gy.ravel())
        wx, wy = gx.ravel()[h < 0], gy.ravel()[h < 0]
        if not len(wx):
            wx, wy = gx.ravel(), gy.ravel()
        R = Raster(self.box, 100.0)
        X, Y = np.meshgrid(R.xc, R.yc)
        x, y = X.ravel(), Y.ravel()
        d = np.full(x.shape, np.inf)
        for s0 in range(0, len(x), 4096):
            px, py = x[s0:s0 + 4096, None], y[s0:s0 + 4096, None]
            d[s0:s0 + 4096] = np.sqrt(((px - wx[None]) ** 2 + (py - wy[None]) ** 2).min(axis=1))
        self.view = (R, d.reshape(X.shape))

    def view_distance(self, x, y):
        R, d = self.view
        return R.sample(d, x, y, float(d.max()))

    def shore(self, x, y):
        s = self.far.signed(x, y)
        if self.inner is None:
            return s
        lb = self.land_box
        din = np.minimum.reduce([x - lb[0], lb[2] - x, y - lb[1], lb[3] - y])  # inside the land box: > 0
        w = np.clip(din / 300.0, 0.0, 1.0)
        sel = w > 0
        if sel.any():
            si = self.inner.signed(x[sel], y[sel])
            s = s.copy()
            s[sel] = w[sel] * si + (1 - w[sel]) * s[sel]
        return s

    def dem_height(self, x, y, s=None):
        """Land height above the water from the elevation model; without one, or where it has no data, the
        polygon's height reached over `hill_width` inland."""
        x = np.asarray(x, float)
        y = np.asarray(y, float)
        h = np.full(x.shape, np.nan) if self.dem is None else self.dem.sample_local(x, y, self.origin) - self.water
        miss = np.isnan(h)
        if miss.any():
            ph = self.Rm.sample(self.poly_h, x[miss], y[miss], 0.0)
            if s is None:
                s = self.shore(x[miss].ravel(), y[miss].ravel()).reshape(ph.shape)
            else:
                s = np.asarray(s)[miss]
            h[miss] = ph * _smooth(0.0, self.p["hill_width"], s) ** 0.7
        return h

    def height(self, x, y):
        """Drawn height (m above the still water) and the signed shore distance at points."""
        x = np.asarray(x, float).ravel()
        y = np.asarray(y, float).ravel()
        p = self.p
        s = self.shore(x, y)
        D = self.dem_height(x, y, s)
        ramp = np.minimum(np.maximum(s, 0.0) * p["shore_slope"], p["shore_cap"])
        w = _smooth(0.0, p["shore_band"], s)
        land = ramp + w * np.maximum(D - ramp, 0.0)
        water = np.maximum(s * p["under_slope"], -p["depth"])
        return np.where(s > 0.0, land, water), s


def _on_box(p, box, eps=1e-2):
    return ((np.abs(p[:, 0] - box[0]) < eps) | (np.abs(p[:, 0] - box[2]) < eps) |
            (np.abs(p[:, 1] - box[1]) < eps) | (np.abs(p[:, 1] - box[3]) < eps))


# --- the adaptive mesh ----------------------------------------------------------------------------------------

def _min_cell(d, p):
    """The finest cell at a distance from the racing water: 5 m at the shore within `shore_fine` (10 m to
    `near`), 20 m to `mid`, 80 m beyond."""
    return np.where(d <= p["shore_fine"], CELL_NEAR, np.where(d <= p["near"], 2 * CELL_NEAR,
                                                               np.where(d <= p["mid"], CELL_MID, CELL_FAR)))


CELL_RELIEF = 10.0  # m, the finest cell for the relief alone (the DEM has 30 m posts): 5 m is for the shore


def quadtree(model, scale=1.0):
    """Leaves (ix, iy, level) on the 5 m lattice of the terrain box, cell size 5 * 2^level."""
    p = model.p
    u = CELL_NEAR
    L = 7  # 640 m roots
    R0 = u * 2 ** L
    b = model.box
    gx0 = math.floor(b[0] / R0) * R0
    gy0 = math.floor(b[1] / R0) * R0
    nrx = int(math.ceil((b[2] - gx0) / R0))
    nry = int(math.ceil((b[3] - gy0) / R0))
    model.lattice = (gx0, gy0, nrx * 2 ** L, nry * 2 ** L)
    I, J = np.meshgrid(np.arange(nrx) * 2 ** L, np.arange(nry) * 2 ** L)
    todo = np.stack([I.ravel(), J.ravel(), np.full(I.size, L)], 1)
    leaves = []
    cache = {}

    def H(ix, iy):
        key = ix.astype(np.int64) * 1000003 + iy
        out = np.empty(len(key))
        miss = np.array([k not in cache for k in key.tolist()], bool)
        if miss.any():
            km = key[miss]
            uk, inv = np.unique(km, return_index=True)
            h, _ = model.height(gx0 + ix[miss][inv] * u, gy0 + iy[miss][inv] * u)
            for k, v in zip(uk.tolist(), h.tolist()):
                cache[k] = v
        return np.array([cache[k] for k in key.tolist()])

    while len(todo):
        ix, iy, lv = todo[:, 0], todo[:, 1], todo[:, 2]
        n = 2 ** lv
        if np.all(lv == 0):
            leaves.append(todo)
            break
        h2 = n // 2
        pts = [(0, 0), (n, 0), (n, n), (0, n), (h2, 0), (n, h2), (h2, n), (0, h2), (h2, h2)]
        hs = [H(ix + dx, iy + dy) for dx, dy in pts]
        c = n * u
        cx = gx0 + (ix + h2) * u
        cy = gy0 + (iy + h2) * u
        d = np.maximum(model.view_distance(cx, cy) - c * 0.7072, 0.0)
        tol = scale * (p["tolerance"] + p["tolerance_per_km"] * d / 1000.0)
        err = np.max(np.abs(np.stack([hs[4] - (hs[0] + hs[1]) / 2, hs[5] - (hs[1] + hs[2]) / 2,
                                      hs[6] - (hs[2] + hs[3]) / 2, hs[7] - (hs[3] + hs[0]) / 2,
                                      hs[8] - (hs[0] + hs[1] + hs[2] + hs[3]) / 4])), axis=0)
        H9 = np.stack(hs)
        shore = (H9.min(axis=0) < 0.0) & (H9.max(axis=0) > 0.0)
        # a cell whose 9 samples all lie on one side can still hold a thin spit or channel: the shore distance
        # tells (|s| under the cell's half diagonal); approximated by a height near the waterline
        shore |= (np.abs(H9).min(axis=0) < 0.5) & (H9.max(axis=0) > -model.p["depth"] + 0.01)
        mc = _min_cell(d * scale, p)  # over the triangle cap the fine zones shrink with the tolerance
        split = (((c > mc) & shore) | ((c > np.maximum(mc, CELL_RELIEF)) & (err > tol))) & (lv > 0)
        leaves.append(todo[~split])
        s = todo[split]
        if not len(s):
            break
        h = (2 ** (s[:, 2] - 1))
        kids = []
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            kids.append(np.stack([s[:, 0] + dx * h, s[:, 1] + dy * h, s[:, 2] - 1], 1))
        todo = np.concatenate(kids)
    leaves = np.concatenate(leaves)
    return _balance(leaves, model.lattice), H


def _balance(leaves, lattice):
    """2:1 balance: no leaf touches a leaf more than one level finer along an edge."""
    _, _, NX, NY = lattice
    while True:
        lv_map = np.full((NY, NX), 127, np.int8)
        id_map = np.zeros((NY, NX), np.int32)
        for k, (ix, iy, lv) in enumerate(leaves.tolist()):
            n = 2 ** lv
            lv_map[iy:iy + n, ix:ix + n] = lv
            id_map[iy:iy + n, ix:ix + n] = k
        split = np.zeros(len(leaves), bool)
        for k, (ix, iy, lv) in enumerate(leaves.tolist()):
            if lv < 2:
                continue
            n = 2 ** lv
            for sl in ((slice(iy - 1, iy), slice(ix, ix + n)), (slice(iy + n, iy + n + 1), slice(ix, ix + n)),
                       (slice(iy, iy + n), slice(ix - 1, ix)), (slice(iy, iy + n), slice(ix + n, ix + n + 1))):
                if sl[0].start < 0 or sl[1].start < 0 or sl[0].stop > NY or sl[1].stop > NX:
                    continue
                if lv_map[sl].min() < lv - 1:
                    split[k] = True
                    break
        if not split.any():
            return leaves
        s = leaves[split]
        h = 2 ** (s[:, 2] - 1)
        kids = [np.stack([s[:, 0] + dx * h, s[:, 1] + dy * h, s[:, 2] - 1], 1)
                for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1))]
        leaves = np.concatenate([leaves[~split]] + kids)


def triangulate(leaves, lattice):
    """Triangles over lattice points (ix, iy) as an (m, 3, 2) int array: two per leaf, or a fan around the
    centre where a finer neighbour puts a vertex on an edge midpoint."""
    _, _, NX, NY = lattice
    present = np.zeros((NY + 1, NX + 1), bool)
    for ix, iy, lv in leaves.tolist():
        n = 2 ** lv
        present[iy, ix] = present[iy, ix + n] = present[iy + n, ix] = present[iy + n, ix + n] = True
    tris = []
    for ix, iy, lv in leaves.tolist():
        n = 2 ** lv
        c = [(ix, iy), (ix + n, iy), (ix + n, iy + n), (ix, iy + n)]
        if lv == 0:
            tris.append((c[0], c[1], c[2]))
            tris.append((c[0], c[2], c[3]))
            continue
        h = n // 2
        mids = [(ix + h, iy), (ix + n, iy + h), (ix + h, iy + n), (ix, iy + h)]
        loop = []
        for k in range(4):
            loop.append(c[k])
            if present[mids[k][1], mids[k][0]]:
                loop.append(mids[k])
        if len(loop) == 4:
            tris.append((c[0], c[1], c[2]))
            tris.append((c[0], c[2], c[3]))
        else:
            ctr = (ix + h, iy + h)
            for k in range(len(loop)):
                tris.append((ctr, loop[k], loop[(k + 1) % len(loop)]))
    return np.array(tris, np.int64)


# --- output ---------------------------------------------------------------------------------------------------

def build_terrain(src, p, origin, bounds, land_box, land, notes, default_h=20.0):
    """The drawn terrain document (header) and its binary blob. Without an elevation model the land rises to
    each polygon's `height` (the source's `land_height` where it has none) over `hill_width` inland."""
    tiles = src["terrain"].get("dem") or []
    dem = Dem([os.path.join(src["_dir"], q) for q in tiles]) if tiles else None
    paths = []
    g = p["margin"]
    box = (bounds[0] - g, bounds[1] - g, bounds[2] + g, bounds[3] + g)
    for e in src.get("coastline", []):
        for q in load_entry(e, origin, src["_dir"], box):
            q["height"] = q.get("height") or default_h
            paths.append(q)
    if dem is None:
        notes.append("terrain: no elevation model, land heights from the polygons")
    model = TerrainModel(dem, origin, p, bounds, land_box, land, paths, notes)
    model.view_distance_raster()
    if model.coast_vertices > CAPS["coast_vertices"]:
        raise InputError(f"drawn coastline needs {model.coast_vertices} vertices (cap {CAPS['coast_vertices']})")
    tol = 1.0
    while True:
        leaves, H = quadtree(model, tol)
        tri = triangulate(leaves, model.lattice)
        gx0, gy0, NX, NY = model.lattice
        key = tri[..., 0] * (NY + 1) + tri[..., 1]
        uk, inv = np.unique(key.ravel(), return_inverse=True)
        vx = gx0 + (uk // (NY + 1)) * CELL_NEAR
        vy = gy0 + (uk % (NY + 1)) * CELL_NEAR
        # centres of 5 m leaves are never used; every vertex sits on the lattice
        vh, vs = model.height(vx, vy)
        idx = inv.reshape(-1, 3)
        dry = vh[idx].max(axis=1) > -p["depth"] + 0.01
        idx = idx[dry]
        if len(idx) <= p["triangles"]:
            break
        if tol > 50.0:
            raise InputError(f"terrain needs {len(idx)} triangles even at 50 times the tolerance; shrink "
                             f"`terrain.margin` or bounds")
        tol *= 1.25
        notes.append(f"terrain tolerance scaled by {tol:.2f} for the triangle cap")
    # skirt along the outer edge of the mesh
    nrm = _normals(vx, vy, vh, idx)
    used = np.unique(idx)
    remap = np.full(len(vx), -1)
    remap[used] = np.arange(len(used))
    vx, vy, vh, vs, nrm = vx[used], vy[used], vh[used], vs[used], nrm[used]
    idx = remap[idx]
    vx, vy, vh, vs, nrm, idx = _skirt(vx, vy, vh, vs, nrm, idx, p["skirt"])

    # chunks: near (bounds + near, they cast shadows) and far, each split west / east
    cx = 0.5 * (bounds[0] + bounds[2])
    tx = vx[idx].mean(axis=1)
    ty = vy[idx].mean(axis=1)
    near = _box_distance(tx, ty, bounds) <= p["near"]
    east = tx >= cx
    chunks, blobs = [], []
    for name, sel, shadows in (("near_w", near & ~east, True), ("near_e", near & east, True),
                               ("far_w", ~near & ~east, False), ("far_e", ~near & east, False)):
        ci = idx[sel]
        if not len(ci):
            continue
        u, inv = np.unique(ci.ravel(), return_inverse=True)
        chunks.append(_chunk_header(name, vx[u], vy[u], vh[u], len(ci), shadows))
        blobs.append(_mesh_blob(vx[u], vy[u], vh[u], nrm[u], vs[u], inv.reshape(-1, 3)))
    ridge_hdr, ridge_blob = _ridge(model, p, bounds)
    ground_hdr, ground_blob = _ground(model, p, bounds)

    data = bytearray()
    for hdr, raw in list(zip(chunks, blobs)) + ([(ridge_hdr, ridge_blob)] if ridge_hdr else []) + \
            [(ground_hdr, ground_blob)]:
        z = gzip.compress(raw, 9, mtime=0)
        hdr["offset"], hdr["bytes"], hdr["raw_bytes"] = len(data), len(z), len(raw)
        data += z
    tris = sum(c["triangles"] for c in chunks)
    doc = {
        "schema": "windmark.terrain/1",
        "id": src["id"],
        "version": src["version"],
        "water_level": p["water_level"],
        "box": [_r(v, 1) for v in model.box],
        "chunks": chunks,
        "ridge": ridge_hdr,
        "ground": ground_hdr,
        "stats": {"triangles": tris, "vertices": sum(c["vertices"] for c in chunks),
                  "ridge_triangles": ridge_hdr["triangles"] if ridge_hdr else 0,
                  "coast_vertices": model.coast_vertices, "tolerance_scale": _r(tol, 2)},
    }
    notes.append(f"terrain: {tris} triangles in {len(chunks)} chunks, ridge {doc['stats']['ridge_triangles']}, "
                 f"coastline {model.coast_vertices} vertices, {len(data) / 1024:.0f} KB")
    return doc, bytes(data)


def _r(v, d):
    v = round(float(v), d)
    return int(v) if v.is_integer() else v


def _chunk_header(name, x, y, h, ntri, shadows):
    return {"id": name, "aabb": [_r(x.min(), 1), _r(y.min(), 1), _r(h.min(), 1), _r(x.max(), 1), _r(y.max(), 1),
                                 _r(h.max(), 1)],
            "vertices": int(len(x)), "triangles": int(ntri), "shadows": shadows}


def _normals(x, y, h, idx):
    P = np.stack([x, y, h], 1)
    a, b, c = P[idx[:, 0]], P[idx[:, 1]], P[idx[:, 2]]
    fn = np.cross(b - a, c - a)
    fn *= np.sign(fn[:, 2:3] + 1e-12)  # up
    n = np.zeros_like(P)
    for k in range(3):
        np.add.at(n, idx[:, k], fn)
    L = np.linalg.norm(n, axis=1, keepdims=True)
    n = np.where(L > 0, n / np.maximum(L, 1e-12), np.array([0.0, 0.0, 1.0]))
    return n


def _skirt(x, y, h, s, n, idx, depth):
    """Vertical strips hung `depth` m below the boundary edges of the mesh (gaps toward the horizon ridge)."""
    e = np.concatenate([idx[:, [0, 1]], idx[:, [1, 2]], idx[:, [2, 0]]])
    key = np.sort(e, axis=1)
    uk, cnt = np.unique(key, axis=0, return_counts=True)
    bset = {tuple(k) for k in uk[cnt == 1].tolist()}
    border = np.array([k for k in e.tolist() if tuple(sorted(k)) in bset], np.int64)
    # keep only the outer boundary (edges of land triangles cut at the water are inner boundaries under water)
    hi = (h[border[:, 0]] > 0.0) | (h[border[:, 1]] > 0.0)
    border = border[hi]
    if not len(border):
        return x, y, h, s, n, idx
    vb = np.unique(border.ravel())
    m = np.full(len(x), -1)
    m[vb] = len(x) + np.arange(len(vb))
    x2 = np.concatenate([x, x[vb]])
    y2 = np.concatenate([y, y[vb]])
    h2 = np.concatenate([h, h[vb] - depth])
    s2 = np.concatenate([s, s[vb]])
    n2 = np.concatenate([n, n[vb]])
    a, b = border[:, 0], border[:, 1]
    # the triangle runs a -> b counter-clockwise seen from above, so the outside is on the right of a -> b
    t1 = np.stack([b, a, m[a]], 1)
    t2 = np.stack([b, m[a], m[b]], 1)
    return x2, y2, h2, s2, n2, np.concatenate([idx, t1, t2])


def _mesh_blob(x, y, h, n, s, idx):
    """float32 positions (x east, y north, h up; n * 3), float32 normals (n * 3), float32 shore distance
    (n) and int32 triangle indices (m * 3), all little-endian."""
    pos = np.stack([np.round(x, 2), np.round(y, 2), np.round(h, 2)], 1).astype("<f4")
    nrm = np.round(n, 4).astype("<f4")
    sh = np.round(np.clip(s, -SMAX, SMAX), 1).astype("<f4")
    return pos.tobytes() + nrm.tobytes() + sh.tobytes() + idx.astype("<i4").tobytes()


def _ridge(model, p, bounds):
    """The far mountains: a grid around the terrain box out to `ridge`, coarse enough for its triangle cap."""
    b = model.box
    gx0, gy0, NX, NY = model.lattice
    tb = (gx0, gy0, gx0 + NX * CELL_NEAR, gy0 + NY * CELL_NEAR)
    cx, cy = 0.5 * (bounds[0] + bounds[2]), 0.5 * (bounds[1] + bounds[3])
    R = p["ridge"]
    if R <= max(b[2] - cx, cy - b[1]):
        return None, b""
    for g in (320.0, 640.0, 1280.0, 2560.0):
        x0 = tb[0] - math.ceil((tb[0] - (cx - R)) / g) * g
        y0 = tb[1] - math.ceil((tb[1] - (cy - R)) / g) * g
        nx = int(math.ceil((cx + R - x0) / g)) + 1
        ny = int(math.ceil((cy + R - y0) / g)) + 1
        X, Y = np.meshgrid(x0 + np.arange(nx) * g, y0 + np.arange(ny) * g)
        Hh = model.dem_height(X.ravel(), Y.ravel()).reshape(ny, nx)
        inner = (X > tb[0] + 1) & (X < tb[2] - 1) & (Y > tb[1] + 1) & (Y < tb[3] - 1)
        Hh = np.where(inner, Hh - 40.0, Hh)  # under the terrain mesh where they overlap
        cells = []
        for j in range(ny - 1):
            for i in range(nx - 1):
                xa, ya = X[j, i], Y[j, i]
                if xa >= tb[0] and xa + g <= tb[2] and ya >= tb[1] and ya + g <= tb[3]:
                    continue
                if max(Hh[j, i], Hh[j, i + 1], Hh[j + 1, i], Hh[j + 1, i + 1]) <= 0.5:
                    continue
                cells.append((j, i))
        if 2 * len(cells) <= p["ridge_triangles"]:
            break
    if not cells:
        return None, b""
    idx = []
    for j, i in cells:
        a, bb, c, d = j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i
        idx += [(a, bb, c), (a, c, d)]
    idx = np.array(idx, np.int64)
    x, y, h = X.ravel(), Y.ravel(), np.maximum(Hh.ravel(), -2.0)
    n = _normals(x, y, h, idx)
    u, inv = np.unique(idx.ravel(), return_inverse=True)
    hdr = _chunk_header("ridge", x[u], y[u], h[u], len(idx), False)
    hdr["spacing"] = g
    blob = _mesh_blob(x[u], y[u], h[u], n[u], np.full(len(u), SMAX), inv.reshape(-1, 3))
    return hdr, blob


def _ground(model, p, bounds):
    """The ground height grid for the cameras' land avoidance: int16 decimetres over bounds + `near`."""
    sp = p["ground_spacing"]
    m = p["near"]
    x0, y0 = bounds[0] - m, bounds[1] - m
    nx = int(math.ceil((bounds[2] + m - x0) / sp)) + 1
    ny = int(math.ceil((bounds[3] + m - y0) / sp)) + 1
    X, Y = np.meshgrid(x0 + np.arange(nx) * sp, y0 + np.arange(ny) * sp)
    h, _ = model.height(X.ravel(), Y.ravel())
    q = np.clip(np.round(h * 10.0), -32767, 32767).astype("<i2")
    hdr = {"grid": {"x0": _r(x0, 1), "y0": _r(y0, 1), "dx": sp, "dy": sp, "nx": nx, "ny": ny}, "scale": 0.1}
    return hdr, q.tobytes()


def wind_heights(R, mask, height, dem, origin, p):
    """The land height raster of the wind model from the DEM (m above the water), where the mask is land."""
    X, Y = np.meshgrid(R.xc, R.yc)
    h = dem.sample_local(X, Y, origin) - p["water_level"]
    h = np.clip(h, p["wind_height_min"], p["wind_height_max"])
    return np.where((mask > 0.5) & ~np.isnan(h), h, height)


def check_terrain(t, bin_bytes=None):
    """Problems of a terrain header against data_format.md §6.10 and the caps of venues.md §4.2."""
    out = []
    if t.get("schema") != "windmark.terrain/1":
        out.append("$.schema: must be windmark.terrain/1")
    chunks = t.get("chunks", [])
    if not 1 <= len(chunks) <= CAPS["chunks"]:
        out.append(f"$.chunks: 1 to {CAPS['chunks']} chunks")
    ridge = t.get("ridge") or {}
    tris = sum(int(c.get("triangles", 0)) for c in chunks) + int(ridge.get("triangles", 0))
    if tris > CAPS["triangles"]:
        out.append(f"triangles: {tris} over the cap of {CAPS['triangles']}")
    if int(ridge.get("triangles", 0)) > CAPS["ridge_triangles"]:
        out.append(f"$.ridge: over {CAPS['ridge_triangles']} triangles")
    if ridge.get("shadows"):
        out.append("$.ridge.shadows: the ridge casts no shadows")
    if sum(1 for c in chunks if c.get("shadows")) > 2:
        out.append("$.chunks: at most 2 chunks cast shadows")
    if int(t.get("stats", {}).get("coast_vertices", 0)) > CAPS["coast_vertices"]:
        out.append("$.stats.coast_vertices: over the cap")
    end = 0
    for k, c in enumerate(chunks + ([ridge] if ridge else []) + [t.get("ground", {})]):
        for key in ("offset", "bytes", "raw_bytes"):
            if not isinstance(c.get(key), int) or c[key] < 0:
                out.append(f"blob {k}: {key} missing")
        end = max(end, int(c.get("offset", 0)) + int(c.get("bytes", 0)))
    if bin_bytes is not None:
        if bin_bytes != end:
            out.append(f"$.bin: {bin_bytes} bytes, the blobs end at {end}")
        if bin_bytes > CAPS["bytes"]:
            out.append(f"$.bin: over {CAPS['bytes']} bytes")
    return out
