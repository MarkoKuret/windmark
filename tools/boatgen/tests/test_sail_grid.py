"""Sail grid contract (tools/boatgen/README.md "Sail grid", docs/specs/sail_visuals.md 3.1): full two-layer grid
topology, layer normals at a collapsed head, and uv1 as exact grid fractions (the key an engine uses to recover
the grid node after re-indexing).

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import os
import tempfile
import unittest

import numpy as np

from boatgen import classfile, gltf
from boatgen.build import Boat

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = [os.path.join(REPO, "data", "classes", "wm12.boat.json"),
           os.path.join(REPO, "data", "classes", "wm7.boat.json"),
           os.path.join(HERE, "fixtures", "test_sym.boat.json")]

_glbs = {}


def sail_prims(path):
    """(boat, {sail node: (P, N, uv0, uv1, I)}) read back from the written GLB."""
    if path not in _glbs:
        np.seterr(all="ignore")
        b = Boat(classfile.load(path), log=lambda *a: None)
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "b.glb")
            b.write_glb(f)
            prims, _ = gltf.read_glb(f)
        _glbs[path] = (b, {n: (P, N, u0, u1, I) for n, m, P, N, u0, u1, I in prims if n.startswith("sail_")})
    return _glbs[path]


class SailGridTest(unittest.TestCase):
    def each_sail(self):
        for path in CLASSES:
            b, prims = sail_prims(path)
            for sid, s in b.sails.items():
                rows, cols = s.P.shape[:2]
                with self.subTest(cls=os.path.basename(path), sail=sid):
                    yield s, rows, cols, prims["sail_" + sid]

    def test_full_topology(self):
        for s, rows, cols, (P, N, uv0, uv1, I) in self.each_sail():
            L = rows * cols
            self.assertEqual(len(P), 2 * L)
            self.assertEqual(len(I), 4 * (rows - 1) * (cols - 1))
            used = np.zeros(len(P), bool)
            used[I.ravel()] = True
            self.assertTrue(used.all(), f"unreferenced vertices {np.nonzero(~used)[0].tolist()}")
            # each layer uses only its own vertices
            self.assertTrue(((I < L).all(1) | (I >= L).all(1)).all())

    def test_layer_normals(self):
        for s, rows, cols, (P, N, uv0, uv1, I) in self.each_sail():
            L = rows * cols
            # flat sail in the centreline plane: port layer normal +X (glTF), starboard -X, head included
            self.assertTrue(np.allclose(N[:L], [1, 0, 0], atol=1e-5), "port layer normals")
            self.assertTrue(np.allclose(N[L:], [-1, 0, 0], atol=1e-5), "starboard layer normals")
            d = P[:L] - P[L:]
            self.assertTrue(np.allclose(d, [0.002, 0, 0], atol=1e-6), "layers 2 mm apart along the normal")
            # winding: the non-degenerate triangles of each layer face that layer's normal
            a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
            fn = np.cross(b - a, c - a)
            big = np.linalg.norm(fn, axis=1) > 1e-10
            port = (I < L).all(1)
            self.assertTrue((fn[big & port, 0] > 0).all())
            self.assertTrue((fn[big & ~port, 0] < 0).all())
            if s.type != "main":
                head = P[(rows - 1) * cols:rows * cols]
                self.assertTrue(np.allclose(head, head[0], atol=1e-6), "pointed head collapses to one point")

    def test_uv1_exact_grid_fractions(self):
        for s, rows, cols, (P, N, uv0, uv1, I) in self.each_sail():
            L = rows * cols
            k = np.arange(L)
            i, j = k // cols, k % cols
            # float32 in the file: exact to the float32 rounding of j / (cols - 1) and 1 - i / (rows - 1)
            u = (j / (cols - 1)).astype(np.float32)
            v = (1 - i / (rows - 1)).astype(np.float32)
            np.testing.assert_array_equal(uv1[:L, 0].astype(np.float32), u)
            np.testing.assert_array_equal(uv1[:L, 1].astype(np.float32), v)
            np.testing.assert_array_equal(uv1[L:, 0].astype(np.float32), (1 - j / (cols - 1)).astype(np.float32))
            np.testing.assert_array_equal(uv1[L:, 1].astype(np.float32), v)
            # the recovery rule of game/scripts/sail_grid.gd gives back the file index for every vertex
            layer = np.where(P[:, 0] > 0, 0, 1)
            uu = np.where(layer == 0, uv1[:, 0], 1 - uv1[:, 0])
            col = np.rint(uu * (cols - 1)).astype(int)
            row = np.rint((1 - uv1[:, 1]) * (rows - 1)).astype(int)
            np.testing.assert_array_equal(layer * L + row * cols + col, np.arange(2 * L))
            # the grid nodes stay well apart in uv1 even at 16-bit precision (half-float step near 1 is 2^-11)
            self.assertGreater(1 / (max(rows, cols) - 1), 20 * 2 ** -11)

    def test_corners_on_grid(self):
        for s, rows, cols, (P, N, uv0, uv1, I) in self.each_sail():
            for name, (i, j) in s.corners.items():
                self.assertTrue(0 <= i < rows and 0 <= j < cols)
            self.assertEqual(s.corners["head"], (rows - 1, 0))


if __name__ == "__main__":
    unittest.main()
