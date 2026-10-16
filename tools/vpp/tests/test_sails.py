import numpy as np
import pytest

from windmark_vpp import sails
from windmark_vpp.boatclass import SHEET_LIMITS
from windmark_vpp.constants import DEG


@pytest.mark.parametrize("t,st", [("main", "main"), ("jib", "jib"), ("code0", "code_zero"),
                                  ("spinnaker", "spinnaker_sym"), ("gennaker", "spinnaker_asym")])
def test_envelope_follows_orc(t, st):
    """Best-trim drive and side coefficients stay close to the ORC per-sail envelopes over the sailing range."""
    lo, hi = SHEET_LIMITS[st]
    e = sails.envelope(t, lo, hi, [1.0])
    b, cl, cd = (np.array(v, float) for v in sails.ORC_REFERENCE[t])
    m = b >= (20 if t in ("main", "jib") else 40)
    bb = b[m] * DEG
    ecl, ecd, _ = e.at(np.zeros(m.sum(), int), bb)
    cx = cl[m] * np.sin(bb) - cd[m] * np.cos(bb)
    ex = ecl * np.sin(bb) - ecd * np.cos(bb)
    assert np.sqrt(np.mean((ex - cx) ** 2)) < 0.12
    assert np.max(np.abs(ex - cx)) < 0.3


def test_luff_and_stall():
    c = sails.COEFFS["jib"]
    cl, cd = sails.coefficients(c, np.array([0.0, 2 * DEG, c.alpha_stall, 90 * DEG]))
    assert cl[0] == 0 and cl[1] == 0                # luffing
    assert cl[2] == pytest.approx(c.cl_max)
    assert cd[3] > 0.4 and abs(cl[3]) < 0.1          # stalled plate across the wind


def test_flat_depowers():
    e = sails.envelope("main", 0, 74 * DEG, [0.5, 1.0])
    i = np.array([0, 1])
    cl, _, _ = e.at(i, np.full(2, 30 * DEG))
    assert cl[0] < cl[1]


def test_sheet_eases_with_awa():
    e = sails.envelope("main", 0, 74 * DEG, [1.0])
    _, _, d = e.at(np.zeros(4, int), np.radians([25, 45, 70, 100]))
    assert np.all(np.diff(d) > 0)
