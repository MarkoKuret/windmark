"""Coastline input: GeoJSON and ESRI shapefile readers, and the lon/lat to local ENU projection.

Every reader returns paths in local ENU metres (x east, y north) around the venue origin, each a dict
``{"points": (n, 2) float64 array, "closed": bool, "role": "land" | "water", "height": float}`` where for a
closed land path the land is on the left (counter-clockwise) and for a water path it is the water that is on the
left before `orient` flips it. Open paths (shore lines) carry the land on their left.
"""

from __future__ import annotations

import json
import math
import os
import struct

import numpy as np

# WGS84
_A = 6378137.0
_F = 1.0 / 298.257223563
_E2 = _F * (2.0 - _F)


class InputError(ValueError):
    pass


def _ecef(lat, lon):
    lat = np.radians(lat)
    lon = np.radians(lon)
    n = _A / np.sqrt(1.0 - _E2 * np.sin(lat) ** 2)
    return (n * np.cos(lat) * np.cos(lon), n * np.cos(lat) * np.sin(lon), n * (1.0 - _E2) * np.sin(lat))


def lonlat_to_enu(lon, lat, origin):
    """WGS84 lon/lat (degrees, arrays) to east/north metres in the tangent plane at origin {"lat", "lon"}.

    Exact ellipsoidal ECEF to ENU at height 0; over a venue (at most ~12 km from the origin) the tangent plane
    differs from the ground by less than a metre horizontally."""
    lat0, lon0 = float(origin["lat"]), float(origin["lon"])
    x0, y0, z0 = _ecef(np.array(lat0), np.array(lon0))
    x, y, z = _ecef(np.asarray(lat, float), np.asarray(lon, float))
    dx, dy, dz = x - x0, y - y0, z - z0
    sl, cl = math.sin(math.radians(lon0)), math.cos(math.radians(lon0))
    sp, cp = math.sin(math.radians(lat0)), math.cos(math.radians(lat0))
    e = -sl * dx + cl * dy
    n = -sp * cl * dx - sp * sl * dy + cp * dz
    return e, n


def enu_to_lonlat_box(box, origin, margin_deg=0.01):
    """A lon/lat box that surely holds the local box (xmin, ymin, xmax, ymax): for prefiltering big inputs."""
    lat0 = float(origin["lat"])
    m_per_deg_lat = 111132.0
    m_per_deg_lon = max(1.0, 111320.0 * math.cos(math.radians(lat0)))
    lon0 = float(origin["lon"])
    return (lon0 + box[0] / m_per_deg_lon - margin_deg, lat0 + box[1] / m_per_deg_lat - margin_deg,
            lon0 + box[2] / m_per_deg_lon + margin_deg, lat0 + box[3] / m_per_deg_lat + margin_deg)


def signed_area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def _clean(points, closed):
    """Drop repeated points (and the repeated closing point of a ring)."""
    p = np.asarray(points, float)[:, :2]
    if len(p) == 0:
        return p
    keep = np.ones(len(p), bool)
    keep[1:] = np.any(p[1:] != p[:-1], axis=1)
    p = p[keep]
    if closed and len(p) > 1 and np.all(p[0] == p[-1]):
        p = p[:-1]
    return p


# --- polygons with roles ------------------------------------------------------------------------------------


def polygon_paths(rings, role, height, rings_are_ccw_outer=None):
    """Rings of one polygon (first = outer, rest = holes) to paths with the land on the left.

    land role: outer ring CCW (land), holes dropped (inland lakes do not matter for sailing).
    water role: outer ring CW (land outside the water), holes CCW (islands in the water)."""
    out = []
    for k, ring in enumerate(rings):
        p = _clean(ring, True)
        if len(p) < 3:
            continue
        a = signed_area(p)
        if a == 0.0:
            continue
        outer = k == 0
        if role == "land":
            if not outer:
                continue
            want_ccw = True
        elif role == "water":
            want_ccw = not outer
        else:
            raise InputError(f"unknown polygon role {role!r}")
        if (a > 0) != want_ccw:
            p = p[::-1].copy()
        out.append({"points": p, "closed": True, "height": height})
    return out


def line_paths(lines, land_side, height):
    """Open shore lines with the land on `land_side` ("left" or "right") of their direction of travel."""
    out = []
    for line in lines:
        p = _clean(line, False)
        if len(p) < 2:
            continue
        if land_side == "right":
            p = p[::-1].copy()
        elif land_side != "left":
            raise InputError("shore lines need land_side 'left' or 'right'")
        out.append({"points": p, "closed": False, "height": height})
    return out


# --- GeoJSON ------------------------------------------------------------------------------------------------


def _geojson_geometries(doc):
    t = doc.get("type")
    if t == "FeatureCollection":
        for f in doc.get("features", []):
            if f.get("geometry"):
                yield f["geometry"], f.get("properties") or {}
    elif t == "Feature":
        if doc.get("geometry"):
            yield doc["geometry"], doc.get("properties") or {}
    elif t == "GeometryCollection":
        for g in doc.get("geometries", []):
            yield g, {}
    else:
        yield doc, {}


def read_geojson(path):
    """Yields (kind, parts, properties): kind "polygon" with a list of rings, or "line" with a list of points."""
    with open(path) as f:
        doc = json.load(f)

    def walk(g, props):
        t = g.get("type")
        c = g.get("coordinates")
        if t == "Polygon":
            yield "polygon", c, props
        elif t == "MultiPolygon":
            for poly in c:
                yield "polygon", poly, props
        elif t == "LineString":
            yield "line", c, props
        elif t == "MultiLineString":
            for line in c:
                yield "line", line, props
        elif t == "GeometryCollection":
            for gg in g.get("geometries", []):
                yield from walk(gg, props)

    for g, props in _geojson_geometries(doc):
        yield from walk(g, props)


# --- ESRI shapefile (.shp), pure Python ---------------------------------------------------------------------

_SHP_POLYGON = {5, 15, 25}
_SHP_POLYLINE = {3, 13, 23}


def check_prj(path):
    """A shapefile's .prj must be geographic (lon/lat) for frame 'lonlat'; projected inputs are reprojected
    first (README: ogr2ogr -t_srs EPSG:4326)."""
    prj = os.path.splitext(path)[0] + ".prj"
    if not os.path.exists(prj):
        return
    with open(prj, errors="replace") as f:
        wkt = f.read().strip().upper()
    if wkt.startswith("PROJCS") or wkt.startswith("PROJCRS"):
        raise InputError(f"{path}: projected coordinate system in .prj; reproject to EPSG:4326 (lon/lat) first")


def read_shapefile(path, bbox=None):
    """Yields (kind, parts, {}) like read_geojson. Polygon rings: the shapefile marks outer rings clockwise and
    holes counter-clockwise, so each outer ring starts a new polygon. `bbox` (xmin, ymin, xmax, ymax) skips
    records whose own box misses it (big national files)."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 100 or struct.unpack(">i", data[0:4])[0] != 9994:
        raise InputError(f"{path}: not an ESRI shapefile")
    pos = 100
    while pos + 8 <= len(data):
        _, length = struct.unpack(">ii", data[pos:pos + 8])
        rec = data[pos + 8:pos + 8 + 2 * length]
        pos += 8 + 2 * length
        if len(rec) < 4:
            continue
        stype = struct.unpack("<i", rec[0:4])[0]
        if stype == 0:
            continue
        if stype not in _SHP_POLYGON and stype not in _SHP_POLYLINE:
            raise InputError(f"{path}: shape type {stype} not supported (polygons and polylines only)")
        xmin, ymin, xmax, ymax = struct.unpack("<4d", rec[4:36])
        if bbox and (xmax < bbox[0] or xmin > bbox[2] or ymax < bbox[1] or ymin > bbox[3]):
            continue
        nparts, npoints = struct.unpack("<ii", rec[36:44])
        parts = list(struct.unpack(f"<{nparts}i", rec[44:44 + 4 * nparts])) + [npoints]
        off = 44 + 4 * nparts
        pts = np.frombuffer(rec[off:off + 16 * npoints], dtype="<f8").reshape(npoints, 2)
        pieces = [pts[parts[i]:parts[i + 1]] for i in range(nparts)]
        if stype in _SHP_POLYLINE:
            for p in pieces:
                yield "line", p, {}
            continue
        poly = []
        for p in pieces:
            if signed_area(np.asarray(p, float)) < 0 and poly:  # clockwise: a new outer ring
                yield "polygon", poly, {}
                poly = []
            poly.append(p)
        if poly:
            yield "polygon", poly, {}


# --- one coastline entry of the source file -----------------------------------------------------------------


def load_entry(entry, origin, base_dir, field_box):
    """Paths (land on the left, local metres) of one `coastline` entry of the source file."""
    height = float(entry.get("height", 0.0)) or None
    role = entry.get("role", "land")
    frame = entry.get("frame", "local")
    out = []
    if "polygons" in entry:  # inline local-metre polygons
        if frame != "local":
            raise InputError("inline polygons are in local metres (frame 'local')")
        for poly in entry["polygons"]:
            h = float(poly.get("height", 0.0)) or height
            paths = polygon_paths([poly["points"]], role, h)
            for p in paths:
                p["id"] = poly.get("id")
            out += paths
        return out
    path = os.path.join(base_dir, entry["path"])
    if not os.path.exists(path):
        raise InputError(f"coastline file not found: {path} (raw downloads are kept out of the repo; see README)")
    ext = os.path.splitext(path)[1].lower()
    if frame == "lonlat":
        if origin is None:
            raise InputError("a lon/lat coastline needs the venue origin")
        if ext == ".shp":
            check_prj(path)
        bbox = enu_to_lonlat_box(field_box, origin)
    elif frame == "local":
        bbox = field_box
    else:
        raise InputError(f"unknown frame {frame!r} (lonlat or local)")
    if ext == ".shp":
        items = read_shapefile(path, bbox)
    elif ext in (".geojson", ".json"):
        items = read_geojson(path)
    else:
        raise InputError(f"{path}: unsupported coastline format (GeoJSON or shapefile; see README)")

    def proj(c):
        c = np.asarray(c, float)[:, :2]
        if frame == "lonlat":
            e, n = lonlat_to_enu(c[:, 0], c[:, 1], origin)
            return np.stack([e, n], axis=1)
        return c

    if role not in ("land", "water", "shore_left", "shore_right"):
        raise InputError(f"unknown coastline role {role!r}")
    for kind, parts, _props in items:
        if kind == "polygon" and role in ("land", "water"):
            out += polygon_paths([proj(r) for r in parts], role, height)
        elif role in ("shore_left", "shore_right"):
            out += line_paths([proj(parts)], role.split("_")[1], height)
        # lines in a polygon file (or the reverse) are skipped
    return out
