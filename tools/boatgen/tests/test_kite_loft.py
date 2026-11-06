"""The lofted kite (boatgen/kite_loft.py, docs/specs/sail_visuals.md 6.5): the kite shape file, the convex section
solve, the loft through the measured sections on a class planform (the cloth's length kept, the corners where the
flat sail has them, the measured camber and draft on every row) and the sidecar block, and the class-file keys.

The drawn kite against the measured sections, as the game places it, is sail_visuals.md 12 test 27
(game/tests/sail_visuals_test.gd). Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import math
import os
import unittest

import numpy as np

from boatgen import classfile, kite_loft as K
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WM7 = os.path.join(REPO, "data", "classes", "wm7.boat.json")

_boat = []


def wm7():
    if not _boat:
        np.seterr(all="ignore")
        _boat.append(Boat(classfile.load(WM7), log=lambda *a: None))
    return _boat[0]


class KiteShapeFile(unittest.TestCase):
    def test_j80_reads(self):
        sh = K.load("j80_deparday2016")
        self.assertIn("Deparday", sh["source"]["citation"])
        self.assertEqual([round(math.degrees(s["awa"])) for s in sh["shapes"]], [64, 124])
        self.assertEqual(sh["shapes"][0]["sections"].shape, (6, 5))

    def test_bad_files(self):
        good = {"schema": K.SCHEMA, "source": {"citation": "x"},
                "shapes": [{"awa_deg": 60, "sections": [{"h": 0, "camber": 0.2, "draft": 0.5, "entry_deg": 50},
                                                         {"h": 0.5, "camber": 0.2, "draft": 0.5, "entry_deg": 50}]},
                           {"awa_deg": 120, "sections": [{"h": 0, "camber": 0.3, "draft": 0.5, "entry_deg": 60},
                                                          {"h": 0.5, "camber": 0.2, "draft": 0.5, "entry_deg": 50}]}]}
        K.validate(good)
        for change in (lambda d: d.pop("source"), lambda d: d["shapes"].pop(),
                       lambda d: d["shapes"][0]["sections"][0].update(h=0.1),
                       lambda d: d["shapes"][0]["sections"][1].update(camber=0.6),
                       lambda d: d["shapes"][1].update(awa_deg=60)):
            d = copy.deepcopy(good)
            change(d)
            with self.assertRaises(K.KiteShapeError):
                K.validate(d)


class Section(unittest.TestCase):
    def test_measured_numbers(self):
        """Every J/80 section: camber and draft exact, the entry where convexity allows it, the curve convex."""
        for s in K.load("j80_deparday2016")["shapes"]:
            for h, f, d, tw, e in s["sections"]:
                sc = K.section(f, d, e)
                X, Y = sc["X"], sc["Y"]
                m = K._measure(X, Y, np.array([sc["entry"]]))
                self.assertAlmostEqual(m[0], f, places=4)
                self.assertAlmostEqual(m[1], d, places=3)
                self.assertTrue(sc["entry"] >= e - 1e-3 or sc["curl"] == 0.0)
                self.assertGreaterEqual(Y.min(), -1e-9)
                # unit arc length
                self.assertAlmostEqual(float(np.sum(np.hypot(np.diff(X), np.diff(Y)))), 1.0, places=4)

    def test_chord_target(self):
        sc = K.section(0.25, 0.44, chord=0.8)
        self.assertAlmostEqual(sc["chord"], 0.8, places=4)
        self.assertGreater(sc["curl"], 0.0)


class Loft(unittest.TestCase):
    def test_wm7(self):
        b = wm7()
        s = b.sails["kite"]
        keep = s.set_override
        s.set_override = dict(keep, shape="j80_deparday2016")      # wm7 flies the AC33 surface; the sections here
        try:
            blk = s.loft_block(b)
        finally:
            s.set_override = keep
        self.assertEqual(blk["shape"], "j80_deparday2016")
        P = s.P
        rows, cols = P.shape[:2]
        T, Ah, Lh, Nh = K.sail_frame(P)
        for awa, loc, clew in zip(blk["awa"], blk["shapes"], blk["clew"]):
            L = np.asarray(loc).reshape(rows, cols, 3)
            Q = T + L[..., :1] * Ah + L[..., 1:2] * Lh + L[..., 2:] * Nh
            # the tack and the head where the flat sail has them; the belly to port
            self.assertLess(np.linalg.norm(Q[0, 0] - P[0, 0]), 1e-4)
            self.assertLess(np.linalg.norm(Q[-1, 0] - P[-1, 0]), 1e-4)
            self.assertGreater(L[rows // 3, cols // 2, 2], 0.0)
            # the cloth keeps its length along each row (but the low rows the clew's lift moves along the luff)
            for i in range(rows // 3, rows - 1):
                flat = np.linalg.norm(np.diff(P[i], axis=0), axis=-1).sum()
                fly = np.linalg.norm(np.diff(Q[i], axis=0), axis=-1).sum()
                self.assertAlmostEqual(fly / flat, 1.0, delta=0.01)
            self.assertLess(clew["sheet_off_bisector_deg"], 25.0)
        sidecar = b.sails["kite"].set_block()
        self.assertEqual(sidecar["model"], "loft")


class ClassFile(unittest.TestCase):
    def test_set_keys(self):
        raw = classfile.load(WM7)["raw"]

        def with_set(st):
            r = copy.deepcopy(raw)
            r["visual"]["sails"]["kite"] = {"set": st}
            return classfile.resolve(r)
        with_set({"model": "loft", "shape": "j80_deparday2016", "loft_depth": 0.9, "loft_trim": 0.05})
        with_set({"model": "hinge"})
        for bad in ({"model": "balloon"}, {"model": "loft"}, {"model": "loft", "shape": "nope"},
                    {"loft_depth": 3.0}):
            with self.assertRaises(classfile.ClassFileError):
                with_set(bad)


if __name__ == "__main__":
    unittest.main()
