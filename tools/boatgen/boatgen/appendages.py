"""Keel fin, ballast bulb and rudder.

The fin and rudder are lofted NACA 00xx sections (chord, taper, sweep, thickness from the class). The bulb is a
body of revolution with a flattened elliptical cross-section, sized so its lead volume matches the bulb mass.
"""
import numpy as np

from .classfile import RHO_LEAD
from .mesh import Geom, Part, foil, grid, mesh_volume, normalize, arclen, box, superellipsoid_box, tube, merge


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
        L = hull.L
        # ---- bulb
        b = k["bulb"]
        self.bulb_mass = float(b["mass"])
        Vb = self.bulb_mass / RHO_LEAD
        Lb = float(b["length"])
        flat = float(b.get("flat", 1.25))
        s = np.linspace(0, 1, 400)
        prof = np.maximum(_bulb_profile(s), 0)
        # V = pi * a * b * integral r^2 ds * Lb with a = R sqrt(flat), b = R / sqrt(flat)
        I2 = np.trapz(prof ** 2, s) * Lb
        R = np.sqrt(Vb / (np.pi * I2))
        if b.get("diameter"):
            R = 0.5 * float(b["diameter"]) / prof.max()
        self.bulb_R, self.bulb_len, self.bulb_flat = R, Lb, flat
        half_h = R * prof.max() / np.sqrt(flat)
        self.bulb_zc = -float(k["depth"]) + half_h
        # ---- fin
        lam = float(k["chord_tip_ratio"])
        c_mean = float(k["chord"])
        self.fin_cr = 2 * c_mean / (1 + lam)
        self.fin_ct = lam * self.fin_cr
        x_qc = hull.x_fwl - float(k["position"]) * hull.Lwl
        xs_root = np.linspace(x_qc - 0.75 * self.fin_cr, x_qc + 0.25 * self.fin_cr, 9)
        z_root = float(np.max(hull.zk(xs_root))) + 0.04      # root buried slightly in the canoe body
        z_tip = self.bulb_zc + 0.35 * half_h                  # tip buried in the bulb
        span = z_root - z_tip
        sweep = np.radians(float(k["sweep_deg"]))
        self.fin_le_root = np.array([x_qc + 0.25 * self.fin_cr, 0.0, z_root])
        self.fin_le_tip = np.array([self.fin_le_root[0] - span * np.tan(sweep), 0.0, z_tip])
        self.fin_tc = float(k["thickness"])
        self.fin_span_wet = -z_tip  # below the DWL
        # bulb placed so its 40 % length sits under the fin tip quarter chord
        x_tip_qc = self.fin_le_tip[0] - 0.25 * self.fin_ct
        self.bulb_nose_x = x_tip_qc + 0.40 * Lb
        self.draft = float(k["depth"])

        # ---- rudder
        r = cls["rudder"]
        lam_r = float(r["chord_tip_ratio"])
        self.rud_cr = 2 * float(r["chord"]) / (1 + lam_r)
        self.rud_ct = lam_r * self.rud_cr
        self.rud_tc = float(r["thickness"])
        pos = float(r["position"])
        self.transom_hung = pos < 0.05
        sw = np.radians(float(r["sweep_deg"]))
        z_tip_r = -float(r["depth"])
        if self.transom_hung:
            x_stock = -0.07 - 0.25 * self.rud_cr
            z_top = float(hull.zs(np.array([0.0]))[0]) + 0.10
        else:
            x_stock = pos
            z_top = float(hull.zk(np.array([pos]))[0]) + 0.04
        self.rud_stock = np.array([x_stock, 0.0, z_top])
        self.rud_le_root = np.array([x_stock + 0.25 * self.rud_cr, 0, z_top])
        span_r = z_top - z_tip_r
        self.rud_le_tip = np.array([self.rud_le_root[0] - span_r * np.tan(sw) + 0.25 * (self.rud_cr - self.rud_ct),
                                    0, z_tip_r])

    # --------------------------------------------------------------------------------------------------------
    def keel_part(self, n_chord=22):
        p = Part()
        fin = foil(_foil_stations(self.fin_le_root, self.fin_le_tip, self.fin_cr, self.fin_ct, self.fin_tc),
                   n_chord=n_chord, tip_cap=False, root_cap=False)
        p.add("antifouling", fin)
        p.add("antifouling", self.bulb_geom())
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
        blade = foil(_foil_stations(self.rud_le_root, self.rud_le_tip, self.rud_cr, self.rud_ct, self.rud_tc),
                     n_chord=n_chord, tip_cap=True, root_cap=self.transom_hung)
        p.add("antifouling" if not self.transom_hung else "gelcoat", blade)
        self.rudder_geom = blade
        if self.transom_hung:
            # rudder head cheeks and pintles on the transom
            top = self.rud_stock + [0, 0, 0.0]
            p.add("carbon", superellipsoid_box((self.rud_cr * 0.55, 0.075, 0.22), 0.3,
                                               center=top + [0.2 * self.rud_cr, 0, 0.05]))
            for zz in (top[2] - 0.35, top[2] - 0.75):
                p.add("metal", tube(np.array([[0.0, 0, zz], [top[0] + 0.06, 0, zz]]), 0.012, 8))
        else:
            # stock stub visible inside the gap to the hull
            p.add("metal", tube(np.array([self.rud_stock + [0, 0, -0.05], self.rud_stock + [0, 0, 0.2]]),
                                0.035 * (self.cls["hull"]["loa"] / 12) ** 0.5, 12))
        return p

    # --------------------------------------------------------------------------------------------------------
    def volumes(self):
        V_fin, C_fin = mesh_volume(self.fin_geom)
        V_bulb, C_bulb = mesh_volume(self.bulb)
        V_rud, C_rud = mesh_volume(self.rudder_geom)
        # only the immersed part displaces: the rudder of a transom-hung boat pokes out of the water
        if self.transom_hung:
            frac = min(1.0, float(self.cls["rudder"]["depth"]) / (self.rud_stock[2] + float(self.cls["rudder"]["depth"])))
            V_rud *= frac
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
        s = np.linspace(0, 1, 40)
        pr = np.maximum(_bulb_profile(s), 0) * self.bulb_R / np.sqrt(self.bulb_flat)
        xb = self.bulb_nose_x - s * self.bulb_len
        bulb = list(zip(xb, self.bulb_zc + pr)) + list(zip(xb[::-1], (self.bulb_zc - pr)[::-1]))
        rud = [self.rud_le_root[[0, 2]], self.rud_le_tip[[0, 2]], (self.rud_le_tip - [self.rud_ct, 0, 0])[[0, 2]],
               (self.rud_le_root - [self.rud_cr, 0, 0])[[0, 2]]]
        return [[tuple(p) for p in fin], bulb, [tuple(p) for p in rud]]

    def lateral_areas(self):
        span = self.fin_span_wet
        A_fin = span * 0.5 * (self.fin_cr + self.fin_ct)
        rspan = float(self.cls["rudder"]["depth"]) + min(0.0, self.rud_le_root[2])
        A_rud = max(rspan, 0) * 0.5 * (self.rud_cr + self.rud_ct)
        return A_fin, A_rud
