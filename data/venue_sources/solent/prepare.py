"""Derived coastline and bank inputs of the Solent venue from the EMODnet Bathymetry downloads.

Run once by hand when the raw downloads change; the outputs next to this script are committed (small, clipped to
the venue, CC-BY 4.0 like their source) so the venue file can be regenerated without the downloads.

Inputs (data/venue_sources/raw/solent/, not committed), fetched with:
  curl --compressed -o emodnet_coastlines_wfs.json "https://ows.emodnet-bathymetry.eu/wfs?SERVICE=WFS&VERSION=2.0.0\
&REQUEST=GetFeature&TYPENAMES=emodnet:coastlines&BBOX=50.70,-1.47,50.88,-1.12,urn:ogc:def:crs:EPSG::4326\
&OUTPUTFORMAT=application/json"
  curl -o emodnet_dtm_solent.tif "https://ows.emodnet-bathymetry.eu/wcs?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage\
&COVERAGEID=emodnet__mean&SUBSET=Lat(50.70,50.88)&SUBSET=Long(-1.47,-1.12)&FORMAT=image/tiff"

  emodnet_coastlines_wfs.json  EMODnet Bathymetry coastlines (WFS layer emodnet:coastlines, GeoJSON); the
                               satellite-derived Mean High Water lines (type MHW) are used
  emodnet_dtm_solent.tif       EMODnet Bathymetry DTM (WCS coverage emodnet__mean, GeoTIFF, 1/16 arc minute)

Outputs:
  mainland.geojson, island.geojson   land polygons (lon/lat, WGS84) of the mainland shore and of the Isle of Wight
  banks.json                         Bramble Bank outlines from the DTM depth contours, in local metres, for
                                     current.banks

The MHW lines come as fragments with small gaps and a 1e-4 degree staircase (the satellite pixels): fragments are
chained end to end (gaps up to `GAP` m closed with a straight segment), smoothed with a short moving average, and
polygonized together with the edge of the box; each face is land when the DTM says so at most of a few sample
points inside it.

Needs NumPy, shapely, tifffile, Matplotlib (its contouring) and windmark_venuegen (its projection), only on the
machine that prepares the inputs:
  uv pip install --python tools/venuegen/.venv/bin/python shapely tifffile matplotlib
  tools/venuegen/.venv/bin/python data/venue_sources/solent/prepare.py
"""

from __future__ import annotations

import json
import math
import os

import numpy as np
import shapely
import tifffile
from shapely.geometry import LineString, MultiLineString, Point, Polygon, box, mapping
from shapely.ops import polygonize, unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "raw", "solent")

BOX = (-1.465, 50.722, -1.160, 50.862)  # lon/lat, a little beyond the venue's field box
LAT0 = 50.785
MX = 111320.0 * math.cos(math.radians(LAT0))  # m per degree of longitude
MY = 111132.0  # m per degree of latitude
GAP = 250.0  # m, largest gap closed between MHW fragments
SMOOTH = 5  # points in the moving average
MIN_LAND = 3000.0  # m², smaller land pieces (marsh islets, jetty heads) are dropped
SPLIT_LAT = 50.772
ORIGIN = {"lat": 50.785, "lon": -1.31}  # the venue origin (solent.venuesrc.json)  # land faces whose centre is south of this are the Isle of Wight

# DTM grid (pixel-is-area, from the GeoTIFF's ModelTransformation)
DTM_X0, DTM_Y0, DTM_S = -1.4697916666666582, 50.88020833333333, 1.0 / 960.0


def metres(c):
    c = np.asarray(c, float)
    return np.stack([(c[:, 0] - BOX[0]) * MX, (c[:, 1] - BOX[1]) * MY], axis=1)


def lonlat(m):
    m = np.asarray(m, float)
    return np.stack([m[:, 0] / MX + BOX[0], m[:, 1] / MY + BOX[1]], axis=1)


def load_lines():
    with open(os.path.join(RAW, "emodnet_coastlines_wfs.json")) as f:
        doc = json.load(f)
    clip = box(*BOX)
    out = []
    for feat in doc["features"]:
        if feat["properties"].get("type") != "MHW":
            continue
        g = shapely.geometry.shape(feat["geometry"]).intersection(clip)
        for part in getattr(g, "geoms", [g]):
            if isinstance(part, LineString) and len(part.coords) >= 2:
                out.append(metres(part.coords))
    return out


def chain(lines):
    """Join fragments whose ends are within GAP of each other (closest pairs first)."""
    lines = [l for l in lines if len(l) >= 2]
    while True:
        best = None
        ends = [(i, e) for i in range(len(lines)) for e in (0, -1)]
        for a in range(len(ends)):
            i, ei = ends[a]
            pi = lines[i][ei]
            for b in range(a + 1, len(ends)):
                j, ej = ends[b]
                if i == j:
                    continue
                d = float(np.hypot(*(pi - lines[j][ej])))
                if d <= GAP and (best is None or d < best[0]):
                    best = (d, i, ei, j, ej)
        if best is None:
            break
        _, i, ei, j, ej = best
        li = lines[i] if ei == -1 else lines[i][::-1]
        lj = lines[j] if ej == 0 else lines[j][::-1]
        joined = np.vstack([li, lj])
        lines = [l for k, l in enumerate(lines) if k not in (i, j)] + [joined]
    # close a line on itself when its own ends are near (an island or a closed bay)
    out = []
    for l in lines:
        if len(l) > 3 and np.hypot(*(l[0] - l[-1])) <= GAP:
            l = np.vstack([l, l[:1]])
        out.append(l)
    return out


def smooth(l):
    if len(l) < SMOOTH + 2:
        return l
    closed = np.allclose(l[0], l[-1])
    k = SMOOTH // 2
    if closed:
        p = l[:-1]
        ext = np.vstack([p[-k:], p, p[:k]])
        s = np.stack([np.convolve(ext[:, c], np.ones(SMOOTH) / SMOOTH, mode="valid") for c in (0, 1)], axis=1)
        return np.vstack([s, s[:1]])
    s = l.copy()
    for c in (0, 1):
        s[k:-k, c] = np.convolve(l[:, c], np.ones(SMOOTH) / SMOOTH, mode="valid")
    return s


def load_dtm():
    return tifffile.imread(os.path.join(RAW, "emodnet_dtm_solent.tif")).astype(float)


def dtm_at(a, lon, lat):
    i = np.floor((lon - DTM_X0) / DTM_S).astype(int)
    j = np.floor((DTM_Y0 - lat) / DTM_S).astype(int)
    ok = (i >= 0) & (j >= 0) & (i < a.shape[1]) & (j < a.shape[0])
    v = np.full(np.shape(lon), np.nan)
    v[ok] = a[j[ok], i[ok]]
    return v


def is_land(face, dtm, rng):
    """Majority vote of the DTM at points inside the face (no data counts as land: the DTM covers the sea)."""
    minx, miny, maxx, maxy = face.bounds
    pts = [face.representative_point()]
    tries = 0
    while len(pts) < 25 and tries < 2000:
        tries += 1
        p = Point(rng.uniform(minx, maxx), rng.uniform(miny, maxy))
        if face.contains(p):
            pts.append(p)
    ll = lonlat([[p.x, p.y] for p in pts])
    z = dtm_at(dtm, ll[:, 0], ll[:, 1])
    land = np.isnan(z) | (z > 0.5)
    return land.mean() > 0.5


def banks(dtm, level, min_area, ids):
    """Closed DTM depth contours at `level` (m, negative = below the datum) around shoals offshore."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    ny, nx = dtm.shape
    lon = DTM_X0 + (np.arange(nx) + 0.5) * DTM_S
    lat = DTM_Y0 - (np.arange(ny) + 0.5) * DTM_S
    z = np.where(np.isnan(dtm), 50.0, dtm)
    cs = plt.contour(lon, lat, z, levels=[level])
    out = []
    for seg in cs.allsegs[0]:
        if len(seg) < 4 or not np.allclose(seg[0], seg[-1]):
            continue
        poly = Polygon(metres(seg))
        if not poly.is_valid or poly.area < min_area:
            continue
        c = poly.centroid
        cl = lonlat([[c.x, c.y]])[0]
        for name, (lo, la, r) in ids.items():
            if math.hypot((cl[0] - lo) * MX, (cl[1] - la) * MY) < r:
                out.append((name, poly))
    plt.close("all")
    return out


def write_land(path, polys, note):
    feats = []
    for p in polys:
        ring = lonlat(np.asarray(p.exterior.coords))
        feats.append({"type": "Feature", "properties": {},
                      "geometry": {"type": "Polygon",
                                   "coordinates": [[[round(x, 6), round(y, 6)] for x, y in ring]]}})
    with open(path, "w") as f:
        json.dump({"type": "FeatureCollection", "name": note, "features": feats}, f, separators=(",", ":"))
        f.write("\n")


def main():
    rng = np.random.default_rng(1)
    dtm = load_dtm()
    lines = [smooth(l) for l in chain(load_lines())]
    frame = metres([[BOX[0], BOX[1]], [BOX[2], BOX[1]], [BOX[2], BOX[3]], [BOX[0], BOX[3]], [BOX[0], BOX[1]]])
    net = unary_union([LineString(l) for l in lines] + [LineString(frame)])
    faces = list(polygonize(net))
    land = [f for f in faces if is_land(f, dtm, rng)]
    merged = unary_union(land)
    pieces = [g for g in getattr(merged, "geoms", [merged]) if g.area >= MIN_LAND]
    pieces = [Polygon(g.exterior).simplify(1.0) for g in pieces]  # holes (ponds) are land too
    island = [p for p in pieces if lonlat([[p.centroid.x, p.centroid.y]])[0][1] < SPLIT_LAT]
    mainland = [p for p in pieces if p not in island]
    write_land(os.path.join(HERE, "mainland.geojson"), mainland,
               "Solent mainland shore, from EMODnet Bathymetry satellite-derived coastline (MHW), CC-BY 4.0")
    write_land(os.path.join(HERE, "island.geojson"), island,
               "Isle of Wight north shore, from EMODnet Bathymetry satellite-derived coastline (MHW), CC-BY 4.0")
    print(f"{len(lines)} chained lines, {len(faces)} faces, land: {len(mainland)} mainland, {len(island)} island "
          f"pieces, {sum(len(p.exterior.coords) for p in pieces)} points")

    # Bramble Bank: the 2 m contour (two drying heads) inside the 4 m contour (the whole shoal), in local metres
    # of the venue origin, for current.banks of solent.venuesrc.json
    from windmark_venuegen.geo import lonlat_to_enu
    out = {"source": "EMODnet Bathymetry DTM (emodnet__mean), depth contours, CC-BY 4.0",
           "origin": ORIGIN, "banks": []}
    for level, name, tol in ((-4.0, "bramble_shoal", 20.0), (-2.0, "bramble_bank", 15.0)):
        for k, (_, poly) in enumerate(banks(dtm, level, 50000.0, {name: (-1.28, 50.794, 2500.0)})):
            ring = lonlat(np.asarray(poly.simplify(tol).exterior.coords)[:-1])
            e, n = lonlat_to_enu(ring[:, 0], ring[:, 1], ORIGIN)
            out["banks"].append({"id": f"{name}_{k + 1}", "depth": -level,
                                 "points": [[round(float(x), 1), round(float(y), 1)] for x, y in zip(e, n)]})
            print(f"{name}_{k + 1}: {len(ring)} points, {poly.area / 1e6:.2f} km²")
    with open(os.path.join(HERE, "banks.json"), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
