"""Douglas-Peucker simplification of land rings with a tolerance that depends on where a vertex lies, and the
polygon checks of data_format.md §6.5 (simple, counter-clockwise) done on the binary32 values the core reads."""

from __future__ import annotations

import numpy as np

from .geo import signed_area


def _seg_dist(p, a, b):
    d = b - a
    L2 = float(d[0] * d[0] + d[1] * d[1])
    if L2 == 0.0:
        return np.hypot(p[:, 0] - a[0], p[:, 1] - a[1])
    t = np.clip(((p[:, 0] - a[0]) * d[0] + (p[:, 1] - a[1]) * d[1]) / L2, 0.0, 1.0)
    q = a + t[:, None] * d
    return np.hypot(p[:, 0] - q[:, 0], p[:, 1] - q[:, 1])


def douglas_peucker_ring(p, tol, fixed=None):
    """Indices kept of the closed ring p (n, 2): a vertex is dropped when it lies within tol[i] of the chord
    that replaces it. `fixed` marks vertices that are always kept (the clip box corners and crossings)."""
    n = len(p)
    if n <= 3:
        return np.arange(n)
    keep = np.zeros(n, bool)
    if fixed is not None:
        keep |= fixed
    # anchors: vertex 0 and the vertex farthest from it, plus every fixed vertex
    far = int(np.argmax(np.hypot(p[:, 0] - p[0, 0], p[:, 1] - p[0, 1])))
    keep[0] = keep[far] = True
    anchors = np.flatnonzero(keep)
    stack = [(anchors[k], anchors[(k + 1) % len(anchors)]) for k in range(len(anchors))]
    while stack:
        i, j = stack.pop()
        idx = np.arange(i + 1, j if j > i else j + n) % n
        if len(idx) == 0:
            continue
        d = _seg_dist(p[idx], p[i], p[j])
        excess = d - tol[idx]
        m = int(np.argmax(excess))
        if excess[m] > 0.0:
            k = int(idx[m])
            keep[k] = True
            stack.append((i, k))
            stack.append((k, j))
    out = np.flatnonzero(keep)
    if len(out) < 3:
        # keep a triangle: the two anchors and the vertex farthest from their chord
        d = _seg_dist(p, p[0], p[far])
        out = np.unique([0, far, int(np.argmax(d))])
    return out


def _orient(a, b, c):
    return np.sign((b[..., 0] - a[..., 0]) * (c[..., 1] - a[..., 1]) - (b[..., 1] - a[..., 1]) * (c[..., 0] - a[..., 0]))


def simple_problem(p):
    """None when the closed polygon is simple (data_format.md §6.5, the core's check), else a reason. Works on
    the values as given; callers pass binary32-rounded points."""
    p = np.asarray(p, float)
    n = len(p)
    if n < 3:
        return "fewer than 3 points"
    q = np.roll(p, -1, axis=0)
    if np.any(np.all(p == q, axis=1)):
        return "two consecutive points are equal"
    r = np.roll(p, -2, axis=0)
    dot = np.sum((q - p) * (r - q), axis=1)
    if np.any((_orient(p, q, r) == 0) & (dot < 0)):
        return "polygon folds back on itself"
    # all pairs of non-adjacent edges, in blocks
    A, B = p, q
    for i0 in range(0, n, 256):
        i = np.arange(i0, min(n, i0 + 256))[:, None]
        k = np.arange(n)[None, :]
        valid = (k >= i + 2) & ~((i == 0) & (k == n - 1))
        if not valid.any():
            continue
        a, b = A[i[:, 0]][:, None, :], B[i[:, 0]][:, None, :]
        c, d = A[None, :, :], B[None, :, :]
        o1, o2 = _orient(a, b, c), _orient(a, b, d)
        o3, o4 = _orient(c, d, a), _orient(c, d, b)
        proper = (o1 != o2) & (o3 != o4) & (o1 != 0) & (o2 != 0) & (o3 != 0) & (o4 != 0)

        def on_seg(s0, s1, t):
            return ((np.minimum(s0[..., 0], s1[..., 0]) <= t[..., 0]) & (t[..., 0] <= np.maximum(s0[..., 0], s1[..., 0]))
                    & (np.minimum(s0[..., 1], s1[..., 1]) <= t[..., 1]) & (t[..., 1] <= np.maximum(s0[..., 1], s1[..., 1])))

        touch = ((o1 == 0) & on_seg(a, b, c)) | ((o2 == 0) & on_seg(a, b, d)) | ((o3 == 0) & on_seg(c, d, a)) | \
                ((o4 == 0) & on_seg(c, d, b))
        if np.any((proper | touch) & valid):
            return "edges intersect"
    return None


def as_written(p, decimals=1):
    """The points as written to the file (rounded to 0.1 m)."""
    return np.round(np.asarray(p, float), decimals)


def as_read(p):
    """The points as the core reads them (binary32)."""
    return np.asarray(p, float).astype(np.float32).astype(np.float64)


def simplify_ring(p, tol, fixed):
    """Simplified ring, halving the tolerances until the written polygon is simple and keeps its orientation."""
    t = tol.copy()
    for _ in range(12):
        idx = douglas_peucker_ring(p, t, fixed)
        q = as_written(p[idx])
        keep = np.ones(len(q), bool)
        keep[1:] = np.any(q[1:] != q[:-1], axis=1)
        q = q[keep]
        if len(q) > 1 and np.all(q[0] == q[-1]):
            q = q[:-1]
        if len(q) >= 3 and signed_area(as_read(q)) > 0 and simple_problem(as_read(q)) is None:
            return q
        t = t * 0.5
    q = as_written(p)
    return q
