"""Attachment checks: every fitting must touch what it is fitted to.

The builders tag the pieces they make (`Part.add(..., tag=)`, `Part.extend(..., tag=)`, `Part.tag_all`) and record
each attachment as `Part.attach(piece, *hosts)`. `gaps()` measures, on the meshes as built, the smallest distance
from a piece to the nearest of its hosts: the piece's vertices and points along its edges (so a tube that passes
through a surface between two rings counts as touching) against the host triangles. A piece that touches or cuts
into its host has a gap of zero (to within the edge sampling, `STEP`).
"""
import numpy as np

STEP = 0.002        # edge sampling of the piece (m)
NEAR = 0.05         # only points and triangles within this of each other are measured exactly (m)
MAX_GAP = 0.005     # the largest allowed gap (m), tools/boatgen/README.md "Attachments"


def pieces(parts):
    """{tag: (points (n, 3), triangles (m, 3, 3))} over the given parts (a dict of Parts or an iterable)."""
    out = {}
    for part in (parts.values() if isinstance(parts, dict) else parts):
        for gs in part.slots.values():
            for g in gs:
                if g.tag is None:
                    continue
                P, T = out.setdefault(g.tag, ([], []))
                P.append(_edge_points(g))
                T.append(g.P[g.I])
    return {k: (np.vstack(P), np.vstack(T)) for k, (P, T) in out.items()}


def links(parts):
    """Every recorded attachment (piece, hosts), without repeats, in the order recorded."""
    seen, out = set(), []
    for part in (parts.values() if isinstance(parts, dict) else parts):
        for ln in part.links:
            if ln not in seen:
                seen.add(ln)
                out.append(ln)
    return out


def gaps(parts):
    """[(piece, hosts, gap in m)] for every attachment; a missing piece or host raises KeyError."""
    geo = pieces(parts)
    out = []
    for piece, hosts in links(parts):
        pts = geo[piece][0]
        best = min(gap(pts, geo[h][1]) for h in hosts)
        out.append((piece, hosts, best))
    return out


def gap(points, tris):
    """Smallest distance from any of the points to any of the triangles."""
    lo, hi = tris.min((0, 1)) - NEAR, tris.max((0, 1)) + NEAR
    near = np.all((points >= lo) & (points <= hi), axis=1)
    if not near.any():
        return float(_bbox_distance(points, tris))
    p = points[near]
    tlo, thi = tris.min(1), tris.max(1)
    plo, phi = p.min(0) - NEAR, p.max(0) + NEAR
    tsel = np.all((thi >= plo) & (tlo <= phi), axis=1)
    if not tsel.any():
        return float(_bbox_distance(points, tris))
    T = tris[tsel]
    best, k = np.inf, max(1, 500000 // len(T))
    for i in range(0, len(p), k):
        best = min(best, float(_point_tri_dist(p[i:i + k], T).min()))
    return best


def _bbox_distance(points, tris):
    a0, a1 = points.min(0), points.max(0)
    b0, b1 = tris.min((0, 1)), tris.max((0, 1))
    d = np.maximum(0.0, np.maximum(b0 - a1, a0 - b1))
    return max(np.linalg.norm(d), NEAR)


def _edge_points(g):
    """The vertices and points every STEP along the triangle edges."""
    E = np.vstack([g.I[:, [0, 1]], g.I[:, [1, 2]], g.I[:, [2, 0]]])
    E = np.unique(np.sort(E, axis=1), axis=0)
    a, b = g.P[E[:, 0]], g.P[E[:, 1]]
    n = np.maximum(1, np.ceil(np.linalg.norm(b - a, axis=1) / STEP).astype(int))
    reps = np.repeat(np.arange(len(E)), n - 1)
    if not len(reps):
        return g.P.copy()
    k = np.concatenate([np.arange(1, m) for m in n if m > 1])
    t = (k / np.repeat(n, n - 1))[:, None]
    return np.vstack([g.P, a[reps] + (b[reps] - a[reps]) * t])


def _point_tri_dist(p, T):
    """(n,) smallest distance from each point to the triangles T (m, 3, 3)."""
    A, B, C = T[:, 0], T[:, 1], T[:, 2]
    N = np.cross(B - A, C - A)
    nn = np.linalg.norm(N, axis=1)
    ok = nn > 1e-14
    Nu = N / np.where(ok, nn, 1.0)[:, None]
    P = p[:, None, :]
    # projection inside the triangle: the distance to the plane
    d_plane = np.abs(np.einsum("nmk,mk->nm", P - A[None], Nu))
    Pp = P - np.einsum("nmk,mk->nm", P - A[None], Nu)[..., None] * Nu[None]
    inside = np.ones(d_plane.shape, bool)
    for U, V in ((A, B), (B, C), (C, A)):
        inside &= np.einsum("nmk,mk->nm", np.cross(V - U, Pp - U[None]), N) >= 0
    inside &= ok[None]
    d = np.where(inside, d_plane, np.inf)
    # otherwise the nearest edge
    for U, V in ((A, B), (B, C), (C, A)):
        e = V - U
        ee = np.maximum(np.einsum("mk,mk->m", e, e), 1e-30)
        t = np.clip(np.einsum("nmk,mk->nm", P - U[None], e) / ee, 0, 1)
        X = U[None] + t[..., None] * e[None]
        d = np.minimum(d, np.linalg.norm(P - X, axis=-1))
    return d.min(1)
