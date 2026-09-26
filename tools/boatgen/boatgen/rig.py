"""Mast, boom, spreaders, bowsprit and standing rigging.

Rig measurements follow the usual conventions: I is the foretriangle height from the sheer at the mast to the
forestay hounds, J the foretriangle base from the forestay tack to the mast front, P the mainsail hoist above the
boom, E the foot from the mast aft face along the boom. mast_height is the masthead above the DWL.
"""
import numpy as np

from .mesh import (Part, sweep, ellipse, rounded_rect, tube, revolve, superellipsoid_box, box, normalize,
                   translate, rot_axis, frame_z, merge)


class Rig:
    def __init__(self, cls, hull, deck):
        self.cls, self.hull, self.deck = cls, hull, deck
        r = cls["rig"]
        L = hull.L
        self.scale = (L / 12.0) ** 0.6
        self.chord = float(r["mast_chord"])
        self.width = self.chord * float(r["mast_width"])
        self.x_mast = float(r["mast_x"]) - self.chord / 2        # mast axis; mast_x is the front at the deck
        self.x_tack = float(r["mast_x"]) + float(r["J"])
        self.z_tack = float(deck.surface(min(self.x_tack, L - 0.02), 0.0)[0]) + 0.04
        self.z_step = float(deck.surface(self.x_mast, 0.0)[0])
        self.z_sheer = float(hull.zs(np.array([self.x_mast]))[0])
        self.z_top = float(r["mast_height"])                     # masthead above the DWL
        self.z_hounds = min(self.z_sheer + float(r["I"]), self.z_top - 0.05)
        self.P, self.E = float(r["P"]), float(r["E"])
        bh = r["boom_height"]
        self.z_boom = float(bh) if bh is not None else self.z_top - self.P - 0.25 * self.scale
        self.x_mast_aft = self.x_mast - self.chord / 2
        self.z_head = min(self.z_boom + 0.08 + self.P, self.z_top - 0.08)
        self.masthead_rig = float(r["fractional"]) > 0.93
        self.sprit = float(r["bowsprit"])
        self.sprit_end = np.array([L + self.sprit, 0.0, float(hull.zs(np.array([L]))[0]) - 0.02 - 0.04 * self.sprit])
        # spinnaker pole (docs/specs/sail_visuals.md 7.3): flown with a symmetric spinnaker, or with an asymmetric
        # one on a class that has a pole and no bowsprit. At rest it points forward on the centreline at the tack
        # height; its pivot is on the mast axis, so it turns with the sail about the mast.
        types = {s["type"] for s in cls["sails"]}
        self.pole_flown = "spinnaker_sym" in types or (
            float(r["pole"]) > 0 and self.sprit <= 0 and "spinnaker_asym" in types)
        self.pole_len = (float(r["pole"]) or 0.95 * float(r["J"])) if self.pole_flown else 0.0
        z_pole = self.z_step + 1.0 * (L / 12) ** 0.5
        self.pole_pivot = np.array([self.x_mast, 0.0, z_pole])
        self.pole_end = np.array([self.x_mast + self.chord / 2 + self.pole_len, 0.0, z_pole])
        self.boom_len = self.E + 0.25 * self.scale
        self.gooseneck = np.array([self.x_mast_aft - 0.03, 0.0, self.z_boom])
        # spreaders
        n = int(r["spreaders"])
        self.sweep = float(r["spreader_sweep"])
        top_ref = self.z_hounds if not self.masthead_rig else self.z_top - 0.3
        self.chainplate_x = self.x_mast - 0.05 - 0.35 * np.tan(self.sweep) * self.scale
        bs_cp = float(hull.bs(np.array([self.chainplate_x]))[0])
        self.chainplate_y = bs_cp - 0.10 * self.scale
        self.chainplate_z = float(deck.deck_z(self.chainplate_x, self.chainplate_y)) + 0.02
        self.spreaders = []
        for i in range(n):
            f = (i + 1) / (n + 1) * (0.96 if n > 1 else 1.05)
            z = self.z_step + (top_ref - self.z_step) * f
            # tip reach from the half-beam: lower spreaders reach out further
            reach = self.chainplate_y * (0.92 - 0.2 * i / max(n, 1)) * (1.0 if n > 1 else 0.85)
            tip = np.array([self.x_mast - reach * np.tan(self.sweep), reach, z + 0.04 * self.scale])
            self.spreaders.append((z, tip))
        self.cap_top = np.array([self.x_mast, 0.0, top_ref])

    # ------------------------------------------------------------------------------------------------------
    def mast_part(self):
        p = Part()
        s = self.scale
        zs = np.linspace(self.z_step - 0.1, self.z_top, 40)
        taper = np.where(zs < self.z_hounds, 1.0, 1.0 - 0.42 * (zs - self.z_hounds) / max(self.z_top - self.z_hounds, 1e-3))
        path = np.stack([np.full_like(zs, self.x_mast), np.zeros_like(zs), zs], -1)
        prof = _mast_section(self.chord, self.width, 24)
        p.add("carbon", sweep(path, prof, scale_along=taper, up=np.array([1.0, 0, 0])))
        # mast collar / partner ring at the deck
        ring = revolve([(0.0, 0.0), (self.chord * 0.75, 0.0), (self.chord * 0.72, 0.035), (self.chord * 0.55, 0.06),
                        (0.0, 0.06)], 24)
        p.add("rubber", ring.transformed(translate([self.x_mast, 0, self.z_step - 0.005]) @ np.diag([1, self.width / self.chord, 1, 1])))
        # mast step plate on the deck
        p.add("metal", superellipsoid_box((self.chord * 1.9, self.width * 2.2, 0.012), 0.2, 12, 4,
                                          center=[self.x_mast, 0, self.z_step + 0.004]))
        # masthead crane: a cap with an arm reaching aft over the main halyard sheave, wind wand and antenna
        top = np.array([self.x_mast, 0, self.z_top])
        p.add("carbon", superellipsoid_box((self.chord * 1.3, self.width * 0.8, 0.07 * s), 0.3, 12, 6,
                                           center=top + [-0.1 * self.chord, 0, 0.02]))
        crane = np.array([top + [0.0, 0, 0.04 * s], top + [-self.chord - 0.18 * s, 0, 0.05 * s]])
        p.add("carbon", sweep(crane, rounded_rect(0.05 * s, 0.045 * s, 0.012 * s, 2), up=np.array([0, 0, 1.0]),
                              scale_along=np.array([1.0, 0.7])))
        for sy in (-1, 1):
            p.add("metal", revolve([(0, -0.006), (0.035 * s, -0.006), (0.035 * s, 0.006), (0, 0.006)], 12, sharp=(1, 2))
                  .transformed(translate(crane[1] + [0.03 * s, sy * 0.012, -0.03 * s]) @ rot_axis([1, 0, 0], np.pi / 2)))
        # instruments on the mast front just above the gooseneck (a bank of three on the bigger boats)
        n_ins = 3 if self.hull.L >= 9.0 else 1
        for k in range(n_ins):
            z = self.z_boom + 0.35 * s + k * 0.2 * s
            ins = Part()
            ins.add("carbon", superellipsoid_box((0.04 * s, 0.2 * s, 0.16 * s), 0.2, 10, 5, center=(0.02 * s, 0, 0)))
            ins.add("glass", superellipsoid_box((0.01 * s, 0.17 * s, 0.13 * s), 0.12, 10, 4, center=(0.042 * s, 0, 0)))
            p.extend(ins, translate([self.x_mast + self.chord / 2, 0, z]))
        # halyard sheave boxes at the hounds and below the masthead
        for z in (self.z_hounds + 0.08 * s, self.z_top - 0.12):
            p.add("metal", superellipsoid_box((0.02, self.width * 0.5, 0.14 * s), 0.3, 8, 4,
                                              center=[self.x_mast + self.chord * 0.49, 0, z]))
        wand0 = top + [0.1, 0, 0.05]
        wand1 = top + [0.9 * s, 0, 0.35 * s]
        p.add("carbon", tube(np.array([wand0, wand1]), 0.008, 6))
        p.add("metal", tube(np.array([wand1, wand1 + [0, 0, 0.12 * s]]), 0.004, 6))
        for k in range(3):
            a = 2 * np.pi * k / 3
            arm = np.array([np.cos(a), np.sin(a), 0]) * 0.06 * s
            p.add("rubber", superellipsoid_box((0.025, 0.025, 0.025), 1.0, 8, 5, center=wand1 + [0, 0, 0.12 * s] + arm))
        p.add("metal", tube(np.array([top + [-0.1, 0.03, 0.05], top + [-0.1, 0.03, 0.95 * s]]), 0.005, 6))
        # spreaders: tapered aerofoil bars
        for z, tip in self.spreaders:
            for side in (1.0, -1.0):
                root = np.array([self.x_mast, side * self.width * 0.45, z])
                t = tip * [1, side, 1]
                path = np.linspace(root, t, 8)
                sc = np.linspace(1.0, 0.55, 8)
                sp = sweep(path, ellipse(0.045 * s, 0.014 * s, 12), scale_along=sc, up=np.array([1.0, 0, 0]))
                p.add("carbon", sp)
                # tip: end fitting clamping the cap shroud, in a rubber boot; root bracket on the mast wall
                p.add("metal", superellipsoid_box((0.05 * s, 0.03 * s, 0.03 * s), 0.4, 8, 5, center=t))
                boot = revolve([(0, -0.07 * s), (0.012 * s, -0.07 * s), (0.028 * s, -0.02 * s), (0.03 * s, 0.03 * s),
                                (0.012 * s, 0.07 * s), (0, 0.07 * s)], 10)
                p.add("rubber", boot.transformed(translate(t)))
                p.add("metal", superellipsoid_box((0.1 * s, 0.035 * s, 0.07 * s), 0.3, 8, 5,
                                                  center=root + [0, side * 0.01 * s, 0]))
        # gooseneck: a bracket on the mast's aft face with a vertical pin; vang tang at the mast foot
        g = self.gooseneck
        p.add("metal", superellipsoid_box((0.05 * s, self.width * 0.9, 0.26 * s), 0.3, 10, 6,
                                          center=[self.x_mast_aft + 0.012, 0, g[2]]))
        for dz in (-0.07 * s, 0.07 * s):
            p.add("metal", superellipsoid_box((0.1 * s, self.width * 0.55, 0.025 * s), 0.35, 8, 4,
                                              center=[g[0] + 0.015, 0, g[2] + dz]))
        p.add("metal", tube(np.array([g + [0, 0, -0.1 * s], g + [0, 0, 0.1 * s]]), 0.012 * s, 8))
        p.add("metal", superellipsoid_box((0.06 * s, 0.06 * s, 0.08 * s), 0.3, 8, 4,
                                          center=[self.x_mast_aft - 0.01, 0, self.z_step + 0.25 * s]))
        # hounds tang
        p.add("metal", superellipsoid_box((0.08 * s, self.width * 0.9, 0.12 * s), 0.3, 8, 5,
                                          center=[self.x_mast + self.chord * 0.5, 0, self.z_hounds]))
        if self.sprit > 0:
            L = self.hull.L
            a = np.array([L - 0.9 * s, 0, float(self.deck.deck_z(L - 0.9 * s, 0)) + 0.06 * s])
            path = np.linspace(a, self.sprit_end, 10)
            r0 = 0.04 * s
            p.add("carbon", sweep(path, _circle(r0, 16), scale_along=np.linspace(1, 0.75, 10)))
            p.add("metal", superellipsoid_box((0.06 * s, 0.06 * s, 0.06 * s), 0.5, 8, 5, center=self.sprit_end))
        return p

    def turnbuckle_len(self):
        return 0.16 * self.scale

    def wires(self):
        """Standing rigging as (start, end, radius) segments; shrouds start on top of their rigging screws."""
        s = self.scale
        r_cap = max(0.0045 * s, 0.003)
        segs = []
        tb = self.turnbuckle_len()
        for side in (1.0, -1.0):
            cp = np.array([self.chainplate_x, side * self.chainplate_y, self.chainplate_z + tb])
            tips = [t * [1, side, 1] for _, t in self.spreaders]
            pts = [cp] + tips + [self.cap_top + [0, side * self.width * 0.4, 0]]
            for a, b in zip(pts[:-1], pts[1:]):
                segs.append((a, b, r_cap))
            # lowers: chainplate to the mast under the first spreader
            z1 = self.spreaders[0][0]
            segs.append((cp + [0.06 * s, 0, 0], np.array([self.x_mast, side * self.width * 0.4, z1 - 0.02]), r_cap * 0.9))
            # intermediates: each spreader tip to the mast under the next spreader
            for i in range(1, len(self.spreaders)):
                zi = self.spreaders[i][0]
                segs.append((tips[i - 1], np.array([self.x_mast, side * self.width * 0.4, zi - 0.02]), r_cap * 0.85))
        segs.append((np.array([self.x_tack, 0, self.z_tack + tb]),
                     np.array([self.x_mast + self.chord / 2, 0, self.z_hounds]), r_cap * 1.1))
        if self.cls["rig"]["backstay"]:
            z_bs = float(self.deck.deck_z(0.15, 0.0)) + 0.05 + tb
            segs.append((np.array([self.x_mast - self.chord * 0.6, 0, self.z_top - 0.05]), np.array([0.15, 0, z_bs]),
                         r_cap * 0.9))
        if self.sprit > 0:
            # bobstay from the sprit end to the stem near the waterline
            L = self.hull.L
            segs.append((self.sprit_end, np.array([L - 0.02, 0, 0.18 * s]), r_cap * 0.9))
        return segs

    def rigging_part(self):
        p = Part()
        for a, b, r in self.wires():
            p.add("metal", tube(np.array([a, b]), r, 6, caps=False))
            # swaged terminals at both ends
            d = normalize(b - a)
            for e, sgn in ((a, 1.0), (b, -1.0)):
                p.add("metal", tube(np.array([e, e + sgn * d * 0.09]), r * 2.0, 8))
        # chainplates (a deck cover plate and the strap), rigging screws on the shrouds, forestay and backstay
        s = self.scale
        tb = self.turnbuckle_len()
        r_cap = max(0.0045 * s, 0.003)
        from .hardware import turnbuckle
        feet = []
        for side in (1.0, -1.0):
            cp = np.array([self.chainplate_x, side * self.chainplate_y, self.chainplate_z])
            p.add("metal", superellipsoid_box((0.16 * s, 0.07 * s, 0.012), 0.25, 10, 4, center=cp - [0, 0, 0.012]))
            p.add("metal", superellipsoid_box((0.10 * s, 0.012, 0.06 * s), 0.3, 8, 5, center=cp + [0, 0, 0.01]))
            feet.append((cp, np.array([self.chainplate_x, side * self.width * 0.4, self.spreaders[0][0] - 0.02])))
        feet.append((np.array([self.x_tack, 0, self.z_tack]), np.array([self.x_mast + self.chord / 2, 0, self.z_hounds])))
        p.add("metal", superellipsoid_box((0.14 * s, 0.06 * s, 0.05 * s), 0.3, 8, 5,
                                          center=[self.x_tack, 0, self.z_tack - 0.01]))
        if self.cls["rig"]["backstay"]:
            z_bs = float(self.deck.deck_z(0.15, 0.0)) + 0.05
            feet.append((np.array([0.15, 0, z_bs]), np.array([self.x_mast - self.chord * 0.6, 0, self.z_top - 0.05])))
        for foot, top in feet:
            d = normalize(top - foot)
            M = frame_z(foot, d, np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 1.0, 0]))
            p.extend(turnbuckle(tb, r_cap * 1.4), M)
        return p

    def boom_part(self):
        """Boom in the boat frame (the writer stores it relative to the gooseneck pivot)."""
        p = Part()
        s = self.scale
        n = 16
        t = np.linspace(0, 1, n)
        path = np.stack([self.gooseneck[0] - t * self.boom_len, np.zeros(n), np.full(n, self.gooseneck[2])], -1)
        depth = 0.17 * s
        prof = rounded_rect(depth, 0.085 * s, 0.03 * s, 3)
        sc = 1.0 - 0.25 * t ** 2
        p.add("carbon", sweep(path, prof, scale_along=sc, up=np.array([0, 0, 1.0])))
        # end fitting and outhaul
        end = path[-1]
        p.add("metal", superellipsoid_box((0.10 * s, 0.07 * s, depth * 0.8), 0.3, 8, 5, center=end))
        # vang: from the mast foot to the boom
        a = np.array([self.x_mast_aft - 0.02, 0, self.z_step + 0.25 * s])
        b = self.gooseneck + [-0.2 * self.E, 0, -depth * 0.4]
        p.add("carbon", tube(np.array([a, a + 0.62 * (b - a)]), 0.025 * s, 10))
        p.add("metal", tube(np.array([a + 0.55 * (b - a), b]), 0.016 * s, 10))
        p.add("metal", superellipsoid_box((0.08 * s, 0.05 * s, 0.05 * s), 0.4, 8, 4, center=a))
        p.add("metal", superellipsoid_box((0.1 * s, 0.07 * s, 0.05 * s), 0.3, 8, 4, center=b + [0, 0, 0.01 * s]))
        # outhaul line along the boom side, cheek blocks near the gooseneck
        for sy in (-1, 1):
            p.add("metal", superellipsoid_box((0.09 * s, 0.02 * s, 0.05 * s), 0.35, 8, 4,
                                              center=self.gooseneck + [-0.35 * s, sy * 0.045 * s, 0.0]))
        p.add("rope", tube(np.array([end + [0.05 * s, 0.047 * s, 0.02 * s], self.gooseneck + [-0.35 * s, 0.047 * s, 0.02 * s]]),
                           max(0.0035, 0.004 * s), 6))
        self.boom_end = end
        return p


    def pole_part(self):
        """Spinnaker pole in the boat frame, pointing forward from the mast front (the writer stores it relative
        to its pivot on the mast axis)."""
        p = Part()
        s = self.scale
        heel = np.array([self.x_mast + self.chord / 2, 0.0, self.pole_pivot[2]])
        path = np.linspace(heel + [0.04 * s, 0, 0], self.pole_end - [0.05 * s, 0, 0], 10)
        t = np.linspace(-1.0, 1.0, 10)
        p.add("carbon", sweep(path, _circle(0.03 * s, 16), scale_along=1.0 - 0.3 * t ** 2))
        # heel fitting on the mast ring and end fitting at the tack
        p.add("metal", superellipsoid_box((0.08 * s, 0.05 * s, 0.05 * s), 0.5, 8, 5, center=heel + [0.03 * s, 0, 0]))
        p.add("metal", superellipsoid_box((0.08 * s, 0.045 * s, 0.045 * s), 0.5, 8, 5,
                                          center=self.pole_end - [0.03 * s, 0, 0]))
        p.add("metal", revolve([(0.0, 0.0), (self.chord * 0.62, 0.0), (self.chord * 0.62, 0.05 * s), (0.0, 0.05 * s)],
                               16).transformed(translate(self.pole_pivot - [0, 0, 0.025 * s])
                                               @ np.diag([1, self.width / self.chord, 1, 1])))
        return p


def _mast_section(c, w, n):
    """Mast section: round leading edge, flatter sides, slightly pointed aft (sail track)."""
    th = np.linspace(0, 2 * np.pi, n + 1)[:-1]
    x = 0.5 * c * np.cos(th)
    y = 0.5 * w * np.sin(th) * (1 - 0.18 * np.clip(-np.cos(th), 0, 1))
    return np.stack([x, y], -1)


def _circle(r, n):
    th = np.linspace(0, 2 * np.pi, n + 1)[:-1]
    return np.stack([r * np.cos(th), r * np.sin(th)], -1)
