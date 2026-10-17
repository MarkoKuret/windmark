"""Twin rudders (docs/specs/data_format.md 3.3, tools/boatgen/README.md "Twin rudders"): with `rudder.count` 2 a
spade hangs either side at `y`, canted outward by `cant`, each on its own node turning about its own stock, the
tips at `-depth`; the tiller turns on its own stock on the centreline (node `rudder`). wm10 is the shipped class.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import copy
import json
import os
import tempfile
import unittest

import numpy as np

from boatgen import classfile, physics
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WM10 = os.path.join(REPO, "data", "classes", "wm10.boat.json")


class TwinRudderClassTest(unittest.TestCase):
    def setUp(self):
        with open(WM10) as f:
            self.raw = json.load(f)

    def _bad(self, **rudder):
        raw = copy.deepcopy(self.raw)
        raw["rudder"].update(rudder)
        with self.assertRaises(classfile.ClassFileError):
            classfile.resolve(raw)

    def test_refused(self):
        self._bad(count=3)
        self._bad(count=True)
        self._bad(type="transom")
        self._bad(y=0.01)
        self._bad(y=3.0)
        self._bad(cant=0.9)

    def test_single_takes_no_twin_keys(self):
        raw = copy.deepcopy(self.raw)
        raw["rudder"]["count"] = 1
        with self.assertRaises(classfile.ClassFileError):
            classfile.resolve(raw)
        for k in ("y", "cant"):
            raw["rudder"].pop(k)
        c = classfile.resolve(raw)
        self.assertEqual((c["rudder"]["count"], c["rudder"]["y"], c["rudder"]["cant"]), (1, 0.0, 0.0))


class TwinRudderBoatTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boat = Boat(classfile.load(WM10), log=lambda *a: None)

    def test_blades(self):
        b = self.boat
        r = b.cls["rudder"]
        self.assertEqual(r["count"], 2)
        blades = {n: b.parts[n] for n in ("rudder_port", "rudder_starboard")}
        pts = {n: np.vstack([g.P for gs in p.slots.values() for g in gs if g.tag == "rudder"])
               for n, p in blades.items()}
        P, S = pts["rudder_port"], pts["rudder_starboard"]
        # mirror images of each other
        self.assertTrue(np.allclose(np.sort(P[:, 0]), np.sort(S[:, 0]), atol=1e-9))
        self.assertTrue(np.allclose(np.sort(P[:, 1]), np.sort(-S[:, 1]), atol=1e-9))
        for n, Q in pts.items():
            with self.subTest(blade=n):
                sy = 1.0 if n == "rudder_port" else -1.0
                # the tip reaches -depth (the class draft of the rudder), within a centimetre
                self.assertAlmostEqual(float(Q[:, 2].min()), -r["depth"], delta=0.01)
                # canted outward: the tip lies further out than the top
                top, tip = Q[Q[:, 2].argmax()], Q[Q[:, 2].argmin()]
                self.assertGreater(sy * (tip[1] - top[1]), 0.5 * np.tan(r["cant"]) * (top[2] - tip[2]))
                # the root is buried in the bottom where it stands
                pv, ax = b.app.blade_pivots()[n]
                self.assertGreater(pv[2], b.app.bottom_z(pv[0], abs(pv[1])))
                self.assertAlmostEqual(abs(float(pv[1])), r["y"], delta=0.05)
                # the stock axis leans inboard at the top by the cant
                self.assertAlmostEqual(float(np.arccos(ax[2])), r["cant"], places=6)
                self.assertLess(sy * ax[1], 0.0)

    def test_nodes_and_sidecar(self):
        b = self.boat
        parts = b.game_parts()
        for n in ("rudder", "rudder_port", "rudder_starboard"):
            self.assertIn(n, parts)
            self.assertIn(n, b.pivots)
        # the tiller's node holds the tiller and no blade
        tags = {g.tag for gs in parts["rudder"].slots.values() for g in gs}
        self.assertIn("tiller", tags)
        self.assertNotIn("rudder", tags)
        rig = physics.rig_data(b)
        self.assertEqual([d["node"] for d in rig["rudders"]], ["rudder_port", "rudder_starboard"])
        self.assertAlmostEqual(rig["rudder_stock"][1], 0.0)
        col = physics.collision(b)
        self.assertIn("rudder_port", col)
        self.assertIn("rudder_starboard", col)
        self.assertNotIn("rudder", col)
        # both blades displace: twice the immersed volume of one
        v = b.app.volumes()["rudder"][0]
        one = b.app.rudder_geoms[0]
        from boatgen.mesh import mesh_volume, mesh_area, split_by_plane_z
        below, _ = split_by_plane_z(one, 0.0)
        self.assertAlmostEqual(v, 2 * mesh_volume(one)[0] * mesh_area(below) / mesh_area(one), places=9)

    def test_glb_nodes(self):
        import struct
        b = self.boat
        bake, b.bake = b.bake, False
        try:
            with tempfile.TemporaryDirectory() as d:
                path = os.path.join(d, "wm10.glb")
                b.write_game_glb(path)
                with open(path, "rb") as f:
                    data = f.read()
        finally:
            b.bake = bake
        n = struct.unpack_from("<I", data, 12)[0]
        doc = json.loads(data[20:20 + n])
        names = {nd.get("name"): nd for nd in doc["nodes"]}
        for k in ("rudder", "rudder_port", "rudder_starboard"):
            self.assertIn(k, names)
            self.assertIn("translation", names[k])        # each turns about its own pivot


if __name__ == "__main__":
    unittest.main()
