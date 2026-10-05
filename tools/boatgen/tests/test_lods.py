"""Game levels of detail (tools/boatgen/README.md "Levels of detail", docs/specs/sail_visuals.md 11.4): triangle
and surface budgets, painted and dropped fittings, the shadow proxy and the boat material's slots.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import os
import tempfile
import unittest

import numpy as np

from boatgen import classfile, gltf, hardware
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = {c: os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm12", "wm7")}
# model triangles without the sails (the sails come on top: about 2.2 to 2.8 k of main and one other sail on LOD0
# and LOD1, a quarter on LOD2 and a sixteenth on LOD3)
BUDGET = {0: 22000, 1: 5600, 2: 1500, 3: 300}
SURFACES = {0: 12, 1: 3, 2: 3, 3: 3}

_boats = {}


def boat(c):
    if c not in _boats:
        np.seterr(all="ignore")
        _boats[c] = Boat(classfile.load(CLASSES[c]), log=lambda *a: None)
    return _boats[c]


class LodTest(unittest.TestCase):
    def test_budgets(self):
        for c in CLASSES:
            b = boat(c)
            for lod in sorted(b.LODS):
                with self.subTest(cls=c, lod=lod):
                    parts = b.lod_parts(lod)
                    tris, surf, _ = b.model_counts(parts)
                    self.assertLessEqual(tris, BUDGET[lod])
                    self.assertLessEqual(surf + (2 if lod == 0 else 0), SURFACES[lod])
                    if lod >= 1:
                        self.assertIn("body", parts)
                    self.assertEqual("mainsheet" in parts, lod <= 1)
                    # no painted or dropped piece is geometry on any level
                    for n, p in parts.items():
                        for gs in p.slots.values():
                            for g in gs:
                                self.assertFalse(hardware.is_painted(g.tag or "") or hardware.is_dropped(g.tag or ""),
                                                 (n, g.tag))

    def test_painted(self):
        for c in CLASSES:
            p = boat(c).painted_part()
            tags = {g.tag.split("_")[0] for gs in p.slots.values() for g in gs}
            with self.subTest(cls=c):
                self.assertGreater(p.tri_count(), 1000)
                for t in ("jib", "mast", "halyard", "traveller"):
                    self.assertIn(t, tags)

    def test_winch_lowpoly(self):
        with hardware.lowpoly(0):
            w = hardware.winch(0.14)
        self.assertLessEqual(w.tri_count(), 260)
        with hardware.lowpoly(0):
            self.assertLessEqual(hardware.block(0.05).tri_count(), 80)

    def test_shadow_proxy(self):
        for c in CLASSES:
            static, boom = boat(c).shadow_proxy()
            with self.subTest(cls=c):
                self.assertLess(static.tri_count() + boom.tri_count(), 800)
                self.assertGreater(boom.tri_count(), 0)

    def test_glb_slots(self):
        """Every vertex of the boat material carries a slot id of the table; the hull and deck slots read their
        livery regions."""
        b = boat("wm7")
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "b.glb")
            b.write_lod_glb(f, 1)
            raw, _ = gltf.read_glb(f, expand=False)
            ex, doc = gltf.read_glb(f)
        body = [r for r in raw if r[0] == "body"]
        self.assertEqual(len(body), 1)
        names = {(n, s) for n, s, t in doc["_slots"]}
        for want in ("hull_gelcoat", "hull_antifouling", "deck_gelcoat", "transom", "keel", "metal", "carbon"):
            self.assertIn(("body", want), names)
        self.assertEqual(gltf.atlas_slot("body", "rudder:antifouling"), gltf.SLOT_ID["rudder"])
        self.assertEqual(gltf.ATLAS_SLOTS[gltf.SLOT_ID["deck_nonslip"]][2], "deck")


if __name__ == "__main__":
    unittest.main()
