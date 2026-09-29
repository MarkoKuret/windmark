"""Mesh container and surface-building helpers.

All geometry is built in the boat frame (x forward from the transom, y to port, z up from the design
waterline, metres) and converted to the glTF frame only when written.

A `Part` maps material slot names to `Geom` pieces. Every helper returns a `Geom` with positions, normals,
two UV sets (uv0 metric for tiling textures, uv1 normalised for decals) and triangle indices.
"""
import contextlib

import numpy as np

# segment-count scale of the round helpers (revolve, tube, circle, ellipse, rounded_rect, superellipsoid_box):
# 1 for the full model, lower for the lower levels of detail (build.py)
_SEG = [1.0]


def seg(n, lo=3):
    """Segment count n scaled by the current level of detail, at least `lo`."""
    return max(lo, int(round(n * _SEG[0])))


@contextlib.contextmanager
def segment_scale(f):
    old = _SEG[0]
    _SEG[0] = f
    try:
        yield
    finally:
        _SEG[0] = old


class Geom:
    def __init__(self, P, I, N=None, uv0=None, uv1=None):
        self.P = np.asarray(P, dtype=np.float64).reshape(-1, 3)
        self.I = np.asarray(I, dtype=np.int64).reshape(-1, 3)
        n = len(self.P)
        self.N = vertex_normals(self.P, self.I) if N is None else np.asarray(N, dtype=np.float64).reshape(-1, 3)
        self.uv0 = np.zeros((n, 2)) if uv0 is None else np.asarray(uv0, dtype=np.float64).reshape(-1, 2)
        self.uv1 = self.uv0.copy() if uv1 is None else np.asarray(uv1, dtype=np.float64).reshape(-1, 2)
        # name of the piece this geometry belongs to, for the attachment checks (attach.py); kept by copies and
        # transforms, dropped by merge()
        self.tag = None

    def _tagged(self, g):
        g.tag = self.tag
        return g

    def copy(self):
        return self._tagged(Geom(self.P.copy(), self.I.copy(), self.N.copy(), self.uv0.copy(), self.uv1.copy()))

    def transformed(self, M):
        """Apply a 4x4 affine matrix (normals by the inverse transpose)."""
        M = np.asarray(M, dtype=np.float64)
        P = self.P @ M[:3, :3].T + M[:3, 3]
        Ni = np.linalg.inv(M[:3, :3]).T
        N = normalize(self.N @ Ni.T)
        I = self.I if np.linalg.det(M[:3, :3]) > 0 else self.I[:, ::-1]
        return self._tagged(Geom(P, I.copy(), N, self.uv0.copy(), self.uv1.copy()))

    def mirrored_y(self):
        return self.transformed(np.diag([1.0, -1.0, 1.0, 1.0]))

    def flipped(self):
        return self._tagged(Geom(self.P.copy(), self.I[:, ::-1].copy(), -self.N, self.uv0.copy(), self.uv1.copy()))

    @property
    def tri_count(self):
        return len(self.I)


def merge(geoms):
    geoms = [g for g in geoms if g is not None and len(g.I)]
    if not geoms:
        return None
    off, Is = 0, []
    for g in geoms:
        Is.append(g.I + off)
        off += len(g.P)
    return Geom(np.vstack([g.P for g in geoms]), np.vstack(Is), np.vstack([g.N for g in geoms]),
                np.vstack([g.uv0 for g in geoms]), np.vstack([g.uv1 for g in geoms]))


class Part:
    """Material slot -> list of Geom, plus the attachments of its tagged pieces (`links`, attach.py)."""

    def __init__(self):
        self.slots = {}
        self.links = []

    def add(self, material, geom, tag=None):
        """Add a piece; `tag` names it for the attachment checks."""
        if geom is not None and len(geom.I):
            if tag is not None:
                geom = geom.copy()
                geom.tag = tag
            self.slots.setdefault(material, []).append(geom)
        return self

    def extend(self, other, M=None, tag=None):
        """Add another part's pieces (transformed by M), tagging every piece `tag` when given; its links come too."""
        for mat, gs in other.slots.items():
            for g in gs:
                self.add(mat, g if M is None else g.transformed(M), tag=tag)
        self.links += other.links
        return self

    def attach(self, piece, *hosts):
        """Record that the piece tagged `piece` is fitted to (touches) one of the pieces tagged `hosts`."""
        self.links.append((piece, tuple(hosts)))
        return self

    def tag_all(self, tag):
        """Tag every untagged piece (a host surface such as the deck or the hull)."""
        for gs in self.slots.values():
            for g in gs:
                if g.tag is None:
                    g.tag = tag
        return self

    def merged(self):
        return {m: merge(gs) for m, gs in self.slots.items() if merge(gs) is not None}

    def tri_count(self):
        return sum(g.tri_count for gs in self.slots.values() for g in gs)


# ---------------------------------------------------------------------------------------------------------
# vector helpers

def normalize(v, eps=1e-12):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, eps)


def vertex_normals(P, I):
    N = np.zeros_like(P)
    if len(I) == 0:
        return N
    a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(N, I[:, k], fn)
    return normalize(N)


def translate(t):
    M = np.eye(4)
    M[:3, 3] = t
    return M


def scale(s):
    s = np.broadcast_to(np.asarray(s, dtype=np.float64), (3,))
    return np.diag([s[0], s[1], s[2], 1.0])


def rot_axis(axis, ang):
    axis = normalize(np.asarray(axis, dtype=np.float64))
    x, y, z = axis
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    R = np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                  [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                  [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])
    M = np.eye(4)
    M[:3, :3] = R
    return M


def frame(origin, x_axis, z_hint):
    """4x4 with local x along x_axis and local z as close to z_hint as possible."""
    xa = normalize(x_axis)
    ya = normalize(np.cross(z_hint, xa))
    za = np.cross(xa, ya)
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = xa, ya, za, origin
    return M


def frame_z(origin, z_axis, x_hint):
    """4x4 with local z along z_axis and local x as close to x_hint as possible."""
    za = normalize(z_axis)
    ya = normalize(np.cross(za, x_hint))
    xa = np.cross(ya, za)
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = xa, ya, za, origin
    return M


def arclen(pts):
    d = np.linalg.norm(np.diff(pts, axis=0), axis=-1)
    return np.concatenate([[0.0], np.cumsum(d)])


def resample_polyline(pts, n):
    """Resample a polyline to n points uniformly by arc length."""
    s = arclen(pts)
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, pts[:, k]) for k in range(pts.shape[1])], axis=-1)


def smax(a, b, k):
    """Smooth maximum with blend width k (log-sum-exp)."""
    if k <= 0:
        return np.maximum(a, b)
    m = np.maximum(a, b)
    return m + k * np.log(np.exp((a - m) / k) + np.exp((b - m) / k))


def smin(a, b, k):
    return -smax(-a, -b, k)


# ---------------------------------------------------------------------------------------------------------
# surfaces

def grid(P, uv0=None, uv1=None, close_u=False, close_v=False, N=None, keep_degenerate=False):
    """Quad grid surface from a (nu, nv, 3) array. Winding: (du x dv) is the outward normal.

    Closing a direction welds the last row to the first by index (the arrays must not repeat the seam).
    Zero-area triangles (collapsed rows) are dropped unless `keep_degenerate`, which keeps the full two
    triangles per cell so every vertex stays referenced (sail grids)."""
    P = np.asarray(P, dtype=np.float64)
    nu, nv = P.shape[:2]
    idx = np.arange(nu * nv).reshape(nu, nv)
    iu = np.arange(nu if close_u else nu - 1)
    iv = np.arange(nv if close_v else nv - 1)
    A = idx[iu[:, None], iv[None, :]]
    B = idx[(iu[:, None] + 1) % nu, iv[None, :]]
    C = idx[(iu[:, None] + 1) % nu, (iv[None, :] + 1) % nv]
    D = idx[iu[:, None], (iv[None, :] + 1) % nv]
    I = np.concatenate([np.stack([A, B, C], -1).reshape(-1, 3), np.stack([A, C, D], -1).reshape(-1, 3)])
    # drop degenerate triangles (collapsed rows at a stem or apex)
    Pf = P.reshape(-1, 3)
    if not keep_degenerate:
        area = np.linalg.norm(np.cross(Pf[I[:, 1]] - Pf[I[:, 0]], Pf[I[:, 2]] - Pf[I[:, 0]]), axis=-1)
        I = I[area > 1e-12]
    f = lambda a: None if a is None else np.asarray(a).reshape(-1, 2)
    if N is None:
        N = grid_normals(P, close_u, close_v)
    return Geom(Pf, I, np.asarray(N).reshape(-1, 3), f(uv0), f(uv1))


def grid_normals(P, close_u=False, close_v=False):
    """Smooth normals of a grid surface by central differences (robust at collapsed edges)."""
    def d(axis, closed):
        if closed:
            return np.roll(P, -1, axis) - np.roll(P, 1, axis)
        return np.gradient(P, axis=axis)
    du, dv = d(0, close_u), d(1, close_v)
    N = np.cross(du, dv)
    bad = np.linalg.norm(N, axis=-1) < 1e-14
    if bad.any():
        # fall back to face-averaged normals where a row collapses to a point
        g = grid(P, close_u=close_u, close_v=close_v, N=np.zeros_like(P))
        Nf = vertex_normals(g.P, g.I).reshape(P.shape)
        N[bad] = Nf[bad]
    return normalize(N)


def revolve(profile, segments=24, uv_scale=1.0, cap_ends=True, sharp=()):
    """Surface of revolution about +z from a (r, z) profile (bottom to top).

    Indices in `sharp` duplicate that profile point so the surface creases there."""
    segments = seg(segments, 6)
    prof = []
    for i, p in enumerate(profile):
        prof.append(p)
        if i in sharp:
            prof.append(p)
    prof = np.asarray(prof, dtype=np.float64)
    th = np.linspace(0, 2 * np.pi, segments + 1)[:-1]
    r, z = prof[:, 0], prof[:, 1]
    P = np.stack([r[None, :] * np.cos(th)[:, None], r[None, :] * np.sin(th)[:, None],
                  np.broadcast_to(z, (segments, len(z)))], -1)
    # normals from the profile tangent, split at duplicated points
    n2 = np.zeros((len(prof), 2))
    for i in range(len(prof)):
        segs = []
        if i > 0 and not np.allclose(prof[i], prof[i - 1]):
            segs.append(prof[i] - prof[i - 1])
        if i < len(prof) - 1 and not np.allclose(prof[i], prof[i + 1]):
            segs.append(prof[i + 1] - prof[i])
        if i > 0 and np.allclose(prof[i], prof[i - 1]):
            segs = [prof[i + 1] - prof[i]] if i < len(prof) - 1 else segs
        elif i < len(prof) - 1 and np.allclose(prof[i], prof[i + 1]):
            segs = [prof[i] - prof[i - 1]] if i > 0 else segs
        t = np.sum([s / (np.linalg.norm(s) + 1e-12) for s in segs], axis=0) if segs else np.array([0.0, 1.0])
        n2[i] = [t[1], -t[0]]  # outward for a bottom-to-top profile
    n2 = normalize(n2)
    N = np.stack([n2[None, :, 0] * np.cos(th)[:, None], n2[None, :, 0] * np.sin(th)[:, None],
                  np.broadcast_to(n2[:, 1], (segments, len(z)))], -1)
    s = arclen(prof)
    uv = np.stack([np.broadcast_to((th / (2 * np.pi))[:, None] * 2 * np.pi * max(r.max(), 1e-3), P.shape[:2]),
                   np.broadcast_to(s[None, :], P.shape[:2])], -1) * uv_scale
    g = grid(P, uv, close_u=True, N=N)
    # grid winding (du around, dv up) gives an outward normal for an upward profile
    parts = [g]
    if cap_ends:
        for end, sign in ((0, -1.0), (-1, 1.0)):
            if prof[end, 0] > 1e-6:
                parts.append(disk(prof[end, 0], prof[end, 1], segments, sign))
    return merge(parts)


def disk(r, z, segments, sign):
    th = np.linspace(0, 2 * np.pi, segments + 1)[:-1]
    P = np.vstack([[0, 0, z], np.stack([r * np.cos(th), r * np.sin(th), np.full_like(th, z)], -1)])
    I = np.array([[0, 1 + i, 1 + (i + 1) % segments] for i in range(segments)])
    if sign < 0:
        I = I[:, ::-1]
    N = np.tile([0, 0, sign], (len(P), 1))
    return Geom(P, I, N, P[:, :2].copy())


SWEEP_MAX_SEG = 0.5


def parallel_frames(path):
    path = np.asarray(path, dtype=np.float64)
    T = np.gradient(path, axis=0)
    T = normalize(T)
    ref = np.array([0.0, 0.0, 1.0]) if abs(T[0, 2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    Nn = [normalize(np.cross(np.cross(T[0], ref), T[0]))]
    for i in range(1, len(path)):
        n = Nn[-1] - T[i] * np.dot(Nn[-1], T[i])
        if np.linalg.norm(n) < 1e-9:
            n = Nn[-1]
        Nn.append(normalize(n))
    Nn = np.array(Nn)
    B = np.cross(T, Nn)
    return T, Nn, B


def sweep(path, profile, closed_profile=True, scale_along=None, caps=True, up=None, max_seg=None):
    """Sweep a 2D profile (m, 2) along a 3D path (n, 3). Profile x maps to the frame normal, y to binormal.

    `up` (3,) pins the profile x axis to the direction closest to `up` (for non-circular sections). Path segments
    longer than `max_seg` are split evenly (so per-vertex data such as baked AO has rings to vary on)."""
    path = np.asarray(path, dtype=np.float64)
    prof = np.asarray(profile, dtype=np.float64)
    if max_seg is None:
        max_seg = SWEEP_MAX_SEG / _SEG[0]
    if max_seg and len(path) > 1:
        seg = np.linalg.norm(np.diff(path, axis=0), axis=-1)
        k = np.maximum(1, np.ceil(seg / max_seg).astype(int))
        if (k > 1).any():
            t = np.concatenate([i + np.arange(k[i]) / k[i] for i in range(len(seg))] + [[len(seg)]])
            idx = np.arange(len(path))
            path = np.stack([np.interp(t, idx, path[:, c]) for c in range(3)], -1)
            if scale_along is not None:
                scale_along = np.interp(t, idx, np.broadcast_to(np.asarray(scale_along, dtype=np.float64), (len(idx),)))
    T, Nn, B = parallel_frames(path)
    if up is not None:
        up = np.asarray(up, dtype=np.float64)
        Nn = normalize(up[None, :] - T * np.sum(T * up[None, :], -1, keepdims=True))
        B = np.cross(T, Nn)
    sc = np.ones(len(path)) if scale_along is None else np.asarray(scale_along, dtype=np.float64)
    P = path[:, None, :] + sc[:, None, None] * (prof[None, :, 0, None] * Nn[:, None, :] + prof[None, :, 1, None] * B[:, None, :])
    s = arclen(path)
    ps = arclen(np.vstack([prof, prof[:1]]) if closed_profile else prof)[:len(prof)]
    uv = np.stack([np.broadcast_to(s[:, None], P.shape[:2]), np.broadcast_to(ps[None, :], P.shape[:2])], -1)
    # orientation: du along path, dv around profile; profile counter-clockwise gives inward, so swap
    g = grid(P[:, ::-1], uv[:, ::-1], close_v=closed_profile)
    parts = [g]
    if caps and closed_profile:
        for end, sgn in ((0, -1.0), (-1, 1.0)):
            ring = P[end]
            c = ring.mean(0)
            Pc = np.vstack([c, ring])
            m = len(ring)
            I = np.array([[0, 1 + (i + 1) % m, 1 + i] for i in range(m)])
            n = T[end] * sgn
            # choose winding matching the outward direction
            test = np.cross(Pc[I[0, 1]] - Pc[0], Pc[I[0, 2]] - Pc[0])
            if np.dot(test, n) < 0:
                I = I[:, ::-1]
            parts.append(Geom(Pc, I, np.tile(n, (len(Pc), 1)), np.zeros((len(Pc), 2))))
    return merge(parts)


def circle(r, n):
    n = seg(n, 4)
    th = np.linspace(0, 2 * np.pi, n + 1)[:-1]
    return np.stack([r * np.cos(th), r * np.sin(th)], -1)


def ellipse(a, b, n):
    n = seg(n, 4)
    th = np.linspace(0, 2 * np.pi, n + 1)[:-1]
    return np.stack([a * np.cos(th), b * np.sin(th)], -1)


def rounded_rect(w, h, r, n_corner=4):
    """Counter-clockwise rounded rectangle centred at the origin (w, h are full sizes)."""
    r = min(r, w / 2 * 0.999, h / 2 * 0.999)
    n_corner = seg(n_corner, 1)
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180),
                       (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n_corner + 1):
            a = np.radians(a0 + 90 * k / n_corner)
            pts.append([cx + r * np.cos(a), cy + r * np.sin(a)])
    return np.array(pts)


def tube(path, r, sides=10, caps=True):
    return sweep(path, circle(r, sides), caps=caps)


def box(size, center=(0, 0, 0)):
    """Axis-aligned box with flat-shaded faces."""
    h = np.asarray(size, dtype=np.float64) / 2
    c0 = np.asarray(center, dtype=np.float64)
    faces = []
    for axis in range(3):
        for sgn in (-1.0, 1.0):
            n = np.zeros(3)
            n[axis] = sgn
            ua, va = (axis + 1) % 3, (axis + 2) % 3
            du, dv = np.eye(3)[ua] * h[ua], np.eye(3)[va] * h[va]
            c = c0 + n * h[axis]
            P = np.array([c - du - dv, c + du - dv, c + du + dv, c - du + dv])
            I = np.array([[0, 1, 2], [0, 2, 3]])
            if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), n) < 0:
                I = I[:, ::-1]
            U, V = 2 * h[ua], 2 * h[va]
            faces.append(Geom(P, I, np.tile(n, (4, 1)), [[0, 0], [U, 0], [U, V], [0, V]]))
    return merge(faces)


def superellipsoid_box(size, e=0.25, nu=16, nv=10, center=(0, 0, 0)):
    """Smooth rounded box (superellipsoid); e -> 0 is a sharp box, 1 an ellipsoid."""
    a, b, c = np.asarray(size, dtype=np.float64) / 2
    nu, nv = seg(nu, 4), seg(nv, 3)
    u = np.linspace(-np.pi, np.pi, nu + 1)[:-1]
    v = np.linspace(-np.pi / 2, np.pi / 2, nv)
    U, V = np.meshgrid(u, v, indexing='ij')
    f = lambda w, m: np.sign(w) * np.abs(w) ** m
    P = np.stack([a * f(np.cos(V), e) * f(np.cos(U), e), b * f(np.cos(V), e) * f(np.sin(U), e), c * f(np.sin(V), e)], -1)
    P = P + np.asarray(center)
    uv = np.stack([U * (a + b), V * c], -1)
    return grid(P, uv, close_u=True)


def extrude(poly, h, z0=0.0, cap_top=True, cap_bottom=False):
    """Prism from a counter-clockwise 2D polygon (xy), from z0 to z0 + h, with sharp side edges."""
    poly = np.asarray(poly, dtype=np.float64)
    m = len(poly)
    sides = []
    for i in range(m):
        a, b = poly[i], poly[(i + 1) % m]
        P = np.array([[a[0], a[1], z0], [b[0], b[1], z0], [b[0], b[1], z0 + h], [a[0], a[1], z0 + h]])
        n = normalize(np.array([b[1] - a[1], -(b[0] - a[0]), 0.0]))
        L = np.linalg.norm(b - a)
        sides.append(Geom(P, [[0, 1, 2], [0, 2, 3]], np.tile(n, (4, 1)), [[0, 0], [L, 0], [L, h], [0, h]]))
    tri = earclip(poly)
    if cap_top:
        P = np.c_[poly, np.full(m, z0 + h)]
        sides.append(Geom(P, tri, np.tile([0, 0, 1.0], (m, 1)), poly.copy()))
    if cap_bottom:
        P = np.c_[poly, np.full(m, z0)]
        sides.append(Geom(P, tri[:, ::-1], np.tile([0, 0, -1.0], (m, 1)), poly.copy()))
    return merge(sides)


def earclip(poly):
    """Triangulate a simple 2D polygon (either winding); returns counter-clockwise triangles."""
    poly = np.asarray(poly, dtype=np.float64)
    n = len(poly)
    area = 0.5 * np.sum(poly[:, 0] * np.roll(poly[:, 1], -1) - np.roll(poly[:, 0], -1) * poly[:, 1])
    idx = list(range(n)) if area > 0 else list(range(n))[::-1]
    tris = []

    def inside(p, a, b, c):
        d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
        d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
        d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

    guard = 0
    while len(idx) > 3 and guard < 10 * n:
        guard += 1
        m = len(idx)
        best = None
        for k in range(m):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, b, c = poly[i0], poly[i1], poly[i2]
            cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cr <= 1e-14:
                continue
            if any(inside(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            # prefer the fattest ear to avoid slivers
            e = [np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c)]
            q = cr / (max(e) ** 2 + 1e-18)
            if best is None or q > best[0]:
                best = (q, k)
        if best is None:
            # degenerate remainder: fan it
            break
        k = best[1]
        m = len(idx)
        tris.append([idx[k - 1], idx[k], idx[(k + 1) % m]])
        idx.pop(k)
    if len(idx) >= 3:
        for k in range(1, len(idx) - 1):
            tris.append([idx[0], idx[k], idx[k + 1]])
    return np.array(tris, dtype=np.int64)


def planar_polygon(P3, normal, uv=None):
    """Triangulated flat polygon from ordered 3D points lying in a plane with the given outward normal."""
    P3 = np.asarray(P3, dtype=np.float64)
    n = normalize(normal)
    u = normalize(np.cross(n, [0, 0, 1.0]) if abs(n[2]) < 0.9 else np.cross(n, [1.0, 0, 0]))
    v = np.cross(n, u)
    p2 = np.stack([(P3 - P3[0]) @ u, (P3 - P3[0]) @ v], -1)
    tri = earclip(p2)
    return Geom(P3, tri, np.tile(n, (len(P3), 1)), p2 if uv is None else uv)


def naca_section(n=24, t=0.12, closed_te=True):
    """Symmetric NACA 4-digit section, unit chord, leading edge at x=0. Returns a closed loop
    (upper surface LE->TE, lower TE->LE) of 2n-2 points, cosine spaced."""
    beta = np.linspace(0, np.pi, n)
    x = 0.5 * (1 - np.cos(beta))
    a4 = -0.1036 if closed_te else -0.1015
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 + a4 * x ** 4)
    upper = np.stack([x, yt], -1)
    lower = np.stack([x[::-1], -yt[::-1]], -1)
    return np.vstack([upper[:-1], lower[:-1]])


def foil(stations, n_chord=20, t=0.12, tip_cap=True, root_cap=False):
    """Lofted foil. stations: list of (le_point(3), chord_dir(3), thick_dir(3), chord, t_over_c)
    from root to tip. Returns a closed surface (with a rounded tip cap)."""
    rows = []
    for le, cd, td, c, tc in stations:
        cd, td = normalize(cd), normalize(td)
        base = naca_section(n_chord, tc)
        rows.append(np.asarray(le)[None, :] + c * (base[:, 0, None] * cd[None, :] + base[:, 1, None] * td[None, :]))
    P = np.array(rows)  # (span, loop, 3)
    span = arclen(np.array([r.mean(0) for r in rows]))
    loop_s = arclen(np.vstack([rows[0], rows[0][:1]]))[:-1] / max(stations[0][3], 1e-6)
    uv = np.stack([np.broadcast_to(loop_s[None, :] * np.array([s[3] for s in stations])[:, None], P.shape[:2]),
                   np.broadcast_to(span[:, None], P.shape[:2])], -1)
    g = grid(P, uv, close_v=True)
    # make sure normals point outward (loop is upper LE->TE then lower: orientation depends on thick_dir)
    c0 = P[0].mean(0)
    if np.mean(np.sum((g.P[:len(rows[0])] - c0) * g.N[:len(rows[0])], -1)) < 0:
        g = g.flipped()
    parts = [g]
    if tip_cap:
        parts.append(_foil_cap(P[-1], outward=P[-1].mean(0) - P[-2].mean(0)))
    if root_cap:
        parts.append(_foil_cap(P[0], outward=P[0].mean(0) - P[1].mean(0)))
    return merge(parts)


def _foil_cap(loop, outward):
    """Close a foil end with a slightly domed cap (upper/lower points paired across the camber line)."""
    m = len(loop)
    half = m // 2
    upper = loop[:half + 1]
    lower = np.vstack([loop[half:], loop[:1]])[::-1]
    k = min(len(upper), len(lower))
    mid = 0.5 * (upper[:k] + lower[:k]) + normalize(outward) * 0.0
    th = np.linalg.norm(upper[:k] - lower[:k], axis=-1)
    dome = mid + normalize(outward) * (0.35 * th)[:, None]
    P = np.vstack([upper[:k], dome, lower[:k]])
    I = []
    for i in range(k - 1):
        a, b, c = i, k + i, 2 * k + i
        I += [[a, a + 1, b + 1], [a, b + 1, b], [b, b + 1, c + 1], [b, c + 1, c]]
    g = Geom(P, I)
    if np.mean(np.sum(g.N * normalize(outward), -1)) < 0:
        g = g.flipped()
    return g


def split_by_plane_z(g, z0):
    """Split a mesh at the horizontal plane z = z0; returns (below, above) with interpolated attributes."""
    P, I = g.P, g.I
    side = P[:, 2] >= z0
    attrs = [g.P, g.N, g.uv0, g.uv1]
    new_attr = [list(a) for a in attrs]
    edge_cache = {}

    def cut(i, j):
        key = (min(i, j), max(i, j))
        if key in edge_cache:
            return edge_cache[key]
        t = (z0 - P[i, 2]) / (P[j, 2] - P[i, 2])
        k = len(new_attr[0])
        for a, na in zip(attrs, new_attr):
            na.append(a[i] + t * (a[j] - a[i]))
        new_attr[0][-1] = np.array([*new_attr[0][-1][:2], z0])
        edge_cache[key] = k
        return k

    below, above = [], []
    for tri in I:
        s = side[tri]
        if s.all():
            above.append(tri)
            continue
        if not s.any():
            below.append(tri)
            continue
        # rotate so that the lone vertex is first
        lone = 0 if s.sum() in (1, 2) and (s.sum() == 1 and s[0] or s.sum() == 2 and not s[0]) else (
            1 if (s.sum() == 1 and s[1]) or (s.sum() == 2 and not s[1]) else 2)
        a, b, c = tri[lone], tri[(lone + 1) % 3], tri[(lone + 2) % 3]
        ab, ac = cut(a, b), cut(a, c)
        t1 = [a, ab, ac]
        q1, q2 = [ab, b, c], [ab, c, ac]
        if side[a]:
            above.append(t1)
            below += [q1, q2]
        else:
            below.append(t1)
            above += [q1, q2]
    NP = np.array(new_attr[0])
    NN = normalize(np.array(new_attr[1]))
    U0, U1 = np.array(new_attr[2]), np.array(new_attr[3])

    def build(tris):
        if not tris:
            return None
        tris = np.array(tris)
        used, inv = np.unique(tris, return_inverse=True)
        return Geom(NP[used], inv.reshape(-1, 3), NN[used], U0[used], U1[used])

    return build(below), build(above)


def mesh_volume(g):
    """Signed volume (divergence theorem) and centroid of a closed mesh."""
    a, b, c = g.P[g.I[:, 0]], g.P[g.I[:, 1]], g.P[g.I[:, 2]]
    v = np.einsum('ij,ij->i', a, np.cross(b, c)) / 6.0
    V = v.sum()
    C = ((a + b + c) / 4.0 * v[:, None]).sum(0) / V if abs(V) > 1e-12 else np.zeros(3)
    return V, C


def mesh_area(g):
    a, b, c = g.P[g.I[:, 0]], g.P[g.I[:, 1]], g.P[g.I[:, 2]]
    return 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=-1).sum()
