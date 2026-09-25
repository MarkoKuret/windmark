import copy

import pytest

BASE = {
    "schema": "windmark.boatclass/1", "id": "test40", "name": "Test 40", "version": 1,
    "hull": {"loa": 12.0, "lwl": 10.5, "beam_max": 3.8, "bwl": 3.0, "draft_canoe": 0.45, "displacement": 6000,
             "prismatic": 0.55, "section_shape": {"type": "round", "midship_coefficient": 0.8},
             "rocker": {"fwd": 0.40, "aft": 0.25}, "freeboard": {"bow": 1.25, "mid": 1.0, "stern": 0.85},
             "transom_width": 2.8, "stem_x": 5.8, "transom_x": -6.2},
    "keel": {"depth": 2.6, "chord_root": 1.1, "chord_tip": 0.7, "x": 0.3, "fin_mass": 350, "bulb_mass": 2400},
    "rudder": {"depth": 2.0, "chord_root": 0.5, "chord_tip": 0.3, "x": -5.0},
    "rig": {"I": 15.0, "J": 4.3, "P": 15.5, "E": 5.2, "mast_height": 18.5, "mast_x": 1.0},
    "sails": [{"id": "main", "type": "main", "area": 52}, {"id": "jib", "type": "jib", "area": 38},
              {"id": "a2", "type": "spinnaker_asym", "area": 130}],
    "crew": {"count": 7, "weight": 600},
}


@pytest.fixture
def raw():
    return copy.deepcopy(BASE)


TRIMARAN = {
    "type": "trimaran", "loa": 16.5, "lwl": 16.0, "beam_max": 13.0, "bwl": 1.6, "draft_canoe": 0.55,
    "displacement": 5500, "prismatic": 0.58, "freeboard": {"bow": 1.4, "mid": 1.2, "stern": 1.0},
    "rocker": {"fwd": 0.45, "aft": 0.3}, "transom_width": 1.0, "stem_x": 8.2, "transom_x": -8.3,
    "floats": {"lwl": 15.0, "bwl": 1.0, "draft": 0.9, "prismatic": 0.6,
               "section_shape": {"type": "v", "midship_coefficient": 0.7}, "freeboard": 1.1, "beam_max": 1.2,
               "rocker": {"fwd": 0.85, "aft": 0.4}, "transom_width": 0.5, "spacing": 6.5, "clearance": 0.25},
}


@pytest.fixture
def tri_raw():
    r = copy.deepcopy(BASE)
    r["hull"] = copy.deepcopy(TRIMARAN)
    del r["keel"]
    r["boards"] = {"depth": 3.0, "chord_root": 0.6, "x": 0.8}
    r["crew"]["hiking_arm"] = 3.0
    return r
