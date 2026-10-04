"""Mast, boom, spreaders, bowsprit and standing rigging.

Rig measurements follow the usual conventions: I is the foretriangle height from the sheer at the mast to the
forestay hounds, J the foretriangle base from the forestay tack to the mast front, P the mainsail hoist above the
boom, E the foot from the mast aft face along the boom. mast_height is the masthead above the DWL.
"""
import numpy as np

from .mesh import (Part, sweep, ellipse, rounded_rect, tube, revolve, superellipsoid_box, box, normalize,
                   translate, rot_axis, frame_z, merge, seg)


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
        self.chainplate_z = float(deck.surface(self.chainplate_x, self.chainplate_y)[0])     # the deck there
        self.spreaders = []
        for i in range(n):
            f = (i + 1) / (n + 1) * (0.96 if n > 1 else 1.05)
            z = self.z_step + (top_ref - self.z_step) * f
            # tip reach from the half-beam: lower spreaders reach out further
            reach = self.chainplate_y * (0.92 - 0.2 * i / max(n, 1)) * (1.0 if n > 1 else 0.85)
            tip = np.array([self.x_mast - reach * np.tan(self.sweep), reach, z + 0.04 * self.scale])
            self.spreaders.append((z, tip))
        self.cap_top = np.array([self.x_mast, 0.0, top_ref])
        # masthead crane arm (root over the mast axis, end aft over the main halyard sheave; the backstay's head)
        top = np.array([self.x_mast, 0, self.z_top])
        self.crane = np.array([top + [0.0, 0, 0.04 * self.scale], top + [-self.chord - 0.18 * self.scale, 0, 0.05 * self.scale]])

    def taper(self, z):
        """Mast section scale at height z (1 up to the hounds, 0.58 at the masthead)."""
        z = np.asarray(z, dtype=np.float64)
        return np.where(z < self.z_hounds, 1.0,
                        1.0 - 0.42 * (z - self.z_hounds) / max(self.z_top - self.z_hounds, 1e-3))

    def boom_bottom(self, x):
        """Height of the boom's underside at x (rest position, boat frame)."""
        t = np.clip((self.gooseneck[0] - x) / self.boom_len, 0, 1)
        return self.gooseneck[2] - 0.5 * 0.17 * self.scale * (1.0 - 0.25 * t ** 2)

    # ------------------------------------------------------------------------------------------------------
    def mast_part(self):
        p = Part()
        s = self.scale
        zs = np.linspace(self.z_step - 0.1, self.z_top, seg(40, 8))
        taper = self.taper(zs)
        path = np.stack([np.full_like(zs, self.x_mast), np.zeros_like(zs), zs], -1)
        prof = _mast_section(self.chord, self.width, seg(24, 8))
        p.add("carbon", sweep(path, prof, scale_along=taper, up=np.array([1.0, 0, 0])), tag="mast")
        p.attach("mast", "deck")
        # mast collar / partner ring at the deck
        ring = revolve([(0.0, 0.0), (self.chord * 0.75, 0.0), (self.chord * 0.72, 0.035), (self.chord * 0.55, 0.06),
                        (0.0, 0.06)], 24)
        p.add("rubber", ring.transformed(translate([self.x_mast, 0, self.z_step - 0.005]) @ np.diag([1, self.width / self.chord, 1, 1])),
              tag="mast_collar")
        p.attach("mast_collar", "deck")
        # mast step plate on the deck
        p.add("metal", superellipsoid_box((self.chord * 1.9, self.width * 2.2, 0.012), 0.2, 12, 4,
                                          center=[self.x_mast, 0, self.z_step + 0.004]), tag="mast_step")
        p.attach("mast_step", "deck")
        # masthead crane: a cap with an arm reaching aft over the main halyard sheave, wind wand and antenna
        top = np.array([self.x_mast, 0, self.z_top])
        p.add("carbon", superellipsoid_box((self.chord * 1.3, self.width * 0.8, 0.07 * s), 0.3, 12, 6,
                                           center=top + [-0.1 * self.chord, 0, 0.02]), tag="masthead")
        p.attach("masthead", "mast")
        crane = self.crane
        p.add("carbon", sweep(crane, rounded_rect(0.05 * s, 0.045 * s, 0.012 * s, 2), up=np.array([0, 0, 1.0]),
                              scale_along=np.array([1.0, 0.7])), tag="crane")
        p.attach("crane", "masthead")
        for sy in (-1, 1):
            p.add("metal", revolve([(0, -0.006), (0.035 * s, -0.006), (0.035 * s, 0.006), (0, 0.006)], 12, sharp=(1, 2))
                  .transformed(translate(crane[1] + [0.03 * s, sy * 0.012, -0.03 * s]) @ rot_axis([1, 0, 0], np.pi / 2)),
                  tag=f"crane_sheave_{sy}")
            p.attach(f"crane_sheave_{sy}", "crane")
        # instruments on the mast front just above the gooseneck (a bank of three on the bigger boats)
        n_ins = 3 if self.hull.L >= 9.0 else 1
        for k in range(n_ins):
            z = self.z_boom + 0.35 * s + k * 0.2 * s
            ins = Part()
            ins.add("carbon", superellipsoid_box((0.04 * s, 0.2 * s, 0.16 * s), 0.2, 10, 5, center=(0.02 * s, 0, 0)))
            ins.add("glass", superellipsoid_box((0.01 * s, 0.17 * s, 0.13 * s), 0.12, 10, 4, center=(0.042 * s, 0, 0)))
            p.extend(ins, translate([self.x_mast + self.chord / 2, 0, z]), tag=f"mast_instrument_{k}")
            p.attach(f"mast_instrument_{k}", "mast")
        # halyard sheave boxes at the hounds and below the masthead
        # (on the mast's front face, which narrows above the hounds)
        for k, z in enumerate((self.z_hounds + 0.08 * s, self.z_top - 0.12)):
            p.add("metal", superellipsoid_box((0.02, self.width * 0.5 * float(self.taper(z)), 0.14 * s), 0.3, 8, 4,
                                              center=[self.x_mast + 0.5 * self.chord * float(self.taper(z)) - 0.004, 0, z]),
                  tag=f"sheave_box_{k}")
            p.attach(f"sheave_box_{k}", "mast")
        # wind wand from the masthead cap's front face, anemometer cups on spokes round its post
        cap_front = top + [0.55 * self.chord - 0.01, 0, 0.02]
        wand1 = top + [0.9 * s, 0, 0.35 * s]
        p.add("carbon", tube(np.array([cap_front, wand1]), 0.008, 6), tag="wind_wand")
        p.attach("wind_wand", "masthead")
        hub = wand1 + [0, 0, 0.12 * s]
        p.add("metal", tube(np.array([wand1 - [0, 0, 0.01], hub]), 0.004, 6), tag="anemometer")
        p.attach("anemometer", "wind_wand")
        for k in range(3):
            a = 2 * np.pi * k / 3
            arm = np.array([np.cos(a), np.sin(a), 0]) * 0.06 * s
            p.add("metal", tube(np.array([hub, hub + arm]), 0.0015, 4), tag="anemometer")
            p.add("rubber", superellipsoid_box((0.025, 0.025, 0.025), 1.0, 8, 5, center=hub + arm), tag="anemometer")
        # VHF antenna standing on the crane arm
        c = crane[0] + 0.45 * (crane[1] - crane[0])
        base = c + [0, 0.012 * s, 0.5 * 0.05 * s * 0.86 - 0.004]
        p.add("metal", tube(np.array([base, base + [0, 0, 0.9 * s]]), 0.005, 6), tag="antenna")
        p.attach("antenna", "crane")
        # spreaders: tapered aerofoil bars
        for i, (z, tip) in enumerate(self.spreaders):
            for side in (1.0, -1.0):
                sp_tag = f"spreader_{i}_{'port' if side > 0 else 'stbd'}"
                root = np.array([self.x_mast, side * self.width * 0.45, z])
                t = tip * [1, side, 1]
                path = np.linspace(root, t, 8)
                sc = np.linspace(1.0, 0.55, 8)
                sp = sweep(path, ellipse(0.045 * s, 0.014 * s, 12), scale_along=sc, up=np.array([1.0, 0, 0]))
                p.add("carbon", sp, tag=sp_tag)
                p.attach(sp_tag, "mast")
                # tip: end fitting clamping the cap shroud, in a rubber boot; root bracket on the mast wall
                p.add("metal", superellipsoid_box((0.05 * s, 0.03 * s, 0.03 * s), 0.4, 8, 5, center=t), tag=sp_tag + "_tip")
                p.attach(sp_tag + "_tip", sp_tag)
                boot = revolve([(0, -0.07 * s), (0.012 * s, -0.07 * s), (0.028 * s, -0.02 * s), (0.03 * s, 0.03 * s),
                                (0.012 * s, 0.07 * s), (0, 0.07 * s)], 10)
                p.add("rubber", boot.transformed(translate(t)), tag=sp_tag + "_boot")
                p.attach(sp_tag + "_boot", sp_tag)
                p.add("metal", superellipsoid_box((0.1 * s, 0.035 * s, 0.07 * s), 0.3, 8, 5,
                                                  center=root + [0, side * 0.01 * s, 0]), tag=sp_tag + "_root")
                p.attach(sp_tag + "_root", "mast")
        # gooseneck: a bracket on the mast's aft face with a vertical pin; vang tang at the mast foot
        g = self.gooseneck
        p.add("metal", superellipsoid_box((0.05 * s, self.width * 0.9, 0.26 * s), 0.3, 10, 6,
                                          center=[self.x_mast_aft + 0.012, 0, g[2]]), tag="gooseneck")
        p.attach("gooseneck", "mast")
        for dz in (-0.07 * s, 0.07 * s):
            p.add("metal", superellipsoid_box((0.1 * s, self.width * 0.55, 0.025 * s), 0.35, 8, 4,
                                              center=[g[0] + 0.015, 0, g[2] + dz]), tag="gooseneck_jaws")
        p.attach("gooseneck_jaws", "gooseneck")
        p.add("metal", tube(np.array([g + [0, 0, -0.1 * s], g + [0, 0, 0.1 * s]]), 0.012 * s, 8), tag="gooseneck_pin")
        p.attach("gooseneck_pin", "gooseneck_jaws")
        p.add("metal", superellipsoid_box((0.06 * s, 0.06 * s, 0.08 * s), 0.3, 8, 4,
                                          center=[self.x_mast_aft - 0.01, 0, self.z_step + 0.25 * s]), tag="vang_tang")
        p.attach("vang_tang", "mast")
        # hounds tang
        p.add("metal", superellipsoid_box((0.08 * s, self.width * 0.9, 0.12 * s), 0.3, 8, 5,
                                          center=[self.x_mast + self.chord * 0.5, 0, self.z_hounds]), tag="hounds")
        p.attach("hounds", "mast")
        if self.sprit > 0:
            L = self.hull.L
            a = np.array([L - 0.9 * s, 0, float(self.deck.deck_z(L - 0.9 * s, 0)) + 0.06 * s])
            path = np.linspace(a, self.sprit_end, 10)
            r0 = 0.04 * s
            p.add("carbon", sweep(path, _circle(r0, 16), scale_along=np.linspace(1, 0.75, 10)), tag="sprit")
            p.attach("sprit", "deck", "hull")
            p.add("metal", superellipsoid_box((0.06 * s, 0.06 * s, 0.06 * s), 0.5, 8, 5, center=self.sprit_end),
                  tag="sprit_end")
            p.attach("sprit_end", "sprit")
        return p

    def turnbuckle_len(self):
        return 0.16 * self.scale

    def wire_radius(self):
        return max(0.0045 * self.scale, 0.003)

    def strap_height(self):
        return 0.07 * self.scale

    def split_backstay(self):
        """True when the backstay cannot land on the centreline aft (an open transom: the cockpit runs out there)
        and splits into two legs to the quarters."""
        return bool(self.cls["rig"]["backstay"]) and self.deck.in_cockpit(0.15, 0.0)

    def feet(self):
        """Wire feet on deck: {name: (pin point, direction up the wire, host tag)}. Each foot is the pin of a
        rigging screw standing on a chainplate strap (the stemhead fitting for the forestay); the wire's own
        direction sets the screw's, so screw and wire stay in line."""
        s = self.scale
        hs = self.strap_height()
        out = {}
        for side in (1.0, -1.0):
            sd = "port" if side > 0 else "stbd"
            for kind, dx, top in (("cap", 0.0, self.spreaders[0][1] * [1, side, 1]),
                                  ("lower", 0.07 * s, self.lower_top(side))):
                x, y = self.chainplate_x + dx, side * self.chainplate_y
                F = np.array([x, y, float(self.deck.surface(x, y)[0]) + hs - 0.015 * s])
                out[f"{kind}_{sd}"] = (F, normalize(top - F), f"chainplate_{sd}_{kind}")
        F = np.array([self.x_tack, 0.0, self.z_tack])
        out["forestay"] = (F, normalize(np.array([self.x_mast + self.chord / 2, 0, self.z_hounds]) - F), "stemhead")
        if self.cls["rig"]["backstay"]:
            if self.split_backstay():
                sp = self.backstay_split()
                for side in (1.0, -1.0):
                    sd = "port" if side > 0 else "stbd"
                    x, y = self.backstay_leg_xy(side)
                    F = np.array([x, y, float(self.deck.surface(x, y)[0]) + hs - 0.015 * s])
                    out[f"backstay_{sd}"] = (F, normalize(sp - F), f"backstay_plate_{sd}")
            else:
                F = np.array([0.15, 0.0, float(self.deck.surface(0.15, 0.0)[0]) + hs - 0.015 * s])
                out["backstay"] = (F, normalize(self.crane[1] - F), "backstay_plate")
        return out

    def lower_top(self, side):
        return np.array([self.x_mast, side * self.width * 0.4, self.spreaders[0][0] - 0.02])

    def backstay_leg_xy(self, side):
        x = 0.15
        yc, bs = float(self.deck.yc(x)), float(self.hull.bs(np.array([x]))[0])
        return x, side * (0.5 * (yc + bs) - 0.02 * self.scale)

    def backstay_split(self):
        """Where a split backstay divides: on the line from the crane down to the transom, a sixth of the way up."""
        z0 = float(self.deck.deck_z(0.15, 0.0))
        a, b = self.crane[1], np.array([0.15, 0.0, z0])
        return b + (a - b) * (1.4 * self.scale / max(np.linalg.norm(a - b), 1e-6))

    def wires(self):
        """Standing rigging as (start, end, radius, name, host at the start, host at the end) segments. A wire
        with a deck end starts on top of its rigging screw, in line with it; the top ends run into the mast wall,
        the spreader tip fittings, the hounds or the crane."""
        s = self.scale
        r_cap = self.wire_radius()
        segs = []
        tb = self.turnbuckle_len() - 0.012
        feet = self.feet()
        for side in (1.0, -1.0):
            sd = "port" if side > 0 else "stbd"
            F, d, _ = feet[f"cap_{sd}"]
            tips = [t * [1, side, 1] for _, t in self.spreaders]
            zc = self.cap_top[2]
            cap_head = np.array([self.x_mast, side * min(0.4, 0.45 * float(self.taper(zc))) * self.width, zc])
            pts = [F + d * tb] + tips + [cap_head]
            hosts = [f"screw_cap_{sd}"] + [f"spreader_{i}_{sd}_tip" for i in range(len(tips))] + ["mast"]
            for k, (a, b) in enumerate(zip(pts[:-1], pts[1:])):
                segs.append((a, b, r_cap, f"cap_{sd}_{k}", hosts[k], hosts[k + 1]))
            # lowers: chainplate to the mast under the first spreader
            F, d, _ = feet[f"lower_{sd}"]
            segs.append((F + d * tb, self.lower_top(side), r_cap * 0.9, f"lower_{sd}", f"screw_lower_{sd}", "mast"))
            # intermediates: each spreader tip to the mast under the next spreader
            for i in range(1, len(self.spreaders)):
                zi = self.spreaders[i][0]
                segs.append((tips[i - 1], np.array([self.x_mast, side * self.width * 0.4, zi - 0.02]), r_cap * 0.85,
                             f"inter_{sd}_{i}", f"spreader_{i - 1}_{sd}_tip", "mast"))
        F, d, _ = feet["forestay"]
        segs.append((F + d * tb, np.array([self.x_mast + self.chord / 2, 0, self.z_hounds]), r_cap * 1.1,
                     "forestay", "screw_forestay", "hounds"))
        if self.cls["rig"]["backstay"]:
            head = self.crane[1] + [0.02 * s, 0, -0.005 * s]
            if self.split_backstay():
                sp = self.backstay_split()
                segs.append((head, sp, r_cap * 0.9, "backstay", "crane", "backstay_split"))
                for side in (1.0, -1.0):
                    sd = "port" if side > 0 else "stbd"
                    F, d, _ = feet[f"backstay_{sd}"]
                    segs.append((sp, F + d * tb, r_cap * 0.8, f"backstay_leg_{sd}", "backstay_split",
                                 f"screw_backstay_{sd}"))
            else:
                F, d, _ = feet["backstay"]
                segs.append((head, F + d * tb, r_cap * 0.9, "backstay", "crane", "screw_backstay"))
        if self.sprit > 0:
            # bobstay from the sprit end to an eye on the stem near the waterline
            segs.append((self.sprit_end, self.bobstay_foot(), r_cap * 0.9, "bobstay", "sprit_end", "bobstay_eye"))
        return segs

    def bobstay_foot(self):
        """Point on the stem, a little above the waterline, where the bobstay lands: on the hull mesh's centreline
        profile (its keel-line vertices) when the skin is built, so the eye sits on the stem as meshed."""
        h, z = self.hull, 0.18 * self.scale
        grid = getattr(h, "skin_grid", None)
        if grid is not None:
            k = grid[:, 0]                                  # keel-line vertices, aft to forward
            for i in range(len(k) - 1, 0, -1):
                a, b = k[i - 1], k[i]
                if (a[2] - z) * (b[2] - z) <= 0 and a[2] != b[2]:
                    t = (z - a[2]) / (b[2] - a[2])
                    return np.array([a[0] + t * (b[0] - a[0]), 0.0, z])
        lo, hi = h.x_md, h.L
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            if float(h.zk(np.array([mid]))[0]) < z:
                lo = mid
            else:
                hi = mid
        return np.array([lo, 0.0, z])

    def rigging_part(self):
        p = Part()
        for a, b, r, name, ha, hb in self.wires():
            p.add("metal", tube(np.array([a, b]), r, 6, caps=False), tag=name)
            # swaged terminals at both ends
            d = normalize(b - a)
            for e, sgn, h, end in ((a, 1.0, ha, "a"), (b, -1.0, hb, "b")):
                p.add("metal", tube(np.array([e, e + sgn * d * 0.09]), r * 2.0, 8), tag=f"{name}_{end}")
                p.attach(f"{name}_{end}", h)
                p.attach(name, f"{name}_{end}")
        # chainplates: a cover plate on the deck with a strap standing through it for each wire, a rigging screw
        # on each strap's pin; the stemhead fitting for the forestay, plates at the transom or quarters for the
        # backstay, an eye on the stem for the bobstay
        s = self.scale
        tb = self.turnbuckle_len()
        hs = self.strap_height()
        r_cap = self.wire_radius()
        from .hardware import turnbuckle
        feet = self.feet()
        for key, (F, d, host) in feet.items():
            if key == "forestay":
                continue
            x, y = F[0], F[1]
            z, n, _ = self.deck.surface(x, y)
            M = frame_z(np.array([x, y, z]), n, np.array([1.0, 0, 0]))
            strap = Part().add("metal", superellipsoid_box((0.075 * s, 0.014, hs + 0.006), 0.3, 8, 5,
                                                           center=(0, 0, 0.5 * hs - 0.006)))
            p.extend(strap, M, tag=host)
            p.attach(host, "deck")
        for side in (1.0, -1.0):
            sd = "port" if side > 0 else "stbd"
            x = self.chainplate_x + 0.035 * s
            y = side * self.chainplate_y
            z, n, _ = self.deck.surface(x, y)
            plate = Part().add("metal", superellipsoid_box((0.22 * s, 0.06 * s, 0.01), 0.25, 10, 4, center=(0, 0, 0.002)))
            p.extend(plate, frame_z(np.array([x, y, z]), n, np.array([1.0, 0, 0])), tag=f"chainplate_{sd}")
            p.attach(f"chainplate_{sd}", "deck")
        # stemhead: two cheek plates from the deck up past the forestay pin
        F = feet["forestay"][0]
        zd = float(self.deck.surface(min(F[0], self.hull.L - 0.02), 0.0)[0])
        for sy in (-1, 1):
            h = F[2] + 0.03 * s - (zd - 0.006)
            p.add("metal", superellipsoid_box((0.12 * s, 0.008, h), 0.25, 8, 5,
                                              center=[F[0], sy * 0.018 * s, zd - 0.006 + 0.5 * h]), tag="stemhead")
        p.add("metal", superellipsoid_box((0.16 * s, 0.05 * s, 0.01), 0.25, 8, 4, center=[F[0], 0, zd + 0.002]),
              tag="stemhead")
        p.add("metal", tube(np.array([F - [0, 0.024 * s, 0], F + [0, 0.024 * s, 0]]), 0.006 * s, 8), tag="stemhead")
        p.attach("stemhead", "deck")
        if self.split_backstay():
            sp = self.backstay_split()
            p.add("metal", superellipsoid_box((0.05 * s, 0.1 * s, 0.07 * s), 0.3, 8, 5, center=sp), tag="backstay_split")
            p.attach("backstay_split", "backstay")
        if self.sprit > 0:
            foot = self.bobstay_foot()
            p.add("metal", superellipsoid_box((0.03 * s, 0.05 * s, 0.07 * s), 0.35, 8, 5, center=foot - [0.004, 0, 0]),
                  tag="bobstay_eye")
            p.attach("bobstay_eye", "hull")
        # rigging screws: along the wire from the pin
        for key, (F, d, host) in feet.items():
            name = "screw_" + key
            M = frame_z(F, d, np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 1.0, 0]))
            p.extend(turnbuckle(tb, r_cap * 1.4), M, tag=name)
            p.attach(name, host)
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
        p.add("carbon", sweep(path, prof, scale_along=sc, up=np.array([0, 0, 1.0])), tag="boom")
        p.attach("boom", "gooseneck_pin")
        # end fitting and outhaul
        end = path[-1]
        p.add("metal", superellipsoid_box((0.10 * s, 0.07 * s, depth * 0.8), 0.3, 8, 5, center=end), tag="boom_end")
        p.attach("boom_end", "boom")
        # vang: from the mast foot to the boom
        a = np.array([self.x_mast_aft - 0.02, 0, self.z_step + 0.25 * s])
        b = self.gooseneck + [-0.2 * self.E, 0, -depth * 0.4]
        p.add("carbon", tube(np.array([a, a + 0.62 * (b - a)]), 0.025 * s, 10), tag="vang")
        p.add("metal", tube(np.array([a + 0.55 * (b - a), b]), 0.016 * s, 10), tag="vang_rod")
        p.attach("vang_rod", "vang")
        p.add("metal", superellipsoid_box((0.08 * s, 0.05 * s, 0.05 * s), 0.4, 8, 4, center=a), tag="vang_foot")
        p.attach("vang_foot", "vang_tang")
        p.attach("vang", "vang_foot")
        p.add("metal", superellipsoid_box((0.1 * s, 0.07 * s, 0.05 * s), 0.3, 8, 4, center=b + [0, 0, 0.01 * s]),
              tag="boom_bail")
        p.attach("boom_bail", "boom")
        p.attach("vang_rod", "boom_bail")
        # outhaul line along the boom side, cheek blocks near the gooseneck
        for sy in (-1, 1):
            p.add("metal", superellipsoid_box((0.09 * s, 0.02 * s, 0.05 * s), 0.35, 8, 4,
                                              center=self.gooseneck + [-0.35 * s, sy * 0.045 * s, 0.0]),
                  tag=f"boom_cheek_{sy}")
            p.attach(f"boom_cheek_{sy}", "boom")
        p.add("rope_control", tube(np.array([end + [0.03 * s, 0.03 * s, 0.02 * s], self.gooseneck + [-0.35 * s, 0.047 * s, 0.02 * s]]),
                                   max(0.0035, 0.004 * s), 6, turn_uv=0.05), tag="outhaul")
        p.attach("outhaul", "boom_end")
        p.attach("outhaul", "boom_cheek_1")
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
