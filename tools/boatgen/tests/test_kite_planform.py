"""Code zero and spinnaker planforms follow the standard proportions of docs/specs/data_format.md 3.5, and the
shipped class areas are the rule areas those planforms give.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import json
import os
import unittest

import numpy as np

from boatgen import classfile
from boatgen.build import Boat
from boatgen.mesh import normalize
from boatgen.sails import FLYING, ROUND_POS, _flying

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = [os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm7", "wm12")]
CLASSES.append(os.path.join(HERE, "fixtures", "test_sym.boat.json"))


_BOATS = []


def boats():
    """The test boats, built once per test run (a build takes about 14 s)."""
    if not _BOATS:
        np.seterr(all="ignore")
        _BOATS.extend(Boat(classfile.load(p), log=lambda *a: None) for p in CLASSES)
    return _BOATS


class KitePlanformTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.boats = boats()

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


    def test_defaults_unchanged(self):
        """With no shaping keys the planform is the standard proportions' (fixtures/kite_planform_ref.json; the
        asymmetric entries rewritten with the proportions of 2026-10-09, docs/specs/sail_visuals.md 14.6)."""
        with open(os.path.join(HERE, "fixtures", "kite_planform_ref.json")) as f:
            ref = json.load(f)
        n = 0
        for b in self.boats:
            for sid, s in b.sails.items():
                key = f"{b.cls['id']}/{sid}"
                if key not in ref:
                    continue
                n += 1
                r = ref[key]
                with self.subTest(sail=key):
                    self.assertEqual(list(s.P.shape), r["shape"])
                    for edge, pts in (("foot", s.P[0, :]), ("leech", s.P[:, -1]), ("luff", s.P[:, 0])):
                        np.testing.assert_allclose(pts, np.array(r[edge]), atol=1e-6)
                    self.assertAlmostEqual(s.measure["rule_area"], r["rule_area"], 5)
        self.assertEqual(n, 4)


def _edge_round(pts, outward):
    """Signed round of an edge polyline over its straight chord (fraction of the chord) and where along the
    edge it is deepest (sample fraction). outward: +1 when the outward side is the _curve normal."""
    a, b = pts[0], pts[-1]
    d = b - a
    n = normalize(np.array([d[2], 0.0, -d[0]]))
    dev = outward * ((pts - a) @ n)
    i = int(np.argmax(np.abs(dev)))
    return dev[i] / np.linalg.norm(d), i / (len(pts) - 1)


EDGES = {"luff": (lambda P: P[:, 0], 1.0), "leech": (lambda P: P[:, -1], -1.0), "foot": (lambda P: P[0, :], -1.0)}


class ShapingKeysTest(unittest.TestCase):
    """The class-file shaping keys of data_format.md 3.5 move the planform as documented."""

    @classmethod
    def setUpClass(cls):
        b = boats()[0]                     # wm7: asymmetric spinnaker on a sprit
        cls.boat = b
        cls.spec = next(s for s in b.cls["sails"] if s["type"] == "spinnaker_asym")
        cls.base = b.sails[cls.spec["id"]]

    def fly(self, **shape):
        return _flying(dict(self.spec, shape=shape), self.boat.cls, self.boat.rig, self.boat.deck)

    def round_of(self, sail, edge):
        f, sign = EDGES[edge]
        return _edge_round(f(sail.P), sign)

    def test_reported_shape_matches_drawing(self):
        for edge in EDGES:
            with self.subTest(edge=edge):
                depth, at = self.round_of(self.base, edge)
                self.assertAlmostEqual(depth, self.base.shape[edge]["round"], 2)
                pos = FLYING["spinnaker_asym"].get("round_pos", ROUND_POS[edge]) if edge != "foot" else ROUND_POS[edge]
                self.assertAlmostEqual(at, pos, delta=0.05)

    def test_mid_girth(self):
        s = self.fly(mid_girth_frac=0.70)
        self.assertAlmostEqual(s.measure["mid_girth"] / s.measure["foot"], 0.70, 3)
        self.assertLess(s.measure["rule_area"], self.base.measure["rule_area"])
        mg = self.base.measure["mid_girth"] + 0.5
        s = self.fly(mid_girth=mg)
        self.assertAlmostEqual(s.measure["mid_girth"], mg, 3)
        self.assertGreater(s.measure["rule_area"], self.base.measure["rule_area"])
        # below half the foot: the solver hollows the edges
        s = self.fly(mid_girth_frac=0.45)
        self.assertAlmostEqual(s.measure["mid_girth"] / s.measure["foot"], 0.45, 3)
        self.assertLess(s.shape["leech"]["round"], 0)

    def test_one_round_fixed_other_solved(self):
        for fixed, other in (("luff", "leech"), ("leech", "luff")):
            with self.subTest(fixed=fixed):
                s = self.fly(**{fixed + "_round": 0.03})
                self.assertAlmostEqual(self.round_of(s, fixed)[0], 0.03, 3)
                self.assertTrue(s.shape[other]["solved"])
                self.assertFalse(s.shape[fixed]["solved"])
                # the mid girth target is still met, by more round on the other edge
                self.assertAlmostEqual(s.measure["mid_girth"], self.base.measure["mid_girth"], 3)
                self.assertGreater(s.shape[other]["round"], self.base.shape[other]["round"])

    def test_both_rounds_fixed(self):
        s = self.fly(luff_round=0.05, leech_round=0.08)
        self.assertAlmostEqual(self.round_of(s, "luff")[0], 0.05, 3)
        self.assertAlmostEqual(self.round_of(s, "leech")[0], 0.08, 3)
        self.assertLess(s.measure["mid_girth"], self.base.measure["mid_girth"])

    def test_foot_round(self):
        s = self.fly(foot_round=0.03)
        self.assertAlmostEqual(self.round_of(s, "foot")[0], 0.03, 3)
        self.assertLess(s.measure["foot"], self.base.measure["foot"])
        # the mid girth follows the (shorter) rounded foot
        self.assertAlmostEqual(s.measure["mid_girth"] / s.measure["foot"], FLYING["spinnaker_asym"]["mid"], 3)

    def test_round_positions(self):
        for edge in EDGES:
            for at in (0.25, 0.7):
                with self.subTest(edge=edge, at=at):
                    s = self.fly(**{edge + "_round_pos": at})
                    self.assertAlmostEqual(self.round_of(s, edge)[1], at, delta=0.05)
                    self.assertEqual(s.shape[edge]["pos"], at)

    def test_unreachable_mid_girth(self):
        with self.assertRaisesRegex(ValueError, "out of reach"):
            self.fly(mid_girth_frac=1.2, luff_round=0.0)


def _raw_with(sail_id, **keys):
    with open(CLASSES[0]) as f:
        raw = json.load(f)
    raw = copy.deepcopy(raw)
    for s in raw["sails"]:
        if s["id"] == sail_id:
            s.update(keys)
    return raw


class ShapingKeysValidationTest(unittest.TestCase):
    def bad(self, sail_id, pattern, **keys):
        with self.assertRaisesRegex(classfile.ClassFileError, pattern):
            classfile.resolve(_raw_with(sail_id, **keys))

    def test_accepts_and_passes_through(self):
        c = classfile.resolve(_raw_with("kite", mid_girth_frac=0.7, luff_round=0.05, foot_round_pos=0.4))
        kite = next(s for s in c["sails"] if s["id"] == "kite")
        self.assertEqual(kite["shape"], {"mid_girth_frac": 0.7, "luff_round": 0.05, "foot_round_pos": 0.4})
        self.assertEqual(next(s for s in c["sails"] if s["id"] == "jib")["shape"], {})

    def test_ranges(self):
        self.bad("kite", r"luff_round must be between -0.1 and 0.3", luff_round=0.35)
        self.bad("kite", r"foot_round must be between", foot_round=-0.2)
        self.bad("kite", r"leech_round_pos must be between 0.1 and 0.9", leech_round_pos=0.0)
        self.bad("kite", r"mid_girth_frac must be between 0.3 and 1.2", mid_girth_frac=1.5)
        self.bad("kite", r"mid_girth must be > 0", mid_girth=0)
        self.bad("kite", r"must be a number", luff_round="0.1")
        self.bad("kite", r"must be a number", foot_round=True)

    def test_conflicts(self):
        self.bad("kite", r"not both", mid_girth=4.5, mid_girth_frac=0.7)
        self.bad("kite", r"mid girth is an outcome", luff_round=0.05, leech_round=0.08, mid_girth_frac=0.7)
        self.bad("jib", r"code zeros and spinnakers only", luff_round=0.05)



class KitePreviewCacheTest(unittest.TestCase):
    """kite_preview reuses the built hull, deck and rig only when nothing but flying-sail settings changed."""

    def test_cache_key(self):
        from boatgen.kite_preview import _cache_key
        base = _cache_key(_raw_with("kite"))
        self.assertEqual(base, _cache_key(_raw_with("kite", foot=5.4, mid_girth_frac=0.7, area=40.0, tack_x=4.0)))
        self.assertNotEqual(base, _cache_key(_raw_with("jib", area=14.0)))
        raw = _raw_with("kite")
        raw["hull"]["beam_max"] += 0.01
        self.assertNotEqual(base, _cache_key(raw))


if __name__ == "__main__":
    unittest.main()
