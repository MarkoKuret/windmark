import pytest

from windmark_vpp import boatclass
from windmark_vpp.constants import RHO_WATER


def test_loads_and_derives(raw):
    b = boatclass.from_dict(raw)
    assert b.kind == "monohull"
    assert b.mass == pytest.approx(6600)
    main = b.bodies[0]
    # midship coefficient follows from displacement, draft, beam, length and Cp
    assert main.cm == pytest.approx(6600 / RHO_WATER / (0.55 * 10.5 * 3.0 * 0.45))
    assert [c[0] for c in b.configs()] == ["main", "jib", "a2"]
    assert b.bulb is not None and b.bulb.depth < 2.6
    assert b.vcg < 0  # a ballasted keelboat has its CG below the waterline


def test_errors(raw):
    raw["hull"]["cp"] = 0.9
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)


def test_unknown_sail(raw):
    raw["sails"].append({"type": "kite"})
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)


def test_section_shape_gives_draft(raw):
    del raw["hull"]["draft_canoe"]
    raw["hull"]["section_shape"] = 0.75
    b = boatclass.from_dict(raw)
    assert b.bodies[0].draft == pytest.approx(6600 / RHO_WATER / (0.55 * 10.5 * 3.0 * 0.75))
