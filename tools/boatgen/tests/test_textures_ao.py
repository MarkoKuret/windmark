"""Texture set and baked ambient occlusion in the exported GLB (tools/boatgen/README.md "Materials and UVs").

Run from tools/boatgen: python3 -m unittest discover -s tests (the bake needs moderngl, as the previews do)
"""
import os
import tempfile
import unittest

import numpy as np

from boatgen import classfile, gltf, textures
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
WM7 = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "data", "classes", "wm7.boat.json")


class TexturesAOTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boat = Boat(classfile.load(WM7), log=lambda *a: None)
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "b.glb")
            cls.boat.write_glb(f)
            cls.prims, cls.doc = gltf.read_glb(f)

    def test_texture_files(self):
        for s in textures.SETS:
            for k, p in textures.paths(s).items():
                if k == "normal" and not textures.has_normal(s):
                    continue
                self.assertTrue(os.path.exists(p), p)

    def test_materials(self):
        doc = self.doc
        self.assertIn("KHR_texture_transform", doc["extensionsUsed"])
        self.assertEqual(len(doc["images"]), len({i["name"] for i in doc["images"]}), "each image embedded once")
        for m in doc["materials"]:
            tset, tiling = textures.SLOTS[m["name"]]
            self.assertEqual(m["extras"]["tiling_m"], tiling)
            pbr = m["pbrMetallicRoughness"]
            self.assertTrue(all(0 <= c <= 1 for c in pbr["baseColorFactor"]) and 0 <= pbr["roughnessFactor"] <= 1)
            if tset is None:
                self.assertNotIn("baseColorTexture", pbr)
                continue
            for info in (pbr["baseColorTexture"], pbr["metallicRoughnessTexture"]):
                self.assertEqual(info["texCoord"], 0)
                np.testing.assert_allclose(info["extensions"]["KHR_texture_transform"]["scale"], [1 / tiling] * 2)
            self.assertEqual("normalTexture" in m, textures.has_normal(tset))
        # real-material albedo (data_format.md 3.7): every slot's mean at most 0.8 linear, and the gelcoat's factor
        # too, so the boat shader's cap never flattens a white hull
        for name, (col, met, rough) in gltf.MATERIALS.items():
            self.assertLessEqual(max(col[:3]), 0.8, name)
        gel = next(m for m in doc["materials"] if m["name"] == "gelcoat")
        self.assertLessEqual(max(gel["pbrMetallicRoughness"]["baseColorFactor"][:3]), 0.8)
        self.assertEqual(textures.SLOTS["nonslip"][0], "diamond", "non-slip has its moulded pattern")
        sail = next(m for m in doc["materials"] if m["name"] == "sailcloth")
        self.assertNotIn("normalTexture", sail, "sails carry no normal map (sail_visuals.md 9)")

    def test_ao(self):
        for n, m, P, N, uv0, uv1, I, ao in self.prims:
            with self.subTest(node=n, slot=m):
                if n.startswith("sail_") or n == "mainsheet":
                    self.assertIsNone(ao)
                    continue
                self.assertIsNotNone(ao)
                self.assertTrue(((ao >= 0) & (ao <= 1)).all())
        hull = [ao for n, m, P, N, uv0, uv1, I, ao in self.prims if n == "hull" and m == "gelcoat"][0]
        self.assertGreater(np.median(hull), 0.9, "open topsides stay light")
        # the cockpit floor is darker than the open side decks
        deck = [(P, N, ao) for n, m, P, N, uv0, uv1, I, ao in self.prims if n == "deck" and m == "nonslip"][0]
        P, N, ao = deck
        up = N[:, 1] > 0.9
        self.assertGreater(np.median(ao[up]), 0.8)
        self.assertLess(np.percentile(ao[up], 5), np.median(ao[up]) - 0.1)


if __name__ == "__main__":
    unittest.main()
