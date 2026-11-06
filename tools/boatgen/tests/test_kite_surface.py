"""The kite shape from a measured surface (boatgen/kite_surface.py, docs/specs/sail_visuals.md 6.5 "The surface
source"): the surface files, the IACC series against its published foot cambers, the IGES reader's B-splines, and
the mapping onto the wm7 and wm21 planforms (the tack and the head where the flat sail has them, the clew in the
rest plane, the belly to port, the measured sections kept).

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import os
import unittest

import numpy as np

from boatgen import classfile, iges, kite_loft, kite_surface as K
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
_boats = {}


def boat(cid):
    if cid not in _boats:
        np.seterr(all="ignore")
        _boats[cid] = Boat(classfile.load(os.path.join(REPO, "data", "classes", f"{cid}.boat.json")),
                           log=lambda *a: None)
    return _boats[cid]


def camber(row):
    """Largest distance from the chord over the chord, and where along it."""
    ch = row[-1] - row[0]
    cl = np.linalg.norm(ch)
    cu = ch / cl
    v = row - row[0]
    x = v @ cu
    d = np.linalg.norm(v - np.outer(x, cu), axis=-1)
    k = int(np.argmax(d))
    return d[k] / cl, x[k] / cl


class Files(unittest.TestCase):
    def test_ac33(self):
        sh = kite_loft.load("ac33_asym")
        self.assertEqual(sh["kind"], "surface")
        self.assertEqual(sh["source"]["licence"], "CC-BY-4.0")
        self.assertIn("10.7488/ds/2857", sh["source"]["citation"])
        M = K.surface_grid(sh["surfaces"]["ac33"])
        self.assertEqual(M.shape, K.GRID + (3,))
        o = K.outline(M)
        self.assertAlmostEqual(o["leech"] / o["luff"], 0.873, delta=0.01)
        self.assertAlmostEqual(o["foot"] / o["luff"], 0.586, delta=0.01)
        # the frame: the tack at the origin, the head up the l axis, the clew in the rest plane, the belly to +n
        self.assertLess(np.abs(M[0, 0]).max(), 1e-9)
        self.assertLess(abs(M[-1, 0, 0]) + abs(M[-1, 0, 2]), 1e-6)
        self.assertLess(abs(M[0, -1, 2]), 1e-6)
        self.assertGreater(M[K.GRID[0] // 3, K.GRID[1] // 2, 2], 0.0)
        self.assertEqual([round(np.degrees(s["awa"])) for s in sh["shapes"]], [55, 130])

    def test_iacc_foot_cambers(self):
        # Peart (2022) table 3.1: the five sails' foot cambers
        sh = kite_loft.load("iacc_sym_series")
        want = {"I": 0.230, "II": 0.285, "III": 0.348, "IV": 0.398, "V": 0.446}
        for k, c in want.items():
            spec = sh["surfaces"][k]
            foot = K.moore_point(spec["coef"], spec["k"], np.linspace(-0.5, 0.5, 2001), 0.1)
            self.assertAlmostEqual(camber(foot)[0], c, delta=0.002, msg=k)
            self.assertAlmostEqual(camber(foot)[1], 0.5, delta=0.01)
        # flatter on a reach, deeper running
        depth = [K.surface_grid(sh["surfaces"][s["surface"]])[..., 2].max() for s in sh["shapes"]]
        self.assertEqual(depth, sorted(depth))

    def test_bad_files(self):
        good = {"schema": K.SCHEMA, "kind": "surface", "source": {"citation": "x", "licence": "CC0"},
                "surfaces": {"s": {"form": "grid", "points": np.zeros((5, 5, 3)).tolist()}},
                "shapes": [{"awa_deg": 60, "surface": "s"}]}
        K.validate(good)
        for path, val in ((("source", "licence"), ""), (("shapes",), []), (("surfaces",), {}),
                          (("surfaces", "s", "form"), "nurbs"), (("shapes", 0, "surface"), "t"),
                          (("shapes", 0, "depth"), 3.0), (("shapes", 0, "awa_deg"), 200)):
            d = copy.deepcopy(good)
            x = d
            for k in path[:-1]:
                x = x[k]
            x[path[-1]] = val
            with self.assertRaises(kite_loft.KiteShapeError):
                K.validate(d)


class Iges(unittest.TestCase):
    def test_basis(self):
        kn = [0, 0, 0, 0, 0.3, 0.6, 1, 1, 1, 1]
        u = np.linspace(0, 1, 101)
        B = iges._basis(kn, 3, u)
        self.assertEqual(B.shape, (6, 101))
        self.assertLess(np.abs(B.sum(0) - 1).max(), 1e-12)
        self.assertGreaterEqual(B.min(), 0.0)


class OnTheClass(unittest.TestCase):
    def check(self, cid, sid, name):
        b = boat(cid)
        s = b.sails[sid]
        blk = s.loft_block(b)
        self.assertEqual((blk["shape"], blk["kind"]), (name, "surface"))
        P = s.P
        rows, cols = P.shape[:2]
        T, Ah, Lh, Nh = kite_loft.sail_frame(P)
        sh = kite_loft.load(name)
        for spec, loc in zip(sh["shapes"], blk["shapes"]):
            L = np.asarray(loc).reshape(rows, cols, 3)
            Q = T + L[..., :1] * Ah + L[..., 1:2] * Lh + L[..., 2:] * Nh
            self.assertLess(np.linalg.norm(Q[0, 0] - P[0, 0]), 1e-4)        # the tack on its fitting
            self.assertLess(np.linalg.norm(Q[-1, 0] - P[-1, 0]), 1e-4)      # the head at its halyard
            self.assertLess(np.ptp(Q[-1], axis=0).max(), 1e-4)              # a pointed head
            self.assertLess(abs(L[0, -1, 2]), 1e-4)                         # the clew in the rest plane
            self.assertGreater(L[rows // 3, cols // 2, 2], 0.0)             # the belly to port
            # the measured sections kept: each row's camber within two points of the measured row at its stripe
            M = K.surface_grid(sh["surfaces"][spec["surface"]])
            for i in range(2, rows - 3, 3):
                h = i / (rows - 1)
                Mi = K.sample(M, np.full(K.GRID[1], h), np.linspace(0, 1, K.GRID[1]))
                want = camber(Mi)[0] * spec["depth"]
                self.assertAlmostEqual(camber(L[i])[0], want, delta=0.02 + 0.1 * abs(spec["depth"] - 1) * want)
        # the outline: the class's foot and leech kept within 3 % along the cloth
        Q0 = np.asarray(blk["shapes"][0]).reshape(rows, cols, 3)
        o, co = K.outline(Q0), K.outline(P)
        self.assertAlmostEqual(o["foot"] / co["foot"], 1.0, delta=0.03)
        self.assertAlmostEqual(o["leech"] / co["leech"], 1.0, delta=0.03)
        return blk

    def test_wm7(self):
        blk = self.check("wm7", "kite", "ac33_asym")
        self.assertEqual(blk["depth"], [1.0, 1.1])

    def test_wm21(self):
        blk = self.check("wm21", "spin", "iacc_sym_series")
        self.assertEqual(blk["surface"], ["I", "II", "III", "IV", "V"])


if __name__ == "__main__":
    unittest.main()
