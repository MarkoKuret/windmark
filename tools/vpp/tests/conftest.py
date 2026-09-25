import copy

import pytest

BASE = {
    "format": "windmark-boat-class", "version": 1, "id": "test40", "name": "Test 40",
    "hull": {"type": "monohull", "loa": 12.0, "lwl": 10.5, "beam_max": 3.8, "bwl": 3.0, "draft_canoe": 0.45,
             "displacement": 6000, "cp": 0.55, "freeboard": 1.0, "transom_width": 1.6, "rocker": 0.3},
    "keel": {"depth": 2.6, "chord": 0.9, "bulb_mass": 2400},
    "rudder": {"depth": 2.0, "chord": 0.4},
    "rig": {"I": 15.0, "J": 4.3, "P": 15.5, "E": 5.2, "mast_height": 18.5},
    "sails": [{"id": "main", "type": "main", "area": 52}, {"id": "jib", "type": "jib", "area": 38},
              {"id": "a2", "type": "gennaker", "area": 130}],
    "crew": {"mass": 600},
}


@pytest.fixture
def raw():
    return copy.deepcopy(BASE)
