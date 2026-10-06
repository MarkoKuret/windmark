"""Clips the Trieste coastline inputs of trieste.venuesrc.json from the EMODnet Bathymetry satellite-derived
coastline 2024 (CC-BY 4.0, EMODnet Bathymetry Consortium, https://emodnet.ec.europa.eu/en/bathymetry).

The release is one 2.5 GB archive, https://downloads.emodnet-bathymetry.eu/v12/EMODnet_Bathymetry_2024_coastlines.zip
(downloaded 2026-10-06). Inside it, Europe_2024_satellite_coastline.zip holds the polyline shapefiles. Extract
Europe_2024_satellite_coastline_MHW.{shp,shx,dbf,prj} (Mean High Water, 1.1 GB) and
Europe_2024_satellite_coastline_ITA.{shp,shx,dbf,prj} (2 GB) into data/venue_sources/raw/trieste/ (not committed),
for example with Python's zipfile, and run from the repo root:

    python3 data/venue_sources/trieste/prep_coast.py

It writes the two small inputs committed next to this script (WGS84 lon/lat, 1e-6 degree):
- coast.geojson: the Mean High Water shore from Koper bay to Duino as one line with the land on its right (role
  shore_right). The lines are cut at a 0.1 degree tile edge (13.7125 E) that runs through Miramare, and the MHW
  file has no piece west of it there, which would cut off the promontory and the castle; the ITA file of the same
  release has that piece (its records 124267 and 126253), so the line takes it there.
- breakwaters.geojson: the MHW closed rings in the sea (moles and small breakwaters) as land polygons (role land,
  a low height).
Vertices are thinned with Douglas-Peucker at 1 m (venuegen simplifies further, at 5 m inside the racing area)."""

import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(HERE, "..", "raw", "trieste")
MHW = os.path.join(RAW_DIR, "Europe_2024_satellite_coastline_MHW")
ITA = os.path.join(RAW_DIR, "Europe_2024_satellite_coastline_ITA")
BOX = (13.56, 45.565, 13.86, 45.78)  # lon/lat box written: the drawn terrain box (bounds + 6 km) with room to spare
# The shore line, pieces in order (file, record, keep up to this latitude, reversed): MHW from Koper bay round
# Debeli rtic (the first piece runs the other way in the file), from Muggia north to just short of the tile edge
# at Miramare, the promontory west of the edge and the shore back east of it (ITA), then the MHW shore west to
# Duino.
CHAIN = ((MHW, 64422, None, True), (MHW, 63647, None, False), (MHW, 64421, 45.70225, False),
         (ITA, 124267, None, False), (ITA, 126253, None, False), (MHW, 63552, None, False))
TOL = 1.0  # m


def records(ids, raw=MHW):
    shx = open(raw + ".shx", "rb").read()
    out = {}
    with open(raw + ".shp", "rb") as shp:
        for i in ids:
            off = struct.unpack(">i", shx[100 + 8 * i:104 + 8 * i])[0] * 2
            shp.seek(off + 8 + 4 + 32)
            nparts, npts = struct.unpack("<2i", shp.read(8))
            shp.read(4 * nparts)
            v = struct.unpack("<%dd" % (2 * npts), shp.read(16 * npts))
            out[i] = list(zip(v[0::2], v[1::2]))
    return out


def all_in_box():
    """(record id, points) of every record whose box meets BOX."""
    shx = open(MHW + ".shx", "rb").read()
    n = (len(shx) - 100) // 8
    hits = []
    with open(MHW + ".shp", "rb") as shp:
        for i in range(n):
            off = struct.unpack(">i", shx[100 + 8 * i:104 + 8 * i])[0] * 2
            shp.seek(off + 8)
            if struct.unpack("<i", shp.read(4))[0] == 0:
                continue
            bb = struct.unpack("<4d", shp.read(32))
            if bb[2] < BOX[0] or bb[0] > BOX[2] or bb[3] < BOX[1] or bb[1] > BOX[3]:
                continue
            hits.append(i)
    return hits


def metres(p, lat0=45.68):
    k = math.cos(math.radians(lat0))
    return [(x * 111320.0 * k, y * 111132.0) for x, y in p]


def dp(p, tol):
    """Douglas-Peucker on lon/lat points with the tolerance in metres; keeps the ends."""
    m = metres(p)
    keep = [False] * len(p)
    keep[0] = keep[-1] = True
    stack = [(0, len(p) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = m[a]
        bx, by = m[b]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = m[i]
            d = abs(dx * (py - ay) - dy * (px - ax)) / L if L > 0 else math.hypot(px - ax, py - ay)
            if d > best:
                best, bi = d, i
        if best > tol:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [q for q, k in zip(p, keep) if k]


def area(p):
    m = metres(p)
    return 0.5 * sum(m[i][0] * m[i - 1][1] - m[i - 1][0] * m[i][1] for i in range(len(m)))


def inside(p):
    return BOX[0] <= p[0] <= BOX[2] and BOX[1] <= p[1] <= BOX[3]


def rnd(p):
    return [[round(x, 6), round(y, 6)] for x, y in p]


def main():
    line = []
    for raw, i, lat_max, rev in CHAIN:
        p = records([i], raw)[i]
        if rev:
            p = p[::-1]
        if lat_max is not None:
            p = p[:max(k for k, q in enumerate(p) if q[1] <= lat_max) + 1]
        line += p if not line or p[0] != line[-1] else p[1:]
    # from the last point before the line first enters BOX to the first point after it last leaves it
    first = next(k for k, q in enumerate(line) if inside(q))
    last = max(k for k, q in enumerate(line) if inside(q))
    line = line[max(0, first - 1):last + 2]
    coast = dp(line, TOL)
    rings = []
    for i in all_in_box():
        if i in [c[1] for c in CHAIN if c[0] == MHW]:
            continue
        r = records([i])[i]
        if r[0] != r[-1] or not all(inside(q) for q in r):
            continue
        rings.append((i, r))
    polys = []
    for i, r in rings:
        q = dp(r, TOL)
        if len(q) < 4:
            continue
        if area(q) < 0:
            q = q[::-1]
        polys.append({"type": "Feature", "properties": {"record": i},
                      "geometry": {"type": "Polygon", "coordinates": [rnd(q)]}})
    note = ("Derived from the EMODnet Bathymetry satellite-derived coastline 2024 (Mean High Water), CC-BY 4.0, "
            "EMODnet Bathymetry Consortium; clipped and thinned by prep_coast.py")
    with open(os.path.join(HERE, "coast.geojson"), "w") as f:
        json.dump({"type": "FeatureCollection", "note": note, "features": [
            {"type": "Feature", "properties": {"records": [f"{os.path.basename(c[0])[-3:]} {c[1]}" for c in CHAIN]},
             "geometry": {"type": "LineString", "coordinates": rnd(coast)}}]}, f, separators=(",", ":"))
        f.write("\n")
    with open(os.path.join(HERE, "breakwaters.geojson"), "w") as f:
        json.dump({"type": "FeatureCollection", "note": note, "features": polys}, f, separators=(",", ":"))
        f.write("\n")
    print(f"coast: {len(line)} -> {len(coast)} points; rings: {len(polys)} ({[p['properties']['record'] for p in polys]})")


if __name__ == "__main__":
    sys.exit(main())
