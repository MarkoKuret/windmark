"""Venue source file (windmark.venuesrc/1, docs/specs/venues.md §5) to venue file (windmark.venue/1)."""

from __future__ import annotations

import copy
import json
import math
import os

import numpy as np

from . import __version__
from .clip import clip_to_box
from .fields import (CURRENT_DEFAULTS, EXPOSURE_DEFAULTS, WIND_DEFAULTS, current_field, exposure, ref_speed,
                     wind_field)
from .geo import InputError, load_entry, signed_area
from .raster import Raster
from .simplify import simplify_ring
from .terrain import TERRAIN_DEFAULTS, build_terrain, check_terrain, wind_heights
from .validate import CAPS, _Checker, check_briefing, check_conditions, validate

SIMPLIFY_DEFAULTS = {
    "inside": 5.0,          # m, Douglas-Peucker tolerance inside bounds (venues.md §4.1)
    "outside": 20.0,        # m, beyond bounds
    "outside_max": 160.0,   # m, the outside tolerance is doubled up to this while the vertex caps are exceeded
    "min_area": 20.0,       # m², smaller land pieces are dropped (rocks belong in obstacles)
    "land_margin": 1000.0,  # m, written land is clipped to bounds grown by this
    "field_margin": 3000.0,  # m, land used for the fields is clipped to bounds grown by this
    "field_tolerance": 10.0,  # m
    "split": 1000.0,        # m, written land polygons wider or taller than this are cut into tiles of this size
}

GRID_DEFAULTS = {"margin": 1000.0, "wind": 100.0, "current": 100.0, "exposure": 100.0}

COPY_HEADER = ("schema", "id", "name", "version", "origin", "bounds", "fetch", "exposure_default")


class SourceError(ValueError):
    pass


def _merged(defaults, over, path):
    out = dict(defaults)
    for k, v in (over or {}).items():
        if k not in defaults:
            raise SourceError(f"{path}.{k}: unknown key")
        out[k] = float(v) if not isinstance(v, bool) else v
    return out


def load_source(path):
    with open(path) as f:
        src = json.load(f)
    if src.get("schema") != "windmark.venuesrc/1":
        raise SourceError(f"{path}: schema must be windmark.venuesrc/1")
    for k in ("id", "name", "version", "bounds"):
        if k not in src:
            raise SourceError(f"{path}: {k} is required")
    src["_dir"] = os.path.dirname(os.path.abspath(path))
    return src


def make_grid(box, spacing, cap):
    """Grid over box at `spacing` (m, at least 50), coarsened to multiples of 10 m until it fits `cap` nodes a
    side. The grid starts at the box corner and may end up to one spacing past it."""
    w, h = box[2] - box[0], box[3] - box[1]
    s = max(float(spacing), CAPS["min_spacing"])
    if math.ceil(max(w, h) / s) + 1 > cap:
        s = math.ceil(max(w, h) / (cap - 1) / 10.0) * 10.0
    return {"x0": _num(box[0]), "y0": _num(box[1]), "dx": _num(s), "dy": _num(s), "nx": int(math.ceil(w / s)) + 1,
            "ny": int(math.ceil(h / s)) + 1}


def _grow(b, m):
    return (b[0] - m, b[1] - m, b[2] + m, b[3] + m)


def _on_box(p, box, eps=1e-2):
    return ((np.abs(p[:, 0] - box[0]) < eps) | (np.abs(p[:, 0] - box[2]) < eps) |
            (np.abs(p[:, 1] - box[1]) < eps) | (np.abs(p[:, 1] - box[3]) < eps))


def _simplify_all(rings, bounds, box, tol_in, tol_out, min_area, notes):
    out = []
    for r in rings:
        p = r["points"]
        inside = (p[:, 0] >= bounds[0]) & (p[:, 0] <= bounds[2]) & (p[:, 1] >= bounds[1]) & (p[:, 1] <= bounds[3])
        tol = np.where(inside, tol_in, tol_out)
        q = simplify_ring(p, tol, _on_box(p, box))
        if signed_area(q) < min_area:
            notes.append(f"dropped a land piece of {signed_area(q):.0f} m² near ({q[0][0]:.0f}, {q[0][1]:.0f})")
            continue
        out.append({"points": q, "height": r["height"], "id": r.get("id")})
    return out


def _split_land(land, size, notes):
    """Land polygons whose box is wider or taller than `size` cut on a grid of that spacing (aligned to world
    0), so the core's per-polygon bounding tests reject the far shore of a big piece of land (a lake's whole
    surroundings); the pieces share their cut edges and keep the polygon's id with a suffix."""
    out = []
    for p in land:
        q = p["points"]
        lo, hi = q.min(axis=0), q.max(axis=0)
        if size <= 0 or max(hi[0] - lo[0], hi[1] - lo[1]) <= size:
            out.append(p)
            continue
        pieces = []
        for gx in np.arange(math.floor(lo[0] / size) * size, hi[0], size):
            for gy in np.arange(math.floor(lo[1] / size) * size, hi[1], size):
                tile = (float(gx), float(gy), float(gx + size), float(gy + size))
                for r in clip_to_box([{"points": q, "closed": True, "height": None}], tile):
                    pts = _snap_tile(r["points"], tile)
                    if len(pts) >= 3 and signed_area(pts) > 1.0:
                        pieces.append(pts)
        for k, pts in enumerate(pieces):
            out.append({"points": pts, "height": p["height"], "id": f"{p['id']}_{k + 1}"})
        notes.append(f"land {p['id']} cut into {len(pieces)} pieces of at most {size:g} m")
    return out


def _snap_tile(pts, tile):
    """Clip points nudged off the tile edge back onto it (the pieces then share their cut edges exactly) and
    repeated points dropped."""
    pts = pts.copy()
    for k, lim in ((0, tile[0]), (0, tile[2]), (1, tile[1]), (1, tile[3])):
        near = np.abs(pts[:, k] - lim) < 1e-2
        pts[near, k] = lim
    keep = np.any(np.abs(pts - np.roll(pts, 1, 0)) > 1e-6, axis=1)
    pts = pts[keep]
    # drop collinear points along the tile edges
    keep = np.ones(len(pts), bool)
    for k in range(len(pts)):
        a, b, c = pts[k - 1], pts[k], pts[(k + 1) % len(pts)]
        if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) < 1e-9:
            keep[k] = False
    return pts[keep]


def _land_ids(polys):
    used = {p["id"] for p in polys if p.get("id")}
    n = 0
    for p in polys:
        if not p.get("id"):
            n += 1
            while f"land_{n}" in used:
                n += 1
            p["id"] = f"land_{n}"
            used.add(p["id"])


def _source_note(src):
    parts = []
    for e in src.get("coastline", []):
        s = e.get("source") or ("own shapes" if "polygons" in e else os.path.basename(e.get("path", "")))
        if e.get("version"):
            s += f" {e['version']}"
        if e.get("downloaded"):
            s += f", downloaded {e['downloaded']}"
        if e.get("licence"):
            s += f" ({e['licence']})"
        parts.append(s)
    t = src.get("terrain")
    if isinstance(t, dict):
        s = t.get("source") or "elevation model"
        if t.get("version"):
            s += f" {t['version']}"
        if t.get("downloaded"):
            s += f", downloaded {t['downloaded']}"
        if t.get("licence"):
            s += f" ({t['licence']})"
        parts.append(f"terrain: {s}")
    elif t:
        parts.append(f"terrain: {t}")
    if src.get("note"):
        parts.append(src["note"])
    return f"venuegen {__version__}; " + "; ".join(parts)


TERRAIN_META = ("dem", "source", "version", "downloaded", "licence")


def terrain_params(src):
    """The `terrain` block's constants (None without an elevation model)."""
    t = src.get("terrain")
    if not isinstance(t, dict):
        return None
    if "dem" in t and not isinstance(t["dem"], list):
        raise SourceError("$.terrain.dem: a list of elevation tiles (GeoTIFF paths relative to the source)")
    return _merged(TERRAIN_DEFAULTS, {k: v for k, v in t.items() if k not in TERRAIN_META}, "$.terrain")


def build(src, terrain_out=None):
    """The venue document and a list of notes. With a list `terrain_out` and an elevation model in the source,
    the drawn terrain (header document and binary blob) is appended to it."""
    notes = []
    bounds = tuple(float(v) for v in src["bounds"])
    simp = _merged(SIMPLIFY_DEFAULTS, src.get("simplify"), "$.simplify")
    grids = dict(GRID_DEFAULTS)
    for k, v in (src.get("grids") or {}).items():
        if k not in grids:
            raise SourceError(f"$.grids.{k}: unknown key")
        grids[k] = float(v)
    wp = _merged(WIND_DEFAULTS, src.get("wind"), "$.wind")
    ep = _merged(EXPOSURE_DEFAULTS, {k: v for k, v in (src.get("exposure") or {}).items() if k != "from"},
                 "$.exposure")
    default_h = float(src.get("land_height", 20.0))
    origin = src.get("origin")

    land_box = _grow(bounds, simp["land_margin"])
    field_box = _grow(bounds, max(simp["field_margin"], simp["land_margin"]))
    paths = []
    for k, e in enumerate(src.get("coastline", [])):
        try:
            ps = load_entry(e, origin, src["_dir"], field_box)
        except InputError as ex:
            raise SourceError(f"$.coastline[{k}]: {ex}") from ex
        for p in ps:
            if not p.get("height"):
                p["height"] = default_h
        paths += ps

    # written land: clipped, simplified within the vertex caps
    rings = clip_to_box(paths, land_box)
    for r in rings:
        r["height"] = r["height"] or default_h
    tol_out = simp["outside"]
    while True:
        land = _simplify_all(rings, bounds, land_box, simp["inside"], tol_out, simp["min_area"], notes)
        total = sum(len(p["points"]) for p in land)
        biggest = max((len(p["points"]) for p in land), default=0)
        if total <= CAPS["land_vertices_total"] and biggest <= CAPS["land_vertices_polygon"]:
            break
        if tol_out >= simp["outside_max"]:
            raise SourceError(f"land needs {total} vertices (largest polygon {biggest}) at {simp['inside']} m "
                              f"inside bounds: over the caps of venues.md §4.1; shrink bounds or split the land")
        tol_out *= 2
        notes.clear()
        notes.append(f"outside tolerance raised to {tol_out:g} m for the vertex caps")
    _land_ids(land)

    # land for the fields: wider box, plain tolerance
    frings = clip_to_box(paths, field_box)
    flands = []
    for r in frings:
        h = r["height"] or default_h
        q = simplify_ring(r["points"], np.full(len(r["points"]), simp["field_tolerance"]),
                          _on_box(r["points"], field_box))
        if len(q) >= 3 and signed_area(q) > 0:
            flands.append({"points": q, "height": h})
    R = Raster(field_box, wp["work_resolution"])
    mask, height = R.rasterize(flands)
    tp = terrain_params(src)
    if tp is not None and src["terrain"].get("dem"):
        from .dem import Dem
        try:
            dem = Dem([os.path.join(src["_dir"], q) for q in src["terrain"]["dem"]])
        except InputError as ex:
            raise SourceError(f"$.terrain: {ex}") from ex
        height = wind_heights(R, mask, height, dem, origin, tp)
        land_h = height[mask > 0.5]
        if land_h.size:
            notes.append(f"wind land heights from the elevation model: mean {land_h.mean():.0f} m, "
                         f"max {land_h.max():.0f} m")

    gbox = _grow(bounds, grids["margin"])
    doc = {k: copy.deepcopy(src[k]) for k in COPY_HEADER if k in src}
    doc["schema"] = "windmark.venue/1"
    doc["source"] = _source_note(src)
    hemi = 1.0 if (origin or {}).get("lat", 1.0) >= 0 else -1.0

    if src.get("wind_field", True):
        wg = make_grid(gbox, grids["wind"], CAPS["wind_nodes"])
        secs = wind_field(wg, R, mask, height, hemi, wp)
        doc["wind_field"] = {"grid": wg, "sectors": [{"f": _round(f, 4), "d": _round(d, 4)} for f, d in secs]}

    cur = src.get("current")
    if cur:
        cp = _merged(CURRENT_DEFAULTS, {k: v for k, v in cur.items() if k not in ("to", "speed", "banks")},
                     "$.current")
        for k in ("to", "speed"):
            if k not in cur:
                raise SourceError(f"$.current.{k} is required")
        cg = make_grid(gbox, grids["current"], CAPS["field_nodes"])
        vx, vy = current_field(cg, R, mask, land, cur, cur.get("banks", []), cp)
        vx, vy = _round(vx, 4), _round(vy, 4)
        doc["current_field"] = {"grid": cg, "vx": vx, "vy": vy,
                                "ref_speed": round(ref_speed(cg, vx, vy, bounds, land), 4)}

    if src.get("exposure") is not False:
        cond = src.get("conditions") or {}
        wfrom = float((src.get("exposure") or {}).get("from", cond.get("wind", {}).get("from", 0.0)))
        eg = make_grid(gbox, grids["exposure"], CAPS["field_nodes"])
        e = exposure(eg, R, mask, land, wfrom, float(src.get("fetch", 10000.0)), ep)
        doc["exposure"] = {"grid": eg, "e": _round(e, 3)}

    out_land = _split_land(land, simp["split"], notes)
    doc["land"] = [{"id": p["id"], "points": [[_num(v) for v in q] for q in p["points"]]} for p in out_land]
    doc["obstacles"] = copy.deepcopy(src.get("obstacles", []))
    if "conditions" in src:
        doc["conditions"] = copy.deepcopy(src["conditions"])
    if "briefing" in src:
        doc["briefing"] = copy.deepcopy(src["briefing"])

    c = _Checker()
    if "conditions" in doc:
        check_conditions(c, doc["conditions"], "current_field" in doc)
    if "briefing" in doc:
        check_briefing(c, doc["briefing"])
    if c.problems:
        raise SourceError("; ".join(c.problems))
    notes.append(f"land: {len(land)} polygons, {sum(len(p['points']) for p in land)} vertices")
    if tp is not None and tp["draw"] and terrain_out is not None:
        try:
            terrain_out.append(build_terrain(src, tp, origin, bounds, land_box, land, notes, default_h))
        except InputError as ex:
            raise SourceError(f"$.terrain: {ex}") from ex
    return doc, notes


def _num(v):
    v = float(v)
    if v == 0.0:
        return 0
    if v.is_integer() and abs(v) < 1e15:
        return int(v)
    return v


def _round(a, decimals):
    a = np.round(np.asarray(a, float), decimals)
    return [_num(v) for v in a.tolist()]


def dumps(doc):
    """JSON text: one key per line at the top, big arrays on one line each."""
    def enc(v, indent):
        pad = "  " * indent
        if isinstance(v, dict):
            if not v:
                return "{}"
            small = json.dumps(v, ensure_ascii=False)
            if len(small) <= 100:
                return small
            items = [f'{pad}  {json.dumps(k)}: {enc(x, indent + 1)}' for k, x in v.items()]
            return "{\n" + ",\n".join(items) + "\n" + pad + "}"
        if isinstance(v, list):
            if all(not isinstance(x, (dict, list)) for x in v):
                return json.dumps(v)
            small = json.dumps(v, ensure_ascii=False)
            if len(small) <= 100:
                return small
            items = [f"{pad}  {enc(x, indent + 1)}" for x in v]
            return "[\n" + ",\n".join(items) + "\n" + pad + "]"
        return json.dumps(v, ensure_ascii=False)
    return enc(doc, 0) + "\n"


def terrain_paths(venue_path):
    """The drawn terrain files next to a venue file: <id>.terrain.json and <id>.terrain.bin."""
    base = venue_path[:-len(".venue.json")] if venue_path.endswith(".venue.json") else venue_path
    return base + ".terrain.json", base + ".terrain.bin"


def build_file(src_path, out_path=None):
    """Builds a venue; with `out_path` writes it (and, with an elevation model, the terrain files beside it).
    Returns (doc, text, notes, terrain) with terrain None or (header text, blob)."""
    src = load_source(src_path)
    tout = []
    doc, notes = build(src, tout)
    text = dumps(doc)
    problems = validate(json.loads(text), text)
    if problems:
        raise SourceError("generated venue fails validation: " + "; ".join(problems[:10]))
    terrain = None
    if tout:
        tdoc, blob = tout[0]
        tdoc["bin"] = os.path.basename(terrain_paths(out_path or f"{src['id']}.venue.json")[1])
        tdoc["source"] = doc["source"]
        tp = check_terrain(tdoc, len(blob))
        if tp:
            raise SourceError("generated terrain fails its checks: " + "; ".join(tp))
        terrain = (dumps(tdoc), blob)
    if out_path:
        with open(out_path, "w") as f:
            f.write(text)
        if terrain:
            tj, tb = terrain_paths(out_path)
            with open(tj, "w") as f:
                f.write(terrain[0])
            with open(tb, "wb") as f:
                f.write(terrain[1])
    return doc, text, notes, terrain
