import json
import math

import numpy as np
import pytest

from windmark_vpp import boatclass, perf
from windmark_vpp.constants import DEG, KNOT


def _t2(t):
    a0 = np.array(t["axes"][0]["points"])
    a1 = np.array(t["axes"][1]["points"])
    return a0, a1, np.array(t["values"]).reshape(len(a0), len(a1))


@pytest.fixture(scope="module")
def generated():
    from conftest import BASE
    b = boatclass.from_dict(json.loads(json.dumps(BASE)))
    return b, perf.generate(b)


def test_schema_and_validation(generated):
    b, p = generated
    perf.validate(p)
    assert p["schema"] == "windmark.perf/1"
    assert p["class_id"] == "test40" and p["class_version"] == 1 and len(p["class_sha256"]) == 64
    assert [c["front_sail"] for c in p["configs"]] == [None, "jib", "a2"]
    assert set(p["sails"]) == {"main", "jib", "a2"}
    assert "handling" in p["sails"]["jib"] and "handling" not in p["sails"]["main"]
    assert p["dynamics"]["collision"]["mass"] == pytest.approx(6600)


def test_polar_shape(generated):
    _, p = generated
    tws, twa, V = _t2(p["configs"][1]["polar"])
    assert np.all(V[0] == 0)                                   # no wind, no speed
    i = int(np.argmin(abs(tws - 10 * KNOT)))
    assert V[i, 0] < 0                                         # sternway head to wind
    k = int(np.flatnonzero(np.diff(twa) == 0)[0])              # the no-go step
    assert V[i, k] < 0 < V[i, k + 1]
    v = lambda a: np.interp(a * DEG, twa, V[i])
    assert 2.5 * KNOT < v(45) < 8 * KNOT
    assert v(90) > v(45) and v(90) > v(180)
    # more wind, more speed on a reach
    j = int(np.argmin(abs(tws - 16 * KNOT)))
    assert np.interp(100 * DEG, twa, V[j]) > np.interp(100 * DEG, twa, V[i])


def test_vmg_sensible(generated):
    _, p = generated
    for v in p["vpp"]["vmg"]:
        if 6 * KNOT < v["tws"] < 22 * KNOT:
            assert 34 * DEG < v["upwind"]["twa"] < 52 * DEG
            assert 130 * DEG < v["downwind"]["twa"] <= math.pi
            assert v["downwind"]["front_sail"] == "a2"


def test_trim_tables(generated):
    _, p = generated
    t = p["configs"][1]["trim_speed"]
    tws = np.array(t["axes"][0]["points"])
    awa = np.array(t["axes"][1]["points"])
    eps = np.array(t["axes"][2]["points"])
    ts = np.array(t["values"]).reshape(len(tws), len(awa), len(eps))
    th = np.array(p["configs"][1]["trim_heel"]["values"]).reshape(ts.shape)
    i = int(np.argmin(abs(tws - 10 * KNOT)))
    j = int(np.argmin(abs(awa - 45 * DEG)))
    k0 = int(np.argmin(abs(eps)))
    assert ts[i, j, k0] == pytest.approx(1.0)
    assert ts[i, j, -1] < 0.2                                  # eased to the wind line: no drive
    k20 = int(np.argmin(abs(eps + 20 * DEG)))
    assert 0.2 < ts[i, j, k20] < 1.0                           # over-sheeted 20 deg: stalled, some drive left
    assert ts[i, j, 0] <= ts[i, j, k20]                        # sheeted to the centreline: worse
    assert th[i, j, -1] < 0.5                                  # flogging sails heel less
    j90 = int(np.argmin(abs(awa - 90 * DEG)))
    assert th[i, j90, k20] > 1.0                               # stalled sails on a reach heel more
    o_tws, o_awa, opt = _t2(p["configs"][1]["optimal_angle"]["jib"])
    assert np.all(np.diff(opt[i]) >= -1e-6)                    # eased progressively as the wind goes aft


def test_dynamics_ranges(generated):
    _, p = generated
    d = p["dynamics"]
    assert 2.0 < d["turn_radius_full"] < 20.0
    assert 0 < d["decel_linear"] < 1.0 and 0 < d["decel_const"] < 0.3
    assert 0.5 < d["heel_freq"] < 4.0
    hsf = np.array(d["heel_speed_factor"]["values"])
    assert hsf[0] == 1.0 and np.all(np.diff(hsf) <= 0) and hsf[-1] < 0.9
    tws, h, rd = _t2(d["rudder_drag_luff"])
    assert np.all(rd[:, 0] <= rd[:, -1])                       # harder helm costs more
    out = np.array(d["collision"]["outline"])
    e = np.roll(out, -1, 0) - out
    cr = e[:, 0] * np.roll(e, -1, 0)[:, 1] - e[:, 1] * np.roll(e, -1, 0)[:, 0]
    assert np.all(cr > 0)                                      # strictly convex, counter-clockwise


def test_physics_sidecar_copied(raw):
    b = boatclass.from_dict(raw)
    g = perf.Generator(b, physics={"perf_inputs": {"hull_points": [[1.0, 0.0], [-1.0, 0.0]],
                                                   "collision": {"outline": [[1, 0], [0, 1], [-1, 0], [0, -1]]},
                                                   "wind_shadow": {"height": 99.0, "width_spinnaker": None}}})
    g.results = [g._solve(f, r) for f, r in g.rigs[:1]]
    d = g._dynamics()
    assert d["hull_points"] == [[1.0, 0.0], [-1.0, 0.0]]
    assert d["collision"]["outline"] == [[1, 0], [0, 1], [-1, 0], [0, -1]]
    assert d["wind_shadow"]["height"] == 99.0 and d["wind_shadow"]["width_spinnaker"] > 0


def test_table_validation_rejects_bad_axes():
    with pytest.raises(ValueError):
        perf.validate_table({"axes": [{"q": "tws", "points": [0, 1, 1, 1]}], "unit": "m/s", "values": [0] * 4}, "t")
    with pytest.raises(ValueError):
        perf.validate_table({"axes": [{"q": "tws", "points": [1, 0]}], "unit": "m/s", "values": [0, 0]}, "t")
