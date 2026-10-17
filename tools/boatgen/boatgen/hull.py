"""Faired hull from class parameters.

Boat frame: x forward from the transom (x = 0) to the stem head (x = LOA), y to port, z up from the DWL.

The hull is a family of station curves over x, each built from five smooth longitudinal curves:

    zk(x)  keel / profile line (centreline bottom), stem and forefoot included
    zm(x)  height of the bilge turn (widest point of the bottom)
    w(x)   half-breadth at the bilge turn
    zs(x)  sheer height
    bs(x)  sheer half-breadth

A station is a superellipse quadrant from the keel point (0, zk) to the bilge turn (w, zm),
|y/w|^ny + |(zm - z)/(zm - zk)|^nz = 1, then a topside curve y = w + (bs - w) q^p up to the sheer
(q = 0 at the turn, 1 at the sheer). Both meet with a vertical tangent, so the skin is smooth unless a
chine is asked for. The section exponents ny, nz come from one fullness exponent n and the class's
section shape ratio r = ny/nz (V < 1 < U).

`solve()` then adjusts the maximum bilge breadth (to hit BWL), the section fullness n (to hit the canoe-body
volume the class displacement leaves after the appendages) and the longitudinal fullness of the
waterline curve (to hit the prismatic coefficient). LWL and canoe-body draft are exact by construction.
"""
import numpy as np

_trapz = getattr(np, "trapezoid", None) or np.trapz

from .mesh import Geom, Part, grid, smax, smin, arclen, normalize


class HullShape:
    def __init__(self, cls):
        h = cls["hull"]
        self.cls = cls
        self.h = h
        self.L = h["loa"]
        self.Lwl = h["lwl"]
        self.Tc = h["canoe_draft"]
        self.x_fwl = self.L - h["bow_overhang"]
        self.x_awl = self.x_fwl - self.Lwl
        self.x_md = self.x_fwl - h["max_draft_pos"] * self.Lwl  # deepest canoe body
        self.x_mw = self.x_fwl - h["max_bwl_pos"] * self.Lwl    # max bilge breadth
        self.s_m = h["max_beam_station"]
        self.x_mb = self.L * self.s_m                             # max sheer beam
        self.k_prof = float(h["keel_line_exponent"])
        # forefoot: where the keel line meets the stem, rocker.fwd above the lowest point
        self.d_ff = self.Tc - h["rocker_fwd"]
        self.stem_slope = h["freeboard_bow"] / max(self.L - self.x_fwl, 0.005)
        self.x_ff = self.x_fwl - self.d_ff / self.stem_slope
        self.transom_immersion = self.Tc - h["rocker_aft"]
        self.p_top = float(h["topside_flare"])
        self.fillet = float(h.get("bilge_fillet", 0.12))
        self.ratio = float(h["section_ratio"])
        # solved knobs (initial guesses)
        self.W = 0.5 * h["bwl"] * 1.04
        self.n = 2.4
        self.phi_f = 1.0   # entrance fullness
        self.phi_a = 1.0   # run fullness
        ch = h.get("chine")
        self.chine = None if not ch else {"start": ch.get("start", 0.45), "sharpness": ch.get("sharpness", 1.0)}

    # ----------------------------------------------------------------------------------------------------
    # longitudinal curves (all vectorised over x)

    def zs(self, x):
        """Sheer height: parabola through the transom, mid-LOA and stem freeboards, minus a sheer spring."""
        h = self.h
        xs = np.array([0.0, 0.5 * self.L, self.L])
        zz = np.array([h["freeboard_stern"], h["freeboard"], h["freeboard_bow"]])
        c = np.polyfit(xs, zz, 2)
        t = np.clip(x / self.L, 0, 1)
        return np.polyval(c, x) - h["sheer_spring"] * 4 * t * (1 - t)

    def bs(self, x):
        """Sheer half-breadth, the class plan-view rule (docs/specs/collisions.md 2.1): with s = x / LOA,
        s <= s_m: T/2 + (B/2 - T/2)(1 - (1 - s/s_m)^2);  s > s_m: B/2 (1 - u^f), u = (s - s_m)/(1 - s_m)."""
        B, Tw = self.h["beam_max"] / 2, self.h["transom_width"] / 2
        s = np.clip(np.asarray(x, dtype=np.float64) / self.L, 0, 1)
        sm, f = self.s_m, self.h["bow_fineness"]
        aft = Tw + (B - Tw) * (1 - (1 - s / sm) ** 2)
        fwd = B * (1 - np.clip((s - sm) / (1 - sm), 0, 1) ** f)
        return np.where(s <= sm, aft, fwd)

    def w(self, x):
        """Half-breadth at the bilge turn; its fore and aft exponents scale with the fullness knob phi."""
        W, Wt = self.W, self.h["transom_bottom_width"] / 2
        x = np.asarray(x, dtype=np.float64)
        u = np.clip((x - self.x_mw) / (self.L - self.x_mw), 0, 1)
        v = np.clip((self.x_mw - x) / self.x_mw, 0, 1)
        # 1 - u^a: zero slope at the maximum for a > 1 and a finite entrance angle at the stem;
        # a small a fines the entrance, a large one fills it
        fwd = W * (1 - u ** float(np.clip(1.8 * self.phi_f, 1.08, 5.0)))
        aft = Wt + (W - Wt) * (1 - v ** max(1.15, 2.1 * self.phi_a))
        res = np.where(x >= self.x_mw, fwd, aft)
        return np.minimum(res, self.bs(x) * 1.02 + 0.02)

    def zk(self, x):
        """Profile line. The canoe-body keel line is deepest (Tc) at x_md and rises by rocker.fwd to the forefoot
        and by rocker.aft to the aft end of the waterline; a straight stem runs from the forefoot through the
        forward waterline end to the stem head, joined to the keel line by a rounded forefoot."""
        x = np.asarray(x, dtype=np.float64)
        h = self.h
        # the run fullness also shapes the aft keel line
        k_aft = self.k_prof * float(np.clip(self.phi_a, 0.5, 2.0)) ** 0.6
        ef = (x - self.x_md) / max(self.x_ff - self.x_md, 1e-6)
        ea = (self.x_md - x) / max(self.x_md - self.x_awl, 1e-6)
        keel_f = -self.Tc + h["rocker_fwd"] * np.abs(ef) ** self.k_prof
        keel_a = -self.Tc + h["rocker_aft"] * np.abs(ea) ** k_aft
        stem = (x - self.x_fwl) * self.stem_slope
        sc = float(h.get("stem_curve") or 0.0)
        if sc > 0 and self.L - self.x_fwl > 0.02:
            # a spoon bow (class character, `stem_curve`): above the DWL the stem bows forward of the straight
            # line by up to `stem_curve` m, fullest a third of the way up, meeting the DWL and the stem head where
            # the straight stem does (so the waterline, the overhang and the physics stay); below the DWL the
            # straight line runs on into the forefoot
            fb = h["freeboard_bow"]
            sc = min(sc, 0.9 * (self.L - self.x_fwl) / 3.08)      # keeps x(z) monotonic (see below)
            zt = np.linspace(0.0, fb, 240)
            t = zt / fb
            bulge = np.sqrt(t) * (1 - t) / 0.3849                  # 1 at t = 1/3
            xt = self.x_fwl + zt / self.stem_slope + sc * bulge
            stem = np.where(x >= self.x_fwl, np.interp(x, xt, zt, right=fb), stem)
        r = h["stem_radius"]
        fwd = smax(keel_f, stem, r)
        # the smooth max lifts the waterline crossing slightly: remove it with a ramp so it stays at x_fwl
        lift = float(smax(-self.Tc + h["rocker_fwd"] * abs((self.x_fwl - self.x_md) / max(self.x_ff - self.x_md, 1e-6))
                          ** self.k_prof, 0.0, r))
        # (cubic ramp: flat at the deepest point, so the canoe-body draft stays exact)
        fwd = fwd - lift * np.clip((x - self.x_md) / (self.x_fwl - self.x_md), 0, 1) ** 3
        z = np.where(x >= self.x_md, fwd, keel_a)
        ch = h.get("counter_height")
        if ch is not None and self.x_awl > 1e-3 and h["rocker_aft"] >= self.Tc - 1e-3:
            # a long counter stern: aft of the waterline the profile runs on as a cubic from the waterline end (its
            # slope continued) to the transom bottom `counter_height` above the DWL, arriving at its mean slope
            T = self.x_awl
            a = h["rocker_aft"] * k_aft / max(self.x_md - self.x_awl, 1e-6)
            z0 = -self.Tc + h["rocker_aft"]
            m = (float(ch) - z0) / T
            t = np.clip((self.x_awl - x) / T, 0, 1)
            hz = (z0 * (2 * t ** 3 - 3 * t ** 2 + 1) + a * T * (t ** 3 - 2 * t ** 2 + t)
                  + float(ch) * (-2 * t ** 3 + 3 * t ** 2) + m * T * (t ** 3 - t ** 2))
            z = np.where(x < self.x_awl, hz, z)
        return np.minimum(z, self.zs(x) - 1e-4)

    def zm(self, x):
        x = np.asarray(x, dtype=np.float64)
        zk, zs = self.zk(x), self.zs(x)
        hb = self.h["bilge_height"]
        z = smax(np.full_like(x, hb), zk + 0.55 * hb, 0.04)
        return smin(z, zk + 0.55 * (zs - zk), 0.03)

    # ----------------------------------------------------------------------------------------------------
    # stations

    def exps(self):
        ny = self.n * np.sqrt(self.ratio)
        nz = self.n / np.sqrt(self.ratio)
        return ny, nz

    def _raw_curve(self, x, n_bot, n_top):
        """Unfilleted station curve (y, z): superellipse bottom (n_bot points, keel..turn) then the topside
        (n_top points, turn..sheer, the turn point shared)."""
        zk, zm, w, zs, bs = [float(f(np.array([x]))[0]) for f in (self.zk, self.zm, self.w, self.zs, self.bs)]
        ny, nz = self.exps()
        d = max(zm - zk, 1e-6)
        ph = np.linspace(np.pi / 2, 0, n_bot)
        yb = w * np.cos(ph) ** (2 / ny)
        zb = zm - d * np.sin(ph) ** (2 / nz)
        q = np.linspace(0, 1, n_top)[1:]
        p = self.p_top
        if self.chine is not None:
            p = 1.0 + (p - 1.0) * (1 - self._chine_weight(x))
        pts = np.concatenate([np.stack([yb, zb], -1), np.stack([w + (bs - w) * q ** p, zm + (zs - zm) * q], -1)])
        return pts, n_bot - 1, zs - zk

    def _curve(self, x, dense=400):
        """Station curve with the bilge turn faired: (points (n, 2) keel..sheer, index of the turn point).

        Both the superellipse end and the topside root have unbounded curvature where they meet (tangent
        continuous, but a visible crease on the mesh). Around the turn the curve is replaced by its Gaussian
        average over arc length (radius `bilge_fillet` of the station depth), blended back to the raw curve
        within four radii, so the skin turns smoothly. A hard chine (`chined`) keeps its crease."""
        pts, it, depth = self._raw_curve(x, dense, dense)
        r = self.fillet * depth * (1 - self._chine_weight(x))
        s = arclen(pts)
        if r < 1e-4 or s[-1] < 1e-6:
            return pts, it
        m = max(int(s[-1] / (0.2 * r)), 64)
        su = np.linspace(0, s[-1], m)
        U = np.stack([np.interp(su, s, pts[:, 0]), np.interp(su, s, pts[:, 1])], -1)
        ds = su[1] - su[0]
        k = np.arange(-int(3 * r / ds) - 1, int(3 * r / ds) + 2) * ds
        ker = np.exp(-0.5 * (k / r) ** 2)
        ker /= ker.sum()
        h = len(k) // 2
        pad = np.vstack([np.repeat(U[:1], h, 0), U, np.repeat(U[-1:], h, 0)])
        sm = np.stack([np.convolve(pad[:, j], ker, mode="valid") for j in range(2)], -1)
        st = s[it]
        u = np.clip(np.abs(su - st) / (4 * r), 0, 1)
        # the ends stay where they are: the keel on the centreline (small sections near the stem) and the sheer on
        # the deck edge, the blend fading out over two radii from each
        e = np.clip(np.minimum(su, s[-1] - su) / (2 * r), 0, 1)
        b = (0.5 * (1 + np.cos(np.pi * u)) * e * e * (3 - 2 * e))[:, None]
        out = (1 - b) * U + b * sm
        # split exactly at the raw turn's arc length (a grid index would jitter from station to station)
        k = int(np.clip(np.searchsorted(su, st), 1, m - 1))
        f = (st - su[k - 1]) / max(su[k] - su[k - 1], 1e-12)
        pt = out[k - 1] + f * (out[k] - out[k - 1])
        return np.vstack([out[:k], pt[None], out[k:]]), k

    def station(self, x, nb, nt, dense=400):
        """Station curve (y, z) from keel to sheer: nb points on the bottom (keel..turn) and nt on the topsides
        (turn..sheer), each resampled uniformly by arc length. Returns (y, z, i_turn)."""
        pts, it = self._curve(x, dense)
        bot = _resample(pts[:it + 1], nb, bend=0.5)
        top = _resample(pts[it:], nt, bend=0.5)
        pts = np.vstack([bot, top[1:]])
        return pts[:, 0], pts[:, 1], nb - 1

    def _chine_weight(self, x):
        if self.chine is None:
            return 0.0
        xs = self.L * (1 - self.chine["start"])
        return float(np.clip((xs - x) / (0.12 * self.L), 0, 1)) * self.chine["sharpness"]

    def dense_section(self, x, n=160):
        """Station curve sampled densely (z increases monotonically keel to sheer)."""
        pts, it = self._curve(x, max(n, 120))
        pts = _resample(pts, n + n // 2 - 1)
        return pts[:, 0], pts[:, 1]

    # ----------------------------------------------------------------------------------------------------
    # hydrostatics of the canoe body

    def hydro(self, nx=161, z_wl=0.0):
        xs = np.linspace(0, self.L, nx)
        A = np.zeros(nx)      # immersed section area (both sides)
        Mz = np.zeros(nx)     # vertical moment of the immersed section
        yw = np.zeros(nx)     # waterline half-breadth
        for i, x in enumerate(xs):
            y, z = self.dense_section(x)
            if z[0] >= z_wl:
                continue
            k = np.searchsorted(z, z_wl)
            if k < len(z):
                t = (z_wl - z[k - 1]) / (z[k] - z[k - 1])
                y = np.concatenate([y[:k], [y[k - 1] + t * (y[k] - y[k - 1])]])
                z = np.concatenate([z[:k], [z_wl]])
            A[i] = 2 * _trapz(y, z)
            Mz[i] = 2 * _trapz(y * z, z)
            yw[i] = y[-1] if z[-1] >= z_wl - 1e-9 else 0.0
        V = _trapz(A, xs)
        lcb = _trapz(A * xs, xs) / V if V > 0 else 0.0
        vcb = _trapz(Mz, xs) / V if V > 0 else 0.0
        Aw = 2 * _trapz(yw, xs)
        lcf = 2 * _trapz(yw * xs, xs) / Aw if Aw > 0 else 0.0
        It = 2.0 / 3.0 * _trapz(yw ** 3, xs)
        Il = 2 * _trapz(yw * (xs - lcf) ** 2, xs)
        lwl = self._dwl_crossing(+1) - self._dwl_crossing(-1)
        bwl = 2 * yw.max()
        Amax = A.max()
        return {
            "V": V, "lcb_x": lcb, "vcb_z": vcb, "Aw": Aw, "lcf_x": lcf, "It": It, "Il": Il,
            "Amax": Amax, "x_Amax": xs[np.argmax(A)], "lwl": lwl, "bwl": bwl,
            "Tc": -min(float(self.zk(np.linspace(0, self.L, 800)).min()), 0.0),
            "xs": xs, "A": A, "yw": yw,
        }

    def _fit_volume(self, V_target, nx):
        lo, hi = 1.3, 9.0
        for _ in range(24):
            self.n = 0.5 * (lo + hi)
            if self.hydro(nx)["V"] < V_target:
                lo = self.n
            else:
                hi = self.n

    def _form(self, nx=81):
        r = self.hydro(nx)
        return np.array([r["V"] / (r["Amax"] * self.Lwl), (self.x_fwl - r["lcb_x"]) / self.Lwl]), r

    def _dwl_crossing(self, sign):
        """x where the profile line meets the DWL at the bow (+1) or stern (-1); the transom if it is immersed."""
        if sign < 0 and float(self.zk(np.array([0.0]))[0]) < 0:
            return 0.0
        lo, hi = (self.x_md, self.L) if sign > 0 else (0.0, self.x_md)
        for _ in range(50):
            mid = 0.5 * (lo + hi)
            below = float(self.zk(np.array([mid]))[0]) < 0
            if (sign > 0) == below:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def solve(self, V_target, iters=6, log=None):
        """Fit W (BWL), n (volume), and the entrance and run fullness (prismatic and LCB) to the class."""
        h = self.h
        target = np.array([h["prismatic"], h["lcb"]])
        for it in range(iters):
            for _ in range(2):
                self.W *= h["bwl"] / max(self.hydro(81)["bwl"], 1e-6)
            self._fit_volume(V_target, 81)
            f0, r = self._form()
            if log:
                log(f"  hull fit {it}: W={self.W:.3f} n={self.n:.2f} phi_f={self.phi_f:.2f} phi_a={self.phi_a:.2f} "
                    f"V={r['V']:.3f}/{V_target:.3f} Cp={f0[0]:.3f}/{target[0]:.3f} LCB={f0[1]:.3f}/{target[1]:.3f} "
                    f"BWL={r['bwl']:.3f}")
            # Newton step on log(phi) with a finite-difference Jacobian (volume re-fitted by n next pass)
            J = np.zeros((2, 2))
            base = (self.phi_f, self.phi_a)
            for j in range(2):
                ph = list(base)
                ph[j] *= 1.08
                self.phi_f, self.phi_a = ph
                self._fit_volume(V_target, 61)
                J[:, j] = (self._form(61)[0] - f0) / np.log(1.08)
            self.phi_f, self.phi_a = base
            try:
                step = np.linalg.solve(J, target - f0)
            except np.linalg.LinAlgError:
                step = np.zeros(2)
            step = np.clip(step, -0.5, 0.5)
            self.phi_f = float(np.clip(self.phi_f * np.exp(step[0]), 0.6, 2.8))
            self.phi_a = float(np.clip(self.phi_a * np.exp(step[1]), 0.25, 4.0))
        for _ in range(2):
            self.W *= h["bwl"] / max(self.hydro(121)["bwl"], 1e-6)
        self._fit_volume(V_target, 121)
        self.n_clamped = self.n < 1.35 or self.n > 8.9
        return self.hydro(241)

    # ----------------------------------------------------------------------------------------------------
    # mesh

    def stations_x(self, n):
        t = np.linspace(0, 1, n)
        return self.L * (0.72 * t + 0.28 * (0.5 - 0.5 * np.cos(np.pi * t)))

    def skin(self, n_st=96, nb=18, nt=13):
        """Starboard and port hull skin as one Part keyed 'hull' (split into paint zones later).

        uv0: (x, girth from keel) in metres. uv1 livery atlas: starboard in v 0..0.5, port in v 0.5..1,
        sheer at the top of each band, u running so text reads bow-first on both sides."""
        xs = self.stations_x(n_st)
        Y = np.zeros((n_st, nb + nt - 1))
        Z = np.zeros_like(Y)
        for i, x in enumerate(xs):
            y, z, it = self.station(x, nb, nt)
            Y[i], Z[i] = y, z
        self.i_turn = it = nb - 1
        X = np.broadcast_to(xs[:, None], Y.shape)
        P = np.stack([X, Y, Z], -1)
        g = np.zeros(Y.shape)
        g[:, 1:] = np.cumsum(np.hypot(np.diff(Y, axis=1), np.diff(Z, axis=1)), axis=1)
        G = max(g.max(), 1e-6)
        self.girth_max = G
        self.girth = g
        self.skin_xs = xs
        uv0 = np.stack([X, g], -1)
        uv1_port = np.stack([1 - X / self.L, 0.5 + 0.5 * (1 - g / G)], -1)
        uv1_stbd = np.stack([X / self.L, 0.5 * (1 - g / G)], -1)
        from .mesh import grid_normals
        N = grid_normals(P)
        Nb, Nt = N[:, :it + 1].copy(), N[:, it:].copy()
        if self.chine is not None:
            # hard chine aft of its start: bottom and topsides keep their own normals along the turn
            wts = np.array([self._chine_weight(x) for x in xs])[:, None]
            Nb[:, -1] = normalize((1 - wts) * N[:, it] + wts * grid_normals(P[:, :it + 1])[:, -1])
            Nt[:, 0] = normalize((1 - wts) * N[:, it] + wts * grid_normals(P[:, it:])[:, 0])
        sides = {}
        for side, sgn, uv1 in (("port", 1.0, uv1_port), ("stbd", -1.0, uv1_stbd)):
            m = np.array([1.0, sgn, 1.0])
            pieces = []
            for sl, Nn in ((slice(0, it + 1), Nb), (slice(it, None), Nt)):
                gg = grid(P[:, sl] * m, uv0[:, sl], uv1[:, sl], N=Nn * m)
                # orient outward: at mid length the topside normal points to its own side
                j = len(gg.P) // 2
                if np.dot(np.cross(gg.P[gg.I[len(gg.I) // 2, 1]] - gg.P[gg.I[len(gg.I) // 2, 0]],
                                   gg.P[gg.I[len(gg.I) // 2, 2]] - gg.P[gg.I[len(gg.I) // 2, 0]]),
                          gg.N[gg.I[len(gg.I) // 2, 0]]) < 0:
                    gg = Geom(gg.P, gg.I[:, ::-1], gg.N, gg.uv0, gg.uv1)
                if gg.N[j, 1] * sgn < 0 and gg.N[j, 2] > -0.5:
                    gg = gg.flipped()
                pieces.append(gg)
            from .mesh import merge
            sides[side] = merge(pieces)
        # the keel-line normals of the two sides average to straight down
        self.skin_grid = P
        return sides["port"], sides["stbd"]

    def half_breadth_at(self, x, z):
        """Hull half-breadth at height z of station x (0 when outside the station)."""
        y, zz = self.dense_section(x, 120)
        if z < zz[0] or z > zz[-1]:
            return 0.0
        return float(np.interp(z, zz, y))


def _resample(pts, n, bend=0.5):
    """Resample a polyline to n points, uniformly by arc length, or with `bend` > 0 by a mix of arc length and
    turning angle (that share of the points goes where the curve bends, so a tight turn keeps its shape)."""
    s = arclen(pts)
    if s[-1] < 1e-9:
        return np.repeat(pts[:1], n, axis=0)
    if bend > 0:
        d = np.diff(pts, axis=0)
        th = np.unwrap(np.arctan2(d[:, 1], d[:, 0]))
        dth = np.abs(np.diff(th, prepend=th[0]))
        tot = dth.sum()
        if tot > 1e-6:
            m = np.concatenate([[0.0], np.cumsum((1 - bend) * np.diff(s) / s[-1] + bend * dth / tot)])
            t = np.linspace(0, m[-1], n)
            return np.stack([np.interp(t, m, pts[:, 0]), np.interp(t, m, pts[:, 1])], -1)
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], -1)
