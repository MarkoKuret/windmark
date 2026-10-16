import math

import numpy as np
import pytest

from windmark_vpp import boatclass, geometry, hydro
from windmark_vpp.constants import G, RHO_WATER


def _model(raw, **kw):
    b = boatclass.from_dict(raw)
    return b, hydro.build(b, geometry.hydrostatics(b), **kw)


def test_dsyhs_parent_like_hull():
    # a hull in the middle of the series: residuary resistance per weight grows steeply through Fn 0.35-0.5
    p = {"LCBfpp/LWL": 0.53, "Cp": 0.56, "V^(2/3)/Aw": 0.16, "BWL/LWL": 0.30, "LCBfpp/LCFfpp": 0.97, "BWL/Tc": 6.0,
         "Cm": 0.72, "V^(1/3)/LWL": 0.17}
    c = hydro.dsyhs_coefficient(p)
    fn = hydro.DSYHS_FN
    at = lambda f: c[np.argmin(abs(fn - f))]
    assert 0.0 <= at(0.25) < 0.004
    assert 0.004 < at(0.40) < 0.04
    assert at(0.50) > 2 * at(0.40)


def test_resistance_monotone_and_components(raw):
    b, m = _model(raw)
    V = np.linspace(0.3, 4.5, 40)             # below the hump (Fn 0.45); beyond it a light hull may unload
    R = m.resistance(V, 0 * V, 0 * V)
    assert np.all(np.diff(R) > 0)
    assert m.resistance(np.array([9.0]), np.zeros(1), np.zeros(1))[0] > R[-1]
    # friction dominates at low speed, waves near hull speed
    _, p = m.resistance(np.array([1.0, 4.2]), np.zeros(2), np.zeros(2), parts=True)
    assert p["friction"][0] > p["residuary"][0]
    assert p["residuary"][1] > p["friction"][1]


def test_induced_drag(raw):
    b, m = _model(raw)
    V = np.array([3.0])
    te = m.effective_draft(V, np.zeros(1))
    assert 0.5 * b.draft_total <= te[0] <= 1.3 * b.draft_total
    q = 0.5 * RHO_WATER * 9.0
    fh = 2000.0
    assert m.induced(V, np.zeros(1), np.array([fh]))[0] == pytest.approx(fh ** 2 / (math.pi * te[0] ** 2 * q),
                                                                         rel=1e-6)


def test_heel_increases_resistance(raw):
    b, m = _model(raw)
    V = np.full(3, 3.5)
    R = m.resistance(V, np.radians([0, 20, 50]), np.zeros(3))
    assert R[2] > R[0]


class _Wigley:
    class body:
        lwl, bwl, draft, transom_wl = 1.0, 0.1, 0.0625, 0.0

    def half_breadth(self, xi, z):
        y = 0.05 * (1 - (2 * np.asarray(xi) - 1) ** 2) * (1 - (np.minimum(z, 0) / 0.0625) ** 2)
        return np.where(np.asarray(z) >= -0.0625, np.maximum(y, 0), 0)


def test_michell_wigley():
    """Michell's integral for the Wigley hull: main hump near Fn 0.5, Cw of a few 1e-3, decaying at high Fn."""
    fns = np.array([0.3, 0.5, 1.0])
    U = fns * math.sqrt(G)
    rw = hydro.michell_rw(_Wigley(), U)
    cw = rw / (0.5 * RHO_WATER * U * U * 0.148)
    assert 1e-3 < cw[1] < 8e-3
    assert cw[1] > cw[0] and cw[1] > cw[2]


def test_thin_ship_agrees_with_dsyhs_in_magnitude(raw):
    b, m = _model(raw)
    _, t = _model(raw, thin_ship=True)
    V = np.array([3.6, 4.1])      # Fn 0.35, 0.40
    a = m.upright_residuary(V)
    r = np.array([hydro._interp2(*t.mh_tables[0], v, b.volume) for v in V])
    assert np.all(r / a > 0.4) and np.all(r / a < 2.5)


def test_planing_stretches_the_hump(raw):
    """A hull that can plane meets the same towed curve below HUMP_FN0 and a lower one through its hump."""
    b, m = _model(raw)
    fn, towed = hydro.residuary_curve(m.dsyhs_params, 1.0)
    for f in (0.2, 0.3):
        assert np.interp(f, m.rr_fn, m.rr_coef) == pytest.approx(np.interp(f, fn, towed), rel=0.05, abs=1e-4)
    for f in (0.5, 0.6):
        assert np.interp(f, m.rr_fn, m.rr_coef) < 0.9 * np.interp(f, fn, towed)


