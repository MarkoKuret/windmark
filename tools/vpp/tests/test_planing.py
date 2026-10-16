"""Planing: gated on the displacement-length ratio, and continuous where it happens."""
import json
import math
import os

import numpy as np
import pytest

from windmark_vpp import boatclass, hydro, perf
from windmark_vpp.constants import DEG, G, KNOT

CLASSES = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "classes")


def _scan(cls, front, twa_deg, tws_kn):
    """Optimised speed (m/s) of one config on a fine TWS scan, -1 where no depowering holds the heel."""
    b = boatclass.load(cls if cls.endswith(".json") else os.path.join(CLASSES, cls + ".boat.json"))
    g = perf.Generator(b)
    rig = dict(g.rigs)[front]
    fi = np.repeat(np.arange(perf.NF), perf.NR)[None, None, :]
    rf = np.tile(perf.REEFS, perf.NF)[None, None, :]
    tws = np.asarray(tws_kn, float) * KNOT
    st = g.solver.solve(rig, fi, rf, tws[:, None, None], np.asarray(twa_deg, float)[None, :, None] * DEG)
    return b, tws, np.where(st.valid, st.V, -1.0).max(axis=-1)


def _max_slope(tws, V):
    ok = (V[1:] > 0) & (V[:-1] > 0)
    return float(np.max(np.where(ok, np.diff(V) / np.diff(tws), 0.0)))


def test_planing_ability_gate():
    assert hydro.planing_ability(80.0) == 1.0
    assert hydro.planing_ability(hydro.PLANING_DLR_NONE) == 0.0
    assert 0.0 < hydro.planing_ability(150.0) < 1.0
    # the conventional ratio: 1 long ton on a 10 ft waterline is 1000
    assert hydro.displacement_length_ratio(1016.047, 3.048) == pytest.approx(1000.0)


def test_froude_similar_classes_plane_alike():
    """wm7 (displacement-length ratio 82) and wm12 (108) have nearly the same hull in Froude terms: both get
    (nearly) the whole planing stretch, with no cliff between them."""
    for cls in ("wm7", "wm12"):
        b = boatclass.load(os.path.join(CLASSES, cls + ".boat.json"))
        assert hydro.planing_ability(hydro.displacement_length_ratio(b.mass_boat, b.lwl)) > 0.95


def test_hump_stretch():
    fn = np.array([0.2, hydro.HUMP_FN0, 0.55, 0.75])
    fe = hydro.hump_froude(fn)
    assert fe[0] == pytest.approx(0.2) and fe[1] == pytest.approx(hydro.HUMP_FN0)
    assert np.all(fe[2:] < fn[2:]) and np.all(np.diff(fe) > 0)


def _heavy(tmp_path, displacement, draft_canoe):
    with open(os.path.join(CLASSES, "wm12.boat.json")) as f:
        raw = json.load(f)
    raw["hull"]["displacement"] = displacement
    raw["hull"]["draft_canoe"] = draft_canoe
    raw["id"] = "heavy"
    p = tmp_path / "heavy.boat.json"
    p.write_text(json.dumps(raw))
    return str(p)


def test_heavy_hull_never_planes(tmp_path):
    """wm12 made a heavy cruiser (displacement-length ratio past PLANING_DLR_NONE): no speed jump reaching at 20
    to 34 kn, and it stays on its wave wall (well below planing speeds) at 30 kn."""
    path = _heavy(tmp_path, 9800, 0.65)
    b, tws, V = _scan(path, "jib", [110, 120, 130], np.arange(20.0, 34.01, 0.5))
    assert hydro.planing_ability(hydro.displacement_length_ratio(b.mass_boat, b.lwl)) == 0.0
    for j in range(V.shape[1]):
        assert _max_slope(tws, V[:, j]) < 1.2
    i30 = int(np.argmin(abs(tws - 30 * KNOT)))
    assert np.all(V[i30] < 0.8 * math.sqrt(G * b.lwl))


def test_keelboat_climbs_continuously():
    """wm12 planes like wm7, and like it takes off without a step: on a 0.5 kn scan at most 1.5 kn of boat speed
    per knot of wind under the kite (12 to 34 kn), 3 with the jib on a reach (20 to 34 kn)."""
    b, tws, V = _scan("wm12", "jib", [110, 120, 130], np.arange(20.0, 34.01, 0.5))
    for j in range(V.shape[1]):
        assert _max_slope(tws, V[:, j]) < 3.0
    b, tws, V = _scan("wm12", "a2", [140, 150], np.arange(12.0, 34.01, 0.5))
    for j in range(V.shape[1]):
        assert _max_slope(tws, V[:, j]) < 1.5


def test_sportsboat_takes_off_continuously():
    """wm7 still gets well over hull speed under the kite in a breeze, but its speed climbs with the wind without
    a step: on a 0.5 kn scan at most 1.5 kn of boat speed per knot of wind under the kite, 3 with the jib on a
    reach (a steep but smooth take-off)."""
    b, tws, V = _scan("wm7", "kite", [140, 150], np.arange(12.0, 30.01, 0.5))
    for j in range(V.shape[1]):
        assert _max_slope(tws, V[:, j]) < 1.5
    assert np.max(V[-1]) > 1.1 * math.sqrt(G * b.lwl)
    b, tws, V = _scan("wm7", "jib", [110, 120, 130], np.arange(12.0, 30.01, 0.5))
    for j in range(V.shape[1]):
        assert _max_slope(tws, V[:, j]) < 3.0
