"""The game model (tools/boatgen/README.md "The game model", docs/specs/sail_visuals.md 11.4): one detailed model,
the static parts merged into `body`, the moving parts on their own, low-poly hardware, painted and dropped
fittings, the shadow proxy and the boat material's slots.

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
CLASSES = {c: os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm12", "wm7", "wm16", "wm21", "wm10")}
MOVING = ("rudder", "rudder_port", "rudder_starboard", "wheel", "wheel_2", "boom", "mainsheet", "pole")

_boats = {}


def boat(c):
    if c not in _boats:
        np.seterr(all="ignore")
        _boats[c] = Boat(classfile.load(CLASSES[c]), log=lambda *a: None)
    return _boats[c]


class GameModelTest(unittest.TestCase):
    def test_nodes(self):
        for c in CLASSES:
            b = boat(c)
            parts = b.game_parts()
            with self.subTest(cls=c):
                names = [n for n in parts if not n.startswith("sail_")]
                self.assertEqual(names[0], "body")
                self.assertTrue(set(names[1:]) <= set(MOVING), names)
                self.assertIn("rudder", names)
                self.assertIn("boom", names)
                self.assertIn("mainsheet", names)
                tris, surf, _ = b.model_counts(parts)
                self.assertLessEqual(surf, 6)
                # the hull, deck and keel keep the full model's detail
                full = sum(b.parts[k].tri_count() for k in ("hull", "keel"))
                kept = sum(g.tri_count for m, gs in parts["body"].slots.items() for g in gs
                           if m.split(":")[0] in ("hull", "keel"))
                self.assertEqual(kept, full)
                for n, p in parts.items():
                    for gs in p.slots.values():
                        for g in gs:
                            t = g.tag or ""
                            painted = hardware.is_painted(t) and not t.startswith("hatch_")
                            if b._modelled_lead(t):
                                continue                # visual.deck.halyard_leads "modelled": geometry
                            if hardware.is_painted_line(t):
                                # a painted line's geometry only where it leaves the surface
                                h = g.P[:, 2] - b.deck.surface_z(g.P[:, 0], g.P[:, 1])
                                self.assertTrue((h[g.I] >= hardware.ROPE_LIFT_MAX).any(1).all(), t)
                                continue
                            self.assertFalse(painted or hardware.is_dropped(t), (n, t))
                tags = {(g.tag or "").split("_")[0] for gs in parts["body"].slots.values() for g in gs}
                self.assertIn("wind", tags)          # the wind wand
                self.assertIn("winch", tags)
                if b.cls["deck"].get("grinders"):
                    self.assertIn("grinder", tags)     # modelled, low-poly
                    gr = [g for gs in parts["body"].slots.values() for g in gs if (g.tag or "").startswith("grinder_")]
                    self.assertLessEqual(sum(g.tri_count for g in gr), 800 * b.cls["deck"]["grinders"])
                self.assertNotIn("pod", tags)          # a regatta helm: no instrument pod or guard
                self.assertNotIn("pedestal_guard", {g.tag for gs in parts["body"].slots.values() for g in gs})

    def test_painted(self):
        for c in CLASSES:
            p = boat(c).painted_part()
            tags = {g.tag.split("_")[0] for gs in p.slots.values() for g in gs}
            with self.subTest(cls=c):
                want = ("jib", "traveller", "hatch")
                if boat(c).cls["deck"].get("halyard_leads") != "modelled":
                    want += ("halyard", "organiser")    # modelled leads (wm16): halyards and organisers are geometry
                for t in want:
                    self.assertIn(t, tags)
                self.assertNotIn("mast", tags)       # the mast-foot blocks stand up: modelled

    def test_lowpoly(self):
        with hardware.lowpoly():
            w = hardware.winch(0.14)
            self.assertTrue(300 <= w.tri_count() <= 500, w.tri_count())
            for name, part in (("block", hardware.block(0.05)), ("padeye block", hardware.padeye_block(0.05)),
                               ("clutch", hardware.clutch_bank(1, 0.05))):
                self.assertTrue(40 <= part.tri_count() <= 150, (name, part.tri_count()))

    def test_shadow_proxy(self):
        for c in CLASSES:
            static, boom, rudder = boat(c).shadow_proxy()
            with self.subTest(cls=c):
                self.assertLess(static.tri_count() + boom.tri_count() + rudder.tri_count(), 800)
                self.assertGreater(boom.tri_count(), 0)

    def test_glb_slots(self):
        """One primitive per node in the boat material; every body vertex carries its slot and source part."""
        b = boat("wm7")
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "b.glb")
            b.write_game_glb(f)
            raw, rdoc = gltf.read_glb(f, expand=False)
            ex, doc = gltf.read_glb(f)
        body = [r for r in raw if r[0] == "body"]
        self.assertEqual(len(body), 1)
        names = {(n, s) for n, s, t in doc["_slots"]}
        for want in ("hull_gelcoat", "hull_antifouling", "deck_gelcoat", "transom", "keel", "metal", "carbon", "deck_face"):
            self.assertIn(("body", want), names)
        self.assertEqual(rdoc["nodes"][rdoc["scenes"][0]["nodes"][0]]["extras"]["body_parts"], gltf.PART_IDS)
        self.assertEqual(gltf.atlas_slot("body", "rudder:antifouling"), gltf.SLOT_ID["rudder"])


if __name__ == "__main__":
    unittest.main()
