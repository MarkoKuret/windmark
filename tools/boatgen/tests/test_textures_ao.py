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
            cls.data = open(f, "rb").read()
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, "b.glb")
        with open(cls.path, "wb") as fh:
            fh.write(cls.data)

    def test_texture_files(self):
        for s in textures.SETS:
            for k, p in textures.paths(s).items():
                if k == "normal" and not textures.has_normal(s):
                    continue
                self.assertTrue(os.path.exists(p), p)

    def test_materials(self):
        """One boat material for every opaque surface (slot table and tiling atlas in its extras), the sails on
        their own; the images once per file."""
        doc = self.doc
        names = [m["name"] for m in doc["materials"] if not m["name"].startswith(tuple(textures.SLOTS))
                 or m["name"] in ("sailcloth",)]
        raw, rdoc = gltf.read_glb(self.path, expand=False)
        mats = [m["name"] for m in rdoc["materials"]]
        self.assertEqual(sorted(mats), ["boat", "sailcloth", "shadow"], mats)
        imgs = [i["name"] for i in rdoc["images"]]
        self.assertEqual(len(imgs), len(set(imgs)), "each image once")
        boat = next(m for m in rdoc["materials"] if m["name"] == "boat")
        ex = boat["extras"]
        self.assertEqual(len(ex["slots"]), len(gltf.ATLAS_SLOTS))
        self.assertEqual(ex["atlas"]["sets"], list(textures.ATLAS_SETS))
        for sl in ex["slots"]:
            self.assertLessEqual(max(sl["color"]), 0.8, sl["name"])
            self.assertTrue(0 <= sl["tile"] < len(textures.ATLAS_SETS))
        for n, m, P, N, uv0, uv1, I, ao in raw:
            if n.startswith("sail_"):
                self.assertEqual(m, "sailcloth")
            elif n.startswith("shadow"):
                self.assertEqual(m, "shadow")
            else:
                self.assertEqual(m, "boat", n)
        # the atlas images: 4 x 2 tiles of 512
        img = textures.atlas_image("color")
        self.assertEqual(img.shape, (2 * textures.SIZE, 4 * textures.SIZE, 3))
        self.assertEqual(textures.SLOTS["nonslip"][0], "diamond", "non-slip has its moulded pattern")
        for name, (col, met, rough) in gltf.MATERIALS.items():
            self.assertLessEqual(max(col[:3]), 0.8, name)
        del names

    def test_ao(self):
        for n, m, P, N, uv0, uv1, I, ao in self.prims:
            with self.subTest(node=n, slot=m):
                if n.startswith("sail_") or n.startswith("shadow"):
                    self.assertIsNone(ao)
                    continue
                if n == "mainsheet":       # rebuilt as the boom moves: no bake, AO 1
                    self.assertTrue((ao == 1).all())
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
