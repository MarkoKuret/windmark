import pytest

from windmark_vpp import boatclass
from windmark_vpp.constants import RHO_WATER


def test_loads_and_derives(raw):
    b = boatclass.from_dict(raw)
    assert b.kind == "monohull"
    assert b.mass == pytest.approx(6600)
    main = b.bodies[0]
    # midship coefficient follows from displacement, draft, beam, length and Cp
    assert 0.1 < b.app_volume < 0.4          # fin, bulb and rudder displace a few percent
    assert main.cm == pytest.approx((6600 / RHO_WATER - b.app_volume) / (0.55 * 10.5 * 3.0 * 0.45))
    assert [c[0] for c in b.configs()] == [None, "jib", "a2"]
    assert b.bulb is not None and b.bulb.depth < 2.6
    assert b.vcg < 0  # a ballasted keelboat has its CG below the waterline


def test_errors(raw):
    raw["hull"]["prismatic"] = 0.9
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)


def test_unknown_sail(raw):
    raw["sails"].append({"type": "kite"})
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)


def test_section_shape_gives_draft(raw):
    del raw["hull"]["draft_canoe"]
    raw["hull"]["section_shape"]["midship_coefficient"] = 0.75
    b = boatclass.from_dict(raw)
    assert b.bodies[0].draft == pytest.approx((6600 / RHO_WATER - b.app_volume) / (0.55 * 10.5 * 3.0 * 0.75))


def test_defaults_shared_with_the_generator(raw):
    b = boatclass.from_dict(raw)
    assert b.boom_height == pytest.approx(18.5 - 15.5 - 0.25 * (12.0 / 12.0) ** 0.6)
    assert b.bodies[0].lcb == pytest.approx(0.535)
    assert b.crew_arm == pytest.approx(0.45 * 3.8)


def test_wrong_schema(raw):
    raw["schema"] = "windmark.boatclass/2"
    with pytest.raises(boatclass.ClassFileError):
        boatclass.from_dict(raw)
