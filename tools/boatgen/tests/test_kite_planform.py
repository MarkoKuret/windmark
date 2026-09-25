"""Code zero and spinnaker planforms follow the standard proportions of docs/specs/data_format.md 3.5, and the
shipped class areas are the rule areas those planforms give.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import os
import unittest

import numpy as np

from boatgen import classfile
from boatgen.build import Boat
from boatgen.sails import FLYING

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = [os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm7", "wm12")]
CLASSES.append(os.path.join(HERE, "fixtures", "test_sym.boat.json"))


class KitePlanformTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boats = [Boat(classfile.load(p), log=lambda *a: None) for p in CLASSES]

    def test_proportions_and_area(self):
        n = 0
        for b in self.boats:
            for spec in b.cls["sails"]:
                s = b.sails[spec["id"]]
                if s.type not in FLYING:
                    continue
                n += 1
                with self.subTest(boat=b.cls["id"], sail=spec["id"]):
                    m, pf = s.measure, FLYING[s.type]
                    straight = np.linalg.norm(s.P[-1, 0] - s.P[0, 0])
                    self.assertAlmostEqual(np.linalg.norm(s.P[-1, -1] - s.P[0, -1]) / straight, pf["leech"], 2)
                    if pf["foot"] is not None:
                        self.assertAlmostEqual(np.linalg.norm(s.P[0, -1] - s.P[0, 0]) / straight, pf["foot"], 2)
                    self.assertAlmostEqual(m["mid_girth"] / m["foot"], pf["mid"], 2)
                    # class area: the rule area rounded down to 0.5 m2
                    self.assertLessEqual(spec["area"], m["rule_area"])
                    self.assertGreater(spec["area"], m["rule_area"] - 0.5)
                    # the clew is well inside the hull length, not behind the transom
                    x_clew = s.P[0, -1][0]            # measured forward from the transom
                    self.assertGreater(x_clew, 0.2 * b.hull.L)
        self.assertEqual(n, 4)


if __name__ == "__main__":
    unittest.main()
