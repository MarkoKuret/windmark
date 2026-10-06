"""Clip coastline paths (land on the left) to a rectangle and close them into simple land polygons.

Each path is cut into the chains that run inside the box, from an entry point on the box edge to an exit point.
Walking the box edge counter-clockwise from an exit (the box interior, and so the land, on the left) reaches
the entry of the next chain of the same land polygon, which links the chains into closed counter-clockwise
rings. Paths wholly inside the box stay as they are. This handles land polygons, water bodies (a lake: the
land is on the left of its reversed outline) and open shore lines in one way, as long as the inputs agree
about which side is land.
"""

from __future__ import annotations

import numpy as np

from .geo import InputError, signed_area

# The box is nudged by these odd amounts so no input vertex lies exactly on its edge (no degenerate crossings).
_NUDGE = (-1.234567e-4, -2.345678e-4, 3.456789e-4, 4.567891e-4)


def _inside(p, box):
    return (p[:, 0] > box[0]) & (p[:, 0] < box[2]) & (p[:, 1] > box[1]) & (p[:, 1] < box[3])


def _clip_segment(a, b, box):
    """Liang-Barsky: the parameter range [t0, t1] of a->b inside the box, or None."""
    t0, t1 = 0.0, 1.0
    d = b - a
    for p, q in ((-d[0], a[0] - box[0]), (d[0], box[2] - a[0]), (-d[1], a[1] - box[1]), (d[1], box[3] - a[1])):
        if p == 0.0:
            if q < 0.0:
                return None
            continue
        r = q / p
        if p < 0.0:
            if r > t1:
                return None
            t0 = max(t0, r)
        else:
            if r < t0:
                return None
            t1 = min(t1, r)
    return (t0, t1) if t0 < t1 else None


def _perimeter(q, box):
    """Counter-clockwise perimeter parameter of a point on the box edge, from (xmin, ymin)."""
    w, h = box[2] - box[0], box[3] - box[1]
    d = (abs(q[1] - box[1]), abs(q[0] - box[2]), abs(q[1] - box[3]), abs(q[0] - box[0]))
    e = int(np.argmin(d))
    if e == 0:
        return q[0] - box[0]
    if e == 1:
        return w + (q[1] - box[1])
    if e == 2:
        return w + h + (box[2] - q[0])
    return 2 * w + h + (box[3] - q[1])


def _corners(box):
    w, h = box[2] - box[0], box[3] - box[1]
    return [(0.0, (box[0], box[1])), (w, (box[2], box[1])), (w + h, (box[2], box[3])),
            (2 * w + h, (box[0], box[3]))]


def _chains(path, box):
    """Chains of one path inside the box: list of point lists, each starting and ending on the box edge; or
    the whole closed path when it lies inside; or [] when it misses the box."""
    p = path["points"]
    closed = path["closed"]
    ins = _inside(p, box)
    if closed and ins.all():
        return "inside", []
    n = len(p)
    if closed:
        start = int(np.argmin(ins))  # an outside vertex
        order = [(start + k) % n for k in range(n)] + [start]
    else:
        if ins[0] or ins[-1]:
            raise InputError("an open shore line ends inside the clip box; extend it beyond the box")
        order = list(range(n))
    chains, cur = [], None
    for k in range(len(order) - 1):
        a, b = p[order[k]], p[order[k + 1]]
        r = _clip_segment(a, b, box)
        if r is None:
            continue
        t0, t1 = r
        if cur is None:
            cur = [a + t0 * (b - a)]
        if t1 < 1.0:
            cur.append(a + t1 * (b - a))
            chains.append(cur)
            cur = None
        else:
            cur.append(b.copy())
    if cur is not None:
        raise InputError("internal: unterminated chain")
    return "chains", chains


def _point_in_ring(q, ring):
    x, y = ring[:, 0], ring[:, 1]
    x2, y2 = np.roll(x, -1), np.roll(y, -1)
    c = ((y > q[1]) != (y2 > q[1])) & (q[0] < (x2 - x) * (q[1] - y) / np.where(y2 == y, 1, y2 - y) + x)
    return bool(np.count_nonzero(c) % 2)


def clip_to_box(paths, box):
    """Land polygons (list of dicts with "points" CCW, "height", "id") of `paths` inside `box`."""
    box = (box[0] + _NUDGE[0], box[1] + _NUDGE[1], box[2] + _NUDGE[2], box[3] + _NUDGE[3])
    rings, holes, chains = [], [], []
    has_water = any(pa["closed"] and signed_area(pa["points"]) < 0 for pa in paths)
    for pa in paths:
        kind, cs = _chains(pa, box)
        if kind == "inside":
            if signed_area(pa["points"]) > 0:
                rings.append({"points": pa["points"].copy(), "height": pa.get("height"), "id": pa.get("id")})
            else:
                holes.append(pa)
        for c in cs:
            chains.append({"points": c, "height": pa.get("height")})
    if holes:
        # Land around a water body wholly inside the box is not one simple polygon: split the box through the
        # first such water body and clip each half (the water body then crosses both halves' edges).
        cx = float(np.mean(holes[0]["points"][:, 0]))
        left = clip_to_box(paths, (box[0] - _NUDGE[0], box[1] - _NUDGE[1], cx, box[3] - _NUDGE[3]))
        right = clip_to_box(paths, (cx, box[1] - _NUDGE[1], box[2] - _NUDGE[2], box[3] - _NUDGE[3]))
        return left + right

    if not chains:
        corner = np.array([box[0], box[1]])
        wind = sum((1 if signed_area(pa["points"]) > 0 else -1) for pa in paths
                   if pa["closed"] and _point_in_ring(corner, pa["points"]))
        if wind + (1 if has_water else 0) > 0:
            rings.insert(0, {"points": np.array([c for _, c in _corners(box)], float), "height": None,
                             "id": None})
        return rings

    events = []
    for i, c in enumerate(chains):
        c["pin"] = _perimeter(c["points"][0], box)
        c["pout"] = _perimeter(c["points"][-1], box)
        events.append((c["pin"], 0, i))
        events.append((c["pout"], 1, i))
    events.sort()
    perim = 2 * ((box[2] - box[0]) + (box[3] - box[1]))
    corners = _corners(box)
    used = [False] * len(chains)
    for s in range(len(chains)):
        if used[s]:
            continue
        pts, heights, i = [], [], s
        while True:
            used[i] = True
            c = chains[i]
            pts.extend(c["points"])
            heights.append(c["height"])
            pout = c["pout"]
            k = next((e for e in events if e[0] > pout), events[0])
            if k[1] != 0:
                raise InputError("coastline sides disagree at the clip box edge (check role / land_side)")
            nxt = k[2]
            pin = chains[nxt]["pin"]
            span = (pin - pout) % perim
            for cp, cc in sorted(corners, key=lambda t: (t[0] - pout) % perim):
                if 0 < (cp - pout) % perim < span:
                    pts.append(np.array(cc, float))
            if nxt == s:
                break
            if used[nxt]:
                raise InputError("coastline chains do not close (check role / land_side)")
            i = nxt
        p = np.array(pts, float)
        keep = np.ones(len(p), bool)
        keep[1:] = np.any(np.abs(p[1:] - p[:-1]) > 1e-9, axis=1)
        p = p[keep]
        if len(p) > 1 and np.all(np.abs(p[0] - p[-1]) <= 1e-9):
            p = p[:-1]
        if len(p) >= 3 and signed_area(p) > 0:
            hs = [h for h in heights if h]
            rings.append({"points": p, "height": max(hs) if hs else None, "id": None})
    return rings
