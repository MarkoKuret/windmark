"""The regatta helm (docs/specs/data_format.md 3.7.3): with `well` the wheel's lower part runs through a slot in the
cockpit floor that clears the rim on every side, the rudder stock stays aft of the slot, and the floor reports the
slot's bottom inside it. Without `well` the wheel stands clear above the floor.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import os
import unittest

import numpy as np

from boatgen import classfile
from boatgen.deck import Deck
from boatgen.hull import HullShape

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "data", "classes")


class HelmTest(unittest.TestCase):
    def setUp(self):
        self.cls = classfile.load(os.path.join(CLASSES, "wm12.boat.json"))

    def test_wheel_through_the_floor(self):
        d = Deck(self.cls, HullShape(self.cls))
        h, sl = d.helm, d.helm["slot"]
        self.assertIsNotNone(sl)
        R, hub = h["diameter"] / 2, h["hub"]
        self.assertAlmostEqual(h["diameter"], 1.7)
        bottom = hub[2] - R
        self.assertLess(bottom, h["floor_z"] - 0.2)              # well into the floor
        self.assertGreater(bottom, sl["z"] + 0.03)               # and clear of the slot's bottom
        rim_t = 0.04 * h["diameter"]
        self.assertGreater(hub[0] - sl["x0"], 0.5 * rim_t + 0.04)
        self.assertGreater(sl["x1"] - hub[0], 0.5 * rim_t + 0.04)
        # the rim where it passes the floor stays 4 cm inside the slot's sides
        y_floor = np.sqrt(R * R - (hub[2] - h["floor_z"]) ** 2)
        self.assertGreater(sl["y"] - y_floor, 0.04)
        stock = self.cls["rudder"]["x_stock"]
        self.assertGreater(sl["x0"] - stock, 0.11 * (d.hull.L / 12) ** 0.7)
        self.assertAlmostEqual(float(d.surface_z(hub[0], 0.0)), sl["z"])
        self.assertAlmostEqual(float(d.surface_z(hub[0], sl["y"] + 0.05)), float(d.floor_z(hub[0])))

    def test_no_well(self):
        cls = copy.deepcopy(self.cls)
        cls["deck"]["wheel"] = {"diameter": None, "well": False, "hub_height": None}
        d = Deck(cls, HullShape(cls))
        self.assertIsNone(d.helm["slot"])
        self.assertGreater(d.helm["hub"][2] - d.helm["diameter"] / 2, d.helm["floor_z"] + 0.1)

    def test_too_big(self):
        cls = copy.deepcopy(self.cls)
        cls["deck"]["wheel"]["diameter"] = 3.0
        with self.assertRaises(ValueError):
            Deck(cls, HullShape(cls))


if __name__ == "__main__":
    unittest.main()
