import copy
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


def test_trim_tables_zero_on_the_wind_line(generated):
    """sails.md 6: with the driving sail on the wind line (eps = AWA - m_opt) trim_speed and trim_heel are 0, on the
    grid and in between (both brackets of the lookup are 0)."""
    _, p = generated
    for c in p["configs"]:
        drive = c["front_sail"] or "main"
        o = c["optimal_angle"][drive]
        tws = np.array(o["axes"][0]["points"])
        awa = np.array(o["axes"][1]["points"])
        opt = np.array(o["values"]).reshape(len(tws), len(awa))
        eps = np.array(c["trim_speed"]["axes"][2]["points"])
        for name in ("trim_speed", "trim_heel"):
            t = np.array(c[name]["values"]).reshape(len(tws), len(awa), len(eps))
            for i in range(len(tws)):
                for j in range(len(awa)):
                    w = awa[j] - opt[i, j]
                    if w < 0.5 * DEG:
                        continue
                    k = int(np.searchsorted(eps, w, side="right")) - 1
                    assert np.all(t[i, j, k:] == 0.0), (c["front_sail"], name, i, j)


def test_tack_dynamics(generated):
    """boat.md 4, 5.8, 5.9: coasting deceleration, the stalled-rudder radius law and the fall_off table."""
    b, p = generated
    d = p["dynamics"]
    r_full, off = d["turn_radius_full"], d["turn_radius_offset"]
    assert -r_full < off <= 0.0                                # turn_c > 0; a rudder that stalls short of full helm
    r_half = (r_full + off) / 0.5 - off
    assert 1.2 * r_full <= r_half <= 2.0 * r_full
    # coasting from the close-hauled speed: slower than the old tangent law, faster than no drag at all
    assert 0.01 < d["decel_linear"] < 0.1
    # a slammed turn bleeds more speed per second than a half-helm one
    v, hh, rd = _t2(d["rudder_drag_luff"])
    i3 = int(np.argmin(abs(v - 3.0)))
    assert np.interp(1.0, hh, rd[i3]) > 2.5 * np.interp(0.5, hh, rd[i3])
    for c in p["configs"]:
        sp, twa, f = _t2(c["fall_off"])
        assert np.all(f >= 0)
        assert np.all(f[:, twa <= 10 * DEG + 1e-9] == 0)      # right head to wind: stays in irons
        k0 = int(np.argmin(abs(sp)))
        j45 = int(np.argmin(abs(twa - 45 * DEG)))
        assert 2 * DEG < f[k0, j45] < 8 * DEG                 # stopped, bow off the wind: falls off
        assert np.all(f[-1] == 0) and sp[-1] < 1.0            # the keel holds the heading once under way


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


def test_no_zero_speed_above_the_no_go_zone(generated):
    _, p = generated
    for c in p["configs"]:
        tws, twa, V = _t2(c["polar"])
        k = int(np.flatnonzero(np.diff(twa) == 0)[0])          # the no-go step
        assert np.all(V[1:, k + 1:] > 0), c["front_sail"]


def test_gale_spinnaker_reach_broaches(generated):
    """a2 at 90 deg TWA in 40 kn: no depowering holds the heel, so the boat wallows at a low broached speed at the
    heel limit instead of stopping."""
    _, p = generated
    c = next(c for c in p["configs"] if c["front_sail"] == "a2")
    tws, twa, V = _t2(c["polar"])
    _, _, H = _t2(c["heel"])
    _, btwa, B = _t2(c["vpp"]["broached"])
    j = int(np.argmin(abs(twa - 90 * DEG)))
    jb = int(np.argmin(abs(btwa - 90 * DEG)))
    assert B[-1, jb] == 1.0 and B[3, jb] == 0.0                # broached in 40 kn, sailing in 8 kn
    sailing = V[1:-1, j][B[:-1, jb] == 0]
    assert 0.1 <= V[-1, j] <= 0.5 * sailing.max()
    assert H[-1, j] == pytest.approx(H.max(), abs=1e-6)      # lying at the heel limit
    _, _, A = _t2(c["accel"])
    assert A[-1, j] > 0.005


FEEL = ("accel", "decel", "turn_rate", "heel", "tack_time")


def test_default_handling_leaves_tables_unchanged(generated, raw):
    b, p = generated
    assert p["handling"] == {k: 1.0 for k in FEEL}
    q = copy.deepcopy(p)
    perf.apply_handling(q, {k: 1.0 for k in FEEL})
    assert q == p
    raw["handling"] = {k: 1.0 for k in FEEL}
    p1 = perf.generate(boatclass.from_dict(raw))
    for key in ("dynamics", "sails", "configs", "start", "handling"):
        assert p1[key] == p[key], key


def test_handling_multipliers_scale_feel_only(generated):
    _, p = generated
    feel = {"accel": 2.0, "decel": 0.5, "turn_rate": 1.25, "heel": 1.2, "tack_time": 1.5}
    q = copy.deepcopy(p)
    perf.apply_handling(q, feel)
    perf.validate(q)
    d0, d1 = p["dynamics"], q["dynamics"]
    for c0, c1 in zip(p["configs"], q["configs"]):
        assert c1["polar"] == c0["polar"]                      # never the speed
        assert c1["trim_speed"] == c0["trim_speed"]
        assert np.allclose(c1["accel"]["values"], 2.0 * np.array(c0["accel"]["values"]))
        assert np.allclose(c1["heel"]["values"], np.minimum(1.2 * np.array(c0["heel"]["values"]), math.pi / 2))
    assert d1["decel_linear"] == pytest.approx(0.5 * d0["decel_linear"])
    assert d1["decel_const"] == pytest.approx(0.5 * d0["decel_const"])
    radius = lambda d, h: (d["turn_radius_full"] + d["turn_radius_offset"]) / h - d["turn_radius_offset"]
    for h in (0.2, 0.5, 1.0):                                  # boat.md 5.9: yaw rate v / R at every helm
        assert radius(d0, h) / radius(d1, h) == pytest.approx(1.25)
    # the speed factor at the scaled heel is the old one at the physical heel
    ph = np.array(d0["heel_speed_factor"]["axes"][0]["points"])
    f0 = lambda x: np.interp(x, ph, d0["heel_speed_factor"]["values"])
    f1 = lambda x: np.interp(x, ph, d1["heel_speed_factor"]["values"])
    x = np.radians([20, 35, 45, 60])
    assert np.allclose(f1(1.2 * x), f0(x), atol=0.03)
    assert d1["heel_max"] <= d1["heel_limit"]
    assert d1["helm_rate"] == pytest.approx(d0["helm_rate"] / 1.5)
    for sid, s in p["sails"].items():
        assert q["sails"][sid]["rate_in"] == pytest.approx(s["rate_in"] / 1.5)
        assert q["sails"][sid]["rate_out"] == pytest.approx(s["rate_out"] / 1.5)


def test_handling_block_parsing(raw):
    raw["handling"] = {"accel": 1.3, "heel_limit": 1.3}
    b = boatclass.from_dict(raw)
    assert b.feel == {"accel": 1.3, "decel": 1.0, "turn_rate": 1.0, "heel": 1.0, "tack_time": 1.0}
    assert b.handling == {"heel_limit": 1.3}
    raw["handling"] = {"turn_rate": 0.0}
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)
    raw["handling"] = {"tack_time": 9.0}
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)
