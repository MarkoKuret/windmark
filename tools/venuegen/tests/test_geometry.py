import json
import math
import struct

import numpy as np
import pytest

from conftest import circle
from windmark_venuegen.clip import clip_to_box
from windmark_venuegen.geo import (InputError, line_paths, load_entry, lonlat_to_enu, polygon_paths,
                                   read_shapefile, signed_area)
from windmark_venuegen.simplify import douglas_peucker_ring, simple_problem, simplify_ring

BOX = (-1000.0, -1000.0, 1000.0, 1000.0)


def area(polys):
    return sum(signed_area(p["points"]) for p in polys)


def test_projection_scale():
    o = {"lat": 45.0, "lon": 13.0}
    e, n = lonlat_to_enu(np.array([13.0, 13.01]), np.array([45.01, 45.0]), o)
    assert abs(n[0] - 1111.4) < 2.0       # 0.01 deg of latitude at 45 N
    assert abs(e[1] - 787.6) < 2.0        # 0.01 deg of longitude at 45 N
    assert abs(e[0]) < 1.0 and abs(n[1]) < 5.0
    e0, n0 = lonlat_to_enu(np.array([13.0]), np.array([45.0]), o)
    assert abs(e0[0]) < 1e-6 and abs(n0[0]) < 1e-6


def test_clip_land_square_across_edge():
    sq = polygon_paths([[[500, -200], [1500, -200], [1500, 200], [500, 200]]], "land", 10)
    out = clip_to_box(sq, BOX)
    assert len(out) == 1
    assert abs(area(out) - 500 * 400) < 5.0
    assert simple_problem(out[0]["points"]) is None


def test_clip_lake_gives_the_land_around_it():
    # a lake crossing the south edge of the box: land is the box minus the lake
    lake = [[-300, -2000], [300, -2000], [300, 500], [-300, 500]]
    out = clip_to_box(polygon_paths([lake], "water", 10), BOX)
    assert abs(area(out) - (2000 * 2000 - 600 * 1500)) < 5.0
    for p in out:
        assert signed_area(p["points"]) > 0 and simple_problem(p["points"]) is None


def test_clip_lake_inside_the_box_is_split():
    lake = [[-300, -300], [300, -300], [300, 300], [-300, 300]]
    out = clip_to_box(polygon_paths([lake], "water", 10), BOX)
    assert len(out) >= 2
    assert abs(area(out) - (2000 * 2000 - 600 * 600)) < 5.0
    for p in out:
        assert simple_problem(p["points"]) is None


def test_clip_open_shore_line():
    # a straight shore along y = 200, land to the north (on the left when walking east)
    shore = line_paths([[[-3000, 200], [3000, 200]]], "left", 10)
    out = clip_to_box(shore, BOX)
    assert abs(area(out) - 2000 * 800) < 5.0
    with pytest.raises(InputError):
        clip_to_box(line_paths([[[0, 0], [-3000, 200]]], "left", 10), BOX)


def test_clip_island_and_mainland_together():
    paths = polygon_paths([circle(0, 0, 200)], "land", 10) + line_paths([[[-3000, 700], [3000, 700]]], "left", 30)
    out = clip_to_box(paths, BOX)
    assert len(out) == 2
    assert abs(area(out) - (signed_area(np.array(circle(0, 0, 200))) + 2000 * 300)) < 5.0


def test_simplification_tolerance_and_simplicity():
    p = np.array(circle(0, 0, 500, n=2000, wobble=0.004))
    q = simplify_ring(p, np.full(len(p), 5.0), np.zeros(len(p), bool))
    assert 20 < len(q) < 400
    assert simple_problem(q) is None and signed_area(q) > 0
    # every original vertex lies within the tolerance (plus the 0.05 m write rounding) of the simplified ring
    a, b = q, np.roll(q, -1, axis=0)
    d = b - a
    t = np.clip(((p[:, None, :] - a[None]) * d[None]).sum(-1) / (d * d).sum(-1)[None], 0, 1)
    dist = np.hypot(*(p[:, None, :] - (a[None] + t[..., None] * d[None])).transpose(2, 0, 1)).min(axis=1)
    assert dist.max() <= 5.0 + 0.1


def test_douglas_peucker_keeps_fixed_vertices():
    p = np.array([[0, 0], [50, 0.1], [100, 0], [100, 100], [0, 100]], float)
    fixed = np.array([False, True, False, False, False])
    assert 1 in douglas_peucker_ring(p, np.full(5, 5.0), fixed)
    assert 1 not in douglas_peucker_ring(p, np.full(5, 5.0), None)


def test_simple_problem_finds_crossings():
    assert simple_problem([[0, 0], [10, 10], [10, 0], [0, 10]]) == "edges intersect"
    assert simple_problem([[0, 0], [10, 0], [10, 10]]) is None
    assert simple_problem([[0, 0], [0, 0], [10, 10]]) == "two consecutive points are equal"


def _write_shp(path, rings):
    """A minimal polygon shapefile (one record): outer rings clockwise as the format wants."""
    pts = [pt for r in rings for pt in r]
    parts = np.cumsum([0] + [len(r) for r in rings[:-1]]).tolist()
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    bbox = (min(xs), min(ys), max(xs), max(ys))
    rec = struct.pack("<i4d2i", 5, *bbox, len(rings), len(pts)) + struct.pack(f"<{len(parts)}i", *parts)
    rec += b"".join(struct.pack("<2d", *p) for p in pts)
    body = struct.pack(">2i", 1, len(rec) // 2) + rec
    hdr = struct.pack(">7i", 9994, 0, 0, 0, 0, 0, (100 + len(body)) // 2) + struct.pack("<2i4d4d", 1000, 5, *bbox,
                                                                                         0, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(hdr + body)


def test_shapefile_and_geojson_read_the_same(tmp_path):
    o = {"lat": 45.0, "lon": 13.0}
    ring = [[13.0, 45.0], [13.0, 45.005], [13.006, 45.005], [13.006, 45.0], [13.0, 45.0]]  # clockwise
    _write_shp(tmp_path / "land.shp", [ring])
    (tmp_path / "land.geojson").write_text(json.dumps(
        {"type": "FeatureCollection", "features": [
            {"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [ring[::-1]]}}]}))
    box = (-5000, -5000, 5000, 5000)
    a = load_entry({"path": "land.shp", "frame": "lonlat", "role": "land"}, o, str(tmp_path), box)
    b = load_entry({"path": "land.geojson", "frame": "lonlat", "role": "land"}, o, str(tmp_path), box)
    assert len(a) == len(b) == 1
    assert abs(signed_area(a[0]["points"]) - signed_area(b[0]["points"])) < 1e-6
    assert signed_area(a[0]["points"]) > 0
    assert abs(signed_area(a[0]["points"]) - 472.6 * 555.7) < 0.01 * 472.6 * 555.7
    assert len(list(read_shapefile(str(tmp_path / "land.shp"), bbox=(20, 20, 21, 21)))) == 0
    (tmp_path / "land.prj").write_text('PROJCS["WGS 84 / UTM zone 33N"]')
    with pytest.raises(InputError):
        load_entry({"path": "land.shp", "frame": "lonlat", "role": "land"}, o, str(tmp_path), box)
