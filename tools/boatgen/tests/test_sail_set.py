"""The sails of the preview poses, set with the game's shape (boatgen/sail_set.py, docs/specs/sail_visuals.md 6, 7).

The parity with the game itself (BoatView with the native and the reference SailShape) is checked by
game/tests/sail_visuals_test.gd (sail_visuals.md 12, test 19) from the `<id>.sets.json` files written here.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import json
import os
import tempfile
import unittest

import numpy as np

from boatgen import classfile, sail_set
from boatgen.build import Boat
from boatgen.kite_preview import set_pose

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = {c: os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm7", "wm12")}
CLASSES["test_sym"] = os.path.join(HERE, "fixtures", "test_sym.boat.json")

_boats = {}


def boat(cid):
    if cid not in _boats:
        np.seterr(all="ignore")
        _boats[cid] = Boat(classfile.load(CLASSES[cid]), log=lambda *a: None)
    return _boats[cid]


def row_camber(G, i):
    """Largest distance of row i from its luff-leech line over that line's length."""
    a, b = G[i, 0], G[i, -1]
    c = np.linalg.norm(b - a)
    d = np.linalg.norm(np.cross(G[i] - a, (b - a) / c), axis=-1)
    return d.max() / c


RECT_LOOK = {"fill_gain": 1.0, "fill_curve": 1.0, "twist_top": 0.0, "camber": 0.26, "tack_line_max": 0.04}
RIG = {"boom_pivot": np.zeros(3), "boom_axis": sail_set.UP, "mast_step": np.array([-1.0, 0, -1]),
       "masthead": np.array([-1.0, 0, 12])}


def rect():
    """sail_visuals.md 12 rectangle: luff on x = 0 from z = 0 to 9 m, leech at x = -3 m, 11 x 11, in y = 0."""
    x = np.linspace(0, -3, 11)
    z = np.linspace(0, 9, 11)
    return np.stack([np.broadcast_to(x[None], (11, 11)), np.zeros((11, 11)), np.broadcast_to(z[:, None], (11, 11))], -1)


class SpecTest(unittest.TestCase):
    def test_17_camber(self):
        # asym defaults, aws 6 kn, awa 90 and 150 deg, beta at the leeward optimum: 0.20 to 0.30 at mid height,
        # smaller at the foot and the head
        for awa, beta in ((90, 42), (150, 64)):
            s = sail_set.SailSet(rect(), "spinnaker_asym", RECT_LOOK, sail_set.LUFF, RIG, 7.2)
            s.clearance = 0.0
            s.update(np.radians(-beta), 0.0, np.radians(awa), 6 * sail_set.KNOT)
            G = s.grid()
            mid, foot, head = row_camber(G, 5), row_camber(G, 0), row_camber(G, 9)
            self.assertTrue(0.20 <= mid <= 0.30, (awa, mid))
            self.assertLess(foot, mid)
            self.assertLess(head, mid)

    def test_chord_keeps_the_cloth(self):
        # 6.3: a full row is shortened so its arc keeps the flat chord (within the parabola's approximation)
        s = sail_set.SailSet(rect(), "spinnaker_asym", RECT_LOOK, sail_set.LUFF, RIG, 7.2)
        s.clearance = 0.0
        s.update(np.radians(-64), 0.0, np.radians(150), 6 * sail_set.KNOT)
        G = s.grid()
        arc = np.linalg.norm(np.diff(G[5], axis=0), axis=-1).sum()
        self.assertAlmostEqual(arc / 3.0, 1.0, delta=0.02)

    def test_main_fill(self):
        # 12 test 1: main defaults, awa 30 deg, beta -5 deg: b = 0.3739, camber b^2 of Sa at mid chord (h ~ 1)
        look = {"fill_gain": 0.6, "fill_curve": 4.0, "twist_top": 0.0}
        s = sail_set.SailSet(rect(), "main", look, sail_set.LUFF, RIG, 7.2)
        b = sail_set.fill(np.sin(np.radians(25)), 0.6, 4.0)
        self.assertAlmostEqual(b, 0.3739, places=4)


class PoseTest(unittest.TestCase):
    def test_flying_sails_clear_of_the_main(self):
        # 7.4 in every preview pose: no flying-sail vertex within 0.9 of the faded margin of the main or the mast
        for cid in CLASSES:
            b = boat(cid)
            for name, pose in sail_set.preview_poses(b):
                grids, shapes = sail_set.set_sails(b, pose)
                for sid, sh in shapes.items():
                    if not sh.flying:
                        continue
                    hd = sh.grid()[-1, 0]
                    for p in sh.mid:
                        cp = sh._margin(p, hd)
                        for o in sh._secs:
                            x, _ = sh._clear_x(o, p, cp + 1.0)
                            self.assertGreaterEqual(x, 0.9 * cp - 1e-3, (cid, name, sid))
                        x, _ = sh._mast_x(p, sail_set.PORT)
                        self.assertGreaterEqual(x, 0.9 * cp - 1e-3, (cid, name, sid, "mast"))

    def test_kite_set_depth_and_tack(self):
        # the set kite: 0.20 to 0.30 camber at mid height on a run with 6 kn apparent or more, tack at the sprit
        # end (the swing of 7.3 is at most tack_line_max of the luff), on the leeward side of the boat
        for cid, sid in (("wm7", "kite"), ("wm12", "a2")):
            b = boat(cid)
            for pt in ("run", "reach"):
                pose = set_pose("spinnaker_asym", pt)
                pose["aws"] = 5.0
                grids, shapes = sail_set.set_sails(b, pose)
                G = grids[sid]
                c = row_camber(G, G.shape[0] // 2)
                self.assertTrue(0.18 <= c <= 0.30, (cid, pt, c))
                rest_tack = b.sails[sid].P[0, 0]
                self.assertLess(np.linalg.norm(G[0, 0] - rest_tack), 0.05 * shapes[sid].sl + 1e-6)
                self.assertLess(G[0, -1][1], 0.0)          # clew to starboard, the lee side

    def test_sets_file(self):
        b = boat("wm7")
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "wm7.sets.json")
            sail_set.write_sets(b, path)
            with open(path) as f:
                js = json.load(f)
        names = [s["name"] for s in js["sets"]]
        self.assertIn("upwind", names)
        self.assertIn("downwind", names)
        self.assertIn("spinnaker_asym_run", names)
        run = next(s for s in js["sets"] if s["name"] == "spinnaker_asym_run")
        kite = next(s for s in run["sails"] if s["id"] == "kite")
        self.assertEqual(len(kite["mid"]), 16 * 26)
        self.assertLess(run["awa"], 0.0)
        self.assertGreater(kite["beta"], 0.0)           # sails to starboard with the wind from port


if __name__ == "__main__":
    unittest.main()
