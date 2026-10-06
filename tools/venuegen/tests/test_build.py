import copy
import json
import math
import os

import numpy as np
import pytest

from conftest import REPO, circle
from windmark_venuegen.build import SourceError, build, build_file, dumps, make_grid
from windmark_venuegen.fields import grid_nodes
from windmark_venuegen.raster import points_in_land
from windmark_venuegen.validate import CAPS, validate


def sample(g, v, x, y, default):
    """The core's grid sampler (wind.md §8.1)."""
    if x < g["x0"] or y < g["y0"] or x > g["x0"] + (g["nx"] - 1) * g["dx"] or y > g["y0"] + (g["ny"] - 1) * g["dy"]:
        return default
    u, w = (x - g["x0"]) / g["dx"], (y - g["y0"]) / g["dy"]
    i, j = min(int(u), g["nx"] - 2), min(int(w), g["ny"] - 2)
    tu, tw = u - i, w - j
    a = np.array(v, float).reshape(g["ny"], g["nx"])
    r0 = a[j, i] * (1 - tu) + a[j, i + 1] * tu
    r1 = a[j + 1, i] * (1 - tu) + a[j + 1, i + 1] * tu
    return r0 * (1 - tw) + r1 * tw


def wind_f(doc, sector, x, y):
    w = doc["wind_field"]
    return sample(w["grid"], w["sectors"][sector]["f"], x, y, 1.0)


def test_deterministic(src):
    a = dumps(build(copy.deepcopy(src))[0])
    b = dumps(build(copy.deepcopy(src))[0])
    assert a == b


def test_output_validates_and_borders(src):
    doc, _ = build(src)
    assert validate(json.loads(dumps(doc))) == []
    g = doc["wind_field"]["grid"]
    for s in doc["wind_field"]["sectors"]:
        f = np.array(s["f"]).reshape(g["ny"], g["nx"])
        d = np.array(s["d"]).reshape(g["ny"], g["nx"])
        for edge in (f[0], f[-1], f[:, 0], f[:, -1]):
            assert np.all(edge == 1.0)
        for edge in (d[0], d[-1], d[:, 0], d[:, -1]):
            assert np.all(edge == 0.0)
        assert np.all(np.isfinite(f)) and np.all(f >= 0) and np.all(np.abs(d) <= math.pi)


def test_land_shadow(src):
    """Wind from the north: the island (north of the area) shelters the water south of it, more near it; the
    windward side and the far side are open; from the south the shadow is on the other side."""
    doc, _ = build(src)
    lee_near = wind_f(doc, 0, 0, 1800)     # 300 m south of the island
    lee_far = wind_f(doc, 0, 0, -1500)
    windward = wind_f(doc, 0, 0, 3400)
    side = wind_f(doc, 0, 1500, 1800)
    assert lee_near < 0.85
    assert lee_near < lee_far < 1.0
    assert lee_far > 0.97
    assert windward > lee_near + 0.1
    assert abs(side - 1.0) < 0.03
    assert wind_f(doc, 4, 0, 1800) > 0.9        # from the south: 0, 1800 is upwind of the island
    # the wind bends around the island on its upwind side: west of the island it veers (+), east backs (-)
    w = doc["wind_field"]
    d_w = sample(w["grid"], w["sectors"][0]["d"], -500, 2700, 0.0)
    d_e = sample(w["grid"], w["sectors"][0]["d"], 500, 2700, 0.0)
    assert d_w > 0.01 and d_e < -0.01


def test_offshore_wind_recovers_away_from_the_shore(src):
    src["coastline"] = [{"frame": "local", "role": "shore_left", "polygons": []}]
    src["coastline"] = [{"frame": "local", "role": "land", "height": 100,
                         "polygons": [{"points": [[-9000, 1000], [9000, 1000], [9000, 9000], [-9000, 9000]]}]}]
    doc, _ = build(src)
    fs = [wind_f(doc, 0, 0, y) for y in (900, 500, 0, -1000, -2000)]  # wind from the north, off the land
    assert all(a < b for a, b in zip(fs, fs[1:]))
    assert fs[0] < 0.7


def test_caps_on_a_big_venue(src):
    src["bounds"] = [-8000, -8000, 8000, 8000]
    src["grids"] = {"wind": 50, "current": 50, "exposure": 50}
    # a long wiggly coast (many vertices): the written land stays within the vertex caps
    xs = np.linspace(-12000, 12000, 6000)
    ys = 3000 + 200 * np.sin(xs / 37.0) + 80 * np.sin(xs / 7.3)
    coast = [[float(x), float(y)] for x, y in zip(xs, ys)] + [[12000, 12000], [-12000, 12000]]
    src["coastline"] = [{"frame": "local", "role": "land", "polygons": [{"points": coast}]}]
    src["current"] = {"to": 1.0, "speed": 1.0}
    doc, notes = build(src)
    assert validate(json.loads(dumps(doc))) == []
    total = sum(len(p["points"]) for p in doc["land"])
    assert total <= CAPS["land_vertices_total"]
    assert max(len(p["points"]) for p in doc["land"]) <= CAPS["land_vertices_polygon"]
    assert doc["wind_field"]["grid"]["nx"] <= 96 and doc["wind_field"]["grid"]["dx"] >= 50
    assert doc["current_field"]["grid"]["nx"] <= 128 and doc["exposure"]["grid"]["ny"] <= 128
    assert len(dumps(doc).encode()) <= CAPS["file_bytes"]


def test_make_grid_caps():
    g = make_grid((-9000, -9000, 9000, 9000), 50, 96)
    assert g["nx"] <= 96 and g["dx"] >= 50 and g["dx"] % 10 == 0
    assert g["x0"] + (g["nx"] - 1) * g["dx"] >= 9000
    g = make_grid((-3000, -3000, 3000, 3000), 10, 128)
    assert g["dx"] == 50 and g["nx"] == 121


def test_current_field(src):
    src["current"] = {"to": math.pi / 2, "speed": 1.0}
    doc, _ = build(src)
    cf = doc["current_field"]
    g = cf["grid"]
    x, y = grid_nodes(g)
    vx, vy = np.array(cf["vx"]), np.array(cf["vy"])
    land = points_in_land(x, y, [{"points": np.array(p["points"])} for p in doc["land"]])
    assert np.all(vx[land] == 0) and np.all(vy[land] == 0)
    sp = np.hypot(vx, vy)
    far = np.hypot(x - 0, y - 2500) > 2500
    assert np.allclose(sp[far], 1.0, atol=0.02)
    near = ~land & (np.hypot(x, y - 2500) < 600)
    assert sp[near].max() < 0.9
    # ref_speed: the 90th percentile over water nodes inside bounds, recomputed here
    b = doc["bounds"]
    inside = (x >= b[0]) & (x <= b[2]) & (y >= b[1]) & (y <= b[3]) & ~land
    assert abs(cf["ref_speed"] - np.percentile(sp[inside], 90)) < 1e-3
    # banks slow the stream
    src2 = copy.deepcopy(src)
    src2["current"]["banks"] = [{"id": "bank", "points": [[-500, -500], [500, -500], [500, 500], [-500, 500]],
                                 "factor": 0.4}]
    doc2, _ = build(src2)
    c2 = doc2["current_field"]
    assert sample(g, c2["vx"], 0, 0, 0) < 0.5 < sample(g, cf["vx"], 0, 0, 0)


def test_exposure(src):
    src["exposure"] = {"from": 0.0}
    doc, _ = build(src)
    e = doc["exposure"]
    assert sample(e["grid"], e["e"], 0, 2500, 1) == 0.0                       # on land
    lee = sample(e["grid"], e["e"], 0, 1800, 1)
    windward = sample(e["grid"], e["e"], 0, 3300, 1)
    assert lee < 0.6 and windward > 0.9
    assert sample(e["grid"], e["e"], 0, -2500, 1) > 0.9


def test_conditions_and_briefing_copied_and_checked(src):
    src["conditions"] = {"wind": {"speed": [5.14, 7.2], "from": 0.0, "from_spread": 0.0},
                         "shift": {"preset": "stable"}, "puffs": {"preset": "light"},
                         "current": {"speed": 0.15, "to": 1.5708}}
    src["briefing"] = {"tag": "Practice", "tip": "Learn the boat."}
    doc, _ = build(copy.deepcopy(src))
    assert doc["conditions"] == src["conditions"] and doc["briefing"] == src["briefing"]
    bad = copy.deepcopy(src)
    bad["briefing"]["tip"] = "Learn the boat — then race."
    with pytest.raises(SourceError):
        build(bad)
    bad = copy.deepcopy(src)
    bad["conditions"]["tide"] = {"scale": 0.6, "period": 44712, "turn": [0.35, 0.65], "turn_to": -1}
    with pytest.raises(SourceError):  # a tide needs a current field
        build(bad)
    bad = copy.deepcopy(src)
    bad["conditions"]["wind"]["from_spread"] = 0.5
    with pytest.raises(SourceError):
        build(bad)


def test_validation_catches_bad_files(src):
    doc, _ = build(src)
    good = json.loads(dumps(doc))
    assert validate(good) == []

    def broken(edit):
        d = copy.deepcopy(good)
        edit(d)
        return validate(d)

    assert any("border" in p for p in broken(lambda d: d["wind_field"]["sectors"][3]["f"].__setitem__(0, 0.9)))
    assert any("counter-clockwise" in p for p in broken(lambda d: d["land"][0]["points"].reverse()))
    assert any("simple" in p or "intersect" in p for p in broken(
        lambda d: d["land"][0]["points"].insert(2, d["land"][0]["points"][len(d["land"][0]["points"]) // 2])))
    assert any("exposure" in p for p in broken(lambda d: d["exposure"]["e"].__setitem__(5, 1.5)))
    assert any("values" in p for p in broken(lambda d: d["exposure"]["grid"].__setitem__("ny", 3)))
    assert any("em dash" in p for p in broken(lambda d: d.__setitem__("name", "Bay — north")))
    assert any("tag" in p for p in broken(lambda d: d.__setitem__("briefing", {"tag": "x" * 30})))
    assert any("convex" in p for p in broken(lambda d: d.__setitem__(
        "obstacles", [{"id": "o", "polygon": [[0, 0], [0, 10], [10, 10], [10, 0]]}])))


def test_unknown_source_keys_are_refused(src):
    src["wind"] = {"shadow_maxx": 0.3}
    with pytest.raises(SourceError):
        build(src)


def test_shipped_venues_are_generated():
    """Every committed venue file with a source is exactly venuegen's output from it (no hand edits)."""
    srcdir = os.path.join(REPO, "data", "venue_sources")
    sources = sorted(f for f in os.listdir(srcdir) if f.endswith(".venuesrc.json"))
    assert "example_bay.venuesrc.json" in sources
    for name in sources:
        with open(os.path.join(srcdir, name)) as f:
            vid = json.load(f)["id"]
        _, text, _ = build_file(os.path.join(srcdir, name))
        with open(os.path.join(REPO, "data", "venues", f"{vid}.venue.json")) as f:
            same = f.read() == text
        assert same, f"{vid}.venue.json differs from venuegen's output (regenerate it, never hand-edit)"
