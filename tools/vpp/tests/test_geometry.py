import numpy as np
import pytest

from windmark_vpp import boatclass, geometry
from windmark_vpp.constants import G


def test_loft_matches_cp_and_volume(raw):
    b = boatclass.from_dict(raw)
    h = geometry.hydrostatics(b)
    up = h.upright
    assert up["cp"] == pytest.approx(0.55, abs=0.01)
    assert up["volume"] == pytest.approx(b.volume, rel=0.01)
    # upright: floats at the static waterline, no heeling arm
    assert abs(h.sinkage[0]) < 0.01
    assert abs(h.yb[0]) < 1e-6


def test_polygon_integrals_square():
    P = np.array([[[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]])
    A, My, Mz, girth = geometry._clip_integrals(P, np.array([0.0]))
    assert A[0] == pytest.approx(2.0)
    assert My[0] == pytest.approx(0.0, abs=1e-12)
    assert Mz[0] / A[0] == pytest.approx(-0.5)
    assert girth[0] == pytest.approx(4.0)


def test_righting_moment_shape(raw):
    b = boatclass.from_dict(raw)
    h = geometry.hydrostatics(b)
    rm = h.rm_boat
    # small-angle slope is the metacentric height; positive and a sensible size for a keelboat
    gm = rm[2] / (b.mass_boat * G * np.sin(h.heel[2]))
    assert 0.8 < gm < 3.0
    phi_max, _ = h.rm_max()
    assert np.radians(40) < phi_max < np.radians(90)
    # the crew adds righting moment upright and loses it as the boat heels
    assert h.rm_crew[0] > 0 and h.rm_crew[60] < h.rm_crew[0]


def test_trimaran_float_lifts(raw):
    raw["hull"].update({"type": "trimaran", "lwl": 16.0, "bwl": 1.6, "draft_canoe": 0.55, "displacement": 5500,
                        "cp": 0.58, "beam_max": 2.2, "transom_width": 0.6,
                        "floats": {"lwl": 15.0, "bwl": 1.0, "draft": 0.9, "cp": 0.6, "section_shape": 0.7,
                                   "spacing": 6.5, "clearance": 0.25, "freeboard": 1.1}})
    del raw["keel"]
    raw["boards"] = {"depth": 3.0, "chord": 0.6}
    b = boatclass.from_dict(raw)
    h = geometry.hydrostatics(b)
    vol = h.body_volume
    assert vol[0, 1] == 0 and vol[0, 2] == 0            # floats clear of the water at rest
    i = 12                                               # 12 deg
    assert vol[i, 2] > 0.5 * b.volume                   # leeward float carries most of the weight
    phi_max, rm_max = h.rm_max()
    assert phi_max < np.radians(25)
    assert rm_max > 0.8 * b.mass * G * 6.5 * 0.8
