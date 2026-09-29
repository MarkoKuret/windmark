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


def _drop_small(part, size):
    out = Part()
    for mat, gs in part.slots.items():
        for g in gs:
            if np.linalg.norm(g.P.max(0) - g.P.min(0)) >= size:
                out.add(mat, g)
    if not out.tri_count():         # keep the node: its largest piece
        mat, g = max(((m, g) for m, gs in part.slots.items() for g in gs),
                     key=lambda mg: np.linalg.norm(mg[1].P.max(0) - mg[1].P.min(0)))
        out.add(mat, g)
    return out


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
        self.parts["hull"] = paint_zones([port, stbd], cls["hull"]["boot_top"]).tag_all("hull")
        self.parts["deck"] = self.deck.build().tag_all("deck")
        self.parts["keel"] = self.app.keel_part()
        self.parts["rudder"] = self.app.rudder_part()
        self.rig = Rig(cls, self.hull, self.deck)
        self.sails = build_sails(cls, self.rig, self.deck)
        for spec in cls["sails"]:
            m = self.sails[spec["id"]].measure
            if m:
                msg = (f"  sail {spec['id']}: luff {m['luff']:.2f}, leech {m['leech']:.2f}, foot {m['foot']:.2f}, "
                       f"mid girth {m['mid_girth']:.2f} m, rule area {m['rule_area']:.1f} m2 (class {spec['area']:.1f})")
                self.log(msg)
                if abs(spec["area"] - m["rule_area"]) > 0.03 * m["rule_area"]:
                    print(f"warning: {cls['id']} sail {spec['id']}: class area {spec['area']:.1f} m2 is not the "
                          f"planform's rule area {m['rule_area']:.1f} m2 (data_format.md 3.5)")
        heads = [sl for sl in self.sails.values() if sl.type in ("jib", "genoa")]
        if heads:
            self.rig.jib_clew = heads[0].P[0, -1]
        self.parts["mast"] = self.rig.mast_part()
        self.parts["rigging"] = self.rig.rigging_part()
        self.parts["boom"] = self.rig.boom_part()
        hw = hardware.place_all(cls, self.hull, self.deck, self.rig)
        self.parts["hardware"] = hw["hardware"]
        self.parts["hardware"].extend(hardware.rudder_fittings(self.app, self.deck, self.hull, (self.hull.L / 12) ** 0.7))
        self.leads = hw["leads"]
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

    # levels of detail: (segment scale of the round parts, hull stations, bottom and topside girth points, deck
    # stations, keel and rudder chord points, switch distance in m); LOD0 is the full model built above
    LODS = {1: (0.5, 48, 10, 7, 45, 12, 10, 30.0), 2: (0.28, 24, 6, 4, 22, 8, 6, 100.0)}
    # pieces with a smaller bounding-box diagonal are left out of that level (m)
    LOD_MIN_SIZE = {1: 0.035, 2: 0.3}

    def lod_parts(self, lod):
        """Nodes of a lower level of detail: the same node set, pivots and sails as the full model (the sail grids
        are the simulation's and stay as they are), with a coarser hull, deck and appendages, fewer segments on
        every round part, and the small fittings dropped (hardware.place_all)."""
        from .mesh import segment_scale
        f, n_st, nb, nt, n_deck, n_keel, n_rud, _ = self.LODS[lod]
        cls = self.cls
        saved = {k: getattr(self.hull, k) for k in ("skin_grid", "girth", "girth_max", "skin_xs", "i_turn")}
        parts = {}
        with segment_scale(f):
            port, stbd = self.hull.skin(n_st, nb, nt)
            for k, v in saved.items():
                setattr(self.hull, k, v)
            parts["hull"] = paint_zones([port, stbd], cls["hull"]["boot_top"])
            deck = Deck(cls, self.hull)
            parts["deck"] = deck.build(n_out=max(3, round(9 * f)), n_st=n_deck, skin=(nb, nt))
            app = Appendages(cls, self.hull)
            parts["keel"] = app.keel_part(n_chord=n_keel)
            if app.has_bulb:
                parts["keel"] = Part().add("antifouling", app.fin_geom)
                parts["keel"].add("antifouling", app.bulb_geom(nl=max(12, round(48 * f)), nr=max(8, round(28 * f))))
            parts["rudder"] = app.rudder_part(n_chord=n_rud)
            rig = Rig(cls, self.hull, deck)
            rig.jib_clew = getattr(self.rig, "jib_clew", None)
            if rig.jib_clew is None:
                del rig.jib_clew
            parts["mast"] = rig.mast_part()
            parts["rigging"] = rig.rigging_part()
            parts["boom"] = rig.boom_part()
            hw = hardware.place_all(cls, self.hull, deck, rig, lod=lod)
            parts["hardware"] = hw["hardware"]
            parts["hardware"].extend(hardware.rudder_fittings(app, deck, self.hull, (self.hull.L / 12) ** 0.7))
            parts["boom"].extend(hw["boom_hardware"])
            parts["mainsheet"] = hw["mainsheet"]
            if rig.pole_flown:
                parts["pole"] = rig.pole_part()
            if hw["helm"].tri_count():
                parts["wheel"] = hw["helm"]
            else:
                parts["rudder"].extend(hardware.tiller(app, deck, self.hull, (self.hull.L / 12) ** 0.7))
        # drop the pieces too small to read at the level's distance (fittings, terminals, screws, bolts)
        min_size = self.LOD_MIN_SIZE[lod]
        for name in ("mast", "rigging", "boom", "hardware", "rudder", "wheel", "pole"):
            if name in parts:
                parts[name] = _drop_small(parts[name], min_size)
        for name in self.sails:
            parts["sail_" + name] = self.parts["sail_" + name]
        assert sorted(parts) == sorted(self.parts), (sorted(parts), sorted(self.parts))
        return parts

    def write_lod_glb(self, path, lod):
        parts = self.lod_parts(lod)
        self._write(path, self.cls["id"], parts, self.pivots,
                    extras={"class": self.cls["id"], "name": self.cls.get("name", ""), "lod": lod,
                            "livery_panels": self.livery_panels()})
        return sum(p.tri_count() for p in parts.values()), parts

    # poses for previews (the exported model keeps the flat standard sail shapes); the sails are drawn with the
    # game's shape and placement (sail_set.py, sail_visuals.md 6 and 7). awa: apparent wind angle, deg (negative:
    # wind from port, so the sails are to starboard); aws: m/s; gamma: pole or tack line to windward, deg; sails:
    # sheet angle per sail type, deg, the core's optimum from the wm7 and wm12 performance tables at 10 kn TWS
    POSES = {
        "upwind": {"awa": -27, "aws": 7.0, "sails": {"main": 13, "jib": 12, "genoa": 12}},
        "reaching": {"awa": -70, "aws": 6.0, "sails": {"main": 43, "code_zero": 50}},
        "downwind": {"awa": -140, "aws": 4.0, "gamma": 20,
                     "sails": {"main": 59, "spinnaker_asym": 64, "spinnaker_sym": 75}},
    }

    def posed_parts(self, pose):
        """Parts with the sails set as the game draws them for a point of sail (sails to starboard, port tack)."""
        from .mesh import rot_axis, translate
        from .sail_set import set_sails
        spec = self.POSES[pose] if isinstance(pose, str) else pose
        parts = dict(self.parts)
        if not any(sl.type.startswith("spinnaker") for sl in self.sails.values() if sl.type in spec["sails"]):
            parts.pop("pole", None)     # the pole is shown only while a spinnaker is set
        grids, shapes = set_sails(self, spec)
        corners, types = {}, {}
        for sid, sail in self.sails.items():
            key = "sail_" + sid
            if sid not in grids:
                parts.pop(key, None)
                continue
            G = grids[sid]
            parts[key] = sail.part(G)
            corners[sid] = {k: G[i, j] for k, (i, j) in sail.corners.items()}
            types[sid] = sail.type
        main_angle =float(spec["sails"].get("main", 0.0)) * (1.0 if spec["awa"] <= 0 else -1.0)
        if "pole" in parts and self.rig.pole_flown:
            gam = float(spec.get("gamma", 0.0)) * (1.0 if spec["awa"] <= 0 else -1.0)
            pv = self.rig.pole_pivot
            parts["pole"] = Part().extend(self.parts["pole"], translate(pv) @ rot_axis([0, 0, 1], np.radians(gam))
                                          @ translate(-pv))
        from .running import sheets
        parts["sheets"] = sheets(self, corners, types)
        # boom swung about the gooseneck with the main, mainsheet re-led from the block on the traveller car to the
        # swung boom block (the car stays where the exported model has it)
        g = self.rig.gooseneck
        M = translate(g) @ rot_axis([0, 0, 1], np.radians(main_angle)) @ translate(-g)
        parts["boom"] = Part().extend(self.parts["boom"], M)
        lower, upper, w_tr, s = self.mainsheet_ends
        up2 = (M @ np.r_[upper, 1.0])[:3]
        parts["mainsheet"] = hardware.mainsheet_tackle(lower, up2, s)
        return parts

    def write_posed_glb(self, path, pose, name=None, drop=()):
        """Posed preview model; `pose` is a POSES name or a {sail type: (angle, camber, twist)} dict, `drop`
        leaves nodes out."""
        parts = {k: v for k, v in self.posed_parts(pose).items() if k not in drop}
        self._write(path, self.cls["id"] + "_" + (name or pose), parts, {})

    def rebuild_sails(self, cls):
        """Redraw the sails from `cls`, a class that differs from the built one only in its code zeros and
        spinnakers (shape keys, luff, leech, foot, tack_x, area): the hull, deck, rig and hardware are kept."""
        self.cls = cls
        self.sails = build_sails(cls, self.rig, self.deck)
        for k in [k for k in self.parts if k.startswith("sail_")]:
            del self.parts[k]
        for name, sail in self.sails.items():
            self.parts["sail_" + name] = sail.part()

    def livery_panels(self):
        """Name and number panels on both topsides for the liveries: [{id, side, x (body, aft..fwd), z below the
        sheer (top, bottom, m), uv1 rect [u0, v0, u1, v1] on the hull atlas at the panel's middle station}]."""
        h = self.hull
        L, fb = h.L, self.cls["hull"]["freeboard"]
        out = []
        for pid, x0, x1, d0, d1 in (("number", 0.60, 0.80, 0.14, 0.66), ("name", 0.10, 0.34, 0.16, 0.46)):
            xm = 0.5 * (x0 + x1) * L
            i = int(np.argmin(np.abs(h.skin_xs - xm)))
            z = h.skin_grid[i, :, 2]
            g = h.girth[i]
            zs = float(h.zs(np.array([xm]))[0])
            ga, gb = (float(np.interp(zs - d * fb, z, g)) for d in (d0, d1))
            G = h.girth_max
            for side in ("port", "stbd"):
                if side == "stbd":
                    u0, u1, v0, v1 = x0, x1, 0.5 * (1 - ga / G), 0.5 * (1 - gb / G)
                else:
                    u0, u1, v0, v1 = 1 - x1, 1 - x0, 0.5 + 0.5 * (1 - ga / G), 0.5 + 0.5 * (1 - gb / G)
                out.append({"id": pid, "side": side,
                            "x": [round(x0 * L - self.origin_x(), 3), round(x1 * L - self.origin_x(), 3)],
                            "below_sheer": [round(d0 * fb, 3), round(d1 * fb, 3)],
                            "uv1": [round(u0, 4), round(v0, 4), round(u1, 4), round(v1, 4)]})
        return out

    def origin_x(self):
        return 0.5 * (self.hull.x_awl + self.hull.x_fwl)

    # set by the command line: embed the texture set, bake per-vertex AO
    textures = True
    bake = True

    def write_glb(self, path):
        self._write(path, self.cls["id"], self.parts, self.pivots,
                    extras={"class": self.cls["id"], "name": self.cls.get("name", ""), "lod": 0,
                            "livery_panels": self.livery_panels()})

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

    def attachment_gaps(self):
        """[(piece, hosts, gap in m)] for every fitting of the full model (attach.py)."""
        from .attach import gaps
        return gaps(self.parts)
