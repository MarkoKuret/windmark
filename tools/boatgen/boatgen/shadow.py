"""The shadow proxy (docs/specs/sail_visuals.md 11.4): the few hundred triangles the game casts the boat's sun shadows
from, while the drawn model casts none.

It only casts where the drawn boat would, and never onto the boat's own lit faces: every face lies at least INSET
(hull, deck, cockpit, coachroof) or INSET_SPAR (mast, boom, rudder, a side) inside the drawn surfaces, so none is
coplanar with or above a drawn surface. A coplanar caster shades its receiver in facets that crawl as the boat moves
against the shadow map's texels, worst with the coarse maps and hard filter of the low tiers.

- Hull: the hull's stations, each section moved INSET inward (mitred at the chine), the stations pulled INSET in from
  the transom and back from the stem to where the bow is 3 INSET wide a side (`bow_setback`), the sheer point INSET in
  from the deck edge and INSET under the deck. Under the cockpit nothing of it rises above the cockpit's floor proxy:
  near an open transom the drawn floor lies close over the bottom, and the bottom (which looks down, away from the
  sun) gives way to the lit floor.
- Deck: the deck surface INSET lower, open over the cockpit: its edge stands INSET back from the cockpit's sides and
  forward end, walls go down from there to a floor INSET under the cockpit floor (the wheel well stays shaded under
  it). The cockpit then takes the shadows of its coamings and of the coachroof, mast, boom and sails, nothing else.
- Coachroof: per station its section inset: the deck, raked side and top lines each moved INSET inward and met at
  their corners (at the convex top edge also held under the eroded surface), its aft face INSET forward of the drawn
  one, down to the cockpit's floor.
- Transom: a face INSET forward of the drawn one, closing hull and deck into one shell, so the hull's shadow on the
  sea has no holes (the shadow pass culls back faces).
- Mast and boom: their sections shrunk INSET_SPAR a side; the rudder (only one that stands above the waterline) its
  pieces shrunk toward their middles, under the rudder node so it turns with the helm. The keel, bulb and a spade
  rudder stay under the water and are left out; fittings, rigging and lines too (thin casters break up into
  crawling dashes in a coarse shadow map).
"""
import numpy as np

from .mesh import Geom, Part, grid, planar_polygon, sweep, rounded_rect, normalize, segment_scale

INSET = 0.04          # m: hull, deck, cockpit and coachroof faces inside the drawn surfaces
INSET_SPAR = 0.012    # m: mast, boom and rudder shrunk by this a side toward their axes
N_STATIONS = 12       # hull and deck stations
N_CABIN = 10          # coachroof stations
ROW_COCKPIT = 0.4     # m: the cockpit's floor, walls and side decks have a row at least this often (the sheer's
                      # rise must not lift a chord through the inset)
RUDDER_ABOVE = 0.05   # m: a rudder whose blade reaches this far above the DWL casts (a transom-hung one)


def proxy(boat):
    """(static, boom, rudder): the static proxy (`shadow`: hull, deck, cockpit, coachroof, transom, mast), the boom's
    (`shadow_boom`) and the rudder's (`shadow_rudder`, empty for a rudder under the water), boat frame, in the
    material `shadow`."""
    static, boom, rudder = Part(), Part(), Part()
    for g in hull_and_deck(boat.hull, boat.deck):
        static.add("shadow", g)
    static.add("shadow", mast(boat.rig))
    boom.add("shadow", boom_geom(boat.rig))
    for g in rudder_geoms(boat):
        rudder.add("shadow", g)
    return static, boom, rudder


# ---------------------------------------------------------------------------------------------------------------
# hull and deck

def bow_setback(hull, m=INSET):
    """How far aft of the stem the proxy hull ends (m): where the hull's section is first 3 m wide a side, so the
    stem's line (the bow's last section, on the centreline) sits that far inside the drawn bow."""
    for d in np.arange(m, 0.25 * hull.L, 0.01):
        y, _, _ = hull.station(float(hull.L - d), 4, 3)
        if float(np.max(y)) >= 3 * m:
            return float(d)
    return 0.25 * hull.L


def _x_in(x, L, m=INSET, bow=None):
    """A hull station's x pulled in from the transom (x = 0) by m and from the stem (x = L) by `bow` (default m)."""
    bow = m if bow is None else bow
    return m + np.asarray(x, dtype=np.float64) * (L - bow - m) / L


def _inset_polyline(P, m):
    """A section polyline from the keel (y = 0) out and up to the sheer, (n, 2) as (y, z), moved m inward: each vertex
    along the bisector of its segments' outward normals, mitred so both faces stay m away; y kept >= 0."""
    d = np.diff(P, axis=0)
    ln = np.linalg.norm(d, axis=1)
    n = np.zeros_like(d)
    ok = ln > 1e-9
    n[ok] = np.stack([d[ok, 1], -d[ok, 0]], -1) / ln[ok, None]    # tangent (dy, dz) -> outward (dz, -dy)
    for i in range(len(n)):                                       # a collapsed segment takes its neighbour's
        if not ok[i]:
            n[i] = n[i - 1] if i > 0 else np.array([0.0, -1.0])
    before = np.vstack([[-n[0, 0], n[0, 1]], n])                  # at the keel the mirror image of the first
    after = np.vstack([n, n[-1:]])
    b = before + after
    bl = np.linalg.norm(b, axis=1)
    b = np.where(bl[:, None] > 1e-9, b / np.maximum(bl, 1e-9)[:, None], after)
    c = np.maximum(np.sum(b * after, 1), 0.25)
    Q = P - b * (m / c)[:, None]
    Q[:, 0] = np.maximum(Q[:, 0], 0.0)
    return Q


def _cockpit_frame(deck, m=INSET):
    """(x0, x1, yo(x), zf(x)): the proxy's cockpit opening, m larger than the drawn one at its ends (an open
    transom from x = m) and its sides m back, and its floor m under the drawn floor."""
    x0 = m if deck.xc0 <= m + 1e-6 else deck.xc0 - m
    return (x0, deck.xc1 + m, lambda x: float(deck.yc(x)) + m, lambda x: float(deck.floor_z(x)) - m)


def hull_section(hull, deck, x, nb=4, nt=3, m=INSET, bow=None):
    """The proxy's port section at hull station x (keel to sheer, (n, 3) boat frame), placed at the pulled-in x. It
    carries a point where the cockpit's proxy wall comes down, and nothing of it rises above the deck lowered by m
    or, under the cockpit, above the proxy's cockpit floor (where the drawn floor lies close over the bottom, near
    an open transom, the bottom, which faces away from the sun, gives way to the lit floor)."""
    xi = float(_x_in(x, hull.L, m, bow))
    y, z, _ = hull.station(float(x), nb, nt)
    P = np.stack([y, z], -1)
    if float(np.max(y)) < 1e-3:              # the stem: a line on the centreline, its ends pulled in
        Q = np.stack([np.zeros_like(z), np.clip(z, z.min() + m, z.max() - m)], -1)
    else:
        Q = _inset_polyline(P, m)
    ye = max(float(hull.bs(np.array([xi]))[0]) - m, 0.0)
    ze = float(deck.deck_z(xi, ye)) - m
    hb = hull.half_breadth_at(xi, ze)
    if hb > 0.0:
        ye = max(min(ye, hb - m), 0.0)       # a deck edge wider than the topsides just under it
    Q[-1] = [ye, ze]
    x0, x1, yo, zf = _cockpit_frame(deck, m)
    yw = yo(xi)
    k = next((i for i in range(1, len(Q)) if Q[i - 1, 0] < yw <= Q[i, 0]), None)
    if k is None:
        Q = np.insert(Q, len(Q) - 1, Q[-2], axis=0)       # no crossing (the bow): a collapsed point
    else:
        t = (yw - Q[k - 1, 0]) / max(Q[k, 0] - Q[k - 1, 0], 1e-12)
        Q = np.insert(Q, k, Q[k - 1] + t * (Q[k] - Q[k - 1]), axis=0)
    Q[:, 1] = np.minimum(Q[:, 1], np.asarray(deck.deck_z(xi, Q[:, 0])) - m)
    if x0 - 1e-9 <= xi <= x1 + 1e-9:
        under = Q[:, 0] <= yw + 1e-9
        Q[under, 1] = np.minimum(Q[under, 1], zf(xi) - 0.005)
    return np.column_stack([np.full(len(Q), xi), Q])


def _orient_away(g, center):
    """Flip a surface so its normals point away from `center(P)` on the whole."""
    if np.sum(np.sum(g.N * (g.P - center(g.P)), 1)) < 0:
        return g.flipped()
    return g


def _orient(g, want):
    if np.mean(g.N @ np.asarray(want, dtype=np.float64)) < 0:
        return g.flipped()
    return g


def _face(P, want):
    """A grid (rows, cols, 3) facing `want`."""
    return _orient(grid(np.asarray(P, dtype=np.float64)), want)


def hull_and_deck(hull, deck, m=INSET):
    """The hull, deck, cockpit, coachroof and transom of the proxy: one closed shell open over the cockpit."""
    out = []
    xs = hull.stations_x(N_STATIONS)
    bow = bow_setback(hull, m)
    secs = np.stack([hull_section(hull, deck, x, m=m, bow=bow) for x in xs])          # (stations, points, 3), port
    zc = 0.5 * (secs[..., 2].min() + secs[..., 2].max())
    port = _orient_away(grid(secs), lambda P: np.column_stack([P[:, 0], np.zeros(len(P)), np.full(len(P), zc)]))
    out += [port, port.mirrored_y()]

    xi = secs[:, 0, 0]                                     # the pulled-in stations
    edge = lambda x: float(np.interp(x, xi, secs[:, -1, 1]))   # the deck edge: the proxy hull's sheer
    dz = lambda x, y: np.asarray(deck.deck_z(x, y), dtype=np.float64) - m
    open_transom = deck.xc0 <= m + 1e-6
    x_ck0, x_ck1, yo, zf = _cockpit_frame(deck, m)
    for x in (x_ck0, x_ck1):
        if edge(x) - yo(x) < 0.02:
            raise ValueError(f"side deck at x = {x:.2f} m is too narrow for the shadow proxy's inset "
                             f"({2 * m:.2f} m): visual.deck.cockpit.width (data_format.md 3.7.2)")

    def rows(a, b, step=None):
        """The pulled-in hull stations between a and b and both ends, with `step` at least every step metres."""
        extra = np.linspace(a, b, int(np.ceil((b - a) / step)) + 1) if step else []
        r = np.unique(np.concatenate([xi[(xi > a + 1e-6) & (xi < b - 1e-6)], [a, b], extra]))
        return r[(r >= a - 1e-9) & (r <= b + 1e-9)]

    def strip(xr, ya, yb, n):
        """Deck lowered by m over rows xr from ya(x) to yb(x) across in n columns, facing up."""
        P = []
        for x in xr:
            ys = np.linspace(ya(x), yb(x), n)
            P.append(np.column_stack([np.full(n, x), ys, dz(x, ys)]))
        return _face(np.stack(P), [0, 0, 1])

    # the deck: aft of the cockpit, beside it, forward of it
    if not open_transom and x_ck0 > m + 0.02:
        out.append(strip(rows(m, x_ck0), lambda x: -edge(x), edge, 5))
    rb = rows(x_ck0, x_ck1, ROW_COCKPIT)
    for s in (1.0, -1.0):
        out.append(strip(rb, lambda x, s=s: s * yo(x), lambda x, s=s: s * edge(x), 3))
    cab_rows = np.linspace(deck.xk0 + m, deck.xk1, N_CABIN) if deck.has_cabin else np.zeros(0)
    out.append(strip(rows(x_ck1, float(xi[-1])), lambda x: -edge(x), edge, 5))

    # the cockpit: side walls, floor, aft wall, forward wall (with the coachroof's aft face above it)
    for s in (1.0, -1.0):
        P = [[[x, s * yo(x), zf(x)], [x, s * yo(x), float(dz(x, yo(x)))]] for x in rb]
        out.append(_face(P, [0, -s, 0]))
    P = [np.column_stack([np.full(3, x), np.linspace(-yo(x), yo(x), 3), np.full(3, zf(x))]) for x in rb]
    out.append(_face(np.stack(P), [0, 0, 1]))
    if not open_transom:
        x = x_ck0
        ys = np.linspace(-yo(x), yo(x), 3)
        out.append(_face([np.column_stack([np.full(3, x), ys, np.full(3, zf(x))]),
                          np.column_stack([np.full(3, x), ys, dz(x, ys)])], [1, 0, 0]))
    sec0 = cabin_section(deck, x_ck1, m) if deck.has_cabin else None
    ys = np.linspace(-yo(x_ck1), yo(x_ck1), 7)
    tz = dz(x_ck1, ys)
    if sec0 is not None:
        out_deck = np.abs(ys) > sec0[-1, 0] + 0.01
        ys = np.concatenate([ys[out_deck], sec0[:, 0]])
        tz = np.concatenate([tz[out_deck], sec0[:, 1]])
        o = np.argsort(ys)
        ys, tz = ys[o], tz[o]
    n = len(ys)
    out.append(_face([np.column_stack([np.full(n, x_ck1), ys, np.full(n, zf(x_ck1))]),
                      np.column_stack([np.full(n, x_ck1), ys, tz])], [-1, 0, 0]))

    # the coachroof
    if deck.has_cabin:
        sec = []
        for x in cab_rows:
            s = cabin_section(deck, x, m)
            if s is None:
                break
            sec.append(np.column_stack([np.full(len(s), x), s]))
        if len(sec) >= 2:
            out.append(_face(np.stack(sec), [0, 0, 1]))

    # the transom face, closing the shell
    ring = secs[0]                                         # port, keel -> sheer, at x = m
    x0 = float(ring[0, 0])
    pts = [list(p * [1, -1, 1]) for p in ring[::-1]] + [list(p) for p in ring[1:]]
    ye = float(ring[-1, 1])
    if open_transom:
        yy = np.linspace(ye, yo(x0), 5)[1:]
        pts += [[x0, y, float(dz(x0, y))] for y in yy]
        pts += [[x0, yo(x0), zf(x0)], [x0, -yo(x0), zf(x0)]]
        pts += [[x0, -y, float(dz(x0, y))] for y in yy[::-1]]
    else:
        yy = np.linspace(ye, -ye, 9)[1:-1]
        pts += [[x0, y, float(dz(x0, y))] for y in yy]
    pts = np.array(pts)
    keep = np.r_[True, np.linalg.norm(np.diff(pts, axis=0), axis=1) > 1e-6]
    pts = pts[keep]
    if np.linalg.norm(pts[0] - pts[-1]) < 1e-6:
        pts = pts[:-1]
    out.append(planar_polygon(pts, [-1, 0, 0]))
    return [g for g in out if g is not None and len(g.I)]


# ---------------------------------------------------------------------------------------------------------------
# coachroof

def eroded_surface(deck, x, y, m=INSET, n=9):
    """The walking surface eroded by a ball of radius m (arrays of points): the highest z at (x, y) whose ball stays
    under the surface, so a point at or under it is at least m from it."""
    x, y = np.broadcast_arrays(np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64))
    t = np.linspace(-m, m, n)
    DX, DY = np.meshgrid(t, t, indexing="ij")
    r2 = DX ** 2 + DY ** 2
    keep = r2 <= m * m + 1e-12
    DX, DY, DZ = DX[keep], DY[keep], np.sqrt(np.maximum(m * m - r2[keep], 0.0))
    Z = deck.surface_z(x[..., None] + DX, y[..., None] + DY) - DZ
    return Z.min(-1)


def _offset_line(a, b, m):
    """The line through a -> b ((y, z) points, running inward toward the centreline) moved m along its outward
    normal into the solid: (point, direction)."""
    t = normalize(np.asarray(b, dtype=np.float64) - a)
    nrm = np.array([t[1], -t[0]])
    return np.asarray(a, dtype=np.float64) - m * nrm, t


def _meet(l1, l2):
    (p, u), (q, v) = l1, l2
    det = u[0] * -v[1] - u[1] * -v[0]
    if abs(det) < 1e-9:
        return None
    s = ((q - p)[0] * -v[1] - (q - p)[1] * -v[0]) / det
    return p + s * u


def cabin_section(deck, x, m=INSET):
    """The coachroof's inset section at station x: (5, 2) points (y, z) from starboard to port (the corner with the
    deck, the top edge, the centreline, then port), or None where the top stands less than 1.5 m high (the deck
    under it carries the shadow there)."""
    x = float(x)
    h = float(deck.cab_height(np.array([x]))[0])
    yb = float(deck.yk(np.array([x]))[0])
    if h < 1.5 * m or yb < 3 * m:
        return None
    pr = deck._cab_prof(np.array([h]), np.array([yb]))
    q, d1, d2, d3 = (float(pr[k][0]) for k in ("q", "d1", "d2", "d3"))
    f = lambda y: float(deck.cabin_z(x, y))
    y1, y2, y3 = yb - d1 / q, yb - d2 / q, yb - d3 / q
    ya = yb + 0.2
    deck_l = _offset_line((ya, float(deck.deck_z(x, ya))), (yb, float(deck.deck_z(x, yb))), m)
    if y1 - y2 > 1e-3:
        side_l = _offset_line((y1, f(y1)), (y2, f(y2)), m)
    else:
        side_l = _offset_line((yb, f(yb)), (y3, f(y3)), m)
    top_l = _offset_line((y3, f(y3)), (0.0, f(0.0)), m)
    q1, q2 = _meet(deck_l, side_l), _meet(side_l, top_l)
    c = _meet(top_l, (np.array([0.0, 0.0]), np.array([0.0, 1.0])))
    if q1 is None or q2 is None or c is None or not (q1[0] > q2[0] > 0.0):
        return None
    half = np.array([q1, q2, c])
    half[:, 1] = np.minimum(half[:, 1], eroded_surface(deck, x, half[:, 0], m))
    return np.array([[-half[0, 0], half[0, 1]], [-half[1, 0], half[1, 1]], half[2], half[1], half[0]])


# ---------------------------------------------------------------------------------------------------------------
# spars and rudder

def mast(rig, ms=INSET_SPAR, m=INSET):
    """The mast: its section shrunk ms a side, from m under the deck at its foot to ms under the masthead, tapering
    above the hounds as the drawn mast does."""
    from .rig import _mast_section
    zs = np.array([rig.z_step - m, rig.z_hounds, rig.z_top - ms])
    path = np.column_stack([np.full(3, rig.x_mast), np.zeros(3), zs])
    prof = _mast_section(rig.chord - 2 * ms, rig.width - 2 * ms, 8)
    return sweep(path, prof, scale_along=rig.taper(zs), up=np.array([1.0, 0, 0]), max_seg=1e9)


def boom_geom(rig, ms=INSET_SPAR):
    """The boom (boat frame, rest position): its section shrunk ms a side, ms in from each end, tapering aft as the
    drawn boom does."""
    s = rig.scale
    ln = rig.boom_len
    t = np.array([ms / ln, 0.5, 1.0 - ms / ln])
    g0 = np.asarray(rig.gooseneck, dtype=np.float64)
    path = np.column_stack([g0[0] - t * ln, np.zeros(3), np.full(3, g0[2])])
    depth, width = 0.17 * s - 2 * ms, 0.085 * s - 2 * ms
    with segment_scale(1.0):
        prof = rounded_rect(depth, width, max(0.03 * s - ms, 0.004), 1)
    return sweep(path, prof, scale_along=1.0 - 0.25 * t ** 2, up=np.array([0, 0, 1.0]), max_seg=1e9)


def rudder_geoms(boat, ms=INSET_SPAR):
    """The rudder's blade and head, each shrunk toward its middle by ms a side (at least to 0.3 of its size), when
    the blade stands above the waterline; none for a rudder under the water."""
    from .appendages import Appendages
    with segment_scale(0.1):
        app = Appendages(boat.cls, boat.hull)
        st = app.rud_stations
        app.rud_stations = st[:-1:4] + st[-1:]            # every fourth station of a finely drawn blade, and the tip
        rp = app.rudder_part(n_chord=3)
    pieces = [g for gs in rp.slots.values() for g in gs if (g.tag or "") in ("rudder", "rudder_head")]
    blade = [g for g in pieces if g.tag == "rudder"]
    if not blade or max(float(g.P[:, 2].max()) for g in blade) < RUDDER_ABOVE:
        return []
    out = []
    for g in pieces:
        lo, hi = g.P.min(0), g.P.max(0)
        c, e = 0.5 * (lo + hi), hi - lo
        k = np.maximum((e - 2 * ms) / np.maximum(e, 1e-9), 0.3)
        out.append(Geom(c + (g.P - c) * k, g.I.copy()))
    return out
