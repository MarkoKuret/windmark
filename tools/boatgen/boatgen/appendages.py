"""Keel fin, ballast bulb and rudder.

The fin and rudder are lofted NACA 00xx sections (chord, taper, sweep, thickness from the class). The bulb is a
body of revolution with a flattened elliptical cross-section, sized so its lead volume matches the bulb mass.
"""
import numpy as np

_trapz = getattr(np, "trapezoid", None) or np.trapz

from .classfile import RHO_LEAD
from .mesh import (Geom, Part, foil, grid, mesh_volume, mesh_area, normalize, arclen, box, superellipsoid_box, tube,
                   merge, split_by_plane_z)


def _bulb_profile(s):
    """Radius distribution of the bulb along its length, s in [0, 1] from the nose: a blunt nose and a long
    tapering tail (NACA 4-digit thickness shape, peak near 30 % length)."""
    return 1.4845 * np.sqrt(s) - 0.63 * s - 1.758 * s ** 2 + 1.4215 * s ** 3 - 0.5075 * s ** 4


def _foil_stations(le_root, le_tip, c_root, c_tip, tc, n=7):
    st = []
    for t in np.linspace(0, 1, n):
        le = le_root + t * (le_tip - le_root)
        c = c_root + t * (c_tip - c_root)
        st.append((le, np.array([-1.0, 0, 0]), np.array([0, 1.0, 0]), c, tc))
    return st


class Appendages:
    def __init__(self, cls, hull):
        self.cls = cls
        self.hull = hull
        k = cls["keel"]
        self.draft = float(k["depth"])
        # ---- bulb (sized from its lead mass unless a diameter is given)
        b = k["bulb"]
        self.has_bulb = b is not None
        self.fin_cr, self.fin_ct = float(k["chord_root"]), float(k["chord_tip"])
        self.fin_tc = float(k["thickness"])
        if self.has_bulb:
            self.bulb_mass = float(b["mass"])
            Lb = float(b["length"])
            flat = float(b["flat"])
            s = np.linspace(0, 1, 400)
            prof = np.maximum(_bulb_profile(s), 0)
            # V = pi * a * b * Lb * integral(r^2 ds) with a = R sqrt(flat), b = R / sqrt(flat)
            I2 = _trapz(prof ** 2, s) * Lb
            R = np.sqrt(self.bulb_mass / RHO_LEAD / (np.pi * I2))
            if b.get("diameter"):
                R = 0.5 * float(b["diameter"]) / prof.max()
            self.bulb_R, self.bulb_len, self.bulb_flat = R, Lb, flat
            half_h = R * prof.max() / np.sqrt(flat)
            self.bulb_zc = -self.draft + half_h
            z_tip = self.bulb_zc + 0.35 * half_h                  # fin tip buried in the bulb
        else:
            self.bulb_mass = 0.0
            z_tip = -self.draft
        # ---- fin: root quarter chord at the class x, quarter-chord line swept by `sweep`
        x_qc = float(k["x_qc"])
        xs_root = np.linspace(x_qc - 0.75 * self.fin_cr, x_qc + 0.25 * self.fin_cr, 9)
        z_root = float(np.max(hull.zk(xs_root))) + 0.04          # root buried slightly in the canoe body
        span = z_root - z_tip
        x_qc_tip = x_qc - span * np.tan(float(k["sweep"]))
        self.fin_le_root = np.array([x_qc + 0.25 * self.fin_cr, 0.0, z_root])
        self.fin_le_tip = np.array([x_qc_tip + 0.25 * self.fin_ct, 0.0, z_tip])
        if not self.has_bulb:
            # a fin without a bulb ends in its domed tip cap: raise the tip so the cap's bottom is at the draft
            cap = foil(_foil_stations(self.fin_le_root, self.fin_le_tip, self.fin_cr, self.fin_ct, self.fin_tc),
                       n_chord=22, tip_cap=True, root_cap=False)
            z_tip += -self.draft - float(cap.P[:, 2].min())
            self.fin_le_tip[2] = z_tip
        self.fin_span_wet = -z_tip
        if self.has_bulb:
            # bulb placed so its 40 % length sits under the fin tip quarter chord
            self.bulb_nose_x = x_qc_tip + 0.40 * self.bulb_len

        # ---- rudder: stock at the class x; a transom rudder hangs aft of the transom
        r = cls["rudder"]
        self.rud_cr, self.rud_ct = float(r["chord_root"]), float(r["chord_tip"])
        self.rud_tc = float(r["thickness"])
        self.transom_hung = r["type"] == "transom"
        z_tip_r = -float(r["depth"])
        x_stock = float(r["x_stock"])
        if self.transom_hung:
            x_stock = min(x_stock, -0.07 - 0.25 * self.rud_cr)
            from .deck import Deck
            d = Deck(cls, hull)
            # the head just above the transom's top: on an open transom that is the cockpit floor's edge, so the
            # tiller runs forward low over the floor; on a closed one the deck
            z_top = (float(d.floor_z(0.0)) + 0.12 if d.open_transom
                     else float(hull.zs(np.array([0.0]))[0]) + 0.10)
        else:
            z_top = float(hull.zk(np.array([x_stock]))[0]) + 0.04
        self.rud_stock = np.array([x_stock, 0.0, z_top])
        self.rud_le_root = np.array([x_stock + 0.25 * self.rud_cr, 0, z_top])
        span_r = z_top - z_tip_r
        self.rud_le_tip = np.array([x_stock - span_r * np.tan(float(r["sweep"])) + 0.25 * self.rud_ct, 0, z_tip_r])
        self.rud_stations = (self._transom_rudder_stations(float(hull.zk(np.array([0.0]))[0])) if self.transom_hung
                             else _foil_stations(self.rud_le_root, self.rud_le_tip, self.rud_cr, self.rud_ct, self.rud_tc))
        # tiller section (width, depth) and, on a transom rudder, the rudder head it is bolted into: a casting round
        # the blade top, the tiller butt in a slot in its forward end on a horizontal bolt (`tiller_pivot`)
        sh = (hull.L / 12.0) ** 0.7
        self.tiller_size = (0.045 * sh, 0.06 * sh)
        self.head_gap = self.rud_tc * self.rud_cr             # inside the head: the blade's root thickness
        self.tiller_pivot = self.rud_stock + [0.12 * self.rud_cr, 0, 0.5 * self.tiller_size[1] + 0.03]
        self.head_cheek = 0.012 + 0.004 * (hull.L / 12.0)       # the head's wall either side of the blade
        self.head_front = min(self.tiller_pivot[0] + 0.2 * self.rud_cr, -0.02)

    def _transom_rudder_stations(self, z_hull, n=26):
        """A sportboat's transom-hung blade: straight swept leading edge on the pintles; above the hull's bottom at
        the transom the trailing edge steps in to a neck 0.6 of the root chord at the head; below it the chord tapers
        to the tip, whose last 30 % of the immersed span is a quarter ellipse closing on 30 % chord. The immersed
        chords are scaled so the blade below the DWL keeps the class planform area (the trapezoid
        chord_root/chord_tip over the immersed depth), which the VPP's rudder is."""
        le0, le1 = self.rud_le_root, self.rud_le_tip
        z_top, z_tip = le0[2], le1[2]
        z_h = min(max(z_hull, z_tip + 0.5 * (0.0 - z_tip)), z_top - 0.05)
        cr, ct = self.rud_cr, self.rud_ct
        u = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))               # clustered at the head and the tip
        z = z_top + u * (z_tip - z_top)
        le_x = le0[0] + (z - z_top) / (z_tip - z_top) * (le1[0] - le0[0])
        # straight taper from the root (at z_h) to the tip
        w = np.clip((z_h - z) / (z_h - z_tip), 0, 1)
        lin = cr + w * (ct - cr)
        neck = np.clip((z_top - z) / (z_top - z_h), 0, 1)
        neck = 0.6 + 0.4 * neck * neck * (3 - 2 * neck)
        tip0 = 0.7
        e = np.sqrt(np.clip(1 - (np.clip((w - tip0) / (1 - tip0), 0, 1)) ** 2, 0, 1))
        e[-1] = 0.0
        e = np.maximum(e, 0.10)
        c_wet = lin * e

        def wet_area(k):
            c = np.where(z < z_h, k * c_wet, np.where(z < z_h + 1e-9, c_wet, lin * neck))
            zz, cc = z[z <= 0.0], c[z <= 0.0]
            zz, cc = np.concatenate([[0.0], zz]), np.concatenate([[np.interp(0.0, z[::-1], c[::-1])], cc])
            return float(np.trapezoid(cc[::-1], zz[::-1]))

        z_wet = min(0.0, z_top)
        target = (z_wet - z_tip) * 0.5 * (cr + ct)                    # lateral_areas(): the class trapezoid
        k = 1.0
        for _ in range(30):
            k *= target / max(wet_area(k), 1e-9)
        c = np.where(z < z_h, k * c_wet, lin * neck)
        # the root band blends from the scaled wet chord to the neck so the trailing edge has no kink at z_h
        b = np.clip((z - z_h) / 0.12, 0, 1)
        c = np.where(z >= z_h, (1 - b * b * (3 - 2 * b)) * k * cr + b * b * (3 - 2 * b) * c, c)
        le_x = le_x - 0.3 * (1 - e) * np.where(z < z_h, k * lin, 0.0)  # the tip closes on 30 % chord
        # above the hull the section keeps the root's thickness, so the blade fills the head
        tc = np.where(z >= z_h, self.rud_tc * cr / c, self.rud_tc)
        return [(np.array([le_x[i], 0.0, z[i]]), np.array([-1.0, 0, 0]), np.array([0, 1.0, 0]), float(c[i]),
                 float(tc[i])) for i in range(n)]

    # --------------------------------------------------------------------------------------------------------
    def keel_part(self, n_chord=22):
        p = Part()
        fin = foil(_foil_stations(self.fin_le_root, self.fin_le_tip, self.fin_cr, self.fin_ct, self.fin_tc),
                   n_chord=n_chord, tip_cap=not self.has_bulb, root_cap=False)   # a fin without a bulb closes its tip
        p.add("antifouling", fin, tag="keel_fin")
        p.attach("keel_fin", "hull")
        if self.has_bulb:
            p.add("antifouling", self.bulb_geom(), tag="keel_bulb")
            p.attach("keel_bulb", "keel_fin")
        self.fin_geom = fin
        return p

    def bulb_geom(self, nl=48, nr=28):
        s = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, nl))
        prof = np.maximum(_bulb_profile(s), 0) * self.bulb_R
        prof[-1] = 0.0
        th = np.linspace(0, 2 * np.pi, nr + 1)[:-1]
        a = prof[:, None] * np.sqrt(self.bulb_flat)
        b = prof[:, None] / np.sqrt(self.bulb_flat)
        X = self.bulb_nose_x - s[:, None] * self.bulb_len + 0 * th[None, :]
        Y = a * np.cos(th)[None, :]
        Z = self.bulb_zc + b * np.sin(th)[None, :]
        P = np.stack([X, Y, Z], -1)
        uv = np.stack([np.broadcast_to(s[:, None] * self.bulb_len, X.shape),
                       np.broadcast_to(th[None, :] * self.bulb_R, X.shape)], -1)
        g = grid(P, uv, close_v=True)
        if np.dot(g.N[len(g.N) // 2], g.P[len(g.P) // 2] - [g.P[len(g.P) // 2][0], 0, self.bulb_zc]) < 0:
            g = g.flipped()
        self.bulb = g
        return g

    def rudder_part(self, n_chord=18):
        """Rudder blade in its own frame: origin on the stock axis at the blade top, so it can turn."""
        p = Part()
        blade = foil(self.rud_stations, n_chord=n_chord, tip_cap=True, root_cap=self.transom_hung)
        p.add("antifouling" if not self.transom_hung else "gelcoat", blade, tag="rudder")
        self.rudder_geom = blade
        if self.transom_hung:
            # rudder head with a through bolt; pintle straps round the leading edge at the transom gudgeons
            # (hardware.rudder_fittings), pins on the stock axis
            top = self.rud_stock + [0, 0, 0.0]
            t = self.rud_tc * self.rud_cr
            # the head: one casting round the blade top, a streamlined section a cheek thicker than the blade on each
            # side, from ahead of the leading edge to past the trailing edge, so the blade goes into it on every side;
            # from 0.10 m down the blade to just over the tiller butt, domed on top
            pv, th = self.tiller_pivot, self.head_cheek
            z0, z1 = top[2] - 0.10, pv[2] + 0.5 * self.tiller_size[1] + 0.03
            le_b, c_b = self.rud_stations[0][0], self.rud_stations[0][3]
            x_le, x_te = self.head_front, le_b[0] - c_b - 0.03
            c_h = x_le - x_te
            tc_h = (t + 2 * th) / c_h
            nh = n_chord + 6 if n_chord > 6 else n_chord               # the shadow proxy's low detail stays low
            p.add("carbon", foil([(np.array([x_le, 0.0, z]), np.array([-1.0, 0, 0]), np.array([0, 1.0, 0]), c_h, tc_h)
                                  for z in (z0, z1)], n_chord=nh, tip_cap=True, root_cap=True), tag="rudder_head")
            p.attach("rudder_head", "rudder")
            # bolt through the head's lower part and the blade top
            p.add("metal", tube(np.array([[top[0] + 0.1 * self.rud_cr, -0.5 * t - th - 0.006, top[2] - 0.06],
                                          [top[0] + 0.1 * self.rud_cr, 0.5 * t + th + 0.006, top[2] - 0.06]]), 0.007, 8),
                  tag="rudder_head_bolt")
            p.attach("rudder_head_bolt", "rudder_head")
            # pintle straps round the leading edge, between the gudgeon arms (hardware.rudder_fittings)
            for i, zz in enumerate(self.pintle_z()):
                p.add("metal", superellipsoid_box((0.3 * self.rud_cr, t + 0.012, 0.04), 0.3, 8, 4,
                                                  center=[top[0] + 0.12 * self.rud_cr, 0, zz]), tag=f"pintle_strap_{i}")
                p.attach(f"pintle_strap_{i}", "rudder")
                p.attach(f"pintle_strap_{i}", f"gudgeon_{i}")
        else:
            # stock stub visible inside the gap to the hull
            p.add("metal", tube(np.array([self.rud_stock + [0, 0, -0.05], self.rud_stock + [0, 0, 0.2]]),
                                max(0.035 * (self.cls["hull"]["loa"] / 12) ** 0.5, 0.5 * self.rud_tc * self.rud_cr),
                                12), tag="rudder_stock")      # at least the blade root's thickness
            p.attach("rudder_stock", "rudder")
            p.attach("rudder_stock", "hull")
        return p

    def pintle_z(self):
        """Heights of the pintles of a transom-hung rudder: on the transom face, the upper one below its top (the
        cockpit floor on an open transom), the lower one near the waterline."""
        from .deck import Deck
        top = self.rud_stock[2]
        z_low = max(float(self.hull.zk(np.array([0.0]))[0]) + 0.08, 0.06)
        d = Deck(self.cls, self.hull)
        z_face = float(d.floor_z(0.0)) if d.open_transom else float(d.deck_z(0.0, 0.0))
        z_up = min(top - 0.22, z_face - 0.06)
        return [z_up, 0.5 * (z_up + z_low)]

    # --------------------------------------------------------------------------------------------------------
    def volumes(self):
        V_fin, C_fin = mesh_volume(self.fin_geom)
        V_bulb, C_bulb = mesh_volume(self.bulb) if self.has_bulb else (0.0, np.zeros(3))
        V_rud, C_rud = mesh_volume(self.rudder_geom)
        # only the immersed part displaces (a transom rudder, or a spade root near the stern, is partly above the
        # DWL); scaled by the immersed share of its surface
        below, _ = split_by_plane_z(self.rudder_geom, 0.0)
        V_rud *= mesh_area(below) / mesh_area(self.rudder_geom) if below is not None else 0.0
        return {"fin": (V_fin, C_fin), "bulb": (V_bulb, C_bulb), "rudder": (V_rud, C_rud)}

    def estimate_volume(self):
        """Appendage displacement before meshes exist (used to size the canoe body)."""
        span = self.fin_le_root[2] - self.fin_le_tip[2]
        V_fin = 0.685 * self.fin_tc * span * (self.fin_cr ** 2 + self.fin_cr * self.fin_ct + self.fin_ct ** 2) / 3
        V_bulb = self.bulb_mass / RHO_LEAD
        rspan = float(self.cls["rudder"]["depth"])
        V_rud = 0.685 * self.rud_tc * rspan * (self.rud_cr ** 2 + self.rud_cr * self.rud_ct + self.rud_ct ** 2) / 3
        return V_fin + V_bulb + V_rud

    def profiles(self):
        """Side-view outlines (x, z) for the lines plan."""
        fin = [self.fin_le_root[[0, 2]], self.fin_le_tip[[0, 2]],
               (self.fin_le_tip - [self.fin_ct, 0, 0])[[0, 2]], (self.fin_le_root - [self.fin_cr, 0, 0])[[0, 2]]]
        out = [[tuple(p) for p in fin]]
        if self.has_bulb:
            s = np.linspace(0, 1, 40)
            pr = np.maximum(_bulb_profile(s), 0) * self.bulb_R / np.sqrt(self.bulb_flat)
            xb = self.bulb_nose_x - s * self.bulb_len
            out.append(list(zip(xb, self.bulb_zc + pr)) + list(zip(xb[::-1], (self.bulb_zc - pr)[::-1])))
        le = [st[0][[0, 2]] for st in self.rud_stations]
        te = [(st[0] - [st[3], 0, 0])[[0, 2]] for st in self.rud_stations]
        out.append([tuple(p) for p in le + te[::-1]])
        return out

    def lateral_areas(self):
        span = self.fin_span_wet
        A_fin = span * 0.5 * (self.fin_cr + self.fin_ct)
        rspan = float(self.cls["rudder"]["depth"]) + min(0.0, self.rud_le_root[2])
        A_rud = max(rspan, 0) * 0.5 * (self.rud_cr + self.rud_ct)
        return A_fin, A_rud
