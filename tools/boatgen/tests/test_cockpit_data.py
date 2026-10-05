"""The sidecar's cockpit block (README "Physics sidecar", docs/specs/water_render.md 4.8): the quadratics through
its three stations follow the generated cockpit's half width, floor and rim within 1 cm, in the body frame.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import os
import types
import unittest

import numpy as np

from boatgen import classfile, physics
from boatgen.deck import Deck
from boatgen.hull import HullShape

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "data", "classes")


def quad(v, t):
    v0, vm, v1 = v
    return v0 + t * (-3 * v0 + 4 * vm - v1) + t * t * (2 * v0 - 4 * vm + 2 * v1)


class CockpitData(unittest.TestCase):
    def test_classes(self):
        for name in sorted(os.listdir(CLASSES)):
            if not name.endswith(".boat.json"):
                continue
            with self.subTest(cls=name):
                cls = classfile.load(os.path.join(CLASSES, name))
                hull = HullShape(cls)
                deck = Deck(cls, hull)
                # cockpit_data needs only the deck and the body origin (mid LWL), not the solved hull
                boat = types.SimpleNamespace(deck=deck, origin_x=lambda h=hull: 0.5 * (h.x_awl + h.x_fwl))
                c = physics.cockpit_data(boat)
                ox = boat.origin_x()
                self.assertAlmostEqual(c["x0"], deck.xc0 - ox, places=3)
                for t in np.linspace(0.0, 1.0, 20):
                    x = deck.xc0 + t * c["len"]
                    w = float(deck.yc(x))
                    self.assertLess(abs(quad(c["half_width"], t) - w), 0.01)
                    self.assertLess(abs(quad(c["floor_z"], t) - float(deck.floor_z(x))), 0.01)
                    self.assertLess(abs(quad(c["rim_z"], t) - float(deck.deck_z(x, w))), 0.01)


if __name__ == "__main__":
    unittest.main()
