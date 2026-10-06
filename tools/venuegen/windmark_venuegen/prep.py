"""Preparing raw downloads for venuegen (no GDAL).

    python -m windmark_venuegen.prep utm IN.shp OUT.geojson --zone 32 --box LON0 LAT0 LON1 LAT1 [--min-area M2]
    python -m windmark_venuegen.prep dem-water DEM.tif OUT.geojson --level H --seed LON LAT --box LON0 LAT0 LON1 LAT1
    python -m windmark_venuegen.prep splice NORTH.geojson SOUTH.geojson OUT.geojson --cut-lat LAT

`utm`: a UTM shapefile (ETRS89 or WGS84) to a lon/lat GeoJSON of the polygons that reach the box.
`dem-water`: the water body of an elevation tile that is flattened to one level (SRTM and NASADEM carry the SRTM
Water Body Data that way): the cells at `level` connected to the seed, inside the box, traced along the cell
edges, smoothed (Chaikin, `--smooth` passes [2]) into a GeoJSON water polygon (the box edge closes it where
the water runs on).
`splice`: one water polygon from two: the outer ring of NORTH north of the cut latitude joined to the outer ring
of SOUTH south of it (each must cross the cut exactly twice), with the holes of each on its side.

The inverse transverse Mercator is the series of Snyder (1987, eq. 8-18 to 8-25) on GRS80 (ETRS89 and WGS84 agree
to well under a metre for this use), good to millimetres within a UTM zone. Polygons whose box misses `--box` are
skipped; the rest are written whole (venuegen clips them), smallest first dropped under `--min-area` (m²)."""

from __future__ import annotations

import argparse
import json
import math
import sys

import numpy as np

from .geo import read_shapefile, signed_area

_A = 6378137.0
_F = 1.0 / 298.257222101  # GRS80
_K0 = 0.9996


def utm_to_lonlat(e, n, zone, north=True):
    """UTM easting/northing (m) to lon/lat (degrees) on GRS80."""
    e = np.asarray(e, float) - 500000.0
    n = np.asarray(n, float) - (0.0 if north else 10000000.0)
    e2 = _F * (2 - _F)
    ep2 = e2 / (1 - e2)
    lon0 = math.radians(6 * zone - 183)
    M = n / _K0
    mu = M / (_A * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    phi1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * np.sin(2 * mu)
            + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * np.sin(4 * mu)
            + (151 * e1 ** 3 / 96) * np.sin(6 * mu) + (1097 * e1 ** 4 / 512) * np.sin(8 * mu))
    s, c, t = np.sin(phi1), np.cos(phi1), np.tan(phi1)
    C1 = ep2 * c ** 2
    T1 = t ** 2
    N1 = _A / np.sqrt(1 - e2 * s ** 2)
    R1 = _A * (1 - e2) / (1 - e2 * s ** 2) ** 1.5
    D = e / (N1 * _K0)
    lat = phi1 - (N1 * t / R1) * (D ** 2 / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 ** 2 - 9 * ep2) * D ** 4 / 24
                                  + (61 + 90 * T1 + 298 * C1 + 45 * T1 ** 2 - 252 * ep2 - 3 * C1 ** 2) * D ** 6 / 720)
    lon = lon0 + (D - (1 + 2 * T1 + C1) * D ** 3 / 6
                  + (5 - 2 * C1 + 28 * T1 - 3 * C1 ** 2 + 8 * ep2 + 24 * T1 ** 2) * D ** 5 / 120) / c
    return np.degrees(lon), np.degrees(lat)


def lonlat_to_utm_box(box, zone):
    """A UTM box that surely holds the lon/lat box (for the shapefile prefilter)."""
    lon0 = 6 * zone - 183
    lat_m = 111132.0
    xs, ys = [], []
    for lon in (box[0], box[2]):
        for lat in (box[1], box[3]):
            xs.append(500000.0 + (lon - lon0) * 111320.0 * math.cos(math.radians(lat)) * _K0)
            ys.append(lat * lat_m * _K0)
    pad = 5000.0
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def utm_shapefile_to_geojson(src, zone, box, min_area=0.0):
    feats = []
    for kind, parts, _ in read_shapefile(src, lonlat_to_utm_box(box, zone)):
        if kind != "polygon":
            continue
        if abs(signed_area(np.asarray(parts[0], float))) < min_area:
            continue
        rings = []
        for p in parts:
            lon, lat = utm_to_lonlat(p[:, 0], p[:, 1], zone)
            rings.append([[round(float(a), 7), round(float(b), 7)] for a, b in zip(lon, lat)])
        lo = np.array(rings[0])
        if lo[:, 0].max() < box[0] or lo[:, 0].min() > box[2] or lo[:, 1].max() < box[1] or lo[:, 1].min() > box[3]:
            continue
        # GeoJSON: outer counter-clockwise, holes clockwise (RFC 7946); the shapefile has the reverse
        rings = [r[::-1] for r in rings]
        feats.append({"type": "Feature", "properties": {},
                      "geometry": {"type": "Polygon", "coordinates": rings}})
    return {"type": "FeatureCollection", "features": feats}


def dem_water(dem_path, level, seed, box, smooth=2):
    from .dem import read_geotiff
    a, lon0, lat0, dlon, dlat = read_geotiff(dem_path)
    c0 = max(0, int(math.floor((box[0] - lon0) / dlon)))
    c1 = min(a.shape[1], int(math.ceil((box[2] - lon0) / dlon)) + 1)
    r0 = max(0, int(math.floor((lat0 - box[3]) / dlat)))
    r1 = min(a.shape[0], int(math.ceil((lat0 - box[1]) / dlat)) + 1)
    sub = a[r0:r1, c0:c1]
    water = np.abs(sub - level) < 0.5
    si = int(round((seed[0] - lon0) / dlon)) - c0
    sj = int(round((lat0 - seed[1]) / dlat)) - r0
    if not (0 <= sj < sub.shape[0] and 0 <= si < sub.shape[1]) or not water[sj, si]:
        raise SystemExit("the seed is not on the water level inside the box")
    comp = np.zeros_like(water)
    comp[sj, si] = True
    while True:  # flood fill by dilation within the water cells (4-neighbours)
        g = comp.copy()
        g[1:] |= comp[:-1]
        g[:-1] |= comp[1:]
        g[:, 1:] |= comp[:, :-1]
        g[:, :-1] |= comp[:, 1:]
        g &= water
        if np.array_equal(g, comp):
            break
        comp = g
    rings = _trace(comp)
    out = []
    for r in rings:  # corner (column, row) -> lon/lat; cell (i, j) spans corners (i, j) to (i + 1, j + 1)
        lon = lon0 + (c0 + r[:, 0] - 0.5) * dlon
        lat = lat0 - (r0 + r[:, 1] - 0.5) * dlat
        out.append(np.stack([lon, lat], 1))
    for _ in range(smooth):  # Chaikin corner cutting: the cell stairs become smooth diagonals
        out = [np.concatenate([0.75 * q + 0.25 * np.roll(q, -1, 0), 0.25 * q + 0.75 * np.roll(q, -1, 0)], 1)
               .reshape(-1, 2) for q in out]
    out.sort(key=lambda q: -abs(signed_area(q)))
    rings = [_orient(out[0], True)] + [_orient(q, False) for q in out[1:]]
    return {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {}, "geometry": {
        "type": "Polygon", "coordinates": [[[round(float(p[0]), 7), round(float(p[1]), 7)] for p in r] for r in rings]}}]}


def _orient(r, ccw):
    return r if (signed_area(r) > 0) == ccw else r[::-1]


def _trace(mask):
    """Closed rings along the cell edges between mask and not-mask, in (column, row) corner coordinates, with
    the mask on the right going in row-down coordinates; collinear corners dropped. At a corner where two rings
    touch diagonally the walk turns so the rings stay apart."""
    ny, nx = mask.shape
    m = np.zeros((ny + 2, nx + 2), bool)
    m[1:-1, 1:-1] = mask
    edges = {}
    # horizontal edges: between rows j-1 and j at corner row j; vertical: between columns i-1 and i
    for j in range(ny + 1):
        up, dn = m[j, 1:-1], m[j + 1, 1:-1]
        for i in np.where(up != dn)[0]:
            if dn[i]:  # water below: walk east (water on the right in row-down coordinates)
                edges.setdefault((i, j), []).append((i + 1, j))
            else:
                edges.setdefault((i + 1, j), []).append((i, j))
    for i in range(nx + 1):
        lf, rt = m[1:-1, i], m[1:-1, i + 1]
        for j in np.where(lf != rt)[0]:
            if lf[j]:  # water to the west: walk south (row increasing) keeps it on the right
                edges.setdefault((i, j), []).append((i, j + 1))
            else:
                edges.setdefault((i, j + 1), []).append((i, j))
    rings = []
    while edges:
        start = next(iter(edges))
        ring = [start]
        cur = start
        prev_dir = None
        while True:
            outs = edges[cur]
            if len(outs) == 1 or prev_dir is None:
                nxt = outs.pop(0)
            else:  # two ways on: take the right turn
                def turn(q):
                    d = (q[0] - cur[0], q[1] - cur[1])
                    return prev_dir[0] * d[1] - prev_dir[1] * d[0]
                outs.sort(key=turn, reverse=True)
                nxt = outs.pop(0)
            if not outs:
                del edges[cur]
            prev_dir = (nxt[0] - cur[0], nxt[1] - cur[1])
            cur = nxt
            if cur == start:
                break
            ring.append(cur)
        p = np.array(ring, float)
        keep = np.ones(len(p), bool)
        for k in range(len(p)):
            a, b, c = p[k - 1], p[k], p[(k + 1) % len(p)]
            if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) == 0:
                keep[k] = False
        if keep.sum() >= 3:
            rings.append(p[keep])
    return rings


def _crossings(ring, lat):
    """Indices k where segment ring[k] -> ring[k+1] crosses the latitude, with the crossing point."""
    out = []
    n = len(ring)
    for k in range(n):
        a, b = ring[k], ring[(k + 1) % n]
        if (a[1] - lat) * (b[1] - lat) < 0:
            t = (lat - a[1]) / (b[1] - a[1])
            out.append((k, a + t * (b - a)))
    return out


def splice(north, south, cut_lat):
    def rings_of(doc):
        polys = [g["coordinates"] for f in doc["features"] for g in [f["geometry"]] if g["type"] == "Polygon"]
        polys.sort(key=lambda p: -abs(signed_area(np.array(p[0], float))))
        return [np.array(r, float) for r in polys[0]]
    nr, sr = rings_of(north), rings_of(south)
    parts = []
    for ring, keep_north in ((_orient(nr[0][:-1] if np.all(nr[0][0] == nr[0][-1]) else nr[0], True), True),
                             (_orient(sr[0][:-1] if np.all(sr[0][0] == sr[0][-1]) else sr[0], True), False)):
        cr = _crossings(ring, cut_lat)
        if len(cr) != 2:
            raise SystemExit(f"a ring crosses the cut latitude {len(cr)} times (want 2)")
        n = len(ring)
        (k0, p0), (k1, p1) = cr
        a = [p0] + [ring[(k0 + 1 + i) % n] for i in range((k1 - k0) % n)] + [p1]
        b = [p1] + [ring[(k1 + 1 + i) % n] for i in range((k0 - k1) % n)] + [p0]
        side = (lambda c: np.mean([q[1] for q in c[1:-1]]) > cut_lat) if keep_north else \
            (lambda c: np.mean([q[1] for q in c[1:-1]]) < cut_lat)
        parts.append(a if side(a) else b)
    # both chains run counter-clockwise: north goes from its east crossing round the north to the west one,
    # south from the west crossing round the south to the east one
    ring = np.array(parts[0] + parts[1], float)
    holes = [h for h in nr[1:] if np.mean(h[:, 1]) > cut_lat] + [h for h in sr[1:] if np.mean(h[:, 1]) < cut_lat]
    rings = [_orient(ring, True)] + [_orient(h, False) for h in holes]
    return {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {}, "geometry": {
        "type": "Polygon", "coordinates": [[[round(float(p[0]), 7), round(float(p[1]), 7)] for p in r] for r in rings]}}]}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="windmark_venuegen.prep", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    u = sub.add_parser("utm", help="UTM shapefile (ETRS89 / WGS84) to a lon/lat GeoJSON clipped to a box")
    u.add_argument("src")
    u.add_argument("out")
    u.add_argument("--zone", type=int, required=True)
    u.add_argument("--box", type=float, nargs=4, required=True, metavar=("LON0", "LAT0", "LON1", "LAT1"))
    u.add_argument("--min-area", type=float, default=0.0)
    d = sub.add_parser("dem-water", help="the flattened water body of an elevation tile as a GeoJSON polygon")
    d.add_argument("src")
    d.add_argument("out")
    d.add_argument("--level", type=float, required=True)
    d.add_argument("--seed", type=float, nargs=2, required=True, metavar=("LON", "LAT"))
    d.add_argument("--box", type=float, nargs=4, required=True, metavar=("LON0", "LAT0", "LON1", "LAT1"))
    d.add_argument("--smooth", type=int, default=2)
    sp = sub.add_parser("splice", help="one water polygon from a north and a south one, joined at a latitude")
    sp.add_argument("north")
    sp.add_argument("south")
    sp.add_argument("out")
    sp.add_argument("--cut-lat", type=float, required=True)
    args = ap.parse_args(argv)
    if args.cmd == "utm":
        doc = utm_shapefile_to_geojson(args.src, args.zone, args.box, args.min_area)
    elif args.cmd == "dem-water":
        doc = dem_water(args.src, args.level, args.seed, args.box, args.smooth)
    else:
        with open(args.north) as f, open(args.south) as g:
            doc = splice(json.load(f), json.load(g), args.cut_lat)
    with open(args.out, "w") as f:
        json.dump(doc, f)
    print(f"{args.out}: {len(doc['features'])} polygons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
