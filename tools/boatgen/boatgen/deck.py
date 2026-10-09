"""Deck, cockpit, cabin top, transom face and the trim along the sheer.

Deck plan: the deck is a cambered surface between the two sheer lines,
    z = zs(x) + camber(x) * (1 - (y / bs(x))^2),   camber = deck_camber * 2 bs(x).
The cockpit is a rectangular well in (x, y / bs) running aft to an open transom; the coachroof sits directly
forward of it (data_format.md 3.7.2): a height field over the deck, low and sloping down forward until it fairs into
the deck at (or just aft of) the mast, its sides raked inward with a fillet at the foot and a radius at the top, its
plan following the sheer and rounding in to the centreline over the last fifth. Only its aft face is upright.

The deck is meshed as an outer strip on each side from the sheer to the cockpit / coachroof base, continued by the
centreline forward of the coachroof. The coachroof is meshed on the same stations from base to base, so the two share
their edge (the coachroof's height is zero there).

uv1 (data_format.md §8.5): every deck surface has the plan view (`plan_rect`, the deck's extent with a 1 % margin,
bow to the right and port at the top), except the transom face, its own slot `transom` with uv1 over the transom as
seen from astern (`transom_rect`: port on the left, its top at the top). The baked livery textures lie on them.
"""
import numpy as np

from .mesh import (Geom, Part, grid, grid_normals, planar_polygon, normalize, arclen, sweep, rounded_rect, box,
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
            if cb.get("length") is not None:
                self.xk1 = self.xk0 + float(cb["length"])
            else:
                r = cls["rig"]          # mast_x is the mast's front at the deck: its aft face is a chord aft of it
                self.xk1 = float(r["mast_x"]) - float(r["mast_chord"]) - float(cb["meet_aft_of_mast"])
            if self.xk1 - self.xk0 < 0.5:
                raise ValueError(f"coachroof from {self.xk0:.2f} to {self.xk1:.2f} m is shorter than 0.5 m: the cockpit "
                                 "reaches the mast (visual.deck.cabin, data_format.md 3.7.2)")
            self.cab_frac = float(cb["width"])
            self.cab_h = float(cb["height"])
            self.cab_slope_from = float(cb.get("slope_from", 0.3))
            self.cab_rake = float(cb.get("side_rake", 0.35))
            self.cab_r = float(cb.get("edge_radius", 0.05 * (L / 12) ** 0.5))
        else:
            self.xk0 = self.xk1 = self.xc1
        self.margin = float(d["nonslip_margin"])
        self.helm = self._helm() if d.get("steering") == "wheel" else None

    def _helm(self):
        """The helm of a wheel boat (data_format.md 3.7.3): wheel position, diameter and hub on the centreline, and
        with `well` the slot let into the cockpit floor for the wheel's lower part (x0, x1, half width, bottom)."""
        L = self.hull.L
        s = (L / 12.0) ** 0.7
        w = self.cls["deck"].get("wheel") or {}
        well = bool(w.get("well", False))
        x_w = min(self.xc0 + 1.25 * s, self.xc1 - 0.8)
        dw = float(w.get("diameter") or min(1.9 * float(self.yc(x_w)) * 0.9, 1.35 * s))
        hub_h = float(w.get("hub_height") or (0.62 * (L / 12.0) ** 0.5 if well else dw / 2 + 0.12))
        slot = None
        if well and hub_h < dw / 2:
            half_x = 0.5 * 0.04 * dw + 0.05                    # the rim's thickness (hardware.wheel) and 5 cm
            r = self.cls.get("rudder") or {}
            if r.get("type", "spade") == "spade" and r.get("x_stock") is not None:
                # the slot's aft wall 5 cm ahead of the rudder stock's bearing (hardware.rudder_fittings)
                x_w = max(x_w, float(r["x_stock"]) + 0.11 * s + 0.05 + half_x)
            zf = float(self.floor_z(x_w))
            R = dw / 2
            slot = {"x0": x_w - half_x, "x1": x_w + half_x, "y": float(np.sqrt(R * R - hub_h * hub_h)) + 0.05,
                    "z": zf - (R - hub_h) - 0.04}
            # the box stays inside the hull: 5 cm above the canoe body's bottom and inside its sides
            for x in (slot["x0"], slot["x1"]):
                zk = float(self.hull.zk(np.array([x]))[0])
                if slot["z"] < zk + 0.05 or slot["y"] > self.hull.half_breadth_at(x, slot["z"]) - 0.05:
                    raise ValueError(f"wheel slot ({2 * slot['y']:.2f} m wide, bottom {slot['z']:.2f} m) does not fit "
                                     "inside the hull: raise visual.deck.wheel.hub_height (data_format.md 3.7.3)")
        if dw > 1.9 * float(self.yc(x_w)):
            raise ValueError(f"wheel diameter {dw:.2f} m does not fit the cockpit ({2 * float(self.yc(x_w)):.2f} m wide "
                             "at the wheel; data_format.md 3.7.3)")
        zf = float(self.floor_z(x_w))
        return {"x": x_w, "diameter": dw, "hub": np.array([x_w, 0.0, zf + hub_h]), "floor_z": zf, "slot": slot}

    def in_slot(self, x, y):
        """Inside the wheel slot in the cockpit floor (arrays)."""
        sl = self.helm["slot"] if self.helm else None
        if sl is None:
            return np.zeros(np.broadcast(np.asarray(x), np.asarray(y)).shape, dtype=bool)
        return (np.asarray(x) > sl["x0"]) & (np.asarray(x) < sl["x1"]) & (np.abs(np.asarray(y)) < sl["y"])

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
        """Coachroof base half-width: `width` of the local half-beam, so its sides follow the sheer (never wider
        than the cockpit), rounding in to the centreline over the last fifth (a quarter ellipse)."""
        if not self.has_cabin:
            return np.zeros_like(np.asarray(x, dtype=np.float64))
        x = np.asarray(x, dtype=np.float64)
        u = np.clip((x - self.xk0) / (self.xk1 - self.xk0), 0, 1)
        base = np.minimum(self.cab_frac * self.hull.bs(x), float(self.yc(self.xk0)))
        e = np.clip((u - 0.8) / 0.2, 0, 1)
        return np.where((x >= self.xk0) & (x <= self.xk1), base * np.sqrt(np.clip(1 - e * e, 0, 1)), 0.0)

    def cab_height(self, x):
        """Height of the coachroof's top above the deck at the centreline (crown excluded): `height` aft of
        `slope_from`, then a half cosine down to zero where it meets the deck; the aft edge rounded by the edge
        radius."""
        x = np.asarray(x, dtype=np.float64)
        if not self.has_cabin:
            return np.zeros_like(x)
        u = (x - self.xk0) / (self.xk1 - self.xk0)
        sf = self.cab_slope_from
        v = np.clip((u - sf) / max(1 - sf, 1e-6), 0, 1)
        h = self.cab_h * 0.5 * (1 + np.cos(np.pi * v))
        r = min(self.cab_r, 0.8 * self.cab_h)
        dx = np.clip(self.xk0 + r - x, 0, r)
        h = np.minimum(h, self.cab_h - r + np.sqrt(np.maximum(r * r - dx * dx, 0)))
        return np.where((x >= self.xk0) & (x <= self.xk1), np.maximum(h, 0.0), 0.0)

    def cab_slope_max(self):
        """The top's steepest slope (rad), for the build log."""
        xs = np.linspace(self.xk0 + self.cab_r, self.xk1, 400)
        return float(np.arctan(np.max(-np.gradient(self.cab_height(xs), xs))))

    def _cab_prof(self, h, yb):
        """Section profile at heights h over base half-widths yb (arrays): base fillet radius rb, edge radius re,
        the breaks d1 (fillet end), d2 (raked side end) and d3 (edge radius end) measured inward from the base, and
        the squeeze q >= 1 that keeps the sides within 0.8 of the half-width. The radii shrink with a low top."""
        h, yb = np.broadcast_arrays(np.asarray(h, dtype=np.float64), np.asarray(yb, dtype=np.float64))
        beta = np.pi / 2 - min(self.cab_rake, np.pi / 2 - 1e-3)        # the side's angle from the horizontal
        sb, cb, tb = np.sin(beta), np.cos(beta), np.tan(beta)
        re0, rb0 = self.cab_r, 0.4 * self.cab_r
        k = np.clip(h / ((re0 + rb0) * (1 - cb)), 0, 1)
        re, rb = re0 * k, rb0 * k
        hv = np.maximum(h - (re + rb) * (1 - cb), 0)
        d1 = rb * sb
        d2 = d1 + hv / tb
        d3 = d2 + re * sb
        q = np.maximum(d3 / np.maximum(0.8 * yb, 1e-9), 1.0)
        return {"h": h, "re": re, "rb": rb, "d1": d1, "d2": d2, "d3": d3, "q": q, "cb": cb, "tb": tb}

    @staticmethod
    def _cab_zrel(pr, d):
        """Height of the section above the deck at distance d inward from its base."""
        dd = np.asarray(d, dtype=np.float64) * pr["q"]
        rb, re, d1, d2, d3, h = pr["rb"], pr["re"], pr["d1"], pr["d2"], pr["d3"], pr["h"]
        z_f = rb - np.sqrt(np.maximum(rb * rb - dd * dd, 0))
        z_s = rb * (1 - pr["cb"]) + (dd - d1) * pr["tb"]
        z_e = h - re + np.sqrt(np.maximum(re * re - (d3 - dd) ** 2, 0))
        z = np.where(dd <= d1, z_f, np.where(dd <= d2, z_s, np.where(dd <= d3, z_e, h)))
        return np.where(dd <= 0, 0.0, z)

    def yk_roof(self, x):
        """Half-width of the coachroof's top: where the edge radius ends."""
        x = np.asarray(x, dtype=np.float64)
        yb = self.yk(x)
        pr = self._cab_prof(self.cab_height(x), yb)
        return np.maximum(yb - pr["d3"] / pr["q"], 0.0)

    def cabin_z(self, x, y):
        """The coachroof's surface (the deck outside its base): deck + section profile + a crown of 0.3 of the deck
        camber scaled with the height."""
        x, y = np.broadcast_arrays(np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64))
        z = self.deck_z(x, y)
        if not self.has_cabin:
            return z
        h, yb = self.cab_height(x), self.yk(x)
        ay = np.abs(y)
        inside = (x >= self.xk0) & (x <= self.xk1) & (ay < yb)
        pr = self._cab_prof(h, yb)
        zr = self._cab_zrel(pr, yb - ay)
        crown = 0.3 * self.camber(x) * (h / self.cab_h) * (1 - np.clip(ay / np.maximum(yb, 1e-9), 0, 1) ** 2)
        return z + np.where(inside, zr + crown, 0.0)

    def roof_z(self, x, y):
        """Coachroof surface height at a point (scalar)."""
        return float(self.cabin_z(x, y))

    def in_cabin(self, x, y):
        """Inside the coachroof's base outline."""
        return self.has_cabin and self.xk0 <= x <= self.xk1 and abs(y) < float(self.yk(x))

    def in_cabin_roof(self, x, y, margin=0.03):
        """On the coachroof's top (inside its edge radius by `margin`), where it stands at least 2 cm proud."""
        return (self.in_cabin(x, y) and abs(y) < float(self.yk_roof(x)) - margin
                and float(self.cab_height(x)) > 0.02)

    def in_cockpit(self, x, y):
        return self.xc0 <= x <= self.xc1 and abs(y) < float(self.yc(x))

    def surface_z(self, x, y):
        """Height of the walking surface (coachroof, cockpit floor or deck) at arrays of points."""
        x, y = np.broadcast_arrays(np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64))
        ck = (x >= self.xc0) & (x <= self.xc1) & (np.abs(y) < self.yc(x))
        cab = self.has_cabin & (x >= self.xk0) & (x <= self.xk1) & (np.abs(y) < self.yk(x))
        z = np.where(ck & ~cab, self.floor_z(x), self.cabin_z(x, y))
        return np.where(ck & self.in_slot(x, y), self.helm["slot"]["z"] if self.helm and self.helm["slot"] else z, z)

    def surface(self, x, y, h=2e-3):
        """(z, normal, kind) of the walking surface at (x, y): coachroof ("roof", its sides included), cockpit floor
        or deck."""
        if self.in_cabin(x, y):
            f, kind = (lambda a, b: self.roof_z(a, b)), "roof"
        elif self.in_cockpit(x, y) and bool(self.in_slot(x, y)):
            f, kind = (lambda a, b: self.helm["slot"]["z"]), "floor"
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
    # uv1 frames of the livery textures

    def plan_rect(self):
        """(x0, y_top, length, height): the plan view the deck's uv1 covers, boat frame (x from the transom, y to
        port): the hull's length and beam with a margin of 1 % of the length all round."""
        L = self.hull.L
        m = 0.01 * L
        hb = 0.5 * float(self.hull.h["beam_max"]) + m
        return (-m, hb, L + 2 * m, 2 * hb)

    def plan_uv1(self, P):
        x0, yt, w, h = self.plan_rect()
        P = np.asarray(P, dtype=np.float64)
        return np.stack([(P[:, 0] - x0) / w, (yt - P[:, 1]) / h], -1)

    def face_frame(self):
        """The coachroof's aft face on the deck's uv1 (data_format.md 8.5): its own rectangle in a corner of the plan
        image the deck does not use (forward of the bow on the port side), so lines painted down it read as on the
        top and the cockpit floor. {"x": the face's x, "y": (min, max), "z": (min, max) of the face, "plan": (x, y)
        of the face's (y min, z max) corner in the plan, "scale": plan metres per face metre}, or None without a
        coachroof."""
        if not self.has_cabin:
            return None
        if hasattr(self, "_face_frame"):
            return self._face_frame
        x = float(self.xk0)
        yb = float(self.yk(x))
        yck = float(self.yc(x))
        z0 = float(self.floor_z(x))
        z1 = float(np.max(self.cabin_z(np.full(9, x), np.linspace(-yb, yb, 9))))
        fy = max(yb, yck)
        W, H = 2 * fy, max(z1 - z0, 0.05)
        x0, yt, w, h = self.plan_rect()
        L = self.hull.L
        best = None
        for xa in np.linspace(0.55 * L, 0.98 * L, 44):
            xs = np.linspace(xa, L, 40)
            room_y = yt - 0.01 * L - float(np.max(self.hull.bs(xs))) - 0.03      # clear of the deck edge
            room_x = (x0 + w - 0.005 * L) - xa
            if room_y <= 0 or room_x <= 0:
                continue
            sc = min(room_x / W, room_y / H)
            if best is None or sc > best[0]:
                best = (sc, xa)
        if best is None:
            self._face_frame = None
            return None
        sc, xa = best
        self._face_frame = {"x": x, "y": (-fy, fy), "z": (z0, z1), "plan": (xa, yt - 0.01 * L), "scale": sc}
        return self._face_frame

    def face_plan(self, P):
        """Points on the aft face (boat frame) to their place in the plan (x, y) of face_frame."""
        f = self.face_frame()
        P = np.asarray(P, dtype=np.float64)
        px = f["plan"][0] + (P[:, 1] - f["y"][0]) * f["scale"]
        py = f["plan"][1] - (f["z"][1] - P[:, 2]) * f["scale"]
        return np.stack([px, py], -1)

    def face_uv1(self, P):
        xy = self.face_plan(P)
        return self.plan_uv1(np.stack([xy[:, 0], xy[:, 1], np.zeros(len(xy))], -1))

    def transom_outline(self, skin=None):
        """The transom face as a closed polygon in the plane x = 0 (boat frame), the skin's station at the
        transom from the starboard sheer down to the keel and up to the port sheer, closed along the deck edge
        (and round the cockpit opening of an open transom)."""
        hull = self.hull
        y, z, _ = hull.station(0.0, *(skin or getattr(self, "_skin_n", (18, 13))))
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
        return np.vstack([stbd, port, np.array(top)])

    def transom_rect(self):
        """(h, top, bottom): the transom's half width and the heights of its top and bottom (boat frame), the
        frame of its uv1: u = (h - y) / 2h from port to starboard, v = (top - z) / (top - bottom)."""
        if not hasattr(self, "_transom_rect"):
            P = self.transom_outline(skin=(18, 13))       # the same on every level of detail
            self._transom_rect = (float(np.abs(P[:, 1]).max()), float(P[:, 2].max()), float(P[:, 2].min()))
        return self._transom_rect

    def transom_uv1(self, P):
        h, top, bot = self.transom_rect()
        P = np.asarray(P, dtype=np.float64)
        return np.stack([(h - P[:, 1]) / (2 * h), (top - P[:, 2]) / (top - bot)], -1)

    def transom_name_panel(self, rudder_half=0.0):
        """The transom's name panel: (y_port, y_stbd, z_top, z_bottom), boat frame. The band below the cockpit
        opening (open transom) or the middle of the transom (closed), above the boot stripe and inside the
        transom's bottom edge; with `rudder_half` > 0 (a transom-hung rudder's fittings, half width) the part of
        the band to starboard of them."""
        hull = self.hull
        y, z, _ = hull.station(0.0, 60, 40)
        bs0 = float(hull.bs(np.array([0.0]))[0])
        z_bt = float(self.cls["hull"]["boot_top"][1])
        if self.open_transom:
            half = 0.9 * float(self.yc(0.0))
            z_hi = float(self.floor_z(0.0))
        else:
            half = 0.6 * bs0
            z_hi = float(self.hull.zs(np.array([0.0]))[0]) - 0.12 * (float(hull.zs(np.array([0.0]))[0]) - float(z.min()))
        ya, yb = -half, half
        if rudder_half > 0:
            ya, yb = -half, -(rudder_half + 0.04)
        # the bottom edge under the panel: the section's highest point within its width (bottom part only)
        it = int(np.argmax(y >= max(abs(ya), abs(yb)))) if np.any(y >= max(abs(ya), abs(yb))) else len(y) - 1
        z_edge = float(np.max(z[: it + 1]))
        z_lo = max(z_edge, z_bt) + 0.02
        band = max(z_hi - z_lo, 0.02)
        return (yb, ya, z_hi - 0.12 * band, z_lo + 0.08 * band)

    # ------------------------------------------------------------------------------------------------------
    def build(self, n_out=9, n_st=90, skin=(18, 13), lite=0):
        """Deck part; `n_st` deck stations (plus the feature breaks) and the hull skin's girth counts `skin`
        (the transom face must meet the skin) set the level of detail. `lite` 1 (the game's LOD0) keeps the coaming
        bevels and trims with plainer sections, 2 (LOD1) leaves the bevels and the rub strake out."""
        self._skin_n = skin
        self._lite = lite
        part = Part()
        hull = self.hull
        L = hull.L
        # deck stations: hull stations plus the feature breaks, dense near the cabin front
        xs = list(hull.stations_x(n_st))
        xs += [self.xc0, self.xc1, self.xk1]
        if self.has_cabin:
            xs += [self.xc1 + 1e-4]     # the deck steps in from the cockpit's edge to the coachroof's base here
        if self.has_cabin:
            # the coachroof: even stations, denser over the rounded aft edge and the nose
            lk = self.xk1 - self.xk0
            xs += list(np.linspace(self.xk0, self.xk1, max(6, round(n_st * lk / L * 1.6))))
            xs += list(self.xk0 + self.cab_r * (1 - np.cos(np.linspace(0, np.pi / 2, max(3, n_st // 18)))))
            xs += list(self.xk1 - 0.2 * lk * (1 - np.sin(np.linspace(0, np.pi / 2, max(4, n_st // 9)))))
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
            self._cabin(part, xs, n_roof=max(3, round(7 * n_st / 90)), fine=n_st >= 60)
        self._sheer_trim(part, n=max(16, round(120 * n_st / 90)), lite=lite)
        for mat, gs in part.slots.items():      # every deck surface: the plan view (the transom has its own)
            for g in gs:
                g.uv1 = self.face_uv1(g.P) if mat == "face" and self.face_frame() else self.plan_uv1(g.P)
        self._transom(part)
        return part

    def build_simple(self, n_st, n_y):
        """The far levels' deck (LOD2, LOD3): one height field over the plan between the sheers on the walking
        surface (deck, coachroof, cockpit sole), `n_st` stations by `n_y` points across, and the transom face. The
        livery's deck map draws the cockpit, coachroof and fittings on it."""
        part = Part()
        hull = self.hull
        L = hull.L
        xs = np.linspace(0.0, L, n_st)
        if self.has_cabin:
            xs = np.unique(np.concatenate([xs, [self.xc0, self.xc1, self.xk0, 0.5 * (self.xk0 + self.xk1)]]))
        else:
            xs = np.unique(np.concatenate([xs, [self.xc0, self.xc1]]))
        bs = np.maximum(hull.bs(xs), 1e-4)
        t = np.linspace(-1.0, 1.0, n_y)
        Y = bs[:, None] * t[None, :]
        X = np.broadcast_to(xs[:, None], Y.shape)
        Z = self.surface_z(X, Y)
        # the sheer points sit on the deck edge (the hull's top)
        Z[:, 0] = self.deck_z(xs, bs)
        Z[:, -1] = Z[:, 0]
        P = np.stack([X, Y, Z], -1)
        g = _orient_up(grid(P, np.stack([X, Y], -1)))
        g.uv1 = self.plan_uv1(g.P)
        part.add("gelcoat", g)
        self._transom(part)
        return part

    # ------------------------------------------------------------------------------------------------------
    def _floor(self, part, xs, ya, yb, n):
        """A strip of the cockpit floor over stations `xs`, across from ya(x) to yb(x) in n columns."""
        t = np.linspace(0, 1, n)
        ya, yb = np.broadcast_to(ya, xs.shape), np.broadcast_to(yb, xs.shape)
        Xf = np.broadcast_to(xs[:, None], (len(xs), n))
        Yf = ya[:, None] + (yb - ya)[:, None] * t[None, :]
        Zf = np.broadcast_to(self.floor_z(xs)[:, None], Yf.shape)
        part.add("nonslip", _orient_up(grid(np.stack([Xf, Yf, Zf], -1), np.stack([Xf, Yf], -1))))

    def _cockpit(self, part, xs):
        xs = xs[(xs >= self.xc0 - 1e-9) & (xs <= self.xc1 + 1e-9)]
        yc = self.yc(xs)
        zf = self.floor_z(xs)
        sl = self.helm["slot"] if self.helm else None
        if sl is None:
            self._floor(part, xs, -yc, yc, 9)
        else:
            # the floor round the wheel slot (data_format.md 3.7.3): aft and forward of it whole, beside it in two
            # strips; the slot a box with gelcoat walls and bottom
            xs_f = np.unique(np.concatenate([xs, [sl["x0"], sl["x1"]]]))
            aft, fwd = xs_f[xs_f <= sl["x0"] + 1e-9], xs_f[xs_f >= sl["x1"] - 1e-9]
            mid = xs_f[(xs_f >= sl["x0"] - 1e-9) & (xs_f <= sl["x1"] + 1e-9)]
            if len(aft) > 1:
                self._floor(part, aft, -self.yc(aft), self.yc(aft), 9)
            if len(fwd) > 1:
                self._floor(part, fwd, -self.yc(fwd), self.yc(fwd), 9)
            self._floor(part, mid, -self.yc(mid), -sl["y"], 3)
            self._floor(part, mid, sl["y"], self.yc(mid), 3)
            x0, x1, yw, zb = sl["x0"], sl["x1"], sl["y"], sl["z"]
            z0, z1 = float(self.floor_z(x0)), float(self.floor_z(x1))
            part.add("gelcoat", planar_polygon(np.array([[x0, -yw, zb], [x1, -yw, zb], [x1, yw, zb], [x0, yw, zb]]),
                                               [0, 0, 1]))
            part.add("gelcoat", planar_polygon(np.array([[x0, -yw, zb], [x0, yw, zb], [x0, yw, z0], [x0, -yw, z0]]),
                                               [1, 0, 0]))
            part.add("gelcoat", planar_polygon(np.array([[x1, yw, zb], [x1, -yw, zb], [x1, -yw, z1], [x1, yw, z1]]),
                                               [-1, 0, 0]))
            for sy in (1.0, -1.0):
                part.add("gelcoat", planar_polygon(np.array([[x0, sy * yw, zb], [x1, sy * yw, zb], [x1, sy * yw, z1],
                                                             [x0, sy * yw, z0]]), [0, -sy, 0]))
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
            # small bevels: a rounded lip on the coaming edge (half sunk into the corner) and a fillet where
            # the wall meets the floor
            rb = 0.012 * (self.hull.L / 12) ** 0.3
            if getattr(self, "_lite", 0) >= 2:
                continue
            edge = np.stack([xs, ytop, ztop], -1)[::2]
            prof = rounded_rect(2 * rb, 2 * rb, 0.95 * rb, 2)
            part.add("gelcoat", sweep(edge + np.array([0, side * 0.35 * rb, -0.35 * rb]), prof, up=np.array([0, 0, 1.0])))
            foot = np.stack([xs, ytop, zf], -1)[::2]
            part.add("nonslip", sweep(foot + np.array([0, -side * 0.45 * rb, 0.45 * rb]), prof * 1.2, up=np.array([0, 0, 1.0])))
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
    def _cabin(self, part, xs, n_roof=7, fine=True):
        """The coachroof on the deck stations from its aft face to where it meets the deck: per station a section
        from the starboard base over the fillet, the raked side, the edge radius and the cambered top to the port
        base (y increasing, so the grid faces up). Gelcoat sides and borders round a non-slip top."""
        xs = xs[(xs >= self.xk0 - 1e-9) & (xs <= self.xk1 + 1e-9)]
        h, yb = self.cab_height(xs), self.yk(xs)
        pr = self._cab_prof(h, yb)
        q = pr["q"]
        nf, ns, na = (2, 2, 4) if fine else ((1, 1, 3) if n_roof >= 4 else (1, 1, 2))
        # columns of the starboard half as distances inward from the base: fillet, raked side, edge radius
        dcols = [np.zeros_like(xs)]
        dcols += [pr["d1"] * (k / nf) for k in range(1, nf + 1)]
        dcols += [pr["d1"] + (pr["d2"] - pr["d1"]) * (k / ns) for k in range(1, ns + 1)]
        dcols += [pr["d2"] + (pr["d3"] - pr["d2"]) * (k / na) for k in range(1, na + 1)]
        D = np.stack(dcols, 1) / q[:, None]
        n_side = D.shape[1]
        y_e = yb - D[:, -1]
        y_m = np.maximum(y_e - 0.05, 0.5 * y_e)          # the top's gelcoat border, 5 cm
        Y_side = yb[:, None] - D                         # base -> roof edge, decreasing
        Y_top = y_m[:, None] * np.linspace(1, 0, n_roof)[None, :]
        half = np.concatenate([Y_side, Y_top], 1)        # from the base to the centreline
        Yrow = np.concatenate([-half, half[:, ::-1][:, 1:]], 1)     # starboard base -> port base
        X = np.broadcast_to(xs[:, None], Yrow.shape)
        Z = self.cabin_z(X, Yrow)
        P = np.stack([X, Yrow, Z], -1)
        # uv0: metres along and girth from the centreline
        seg_len = np.linalg.norm(np.diff(P, axis=1), axis=-1)
        g = np.concatenate([np.zeros((len(xs), 1)), np.cumsum(seg_len, 1)], 1)
        nc = Yrow.shape[1]
        g = g - g[:, nc // 2][:, None]
        uv = np.stack([X, g], -1)
        N = grid_normals(P)
        c0, c1 = n_side, nc - 1 - n_side                  # the top's border columns (y = -y_m and y_m)
        # rows of the non-slip top: from the aft edge's radius plus the border to where the top is 15 % high
        r0 = int(np.searchsorted(xs, self.xk0 + self.cab_r + 0.05))
        hi = np.nonzero(h >= 0.15 * self.cab_h)[0]
        r1 = int(hi.max()) if len(hi) else r0
        sub = lambda a, b, c, d: grid(P[a:b, c:d], uv[a:b, c:d], N=N[a:b, c:d])
        part.add("gelcoat", sub(0, len(xs), 0, c0 + 1))
        part.add("gelcoat", sub(0, len(xs), c1, nc))
        if r1 > r0 + 1:
            part.add("gelcoat", sub(0, r0 + 1, c0, c1 + 1))
            part.add("nonslip", sub(r0, r1 + 1, c0, c1 + 1))
            part.add("gelcoat", sub(r1, len(xs), c0, c1 + 1))
        else:
            part.add("gelcoat", sub(0, len(xs), c0, c1 + 1))
        self._roof_rows = P
        # aft face: from the cockpit floor up to the deck at the cockpit's edges, along the deck in to the coachroof's
        # base and up over its section at x = xk0
        x = self.xk0
        yck = float(self.yc(x))
        zf = float(self.floor_z(x))
        row = P[0]
        lip = np.linspace(yck, float(yb[0]), 5)[:-1] if yck > yb[0] + 1e-4 else np.zeros(0)
        poly = [[x, -yck, zf], [x, yck, zf]] + [[x, y, float(self.deck_z(x, y))] for y in lip]
        poly += [[x, p[1], p[2]] for p in row[::-1]]
        poly += [[x, -y, float(self.deck_z(x, y))] for y in lip[::-1]]
        part.add("face", planar_polygon(np.array(poly), [-1, 0, 0]))
        self._companionway(part, x, yck, zf, row)
        self._windows(part, xs, pr, yb, fine)

    def _drape(self, g, lift):
        """A shape built round z = 0 laid on the coachroof: every vertex lifted by the surface below it, so a
        hatch follows the top's slope and crown (flush, no gap and no corner sunk)."""
        P = g.P.copy()
        P[:, 2] += self.cabin_z(P[:, 0], P[:, 1]) + lift
        out = Geom(P, g.I, None, g.uv0, g.uv1)
        out.tag = g.tag
        return out

    def _companionway(self, part, x, yck, zf, roof_row):
        """Washboard opening in the aft face and a low sliding hatch lying on the top."""
        top = float(np.min(roof_row[len(roof_row) // 2 - 1: len(roof_row) // 2 + 2, 2]))
        w = min(0.42 * float(self.yk(x)), 0.375)          # the opening, about 0.5 m on a sportsboat
        z0, z1 = zf + 0.12 * self.ck_depth + 0.05, top - 0.035
        P = np.array([[x - 0.004, w, z0], [x - 0.004, -w, z0], [x - 0.004, -w * 0.88, z1], [x - 0.004, w * 0.88, z1]])
        part.add("glass", planar_polygon(P, [-1, 0, 0]))
        # sliding hatch: a low moulded lid following the top, with a tinted panel
        L = min(0.9, 0.3 * (self.xk1 - self.xk0))
        hx = x + 0.5 * L + 0.02
        self.companion = {"x": float(x), "half_width": float(w), "hatch_x": float(hx), "hatch_len": float(L),
                          "hatch_width": float(2 * w + 0.06)}
        lid = superellipsoid_box((L, 2 * w + 0.06, 0.045), 0.18, 16, 8, center=(hx, 0, 0.008))
        part.add("gelcoat", self._drape(lid, 0.0))
        pane = superellipsoid_box((L * 0.8, 2 * w - 0.05, 0.012), 0.1, 12, 6, center=(hx, 0, 0.027))
        part.add("glass", self._drape(pane, 0.0))

    def _windows(self, part, xs, pr, yb, fine):
        """Dark glazing along the raked sides where the top is at least 0.15 m high, just proud of the side."""
        if not self.cls["deck"]["cabin"].get("windows", True) or self.cab_h < 0.15:
            return
        h = self.cab_height(xs)
        ok = np.nonzero(h >= 0.15)[0]
        if len(ok) < 2:
            return
        xa = self.xk0 + 0.15 * (self.xk1 - self.xk0)
        xb = float(xs[ok.max()]) - 0.2
        if xb - xa < 0.3:
            return
        lite = getattr(self, "_lite", 0) >= 2
        xw = np.linspace(xa, xb, 24 if fine else (6 if lite else 10))
        hw, ybw = self.cab_height(xw), self.yk(xw)
        p = self._cab_prof(hw, ybw)
        t = np.linspace(0, 1, xw.size)
        env = np.sqrt(np.clip(np.sin(np.pi * t) * 1.8, 0, 1))
        rows = []
        for f in np.linspace(-1, 1, 3 if lite else 5):
            fm = 0.58 + 0.17 * f * env                 # along the raked side, from its foot (0) to its top (1)
            d = (p["d1"] + (p["d2"] - p["d1"]) * fm) / p["q"]
            y = ybw - d
            rows.append(np.stack([xw, y, self.cabin_z(xw, y)], -1))
        G = np.stack(rows, 1)
        nrm = normalize(np.cross(np.gradient(G, axis=0), np.gradient(G, axis=1)))
        nrm = nrm * np.sign(np.mean(nrm[..., 1]))      # outward: +y on this side
        G = G + nrm * 0.004
        for side in (1.0, -1.0):
            g = grid(G * [1, side, 1], np.stack([G[..., 0], G[..., 2]], -1))
            part.add("glass", _orient(g, np.array([0.0, side, 0.0])))

    # ------------------------------------------------------------------------------------------------------
    def _transom(self, part):
        """The transom face: its own slot (the livery paints it in the hull's colours) and uv1."""
        g = planar_polygon(self.transom_outline(), [-1, 0, 0])
        g.uv1 = self.transom_uv1(g.P)
        part.add("transom", g)

    def _sheer_trim(self, part, n=120, lite=0):
        """Toe rail on the deck edge and a rub strake just below the sheer on the hull (`lite`: plainer sections,
        2 without the rub strake)."""
        hull = self.hull
        xs = np.linspace(0.0, hull.L - 0.01, n)
        tr = float(self.cls["deck"]["toe_rail"])
        for side in (1.0, -1.0):
            bs = hull.bs(xs)
            inboard = np.minimum(tr * 0.6, bs * 0.5)
            path = np.stack([xs, side * (bs - inboard), self.deck_z(xs, bs - inboard) + tr * 0.35], -1)
            prof = rounded_rect(tr * 0.9, tr * 0.7, tr * 0.25, 2)
            if lite:
                prof = np.array([[0.45, 0.35], [-0.45, 0.35], [-0.45, -0.35], [0.45, -0.35]]) * tr
            part.add("gelcoat", sweep(path, prof, up=np.array([0, 0, 1.0])))
            if lite >= 2:
                continue
            # rub strake: a small half-round just below the sheer, following the topside
            y2 = np.array([hull.half_breadth_at(x, float(hull.zs(np.array([x]))[0]) - 0.03) for x in xs])
            path2 = np.stack([xs, side * (y2 + 0.004), hull.zs(xs) - 0.03], -1)
            ok = y2 > 0.02
            if ok.sum() > 4 and n >= 40:     # the rub strake is left out of the far level of detail
                rs = rounded_rect(0.022, 0.018, 0.008, 2) if not lite else \
                    np.array([[0.009, 0.011], [-0.009, 0.011], [-0.009, -0.011], [0.009, -0.011]])
                part.add("rubber", sweep(path2[ok], rs, up=np.array([0, 0, 1.0])))


def _orient(g, want):
    """Flip a surface so that its average normal agrees with the wanted direction."""
    if np.mean(g.N @ np.asarray(want, dtype=np.float64)) < 0:
        return g.flipped()
    return g


def _orient_up(g):
    return _orient(g, np.array([0, 0, 1.0]))
