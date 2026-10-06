"""Terrain from an elevation model (venues.md §5.7, data_format.md §6.10), the land split, and the prep tools."""

import copy
import gzip
import json
import math
import struct

import numpy as np
import pytest

from conftest import circle
from windmark_venuegen.build import build, dumps
from windmark_venuegen.dem import Dem, enu_to_lonlat, read_geotiff
from windmark_venuegen.geo import lonlat_to_enu, signed_area
from windmark_venuegen.prep import _trace, splice, utm_to_lonlat
from windmark_venuegen.raster import points_in_land
from windmark_venuegen.terrain import CAPS
from windmark_venuegen.validate import validate

ORIGIN = {"lat": 45.0, "lon": 13.0}


def write_geotiff(path, a, lon0, lat0, d):
    """A one-strip int16 GeoTIFF, PixelIsPoint, (lon0, lat0) the centre of pixel (0, 0)."""
    h, w = a.shape
    data = a.astype("<i2").tobytes()
    geokeys = [1, 1, 0, 2, 1024, 0, 1, 2, 1025, 0, 1, 2]
    entries = []  # (tag, type, values)
    entries.append((256, 3, [w]))
    entries.append((257, 3, [h]))
    entries.append((258, 3, [16]))
    entries.append((259, 3, [1]))
    entries.append((262, 3, [1]))
    entries.append((273, 4, [0]))  # patched below
    entries.append((277, 3, [1]))
    entries.append((278, 3, [h]))
    entries.append((279, 4, [len(data)]))
    entries.append((339, 3, [2]))
    entries.append((33550, 12, [d, d, 0.0]))
    entries.append((33922, 12, [0.0, 0.0, 0.0, lon0, lat0, 0.0]))
    entries.append((34735, 3, geokeys))
    fmt = {3: "H", 4: "I", 12: "d"}
    size = {3: 2, 4: 4, 12: 8}
    ifd_off = 8
    n = len(entries)
    extra_off = ifd_off + 2 + 12 * n + 4
    extra = b""
    body = b""
    offsets = {}
    for tag, typ, vals in entries:
        nb = size[typ] * len(vals)
        if nb > 4:
            offsets[tag] = extra_off + len(extra)
            extra += struct.pack("<" + fmt[typ] * len(vals), *vals)
    data_off = extra_off + len(extra)
    for tag, typ, vals in entries:
        if tag == 273:
            vals = [data_off]
        nb = size[typ] * len(vals)
        if nb > 4:
            val = struct.pack("<I", offsets[tag])
        else:
            val = struct.pack("<" + fmt[typ] * len(vals), *vals).ljust(4, b"\0")
        body += struct.pack("<HHI", tag, typ, len(vals)) + val
    with open(path, "wb") as f:
        f.write(b"II" + struct.pack("<HI", 42, ifd_off) + struct.pack("<H", n) + body + b"\0\0\0\0" + extra + data)


def hill_dem(tmp_path, peak=120.0, level=0.0):
    """A DEM around ORIGIN: a round hill of `peak` m centred 2500 m north, at `level` m elsewhere."""
    d = 1.0 / 3600.0
    lon0, lat0 = 12.9, 45.1
    n = int(0.2 / d) + 1
    lon = lon0 + np.arange(n) * d
    lat = lat0 - np.arange(n) * d
    LON, LAT = np.meshgrid(lon, lat)
    e, nn = lonlat_to_enu(LON, LAT, ORIGIN)
    r = np.hypot(e, nn - 2500.0)
    a = level + np.where(r < 700.0, peak * np.cos(np.clip(r / 700.0, 0, 1) * math.pi / 2) ** 2 + 3.0, 0.0)
    path = tmp_path / "dem.tif"
    write_geotiff(str(path), np.round(a), lon0, lat0, d)
    return path


@pytest.fixture
def tsrc(src, tmp_path):
    s = copy.deepcopy(src)
    s["coastline"][0]["polygons"][0]["points"] = circle(0, 2500, 400, n=96)
    s["terrain"] = {"dem": [str(hill_dem(tmp_path))], "source": "test hill", "margin": 2000.0, "ridge": 6000.0}
    return s


def test_geotiff_reader_and_inverse_projection(tmp_path):
    a = np.arange(12, dtype=np.int16).reshape(3, 4) - 5
    p = tmp_path / "t.tif"
    write_geotiff(str(p), a, 13.0, 45.0, 0.001)
    arr, lon0, lat0, dlon, dlat = read_geotiff(str(p))
    assert np.array_equal(arr, a.astype(float)) and (lon0, lat0, dlon, dlat) == (13.0, 45.0, 0.001, 0.001)
    dem = Dem([str(p)])
    assert dem.sample(np.array([13.0015]), np.array([44.999]))[0] == pytest.approx(0.5 * (a[1, 1] + a[1, 2]))
    assert np.isnan(dem.sample(np.array([14.0]), np.array([45.0]))[0])
    x, y = np.array([0.0, 3000.0, -6000.0]), np.array([0.0, -4000.0, 7000.0])
    lon, lat = enu_to_lonlat(x, y, ORIGIN)
    e, n = lonlat_to_enu(lon, lat, ORIGIN)
    assert np.allclose(e, x, atol=1e-3) and np.allclose(n, y, atol=1e-3)


def test_wind_heights_from_the_dem(tsrc):
    """The wake behind the hill follows the DEM's height, not the polygon's: a low polygon height with a high
    hill shelters more than the low polygon alone, and at most like a uniformly high one."""
    low = copy.deepcopy(tsrc)
    low["coastline"][0]["polygons"][0]["height"] = 5
    flat = copy.deepcopy(low)
    del flat["terrain"]
    high = copy.deepcopy(flat)
    high["coastline"][0]["polygons"][0]["height"] = 120
    f = {}
    for k, s in (("dem", low), ("flat", flat), ("high", high)):
        doc, notes = build(s)
        w = doc["wind_field"]
        g = w["grid"]
        a = np.array(w["sectors"][0]["f"]).reshape(g["ny"], g["nx"])
        i, j = int(round((0 - g["x0"]) / g["dx"])), int(round((1500 - g["y0"]) / g["dy"]))
        f[k] = a[j, i]
    assert f["high"] - 0.01 <= f["dem"] < f["flat"] - 0.02


def _mesh(doc, blob, c):
    raw = gzip.decompress(blob[c["offset"]:c["offset"] + c["bytes"]])
    assert len(raw) == c["raw_bytes"]
    n, m = c["vertices"], c["triangles"]
    pos = np.frombuffer(raw[:12 * n], "<f4").reshape(n, 3).astype(float)
    nrm = np.frombuffer(raw[12 * n:24 * n], "<f4").reshape(n, 3)
    shore = np.frombuffer(raw[24 * n:28 * n], "<f4")
    idx = np.frombuffer(raw[28 * n:28 * n + 12 * m], "<i4").reshape(m, 3)
    return pos, nrm, shore, idx


def _mesh_height(pos, idx, pts):
    """Height of the mesh at points (NaN where no triangle covers them)."""
    out = np.full(len(pts), np.nan)
    A, B, C = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
    lo = np.minimum(np.minimum(A, B), C)
    hi = np.maximum(np.maximum(A, B), C)
    for k, (x, y) in enumerate(pts):
        cand = np.flatnonzero((lo[:, 0] <= x) & (hi[:, 0] >= x) & (lo[:, 1] <= y) & (hi[:, 1] >= y))
        for t in cand:
            a, b, c = A[t], B[t], C[t]
            den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(den) < 1e-9:
                continue
            l1 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / den
            l2 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / den
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -1e-6:
                out[k] = l1 * a[2] + l2 * b[2] + l3 * c[2]
                break
    return out


def test_drawn_terrain(tsrc):
    out = []
    doc, notes = build(tsrc, out)
    assert len(out) == 1
    t, blob = out[0]
    assert t["schema"] == "windmark.terrain/1" and t["id"] == "test_bay"
    chunks = t["chunks"]
    assert 1 <= len(chunks) <= CAPS["chunks"]
    ridge = t["ridge"] or {"triangles": 0}
    assert sum(c["triangles"] for c in chunks) + ridge["triangles"] <= CAPS["triangles"]
    assert ridge["triangles"] <= CAPS["ridge_triangles"]
    assert all(c["shadows"] == c["id"].startswith("near") for c in chunks)
    # the waterline follows the core's land polygon: 5 m inside it the mesh is above the water, 5 m off below
    land = [{"points": np.array(l["points"], float)} for l in doc["land"]]
    p = land[0]["points"]
    q = np.roll(p, -1, 0)
    mid = 0.5 * (p + q)
    e = q - p
    out_n = np.stack([e[:, 1], -e[:, 0]], 1) / np.hypot(e[:, 0], e[:, 1])[:, None]
    pos, nrm, shore, idx = zip(*[_mesh(t, blob, c) for c in chunks])
    allpos = np.concatenate(pos)
    offs = np.cumsum([0] + [len(x) for x in pos[:-1]])
    allidx = np.concatenate([i + o for i, o in zip(idx, offs)])
    hin = _mesh_height(allpos, allidx, mid - 5 * out_n)
    hout = _mesh_height(allpos, allidx, mid + 5 * out_n)
    assert np.all(hin > 0.0), hin.min()
    assert np.all((hout < 0.0) | np.isnan(hout)), np.nanmax(hout)
    # the hill is drawn: near the DEM's peak in the middle of the island
    top = _mesh_height(allpos, allidx, np.array([[0.0, 2500.0]]))[0]
    assert top == pytest.approx(123.0, abs=6.0)
    # normals point up and are unit length
    nn = np.concatenate(nrm)
    assert np.all(nn[:, 2] > 0.0) and np.allclose(np.linalg.norm(nn, axis=1), 1.0, atol=1e-3)
    # ground grid: open water far from the island, land on it
    g = t["ground"]
    a = np.frombuffer(gzip.decompress(blob[g["offset"]:g["offset"] + g["bytes"]]), "<i2").reshape(
        g["grid"]["ny"], g["grid"]["nx"]) * g["scale"]
    gr = g["grid"]
    i, j = int((0 - gr["x0"]) / gr["dx"]), int((2500 - gr["y0"]) / gr["dy"])
    assert a[j, i] > 100.0
    i, j = int((0 - gr["x0"]) / gr["dx"]), int((-1500 - gr["y0"]) / gr["dy"])
    assert a[j, i] < -7.0
    # deterministic, and the source note names the terrain
    out2 = []
    build(copy.deepcopy(tsrc), out2)
    assert dumps(out2[0][0]) == dumps(t) and out2[0][1] == blob
    assert "terrain: test hill" in doc["source"]
    assert validate(json.loads(dumps(doc))) == []


def test_terrain_needs_its_dem(tsrc):
    from windmark_venuegen.build import SourceError
    tsrc["terrain"]["dem"] = ["missing.tif"]
    with pytest.raises(SourceError):
        build(tsrc)


def test_big_land_is_split(src):
    """A big land polygon is cut into tiles of at most `split` m; the pieces cover the same land."""
    big = [[-3000.0, 1000.0], [3000.0, 1000.0], [3000.0, 4000.0], [800.0, 4000.0], [0.0, 1600.0],
           [-800.0, 4000.0], [-3000.0, 4000.0]]
    src["coastline"] = [{"source": "t", "frame": "local", "role": "land",
                         "polygons": [{"id": "shore", "height": 30, "points": big}]}]
    doc, notes = build(src)
    pieces = doc["land"]
    assert len(pieces) > 4 and len({l["id"] for l in pieces}) == len(pieces)
    for l in pieces:
        p = np.array(l["points"])
        assert p[:, 0].max() - p[:, 0].min() <= 1000.0 + 1e-6 and p[:, 1].max() - p[:, 1].min() <= 1000.0 + 1e-6
        assert signed_area(p) > 0
    # same land: points in the union are in the original
    rng = np.random.default_rng(3)
    x = rng.uniform(-2900, 2900, 400)
    y = rng.uniform(900, 3000, 400)
    a = points_in_land(x, y, [{"points": np.array(l["points"], float)} for l in pieces])
    b = points_in_land(x, y, [{"points": np.array(big, float)}])
    assert np.array_equal(a, b)
    assert validate(json.loads(dumps(doc))) == []


def test_prep_tools():
    lon, lat = utm_to_lonlat(np.array([500000.0]), np.array([5000000.0]), 32)
    assert lon[0] == pytest.approx(9.0, abs=1e-9) and lat[0] == pytest.approx(45.15348, abs=1e-5)
    m = np.zeros((6, 7), bool)
    m[1:5, 1:6] = True
    m[2:4, 3] = False  # a hole
    rings = _trace(m)
    areas = sorted(abs(signed_area(r)) for r in rings)
    assert areas == [2.0, 20.0]

    def poly(rings):
        return {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {
            "type": "Polygon", "coordinates": rings}}]}
    north = poly([[[0, 0], [2, 0], [2, 3], [0, 3], [0, 0]]])
    south = poly([[[0.1, -3], [1.9, -3], [1.9, 1], [0.1, 1], [0.1, -3]]])
    out = splice(north, south, 0.5)
    r = np.array(out["features"][0]["geometry"]["coordinates"][0])
    assert signed_area(r) == pytest.approx(2.0 * 2.5 + 1.8 * 3.5, abs=1e-6)
