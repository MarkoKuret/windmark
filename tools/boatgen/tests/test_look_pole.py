"""Sidecar look blocks (docs/specs/sail_visuals.md 4) and the spinnaker pole node (sail_visuals.md 7.3).

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import json
import os
import unittest

import numpy as np

from boatgen import classfile, physics
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WM7 = os.path.join(REPO, "data", "classes", "wm7.boat.json")
SYM = os.path.join(HERE, "fixtures", "test_sym.boat.json")

_boats = {}


def boat(path):
    if path not in _boats:
        np.seterr(all="ignore")
        _boats[path] = Boat(classfile.load(path), log=lambda *a: None)
    return _boats[path]


class LookTest(unittest.TestCase):
    def test_defaults_and_size_rules(self):
        b = boat(WM7)
        sails = physics.sail_data(b)
        main, jib, kite = sails["main"]["look"], sails["jib"]["look"], sails["kite"]["look"]
        self.assertEqual((main["fill_gain"], main["fill_curve"], main["flutter_amp"], main["twist_top"]),
                         (0.6, 4.0, 0.15, 0.070))
        self.assertEqual((jib["fill_gain"], jib["fill_curve"], jib["flutter_amp"], jib["twist_top"]),
                         (0.75, 1.2, 0.07, 0.105))
        self.assertEqual((kite["fill_gain"], kite["camber"], kite["tack_line_max"], kite["twist_top"]),
                         (1.0, 0.26, 0.04, 0.0))
        self.assertNotIn("depth", kite)
        # wm7: LOA 7.2 m -> r_f = 2.904, w_max = 9.04 (sail_visuals.md 12, test 6)
        for look in (main, jib, kite):
            self.assertAlmostEqual(look["flutter_rate"], 2.904, places=6)
            self.assertAlmostEqual(look["flutter_rate_max"], 9.04, places=6)
        # keys that do not apply to a type are left out
        self.assertNotIn("camber", main)
        self.assertNotIn("camber", jib)
        self.assertNotIn("furl_radius", main)
        self.assertNotIn("furl_radius", kite)
        # furl radius from the chord extent Sa of the flat sail
        Sa = b.sails["jib"].chord_extent()
        self.assertAlmostEqual(jib["furl_radius"], 0.02 + 0.006 * Sa, places=6)
        self.assertTrue(1.0 < Sa < 4.0)

    def test_class_overrides(self):
        sails = physics.sail_data(boat(SYM))
        self.assertEqual(sails["s1"]["look"]["camber"], 0.24)
        self.assertEqual(sails["s1"]["look"]["fill_gain"], 1.5)
        self.assertEqual(sails["main"]["look"]["twist_top"], 0.09)
        self.assertEqual(sails["main"]["look"]["fill_curve"], 4.0)

    def test_old_depth_key_dropped(self):
        # sail_visuals.md 4: `camber` replaced `depth`; an old class file still loads, the sidecar has no depth
        with open(WM7) as f:
            raw = json.load(f)
        raw["visual"].setdefault("sails", {})["kite"] = {"look": {"depth": 0.3}}
        b = Boat(classfile.resolve(raw), log=lambda *a: None)
        look = physics.sail_data(b)["kite"]["look"]
        self.assertNotIn("depth", look)
        self.assertEqual(look["camber"], 0.26)

    def test_bad_look_keys(self):
        with open(WM7) as f:
            raw = json.load(f)
        for look in ({"fill_gian": 1.0}, {"camber": "deep"}, {"camber": -1}, {"camber": float("nan")},
                     {"depth": -1}):
            r = copy.deepcopy(raw)
            r["visual"]["sails"]["kite"] = {"look": look}
            with self.assertRaises(classfile.ClassFileError):
                classfile.resolve(r)


class PoleTest(unittest.TestCase):
    def test_no_pole_on_a_sprit_boat(self):
        b = boat(WM7)
        self.assertNotIn("pole", b.parts)
        self.assertNotIn("pole", b.pivots)
        self.assertNotIn("pole_pivot", physics.rig_data(b))

    def test_pole_node(self):
        b = boat(SYM)
        self.assertIn("pole", b.parts)
        self.assertGreater(b.parts["pole"].tri_count(), 0)
        rig = physics.rig_data(b)
        step, head = np.array(rig["mast_step"]), np.array(rig["masthead"])
        piv, end = np.array(rig["pole_pivot"]), np.array(rig["pole_end"])
        # pivot on the mast axis, turning about the vertical
        axis = (head - step) / np.linalg.norm(head - step)
        off = (piv - step) - np.dot(piv - step, axis) * axis
        self.assertLess(np.linalg.norm(off), 1e-3)
        self.assertEqual(rig["pole_axis"], [0.0, 0.0, 1.0])
        # at rest the pole points forward on the centreline; its end is the spinnaker tack
        self.assertAlmostEqual(end[1], 0.0)
        self.assertAlmostEqual(end[2], piv[2])
        self.assertAlmostEqual(end[0] - piv[0], rig["pole_length"] + rig["mast_chord"] / 2, places=3)
        self.assertEqual(rig["pole_length"], 4.4)
        tack = physics.sail_data(b)["s1"]["corners"]["tack"]["position"]
        self.assertLess(np.linalg.norm(np.array(tack) - end), 1e-3)
        # the pole geometry runs forward from the mast to the pole end
        P = np.concatenate([g.P for gs in b.parts["pole"].slots.values() for g in gs])
        self.assertLess(P[:, 0].max(), b.rig.pole_end[0] + 0.05)
        self.assertGreater(P[:, 0].max(), b.rig.pole_end[0] - 0.1)
        self.assertLess(np.abs(P[:, 2] - b.rig.pole_pivot[2]).max(), 0.2)


if __name__ == "__main__":
    unittest.main()
