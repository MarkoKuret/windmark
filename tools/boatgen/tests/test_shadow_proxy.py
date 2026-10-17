"""The shadow proxy's shape (docs/specs/sail_visuals.md 11.4, boatgen/shadow.py): open over the cockpit, every face
inside the drawn surfaces by the inset, facing out of the shell, the spars inside the drawn spars.

Run from tools/boatgen: python3 -m unittest tests.test_shadow_proxy
"""
import os
import unittest

import numpy as np
from scipy.spatial import cKDTree

from boatgen import classfile, shadow
from boatgen.build import Boat
from boatgen.mesh import merge, normalize

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CLASSES = {c: os.path.join(REPO, "data", "classes", f"{c}.boat.json") for c in ("wm12", "wm7", "wm16", "wm21")}
# what the checks hold the proxy to: most of the inset from every drawn surface the sun can light (the drawn
# surfaces' facets and the proxy's chords take some of it, and near the transom the cockpit's sides come within a
# few centimetres of the narrowing topsides); from one that looks down (the hull's bottom, which gives way to the
# lit cockpit floor over it near an open transom) a quarter of it
MARGIN = 0.7 * shadow.INSET
MARGIN_DOWN = 0.25 * shadow.INSET
LOOKS_DOWN = -0.7   # a drawn face whose normal's z is under this looks down
MARGIN_SPAR = 0.5 * shadow.INSET_SPAR

_boats = {}


def boat(c):
    if c not in _boats:
        np.seterr(all="ignore")
        _boats[c] = Boat(classfile.load(CLASSES[c]), log=lambda *a: None)
    return _boats[c]


def samples(g, per=6, seed=1):
    """Points on every triangle (corners pulled 2 % in, the centroid and random ones) with each one's face normal."""
    rng = np.random.default_rng(seed)
    T = g.P[g.I]
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    a = np.linalg.norm(n, axis=1)
    T, n = T[a > 1e-12], n[a > 1e-12] / a[a > 1e-12, None]
    W = np.vstack([np.eye(3) * 0.97 + 0.01, [[1 / 3] * 3], rng.dirichlet([1, 1, 1], per)])
    P = np.einsum("sk,tkd->tsd", W, T).reshape(-1, 3)
    return P, np.repeat(n, len(W), axis=0)


def _closest_on_triangles(p, A, B, C):
    """Closest points on triangles (A, B, C) to points p, all (n, 3) (Ericson, Real-Time Collision Detection 5.1.5)."""
    ab, ac, ap = B - A, C - A, p - A
    d1, d2 = np.sum(ab * ap, 1), np.sum(ac * ap, 1)
    bp = p - B
    d3, d4 = np.sum(ab * bp, 1), np.sum(ac * bp, 1)
    cp = p - C
    d5, d6 = np.sum(ab * cp, 1), np.sum(ac * cp, 1)
    vc = d1 * d4 - d3 * d2
    vb = d5 * d2 - d1 * d6
    va = d3 * d6 - d5 * d4
    den = np.where(np.abs(va + vb + vc) < 1e-30, 1e-30, va + vb + vc)
    v, w = vb / den, vc / den
    out = A + ab * v[:, None] + ac * w[:, None]
    sel = lambda m, q: np.where(m[:, None], q, out)
    tab = d1 / np.where(np.abs(d1 - d3) < 1e-30, 1e-30, d1 - d3)
    out = sel((vc <= 0) & (d1 >= 0) & (d3 <= 0), A + ab * tab[:, None])
    tac = d2 / np.where(np.abs(d2 - d6) < 1e-30, 1e-30, d2 - d6)
    out = sel((vb <= 0) & (d2 >= 0) & (d6 <= 0), A + ac * tac[:, None])
    e = d4 - d3
    tbc = e / np.where(np.abs(e + d5 - d6) < 1e-30, 1e-30, e + d5 - d6)
    out = sel((va <= 0) & (e >= 0) & (d5 - d6 >= 0), B + (C - B) * tbc[:, None])
    out = sel((d6 >= 0) & (d5 <= d6), C)
    out = sel((d3 >= 0) & (d4 <= d3), B)
    out = sel((d1 <= 0) & (d2 <= 0), A)
    return out


class Surface:
    """Distance from points to a triangle soup: the k triangles with the nearest centroids, exactly."""

    def __init__(self, geoms, k=24, keep=None):
        g = merge(geoms)
        self.T = g.P[g.I]
        if keep is not None:
            self.T = self.T[keep(self.T)]
        self.k = k
        self.tree = cKDTree(self.T.mean(1))
        self.reach = float(np.max(np.linalg.norm(self.T - self.T.mean(1)[:, None], axis=-1)))

    def distance(self, P):
        _, idx = self.tree.query(P, self.k)
        best = np.full(len(P), np.inf)
        for j in range(self.k):
            T = self.T[idx[:, j]]
            q = _closest_on_triangles(P, T[:, 0], T[:, 1], T[:, 2])
            best = np.minimum(best, np.linalg.norm(P - q, axis=1))
        return best


def drawn(b, names):
    return [g for n in names for gs in b.parts[n].slots.values() for g in gs]


class ShadowProxyTest(unittest.TestCase):
    def test_counts(self):
        for c in CLASSES:
            static, boom, rudder = boat(c).shadow_proxy()
            with self.subTest(cls=c):
                self.assertLess(static.tri_count() + boom.tri_count() + rudder.tri_count(), 800)
                self.assertGreater(boom.tri_count(), 0)
        # a transom-hung rudder stands above the water and casts; a spade rudder under the hull does not
        self.assertGreater(boat("wm7").shadow_proxy()[2].tri_count(), 0)
        self.assertEqual(boat("wm12").shadow_proxy()[2].tri_count(), 0)

    def test_open_over_the_cockpit(self):
        """No proxy face over the cockpit opening: inside the cockpit's plan every face lies at least the margin
        under the drawn floor (the hull, deck, cockpit and coachroof of the static proxy)."""
        for c in CLASSES:
            b = boat(c)
            d = b.deck
            P = np.vstack([samples(g, 12)[0] for g in shadow.hull_and_deck(b.hull, d)])
            ck = (P[:, 0] >= d.xc0) & (P[:, 0] <= d.xc1) & (np.abs(P[:, 1]) < d.yc(P[:, 0]))
            h = P[ck, 2] - d.floor_z(P[ck, 0])
            with self.subTest(cls=c):
                self.assertGreater(ck.sum(), 50)
                self.assertLessEqual(float(h.max()), -MARGIN, f"{c}: a face {h.max():.3f} m from the cockpit floor")

    def test_inside_the_hull_and_deck(self):
        """Every face of the hull, deck, cockpit, coachroof and transom proxy lies under the walking surface and
        inside the hull's sections, at least the margin from the drawn hull and deck (a face looking down at least
        MARGIN_DOWN), and faces the drawn surface it lies under (out of the shell, the side the shadow pass draws)."""
        for c in CLASSES:
            b = boat(c)
            d, hull = b.deck, b.hull
            body = drawn(b, ("hull", "deck"))
            surf = Surface(body)
            nz = lambda T: normalize(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]))[:, 2]
            lit = Surface(body, keep=lambda T: nz(T) > LOOKS_DOWN)
            P, N = map(np.vstack, zip(*[samples(g) for g in shadow.hull_and_deck(hull, d)]))
            # the wheel well under the cockpit floor stays shaded: the floor's proxy crosses its walls
            for sl in (d.helm["slots"] if d.helm else []):
                m = shadow.INSET
                well = ((P[:, 0] > sl["x0"] - m) & (P[:, 0] < sl["x1"] + m)
                        & (np.abs(P[:, 1] - sl["yc"]) < sl["y"] + m) & (P[:, 2] > sl["z"] - m))
                P, N = P[~well], N[~well]
            with self.subTest(cls=c):
                self.assertTrue(((P[:, 0] > 0) & (P[:, 0] < hull.L)).all())
                # under the walking surface (within the deck's plan) and inside the hull's sections (below the sheer)
                plan = np.abs(P[:, 1]) < hull.bs(P[:, 0])
                ws = d.surface_z(P[plan, 0], P[plan, 1])
                well = d.in_slot(P[plan, 0], P[plan, 1])      # the wheel well stays shaded under the floor
                ws[well] = d.floor_z(P[plan, 0][well])
                under = P[plan, 2] - ws
                self.assertLessEqual(float(under.max()), -MARGIN * 0.99, f"{c}: {under.max():.3f} m under the surface")
                low = P[::5][P[::5, 2] < hull.zs(P[::5, 0])]
                hb = np.array([hull.half_breadth_at(x, z) for x, z in low[:, [0, 2]]])
                out = np.abs(low[:, 1]) > hb
                self.assertFalse(out.any(), f"{c}: points outside the hull's sections: {low[out][:3]}")
                dist, dlit = surf.distance(P), lit.distance(P)
                w = np.argmin(dlit)
                self.assertGreaterEqual(float(dlit.min()), MARGIN, f"{c}: {dlit[w]:.3f} m from a drawn surface the "
                                        f"sun can light at {np.round(P[w], 3)} (normal {np.round(N[w], 2)})")
                w = np.argmin(dist)
                self.assertGreaterEqual(float(dist.min()), MARGIN_DOWN, f"{c}: {dist[w]:.3f} m from the drawn "
                                        f"surface at {np.round(P[w], 3)}")
                print(f"  {c}: hull and deck proxy at least {dlit.min():.3f} m from the drawn surfaces the sun can "
                      f"light, {dist.min():.3f} m from any")
                # facing the drawn surface: a step along the face normal comes closer to it
                step = surf.distance(P + 0.01 * N)
                closer = step < dist
                self.assertGreater(closer.mean(), 0.98, f"{c}: {(~closer).sum()} of {len(P)} samples face inward")

    def test_mast_and_boom_inside_the_drawn_ones(self):
        from boatgen.rig import _mast_section
        for c in CLASSES:
            b = boat(c)
            r = b.rig
            with self.subTest(cls=c, part="mast"):
                P = samples(shadow.mast(r), 12)[0]
                P = P[P[:, 2] > r.z_step + 0.01]
                spar = [g for gs in b.parts["mast"].slots.values() for g in gs if (g.tag or "") == "mast"]
                sec = Surface(spar, k=16).distance(P)
                self.assertGreaterEqual(float(sec.min()), MARGIN_SPAR)
                tp = r.taper(P[:, 2])
                rx, ry = (P[:, 0] - r.x_mast) / (0.5 * r.chord * tp), P[:, 1] / (0.5 * r.width * tp)
                self.assertTrue((rx ** 2 + ry ** 2 < 1.0).all(), "mast proxy outside the mast's section")
            with self.subTest(cls=c, part="boom"):
                P = samples(shadow.boom_geom(r), 12)[0]
                boom = [g for gs in r.boom_part().slots.values() for g in gs if (g.tag or "") == "boom"]
                dist = Surface(boom, k=16).distance(P)
                self.assertGreaterEqual(float(dist.min()), MARGIN_SPAR)
                s = r.scale
                t = (r.gooseneck[0] - P[:, 0]) / r.boom_len
                sc = 1.0 - 0.25 * t ** 2
                self.assertTrue(((t > 0) & (t < 1)).all())
                self.assertTrue((np.abs(P[:, 1]) < 0.5 * 0.085 * s * sc).all()
                                and (np.abs(P[:, 2] - r.gooseneck[2]) < 0.5 * 0.17 * s * sc).all())

    def test_rudder_inside(self):
        b = boat("wm7")
        from boatgen.appendages import Appendages
        blade = [g for gs in Appendages(b.cls, b.hull).rudder_part().slots.values() for g in gs
                 if (g.tag or "") in ("rudder", "rudder_head")]
        lo = np.min([g.P.min(0) for g in blade], 0)
        hi = np.max([g.P.max(0) for g in blade], 0)
        for g in shadow.rudder_geoms(b):
            P = samples(g)[0]
            self.assertTrue(((P > lo) & (P < hi)).all())


if __name__ == "__main__":
    unittest.main()
