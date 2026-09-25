"""Build a boat from a class file: glTF model, physics sidecar and optional previews."""
import json
import os
import time

import numpy as np

from . import classfile
from .appendages import Appendages
from .deck import Deck
from .gltf import GLBWriter
from .hull import HullShape
from .mesh import Part, split_by_plane_z
from .rig import Rig
from .sails import build_sails
from . import hardware


def paint_zones(geoms, boot):
    """Split hull skin geometry into antifouling / boot-top / gelcoat by height above the DWL."""
    part = Part()
    z_af, z_bt = boot
    for g in geoms:
        below, rest = split_by_plane_z(g, z_af)
        stripe, above = split_by_plane_z(rest, z_bt) if rest is not None else (None, None)
        part.add("antifouling", below)
        part.add("boottop", stripe)
        part.add("gelcoat", above)
    return part


class Boat:
    def __init__(self, cls, log=print):
        self.cls = cls
        self.log = log
        t0 = time.time()
        self.hull = HullShape(cls)
        self.app = Appendages(cls, self.hull)
        rho = classfile.RHO_SEA
        # the DWL floats the boat in sailing trim with the crew aboard
        V_total = cls["hull"]["dwl_mass"] / rho
        self.V_app_est = self.app.estimate_volume()
        self.V_canoe_target = V_total - self.V_app_est
        log(f"{cls['id']}: {cls['hull']['displacement']:.0f} kg + crew {cls['crew']['weight']:.0f} kg -> "
            f"{V_total:.3f} m3 at the DWL, appendages ~{self.V_app_est:.3f} m3, canoe body {self.V_canoe_target:.3f} m3")
        self.hydro = self.hull.solve(self.V_canoe_target, log=log)
        # second pass with the meshed appendage volumes (the fin and rudder roots depend on the hull bottom)
        self.app = Appendages(cls, self.hull)
        self.app.keel_part()
        self.app.rudder_part()
        V_app = sum(v for v, _ in self.app.volumes().values())
        if abs(V_app - self.V_app_est) > 1e-4 * V_total:
            self.V_canoe_target = V_total - V_app
            log(f"  meshed appendages {V_app:.4f} m3: refit canoe body to {self.V_canoe_target:.4f} m3")
            self.hull._fit_volume(self.V_canoe_target, 121)
            self.hydro = self.hull.hydro(241)
            self.app = Appendages(cls, self.hull)
        self.deck = Deck(cls, self.hull)
        self.parts = {}
        self._build()
        log(f"  built in {time.time() - t0:.1f} s")

    def _build(self):
        cls = self.cls
        port, stbd = self.hull.skin()
        self.skin = (port, stbd)
        self.parts["hull"] = paint_zones([port, stbd], cls["hull"]["boot_top"])
        self.parts["deck"] = self.deck.build()
        self.parts["keel"] = self.app.keel_part()
        self.parts["rudder"] = self.app.rudder_part()
        self.rig = Rig(cls, self.hull, self.deck)
        self.sails = build_sails(cls, self.rig, self.deck)
        heads = [sl for sl in self.sails.values() if sl.type in ("jib", "genoa")]
        if heads:
            self.rig.jib_clew = heads[0].P[0, -1]
        self.parts["mast"] = self.rig.mast_part()
        self.parts["rigging"] = self.rig.rigging_part()
        self.parts["boom"] = self.rig.boom_part()
        hw = hardware.place_all(cls, self.hull, self.deck, self.rig)
        self.parts["hardware"] = hw["hardware"]
        self.parts["boom"].extend(hw["boom_hardware"])
        self.parts["mainsheet"] = hw["mainsheet"]
        self.mainsheet_ends = hw["mainsheet_ends"]
        self.pivots = {"rudder": self.app.rud_stock, "boom": self.rig.gooseneck}
        if self.rig.pole_flown:
            self.parts["pole"] = self.rig.pole_part()
            self.pivots["pole"] = self.rig.pole_pivot
        if hw["helm"].tri_count():
            self.parts["wheel"] = hw["helm"]
            self.pivots["wheel"] = hw["helm_pivot"]
        else:
            # a tiller turns with the rudder
            self.parts["rudder"].extend(hardware.tiller(self.app, self.deck, self.hull, (self.hull.L / 12) ** 0.7))
        for name, sail in self.sails.items():
            self.parts["sail_" + name] = sail.part()

    # poses for previews: the exported model keeps the flat standard sail shapes
    POSES = {
        # sail type -> (angle off the centreline deg, camber, twist deg)
        "upwind": {"main": (4, 0.09, 7), "jib": (11, 0.11, 9), "genoa": (10, 0.11, 9)},
        "reaching": {"main": (28, 0.12, 12), "code_zero": (22, 0.10, 12)},
        "downwind": {"main": (55, 0.14, 16), "spinnaker_asym": (58, 0.24, 14), "spinnaker_sym": (70, 0.26, 10)},
    }

    def posed_parts(self, pose):
        """Parts with the sails set and trimmed for a point of sail (sails to starboard, port tack)."""
        from .mesh import rot_axis, translate
        spec = self.POSES[pose]
        parts = dict(self.parts)
        if not any(sl.type.startswith("spinnaker") for sl in self.sails.values() if sl.type in spec):
            parts.pop("pole", None)     # the pole is shown only while a spinnaker is set
        main_angle = 0.0
        for sid, sail in self.sails.items():
            key = "sail_" + sid
            if sail.type not in spec:
                parts.pop(key, None)
                continue
            ang, camber, twist = spec[sail.type]
            if sail.type == "main":
                main_angle = ang
            parts[key] = sail.part(sail.trim(ang, camber, twist, side=-1.0))
        # boom swung to starboard about the gooseneck, mainsheet re-led to the traveller car below it
        g = self.rig.gooseneck
        M = translate(g) @ rot_axis([0, 0, 1], np.radians(main_angle)) @ translate(-g)
        parts["boom"] = Part().extend(self.parts["boom"], M)
        lower, upper, w_tr, s = self.mainsheet_ends
        up2 = (M @ np.r_[upper, 1.0])[:3]
        low2 = lower.copy()
        low2[1] = float(np.clip(up2[1], -0.45 * w_tr, 0.45 * w_tr))
        parts["mainsheet"] = hardware.mainsheet_tackle(low2, up2, s)
        return parts

    def write_posed_glb(self, path, pose):
        self._write(path, self.cls["id"] + "_" + pose, self.posed_parts(pose), {})

    def origin_x(self):
        return 0.5 * (self.hull.x_awl + self.hull.x_fwl)

    # set by the command line: embed the texture set, bake per-vertex AO
    textures = True
    bake = True

    def write_glb(self, path):
        self._write(path, self.cls["id"], self.parts, self.pivots,
                    extras={"class": self.cls["id"], "name": self.cls.get("name", "")})

    def _write(self, path, root, parts, pivots, extras=None):
        w = GLBWriter(self.origin_x(), textures=self.textures)
        merged = {n: p.merged() for n, p in parts.items()}
        ao = self.bake_ao(merged) if self.bake else {}
        kids = [w.add_mesh(n, parts[n], pivot=pivots.get(n), ao=ao.get(n), merged=merged[n]) for n in parts]
        w.write(path, root, kids, extras=extras)

    def bake_ao(self, merged):
        """{node: {slot: per-vertex AO}} for every node but the sails and the mainsheet (deformed or rebuilt at
        run time; bake.py)."""
        from .bake import bake_ao
        keys = [(n, m) for n, ms in merged.items() if not (n.startswith("sail_") or n == "mainsheet") for m in ms]
        vals = bake_ao([merged[n][m] for n, m in keys], [True] * len(keys))
        out = {}
        for (n, m), a in zip(keys, vals):
            out.setdefault(n, {})[m] = a
        return out

    def tri_count(self):
        return sum(p.tri_count() for p in self.parts.values())
