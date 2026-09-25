"""Deck, cockpit, cabin top, transom face and the trim along the sheer.

Deck plan: the deck is a cambered surface between the two sheer lines,
    z = zs(x) + camber(x) * (1 - (y / bs(x))^2),   camber = deck_camber * 2 bs(x).
The cockpit is a rectangular well in (x, y / bs) running aft to an open transom; the cabin top sits directly
forward of it with a plan outline that rounds in to the centreline at its front, sides leaning inward.

The deck is meshed as an outer strip on each side from the sheer to the cockpit / cabin outline, which is
continued by the centreline forward of the cabin. The cabin is a separate closed-looking shell whose base sits
slightly below the deck, so the two never show a crack.
"""
import numpy as np

from .mesh import (Geom, Part, grid, planar_polygon, normalize, arclen, sweep, rounded_rect, box,
                   superellipsoid_box, merge, resample_polyline)


class Deck:
    def __init__(self, cls, hull):
        self.cls, self.hull = cls, hull
        d = cls["deck"]
        L = hull.L
        self.camber_k = float(cls["hull"]["deck_camber"])
        ck = d["cockpit"]
        self.xc0 = float(ck.get("aft_deck", 0.0))
        self.xc1 = self.xc0 + float(ck["length"])
        self.ck_frac = float(ck["width"])
        self.ck_depth = float(ck["depth"])
        self.open_transom = bool(ck.get("open_transom", True)) and self.xc0 <= 1e-6
        cb = d.get("cabin")
        self.has_cabin = cb is not None
        if self.has_cabin:
            self.xk0 = self.xc1
            self.xk1 = self.xk0 + float(cb["length"])
            self.cab_frac = float(cb["width"])
            self.cab_h = float(cb["height"])
            self.cab_slope = float(cb.get("side_slope", 0.22))
        else:
            self.xk0 = self.xk1 = self.xc1
        self.margin = float(d["nonslip_margin"])

    # ------------------------------------------------------------------------------------------------------
    # analytic surfaces (for placing hardware)

    def camber(self, x):
        return self.camber_k * 2 * self.hull.bs(x)

    def deck_z(self, x, y):
        bs = np.maximum(self.hull.bs(x), 1e-6)
        return self.hull.zs(x) + self.camber(x) * (1 - np.clip(np.abs(y) / bs, 0, 1) ** 2)

    def deck_normal(self, x, y, h=1e-3):
        x, y = float(x), float(y)
        dzdx = (float(self.deck_z(x + h, y)) - float(self.deck_z(x - h, y))) / (2 * h)
        dzdy = (float(self.deck_z(x, y + h)) - float(self.deck_z(x, y - h))) / (2 * h)
        return normalize(np.array([-dzdx, -dzdy, 1.0]))

    def yc(self, x):
        """Cockpit half-width."""
        return self.ck_frac * self.hull.bs(np.clip(x, self.xc0, self.xc1))

    def floor_z(self, x):
        return self.deck_z(x, 0.0) - self.ck_depth

    def yk(self, x):
        """Cabin plan half-width: matches the cockpit at its aft end, rounds in to zero at the front."""
        if not self.has_cabin:
            return np.zeros_like(np.asarray(x, dtype=np.float64))
        x = np.asarray(x, dtype=np.float64)
        u = np.clip((x - self.xk0) / (self.xk1 - self.xk0), 0, 1)
        w_aft = float(self.yc(self.xk0))
        w_fwd = self.cab_frac * self.hull.bs(x)
        base = w_aft + (w_fwd - w_aft) * np.clip(u / 0.5, 0, 1)
        return base * np.sqrt(np.clip(1 - u ** 5, 0, 1))

    def roof_z(self, x, y):
        """Cabin roof height (crown follows the deck centreline, lifted by the cabin height, with camber)."""
        yr = max(float(self.yk(x)) - self.cab_h * self.cab_slope, 1e-3)
        return float(self.deck_z(x, 0)) + self.cab_h + 0.3 * self.camber(x) * (1 - min(abs(y) / yr, 1) ** 2)

    def in_cabin_roof(self, x, y):
        if not self.has_cabin:
            return False
        inset = self.cab_h * self.cab_slope
        return self.xk0 <= x <= self.xk1 - inset and abs(y) < float(self.yk(x)) - inset - 0.03

    def in_cockpit(self, x, y):
        return self.xc0 <= x <= self.xc1 and abs(y) < float(self.yc(x))

    def surface(self, x, y, h=2e-3):
        """(z, normal, kind) of the walking surface at (x, y): cabin roof, cockpit floor or deck."""
        if self.in_cabin_roof(x, y):
            f, kind = (lambda a, b: self.roof_z(a, b)), "roof"
        elif self.in_cockpit(x, y):
            f, kind = (lambda a, b: float(self.floor_z(a))), "floor"
        else:
            f, kind = (lambda a, b: float(self.deck_z(a, b))), "deck"
        z = f(x, y)
        n = normalize(np.array([-(f(x + h, y) - f(x - h, y)) / (2 * h), -(f(x, y + h) - f(x, y - h)) / (2 * h), 1.0]))
        return z, n, kind

    def y_inner(self, x):
        x = np.asarray(x, dtype=np.float64)
        return np.where(x <= self.xc1, self.yc(x), np.where(x <= self.xk1, self.yk(x), 0.0))

    # ------------------------------------------------------------------------------------------------------
    def build(self, n_out=9):
        part = Part()
        hull = self.hull
        L = hull.L
        # deck stations: hull stations plus the feature breaks, dense near the cabin front
        xs = list(hull.stations_x(90))
        xs += [self.xc0, self.xc1, self.xk1]
        if self.has_cabin:
            xs += list(self.xk0 + (self.xk1 - self.xk0) * (1 - (np.linspace(0, 1, 18)) ** 2) ** 0.5)
        xs = np.unique(np.clip(np.round(np.array(xs), 5), 0, L))
        bs = hull.bs(xs)
        yin = np.minimum(self.y_inner(xs), bs * 0.98)
        # outer strip columns from the sheer (0) to the inner outline (1): gelcoat margins at both edges
        span = np.maximum(bs - yin, 1e-6)
        sig = np.linspace(0, 1, n_out + 1)
        a = np.clip(self.margin / span, 0, 0.3)
        # warp the first and last interior columns to the margin width
        S = np.broadcast_to(sig[None, :], (len(xs), len(sig))).copy()
        S[:, 1] = a
        S[:, -2] = 1 - a
        S[:, 2:-2] = a[:, None] + (1 - 2 * a[:, None]) * ((np.arange(2, n_out - 1) - 1) / (n_out - 2))[None, :]
        Y = bs[:, None] - S * span[:, None]
        X = np.broadcast_to(xs[:, None], Y.shape)
        Z = self.deck_z(X, Y)
        P = np.stack([X, Y, Z], -1)
        uv0 = np.stack([X, Y], -1)
        uv1 = np.stack([X / L, 0.5 + Y / (2 * hull.h["beam_max"])], -1)
        for side in (1.0, -1.0):
            m = np.array([1.0, side, 1.0])
            for c0, c1, mat in ((0, 2, "gelcoat"), (1, n_out, "nonslip"), (n_out - 1, n_out + 1, "gelcoat")):
                g = grid(P[:, c0:c1] * m, uv0[:, c0:c1] * m[:2], uv1[:, c0:c1])
                part.add(mat, _orient_up(g))
        self._deck_P = P
        self._cockpit(part, xs)
        if self.has_cabin:
            self._cabin(part)
        self._transom(part)
        self._sheer_trim(part)
        return part

    # ------------------------------------------------------------------------------------------------------
    def _cockpit(self, part, xs):
        xs = xs[(xs >= self.xc0 - 1e-9) & (xs <= self.xc1 + 1e-9)]
        yc = self.yc(xs)
        zf = self.floor_z(xs)
        n = 9
        t = np.linspace(-1, 1, n)
        Xf = np.broadcast_to(xs[:, None], (len(xs), n))
        Yf = yc[:, None] * t[None, :]
        Zf = np.broadcast_to(zf[:, None], Yf.shape)
        Pf = np.stack([Xf, Yf, Zf], -1)
        part.add("nonslip", _orient_up(grid(Pf, np.stack([Xf, Yf], -1))))
        # side walls
        for side in (1.0, -1.0):
            ytop = side * yc
            ztop = self.deck_z(xs, ytop)
            k = 5
            h = np.linspace(0, 1, k)
            Pw = np.stack([np.broadcast_to(xs[:, None], (len(xs), k)), np.broadcast_to(ytop[:, None], (len(xs), k)),
                           zf[:, None] + (ztop - zf)[:, None] * h[None, :]], -1)
            g = grid(Pw, np.stack([Pw[..., 0], Pw[..., 2]], -1))
            part.add("gelcoat", _orient(g, np.array([0, -side, 0])))
        # forward bulkhead (cabin aft face when there is a cabin: built with the cabin)
        if not self.has_cabin:
            x = self.xc1
            ys = np.linspace(-float(self.yc(x)), float(self.yc(x)), 9)
            top = np.stack([np.full_like(ys, x), ys, self.deck_z(x, ys)], -1)
            bot = np.stack([np.full_like(ys, x), ys[::-1], np.full_like(ys, float(self.floor_z(x)))], -1)
            part.add("gelcoat", planar_polygon(np.vstack([top, bot]), [-1, 0, 0]))
        if not self.open_transom:
            x = self.xc0
            ys = np.linspace(-float(self.yc(x)), float(self.yc(x)), 9)
            top = np.stack([np.full_like(ys, x), ys, self.deck_z(x, ys)], -1)
            bot = np.stack([np.full_like(ys, x), ys[::-1], np.full_like(ys, float(self.floor_z(x)))], -1)
            part.add("gelcoat", planar_polygon(np.vstack([top, bot]), [1, 0, 0]))

    # ------------------------------------------------------------------------------------------------------
    def _cabin(self, part, n_half=40, n_roof=11):
        # footprint half-curve (starboard side: y > 0 is port, mirrored later), aft end to the front apex
        xd = self.xk0 + (self.xk1 - self.xk0) * np.linspace(0, 1, 600)
        yd = self.yk(xd)
        curve = resample_polyline(np.stack([xd, yd], -1), n_half)
        curve[-1] = [self.xk1, 0.0]
        tang = np.gradient(curve, axis=0)
        nrm = normalize(np.stack([-tang[:, 1], tang[:, 0]], -1))
        nrm[0] = [0.0, 1.0]
        nrm[-1] = [1.0, 0.0]
        nrm = normalize(np.where((nrm[:, 1:2] < 0) | ((nrm[:, 1:2] == 0) & (nrm[:, 0:1] < 0)), -nrm, nrm))
        inset = self.cab_h * self.cab_slope
        top2 = curve - nrm * inset
        top2[-1, 1] = 0.0
        # roof edge with a small rounded fillet: three rows between the wall top and the roof
        base_z = self.deck_z(curve[:, 0], curve[:, 1]) - 0.02
        roof_edge_z = np.array([self.roof_z(x, y) for x, y in top2]) - 0.3 * self.camber(top2[:, 0]) * 0.0
        r = min(0.035, 0.25 * self.cab_h)
        rows = []
        for h in (0.0, 0.5, 0.85):
            p = curve + (top2 - curve) * h
            rows.append(np.c_[p, base_z + (roof_edge_z - base_z) * h])
        # fillet: from wall top (slightly below the edge) curving over onto the roof
        edge = np.c_[top2, roof_edge_z]
        wall_dir = normalize(np.c_[top2 - curve, (roof_edge_z - base_z)[:, None]])
        for a in np.linspace(0.25, 1.0, 4):
            ang = a * np.pi / 2
            inward = np.c_[-nrm, np.zeros(len(nrm))]
            p = edge - wall_dir * r * (1 - np.sin(ang)) + inward * r * (1 - np.cos(ang))
            rows.append(p)
        W = np.stack(rows, 1)  # (n_half, rows, 3)
        self._cab_wall = (curve, top2, base_z, roof_edge_z)
        for side in (1.0, -1.0):
            m = np.array([1.0, side, 1.0])
            Pw = W * m
            s = arclen(curve)
            uv = np.stack([np.broadcast_to(s[:, None], W.shape[:2]), W[..., 2]], -1)
            g = grid(Pw, uv)
            part.add("gelcoat", _orient(g, np.array([0.0, side, 0.3])))
        # roof: rows across from the starboard fillet end to the port one
        inner = W[:, -1, :]
        t = np.linspace(-1, 1, n_roof)
        Pr = np.zeros((n_half, n_roof, 3))
        for j in range(n_half):
            yj = inner[j, 1]
            Pr[j, :, 0] = inner[j, 0]
            Pr[j, :, 1] = yj * t
            Pr[j, :, 2] = [self.roof_z(inner[j, 0], yy) for yy in yj * t]
            Pr[j, :, 2] += inner[j, 2] - Pr[j, 0, 2]
        # non-slip roof panel inside gelcoat borders
        part.add("gelcoat", _orient_up(grid(Pr[:, :2], np.stack([Pr[:, :2, 0], Pr[:, :2, 1]], -1))))
        part.add("gelcoat", _orient_up(grid(Pr[:, -2:], np.stack([Pr[:, -2:, 0], Pr[:, -2:, 1]], -1))))
        part.add("nonslip", _orient_up(grid(Pr[:-2, 1:-1], np.stack([Pr[:-2, 1:-1, 0], Pr[:-2, 1:-1, 1]], -1))))
        part.add("gelcoat", _orient_up(grid(Pr[-3:, 1:-1], np.stack([Pr[-3:, 1:-1, 0], Pr[-3:, 1:-1, 1]], -1))))
        self._roof_rows = Pr
        # aft face: cockpit floor up to the roof, in the plane x = xk0
        x = self.xk0
        wall = W[0]                                     # starboard wall profile at the aft end (y > 0 here)
        roof_row = Pr[0]
        yck = float(self.yc(x))
        zf = float(self.floor_z(x))
        poly = [[x, -yck, zf], [x, yck, zf]]
        poly += [[x, p[1], p[2]] for p in wall]
        poly += [[x, p[1], p[2]] for p in roof_row[::-1][1:-1]]
        poly += [[x, -p[1], p[2]] for p in wall[::-1]]
        part.add("gelcoat", planar_polygon(np.array(poly), [-1, 0, 0]))
        self._companionway(part, x, yck, zf, roof_row)
        self._windows(part, W)

    def _companionway(self, part, x, yck, zf, roof_row):
        """Washboard opening in the aft face and a sliding hatch on the roof."""
        top = roof_row[len(roof_row) // 2, 2]
        w = min(0.34 * 2 * yck, 0.75) / 2
        z0, z1 = zf + 0.12 * self.ck_depth + 0.05, top - 0.03
        P = np.array([[x - 0.004, w, z0], [x - 0.004, -w, z0], [x - 0.004, -w * 0.88, z1], [x - 0.004, w * 0.88, z1]])
        part.add("glass", planar_polygon(P, [-1, 0, 0]))
        # sliding hatch
        L = min(0.9, 0.35 * (self.xk1 - self.xk0))
        hx = x + 0.5 * L + 0.02
        hz = self.roof_z(hx, 0)
        part.add("gelcoat", superellipsoid_box((L, 2 * w + 0.1, 0.07), 0.18, 16, 8, center=(hx, 0, hz + 0.02)))
        part.add("glass", superellipsoid_box((L * 0.8, 2 * w - 0.02, 0.02), 0.1, 12, 6, center=(hx, 0, hz + 0.055)))

    def _windows(self, part, W):
        """Dark glazing panels along the cabin sides, standing just proud of the wall."""
        if not self.cls["deck"]["cabin"].get("windows", True) or self.cab_h < 0.18:
            return
        n = W.shape[0]
        j0, j1 = int(0.14 * n), int(0.68 * n)
        rows = []
        for h in np.linspace(0.3, 0.72, 5):
            rows.append(W[j0:j1, 0] + (W[j0:j1, 2] - W[j0:j1, 0]) * h / 0.85)
        G = np.stack(rows, 1)
        # taper the ends into a teardrop-ish shape
        t = np.linspace(0, 1, G.shape[0])
        env = np.sqrt(np.clip(np.sin(np.pi * t) * 1.6, 0, 1))
        mid = G[:, 2:3]
        G = mid + (G - mid) * env[:, None, None]
        nrm = normalize(np.cross(np.gradient(G, axis=0), np.gradient(G, axis=1)))
        G = G + nrm * 0.004 * np.sign(np.mean(nrm[..., 1]))
        for side in (1.0, -1.0):
            g = grid(G * [1, side, 1], np.stack([G[..., 0], G[..., 2]], -1))
            part.add("glass", _orient(g, np.array([0.0, side, 0.0])))

    # ------------------------------------------------------------------------------------------------------
    def _transom(self, part):
        hull = self.hull
        y, z, _ = hull.station(0.0, 18, 13)
        stbd = np.stack([np.zeros_like(y), -y, z], -1)[::-1]    # sheer -> keel on starboard
        port = np.stack([np.zeros_like(y), y, z], -1)[1:]        # keel -> sheer on port
        bs0 = float(hull.bs(np.array([0.0]))[0])
        top = []
        if self.open_transom:
            yc = float(self.yc(0.0))
            zf = float(self.floor_z(0.0))
            ys = np.linspace(bs0, yc, 6)
            top += [[0, yy, float(self.deck_z(0.0, yy))] for yy in ys[1:]]
            top += [[0, yc, zf], [0, -yc, zf]]
            top += [[0, -yy, float(self.deck_z(0.0, yy))] for yy in ys[::-1][:-1]]
        else:
            ys = np.linspace(bs0, -bs0, 13)
            top += [[0, yy, float(self.deck_z(0.0, yy))] for yy in ys[1:-1]]
        poly = np.vstack([stbd, port, np.array(top)])
        part.add("gelcoat", planar_polygon(poly, [-1, 0, 0]))

    def _sheer_trim(self, part):
        """Toe rail on the deck edge and a rub strake just below the sheer on the hull."""
        hull = self.hull
        xs = np.linspace(0.0, hull.L - 0.01, 120)
        tr = float(self.cls["deck"]["toe_rail"])
        for side in (1.0, -1.0):
            bs = hull.bs(xs)
            inboard = np.minimum(tr * 0.6, bs * 0.5)
            path = np.stack([xs, side * (bs - inboard), self.deck_z(xs, bs - inboard) + tr * 0.35], -1)
            prof = rounded_rect(tr * 0.9, tr * 0.7, tr * 0.25, 2)
            part.add("gelcoat", sweep(path, prof, up=np.array([0, 0, 1.0])))
            # rub strake: a small half-round just below the sheer, following the topside
            y2 = np.array([hull.half_breadth_at(x, float(hull.zs(np.array([x]))[0]) - 0.03) for x in xs])
            path2 = np.stack([xs, side * (y2 + 0.004), hull.zs(xs) - 0.03], -1)
            ok = y2 > 0.02
            if ok.sum() > 4:
                part.add("rubber", sweep(path2[ok], rounded_rect(0.022, 0.018, 0.008, 2), up=np.array([0, 0, 1.0])))


def _orient(g, want):
    """Flip a surface so that its average normal agrees with the wanted direction."""
    if np.mean(g.N @ np.asarray(want, dtype=np.float64)) < 0:
        return g.flipped()
    return g


def _orient_up(g):
    return _orient(g, np.array([0, 0, 1.0]))
