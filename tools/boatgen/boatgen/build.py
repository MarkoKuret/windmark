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
        V_total = cls["hull"]["displacement"] / rho
        self.V_app_est = self.app.estimate_volume()
        self.V_canoe_target = V_total - self.V_app_est
        log(f"{cls['id']}: displacement {cls['hull']['displacement']:.0f} kg -> {V_total:.3f} m3, "
            f"appendages ~{self.V_app_est:.3f} m3, canoe body target {self.V_canoe_target:.3f} m3")
        self.hydro = self.hull.solve(self.V_canoe_target, log=log)
        # appendages depend on the hull bottom: rebuild now that the hull is final
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

    def origin_x(self):
        return 0.5 * (self.hull.x_awl + self.hull.x_fwl)

    def write_glb(self, path):
        w = GLBWriter(self.origin_x())
        pivots = {"rudder": self.app.rud_stock}
        kids = []
        for name, part in self.parts.items():
            kids.append(w.add_mesh(name, part, pivot=pivots.get(name)))
        w.write(path, self.cls["id"], kids, extras={"class": self.cls["id"], "name": self.cls.get("name", "")})

    def tri_count(self):
        return sum(p.tri_count() for p in self.parts.values())
