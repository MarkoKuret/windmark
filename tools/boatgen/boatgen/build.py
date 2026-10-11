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
from . import gltf, hardware


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


def rig_aft(cls):
    """The mast's aft face at the deck (x from the transom)."""
    return float(cls["rig"]["mast_x"]) - float(cls["rig"]["mast_chord"])


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
        if self.deck.has_cabin:
            d = self.deck
            log(f"  coachroof: {d.xk1 - d.xk0:.2f} m from the cockpit to where it meets the deck "
                f"({rig_aft(cls) - d.xk1:.2f} m aft of the mast), {d.cab_h:.2f} m high aft, steepest slope "
                f"{np.degrees(d.cab_slope_max()):.1f} deg")
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
        self.rope_paths = hw["rope_paths"]
        self.lifelines = hw["lifelines"]
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

    # The game model (docs/specs/sail_visuals.md 11.4, tools/boatgen/README.md "The game model"): one detailed model
    # per class, the engine simplifies it by screen size (Godot's automatic mesh LOD, generated on import). The hull,
    # deck, keel and rig keep the full model's detail; the hardware is low-poly (hardware.lowpoly); flat fittings and
    # the lines on deck are painted (hardware.PAINTED), sub-pixel pieces dropped (hardware.DROPPED). Every static
    # part is one node, `body` (one draw); the moving parts stay their own nodes.
    BODY = ("hull", "deck", "keel", "mast", "rigging", "hardware")

    def game_parts(self):
        """The nodes of the game model: `body` (hull, deck, keel, mast, rigging and static hardware, pieces named
        "<part>:<slot>"), the moving parts (rudder with the tiller, wheel, boom, mainsheet, pole) and the sails."""
        cls = self.cls
        parts = {"hull": self.parts["hull"], "deck": self.parts["deck"], "keel": self.parts["keel"]}
        with hardware.lowpoly():
            app = Appendages(cls, self.hull)
            app.keel_part()
            parts["rudder"] = app.rudder_part()
            rig = self.rig
            parts["mast"] = rig.mast_part()
            parts["rigging"] = rig.rigging_part()
            parts["boom"] = rig.boom_part()
            hw = hardware.place_all(cls, self.hull, self.deck, rig, lod=0)
            parts["hardware"] = hw["hardware"]
            parts["hardware"].extend(hardware.rudder_fittings(app, self.deck, self.hull, (self.hull.L / 12) ** 0.7))
            parts["boom"].extend(hw["boom_hardware"])
            parts["mainsheet"] = hw["mainsheet"]
            if rig.pole_flown:
                parts["pole"] = rig.pole_part()
            if hw["helm"].tri_count():
                parts["wheel"] = hw["helm"]
            else:
                parts["rudder"].extend(hardware.tiller(app, self.deck, self.hull, (self.hull.L / 12) ** 0.7))
        for name in ("mast", "rigging", "boom", "hardware", "rudder", "wheel", "pole"):
            if name not in parts:
                continue
            q = Part()
            for mat, gs in parts[name].slots.items():
                for g in gs:
                    t = g.tag or ""
                    if t.startswith("hatch_") and name == "hardware":
                        # the hatch's raised box reads the deck maps (its painted top): a deck surface
                        g = g.copy()
                        g.uv1 = self.deck.plan_uv1(g.P)
                        parts["deck"] = Part().extend(parts["deck"]).add(mat, g)
                        continue
                    if hardware.is_painted_line(t):
                        # the line's lengths off the surface stay geometry (the deck maps paint the rest)
                        g = self._rope_off_surface(g)
                        if g is not None:
                            q.add(mat, g)
                        continue
                    if hardware.is_painted(t) or hardware.is_dropped(t):
                        continue
                    q.add(mat, g)
            parts[name] = q
        body = Part()
        for name in self.BODY:
            for mat, gs in parts.pop(name).slots.items():
                for g in gs:
                    body.add(f"{name}:{mat}", g)
        out = {"body": body, **parts}
        for name in self.sails:
            out["sail_" + name] = self.parts["sail_" + name]
        return out

    def line_on_face(self, P):
        """Points of a line that lie against the coachroof's aft face (within 3 cm of it, inside its outline):
        painted on the face's own uv1 (Deck.face_frame)."""
        f = self.deck.face_frame()
        P = np.asarray(P, dtype=np.float64)
        if f is None:
            return np.zeros(len(P), bool)
        return ((np.abs(P[:, 0] - f["x"]) < 0.03) & (P[:, 1] >= f["y"][0]) & (P[:, 1] <= f["y"][1])
                & (P[:, 2] >= f["z"][0] - 0.01) & (P[:, 2] <= f["z"][1] + 0.01))

    def _rope_off_surface(self, g):
        """The triangles of a line that hang in the air: a vertex more than hardware.ROPE_LIFT_MAX above the walking
        surface under it and not against the coachroof's aft face (None when the line lies on surfaces all along;
        the deck maps paint it there)."""
        from .mesh import Geom
        h = g.P[:, 2] - np.asarray(self.deck.surface_z(g.P[:, 0], g.P[:, 1]), dtype=np.float64)
        air = (h >= hardware.ROPE_LIFT_MAX) & ~self.line_on_face(g.P)
        keep = air[g.I].any(1) & ~self.line_on_face(g.P)[g.I].all(1)
        if not keep.any():
            return None
        out = Geom(g.P, g.I[keep], g.N, g.uv0, g.uv1)
        out.tag = g.tag
        return out

    def painted_part(self):
        """The full model's pieces the game paints into the livery's deck maps instead of modelling them
        (hardware.PAINTED): tracks, hatches, organisers, small cleats, turning blocks, the halyards on deck, the
        coils and tails (boat frame, slots and tags as built). tools/liverybake draws them."""
        out = Part()
        for name in ("hardware",):
            for mat, gs in self.parts[name].slots.items():
                for g in gs:
                    if hardware.is_painted(g.tag or ""):
                        out.add(mat, g)
        return out

    def shadow_proxy(self):
        """The shadow casters of every level (sail_visuals.md 11.4): the hull, the deck with its coachroof, keel,
        rudder and mast as a few hundred triangles (`shadow`, static), and the boom (`shadow_boom`, under the boom
        node). Every vertex lies on the full model's surfaces or inside them, so the proxy never shades a lit face
        of the drawn boat."""
        from .mesh import segment_scale, tube
        cls = self.cls
        saved = {k: getattr(self.hull, k) for k in ("skin_grid", "girth", "girth_max", "skin_xs", "i_turn")}
        static = Part()
        with segment_scale(0.1):
            port, stbd = self.hull.skin(12, 4, 3)
            for k, v in saved.items():
                setattr(self.hull, k, v)
            static.add("shadow", port)
            static.add("shadow", stbd)
            deck = Deck(cls, self.hull)
            deck.build(n_out=3, n_st=12, skin=(4, 3), lite=2)
            for gs in deck.build_simple(8, 5).slots.values():
                for g in gs:
                    static.add("shadow", g)
            app = Appendages(cls, self.hull)
            keel = app.keel_part(n_chord=4)
            if app.has_bulb:
                static.add("shadow", app.fin_geom)
                static.add("shadow", app.bulb_geom(nl=6, nr=4))
            else:
                for gs in keel.slots.values():
                    for g in gs:
                        static.add("shadow", g)
            for gs in app.rudder_part(n_chord=3).slots.values():
                for g in gs:
                    static.add("shadow", g)
            r = self.rig
            static.add("shadow", tube(np.array([[r.x_mast, 0, r.z_step], [r.x_mast, 0, r.z_top]]),
                                      0.5 * float(cls["rig"]["mast_chord"]) * 0.8, 4, caps=False))
            boom = Part()
            for gs in r.boom_part().slots.values():
                for g in gs:
                    if (g.tag or "") == "boom":
                        boom.add("shadow", g)
        return static, boom

    def write_game_glb(self, path):
        """The game model with its shadow proxy (sail_visuals.md 11.4)."""
        parts = self.game_parts()
        self._write(path, self.cls["id"], parts, self.pivots,
                    extras={"class": self.cls["id"], "name": self.cls.get("name", ""),
                            "body_parts": dict(gltf.PART_IDS), **self.livery_extras()},
                    shadow=True)
        return parts

    @staticmethod
    def model_counts(parts):
        """(triangles without the sails, surfaces without the sails, sail triangles) of a level's parts as the
        GLB holds them: one surface per node in the boat material, the sails apart."""
        tris = sum(p.tri_count() for n, p in parts.items() if not n.startswith("sail_"))
        surf = sum(1 for n, p in parts.items() if not n.startswith("sail_") and p.tri_count())
        sails = sum(p.tri_count() for n, p in parts.items() if n.startswith("sail_"))
        return tris, surf, sails

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
        # the boom follows the main as drawn (it stops on a flying sail's sheet, sail_visuals.md 7.6)
        mid_ = next((k for k, v in shapes.items() if v.kind == 0), None)
        main_angle = float(np.degrees(shapes[mid_].beta)) if mid_ is not None else \
            float(spec["sails"].get("main", 0.0)) * (1.0 if spec["awa"] <= 0 else -1.0)
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

    def livery_transom(self):
        """The transom's uv1 frame and name panel for the liveries (data_format.md §8.5), GLB frame: {"rect": [h,
        top, bottom] (half width, heights of the top and bottom), "panel": {"uv1": [u0, v0, u1, v1], "size": [w, h]
        m}}. With a transom-hung rudder the panel lies to starboard of the gudgeons."""
        d = self.deck
        h, top, bot = d.transom_rect()
        r_half = 0.0
        if self.app.transom_hung:
            for gs in self.parts["hardware"].slots.values():
                for g in gs:
                    if g.tag and g.tag.startswith("gudgeon"):
                        r_half = max(r_half, float(np.abs(g.P[:, 1]).max()))
        yp, ys, zt, zb = d.transom_name_panel(r_half)
        uv = d.transom_uv1(np.array([[0.0, yp, zt], [0.0, ys, zb]]))
        return {"rect": [round(h, 4), round(top, 4), round(bot, 4)],
                "panel": {"uv1": [round(float(v), 4) for v in (uv[0, 0], uv[0, 1], uv[1, 0], uv[1, 1])],
                          "size": [round(yp - ys, 3), round(zt - zb, 3)]}}

    def livery_extras(self):
        """GLB root extras for the liveries: the topsides' name and number panels, the transom's frame and name
        panel, and the deck's plan rectangle (its uv1 frame) as [forward_min, port_top, length, height]."""
        x0, yt, w, h = self.deck.plan_rect()
        return {"livery_panels": self.livery_panels(), "livery_transom": self.livery_transom(),
                "deck_plan": [round(x0 - self.origin_x(), 4), round(yt, 4), round(w, 4), round(h, 4)]}

    def origin_x(self):
        return 0.5 * (self.hull.x_awl + self.hull.x_fwl)

    # set by the command line: write the texture atlas (by URI under `tex_uri`, else embedded), bake per-vertex AO
    textures = True
    bake = True
    tex_uri = None

    def write_glb(self, path):
        """The game model (game_parts)."""
        return self.write_game_glb(path)

    def _write(self, path, root, parts, pivots, extras=None, shadow=False):
        w = GLBWriter(self.origin_x(), textures=self.textures, tex_uri=self.tex_uri)
        merged = {n: p.merged() for n, p in parts.items()}
        ao = self.bake_ao(merged) if self.bake else {}
        kids = [w.add_mesh(n, parts[n], pivot=pivots.get(n), ao=ao.get(n), merged=merged[n]) for n in parts]
        if shadow:
            static, boom = self.shadow_proxy()
            kids.append(w.add_mesh("shadow", static, material="shadow"))
            bn = next((k for k in kids if k is not None and k["name"] == "boom"), None)
            if bn is not None and boom.tri_count():
                child = w.add_mesh("shadow_boom", boom, pivot=pivots.get("boom"), material="shadow")
                child.pop("translation", None)
                bn["children"] = [child]
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
