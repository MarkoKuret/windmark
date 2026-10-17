"""The shorthanded offshore deck (docs/specs/data_format.md 3.7.4) on wm10: the coaming's height field, the winches
on its flat top, the dodger over the companionway and the offshore fittings, and the class keys' checks.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import json
import os
import unittest

import numpy as np

from boatgen import classfile, hardware
from boatgen.deck import Deck
from boatgen.hull import HullShape

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WM10 = os.path.join(REPO, "data", "classes", "wm10.boat.json")


class OffshoreDeckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        with open(WM10) as f:
            cls.raw = json.load(f)
        cls.cls = classfile.resolve(cls.raw)
        cls.hull = HullShape(cls.cls)
        cls.deck = Deck(cls.cls, cls.hull)

    def test_keys_refused(self):
        for blk, k, v in (("coaming", "height", 2.0), ("coaming", "wide", 0.2), ("dodger", "solar_panel", 1),
                          ("offshore", "foot_braces", [-1.0]), ("dodger", "length", "long")):
            raw = copy.deepcopy(self.raw)
            raw["visual"]["deck"][blk][k] = v
            with self.subTest(key=f"{blk}.{k}"), self.assertRaises(classfile.ClassFileError):
                classfile.resolve(raw)

    def test_coaming(self):
        d, c = self.deck, self.deck.coaming
        x = 0.5 * (d.xc0 + d.xc1)
        yc = float(d.yc(x))
        self.assertAlmostEqual(float(d.coaming_h(x, yc + 0.5 * c["w"])), c["h"], places=6)
        self.assertAlmostEqual(float(d.coaming_h(x, yc + c["w"] + c["r"] + 0.01)), 0.0, places=9)
        self.assertEqual(float(d.coaming_h(x, 0.0)), 0.0)                 # the cockpit floor stays where it was
        self.assertAlmostEqual(float(d.coaming_h(d.xc0, yc + 0.1)), 0.0)  # faded out at the transom
        self.assertAlmostEqual(float(d.coaming_h(d.xc1, yc + 0.1)), 0.0)  # and at the coachroof
        # the stanchions' line stays on the plain side deck
        s = (self.hull.L / 12) ** 0.7
        for xx in np.linspace(d.xc0, d.xc1, 9):
            ys = float(self.hull.bs(np.array([xx]))[0]) - 0.07 * s
            self.assertAlmostEqual(float(d.coaming_h(xx, ys)), 0.0, places=6)

    def test_fittings(self):
        hw = hardware.place_all(self.cls, self.hull, self.deck, _Rig(self.cls, self.hull, self.deck))["hardware"]
        tags = {g.tag for gs in hw.slots.values() for g in gs}
        for t in ("dodger", "solar_panel", "foot_brace_0", "foot_brace_1", "liferaft", "autopilot"):
            self.assertIn(t, tags)
        # the dodger's windows are glass, its shell gelcoat: no new material
        self.assertTrue(set(hw.slots) <= set(hardware_slots()))
        # the primaries stand on the coaming's flat top, level
        d = self.deck
        P = np.vstack([g.P for gs in hw.slots.values() for g in gs if g.tag == "winch_primary_1"])
        x, y = P[:, 0].mean(), P[:, 1].mean()
        r = 0.5 * (P[:, 1].max() - P[:, 1].min())
        for yy in (y - 0.6 * r, y, y + 0.6 * r):           # its base's breadth on the flat top
            self.assertAlmostEqual(float(d.coaming_h(x, yy)), d.coaming["h"], delta=0.01)


def hardware_slots():
    from boatgen import gltf
    return [s["name"] if isinstance(s, dict) else s[0] for s in gltf.ATLAS_SLOTS]


def _Rig(cls, hull, deck):
    from boatgen.rig import Rig
    return Rig(cls, hull, deck)


if __name__ == "__main__":
    unittest.main()
