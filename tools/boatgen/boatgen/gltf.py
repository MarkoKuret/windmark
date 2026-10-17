"""Minimal binary glTF 2.0 (GLB) writer and reader.

Frame conversion: the boat frame (x forward, y port, z up) maps to glTF (+X port, +Y up, +Z forward) by the
cyclic permutation (x, y, z) -> (Z, X, Y) - a rotation, so triangle winding is kept. The origin is shifted to the
centreline, on the DWL, at mid LWL.
"""
import json
import struct

import numpy as np

from . import textures as tex

# name -> (mean base colour RGBA linear, metallic, mean roughness); the tile size and texture set are in
# textures.SLOTS. With textures the factors are divided by the texture means, so the mean look stays the same.
# Real-material values (docs/specs/data_format.md 3.7): a white gelcoat reflects about 70 % and keeps a soft sheen,
# not a mirror; the moulded non-slip is a shade greyer and matt; deck metal is polished stainless (about 60 %,
# slightly blurred); rope is a flecked braid. No mean colour is above the boat shader's 0.8 albedo cap.
MATERIALS = {
    "gelcoat":     ((0.72, 0.72, 0.70, 1.0), 0.0, 0.22),
    "transom":     ((0.72, 0.72, 0.70, 1.0), 0.0, 0.22),     # the transom face: gelcoat, its own slot and uv1 for the livery
    "nonslip":     ((0.47, 0.47, 0.45, 1.0), 0.0, 0.85),
    "antifouling": ((0.035, 0.045, 0.07, 1.0), 0.0, 0.75),
    "boottop":     ((0.50, 0.03, 0.03, 1.0), 0.0, 0.25),
    "carbon":      ((0.035, 0.035, 0.038, 1.0), 0.0, 0.30),   # clear-coated carbon: dark, slightly glossy, no weave
    "metal":       ((0.62, 0.62, 0.64, 1.0), 1.0, 0.22),
    "sailcloth":   ((0.80, 0.80, 0.78, 1.0), 0.0, 0.55),
    "glass":       ((0.02, 0.025, 0.03, 1.0), 0.0, 0.05),
    "face":        ((0.72, 0.72, 0.70, 1.0), 0.0, 0.22),     # the coachroof's aft face: deck gelcoat on its own uv1
    "rope":        ((0.34, 0.33, 0.31, 1.0), 0.0, 0.85),
    "rubber":      ((0.05, 0.05, 0.05, 1.0), 0.0, 0.80),
    "shadow":      ((0.5, 0.5, 0.5, 1.0), 0.0, 1.0),       # the shadow proxy: never drawn, only casts
}

# The running rigging by function (docs/specs/data_format.md 8.7): braid colour and fleck colour (sRGB), the
# generator's look of the class rope set's defaults: each function its own clear colour with a contrasting fleck. A slot's mean colour is the braid's: 14 of 16 carriers in the
# main colour and 2 in the fleck. `rope` stays the grey of the lifelines and anything else.
ROPES = {
    "mainsheet": ("#ae7249", "#2d3548"),
    "sheet": ("#3e797b", "#d6d6ce"),
    "kite_sheet": ("#91506f", "#d6d6ce"),
    "halyard_main": ("#9c4c4e", "#d6d6ce"),
    "halyard_jib": ("#486792", "#d6d6ce"),
    "halyard_kite": ("#497551", "#d6d6ce"),
    "halyard_code": ("#b79c5a", "#2a2b2e"),
    "control": ("#6b5986", "#d6d6ce"),
}


def _srgb_lin(h):
    c = np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)]) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


for _fn, (_main, _fleck) in ROPES.items():
    _m = (14 * _srgb_lin(_main) + 2 * _srgb_lin(_fleck)) / 16
    MATERIALS["rope_" + _fn] = ((round(float(_m[0]), 4), round(float(_m[1]), 4), round(float(_m[2]), 4), 1.0), 0.0, 0.85)


def to_gltf(P, origin_x):
    P = np.asarray(P, dtype=np.float64)
    return np.stack([P[..., 1], P[..., 2], P[..., 0] - origin_x], -1)


def to_gltf_dir(N):
    N = np.asarray(N, dtype=np.float64)
    return np.stack([N[..., 1], N[..., 2], N[..., 0]], -1)


# ---------------------------------------------------------------------------------------------------------
# The boat material (sail_visuals.md 11.4, tools/boatgen/README.md "Materials and UVs"): every opaque surface of the
# model but the sails is one glTF material, `boat`, so a node is one draw. Each vertex carries its slot in COLOR_0
# (red: the baked AO, green: the slot id / 255); the material's extras hold the slot table (mean colour, roughness,
# metallic, tiling texture and tile size, livery region) and the tiling texture atlas. The livery regions say which
# baked livery map a slot reads in the game (data_format.md 8.5): `hull` (uv1 hull atlas), `deck` (uv1 plan view,
# with the non-slip mask), `transom` (its uv1), `keel` (side view of the model), `keel_colour` (the livery's keel
# colour, no map).

# slot id -> (slot name, base material of MATERIALS, livery region)
ATLAS_SLOTS = [
    ("hull_gelcoat", "gelcoat", "hull"),
    ("hull_boottop", "boottop", "hull"),
    ("hull_antifouling", "antifouling", "hull"),
    ("deck_gelcoat", "gelcoat", "deck"),
    ("deck_nonslip", "nonslip", "deck"),
    ("transom", "transom", "transom"),
    ("keel", "antifouling", "keel"),
    ("rudder", "antifouling", "keel_colour"),
    ("gelcoat", "gelcoat", ""),
    ("carbon", "carbon", ""),
    ("metal", "metal", ""),
    ("rubber", "rubber", ""),
    ("rope", "rope", ""),
    ("rope_control", "rope_control", ""),
    ("glass", "glass", ""),
    ("rope_mainsheet", "rope_mainsheet", ""),
    ("nonslip", "nonslip", ""),
    ("rope_sheet", "rope_sheet", ""),
    ("rope_kite_sheet", "rope_kite_sheet", ""),
    ("antifouling", "antifouling", ""),
    ("boottop", "boottop", ""),
    ("rope_halyard_main", "rope_halyard_main", ""),
    ("rope_halyard_jib", "rope_halyard_jib", ""),
    ("rope_halyard_kite", "rope_halyard_kite", ""),
    ("rope_halyard_code", "rope_halyard_code", ""),
    ("deck_face", "gelcoat", "deck"),
]
SLOT_ID = {n: i for i, (n, _, _) in enumerate(ATLAS_SLOTS)}
# the source part of a merged node's vertex (COLOR_0 blue, data_format.md 8.5): 0 the node itself
PART_IDS = {"hull": 1, "deck": 2, "keel": 3, "mast": 4, "rigging": 5, "hardware": 6}
REGIONS = ["", "hull", "deck", "transom", "keel", "keel_colour"]
# slots that keep their own material: the sails (deformed per vertex at run time, their own shaders)
OWN_MATERIAL = ("sailcloth",)


def atlas_slot(node, mat):
    """The boat material's slot id of a piece of `node` in material `mat` (a merged node's pieces carry
    "<node>:<mat>")."""
    if ":" in mat:
        node, mat = mat.split(":", 1)
    if node == "hull" and mat in ("gelcoat", "boottop", "antifouling"):
        return SLOT_ID["hull_" + mat]
    if node == "deck" and mat == "face":
        return SLOT_ID["deck_face"]
    if node == "deck" and mat in ("gelcoat", "nonslip"):
        return SLOT_ID["deck_" + mat]
    if node == "keel" and mat == "antifouling":
        return SLOT_ID["keel"]
    if node in ("rudder", "rudder_port", "rudder_starboard") and mat == "antifouling":
        return SLOT_ID["rudder"]
    return SLOT_ID[mat]


def atlas_extras():
    """The boat material's extras: the slot table and the tiling atlas layout."""
    slots = []
    for name, base, region in ATLAS_SLOTS:
        col, met, rough = MATERIALS[base]
        tset, tiling = tex.SLOTS[base]
        slots.append({"name": name, "region": region, "color": [round(float(c), 5) for c in col[:3]],
                      "roughness": rough, "metallic": met, "tile": tex.ATLAS_SETS.index(tset or "flat"),
                      "tiling_m": tiling, "normal_scale": 1.0, "steep_map": name == "deck_face"})
    return {"slots": slots, "atlas": {"cols": tex.ATLAS_COLS, "rows": tex.ATLAS_ROWS, "tile_px": tex.SIZE,
                                      "sets": list(tex.ATLAS_SETS)},
            "detail_mean": tex.DETAIL_MEAN, "rough_mean": tex.ROUGH_MEAN}


class GLBWriter:
    def __init__(self, origin_x, textures=True, tex_uri=None):
        """`tex_uri`: the folder of the shared texture atlas relative to the GLB (`_tex`), referenced by URI; None
        embeds the atlas (tests and previews that write a GLB alone)."""
        self.ox = origin_x
        self.textures = textures
        self.tex_uri = tex_uri
        self.bin = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.mat_index = {}
        self.materials = []
        self.images, self.gltf_textures, self.tex_index = [], [], {}

    def _texture(self, key, name):
        """The texture index of the shared atlas image `name` (tiles_color.png, ...) or a sail set image, once
        per file: by URI under `tex_uri`, else embedded."""
        if key not in self.tex_index:
            if self.tex_uri is not None:
                self.images.append({"name": name.rsplit(".", 1)[0], "uri": f"{self.tex_uri}/{name}"})
            else:
                data = tex.image_bytes(name)
                while len(self.bin) % 4:
                    self.bin.append(0)
                self.views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)})
                self.bin += data
                self.images.append({"name": name.rsplit(".", 1)[0], "bufferView": len(self.views) - 1,
                                    "mimeType": "image/png" if name.endswith(".png") else "image/jpeg"})
            self.gltf_textures.append({"sampler": 0, "source": len(self.images) - 1})
            self.tex_index[key] = len(self.gltf_textures) - 1
        return self.tex_index[key]

    def _mat(self, name):
        if name not in self.mat_index:
            if name == "boat":
                m = {"name": "boat", "pbrMetallicRoughness": {"baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                                                              "metallicFactor": 1.0, "roughnessFactor": 1.0},
                     "extras": atlas_extras()}
                if self.textures:
                    info = lambda f: {"index": self._texture(f, f), "texCoord": 0}
                    m["pbrMetallicRoughness"]["baseColorTexture"] = info(tex.ATLAS_FILES["color"])
                    m["pbrMetallicRoughness"]["metallicRoughnessTexture"] = info(tex.ATLAS_FILES["mr"])
                    m["normalTexture"] = info(tex.ATLAS_FILES["normal"])
            else:
                # a slot with its own material (the sails): its tiling set by URI or embedded
                col, met, rough = MATERIALS[name]
                tset, tiling = tex.SLOTS[name]
                pbr = {"baseColorFactor": list(col), "metallicFactor": met, "roughnessFactor": rough}
                m = {"name": name, "pbrMetallicRoughness": pbr, "extras": {"tiling_m": tiling}}
                if self.textures and tset:
                    s = 1.0 / tiling
                    info = lambda f: {"index": self._texture(f, f), "texCoord": 0,
                                      "extensions": {"KHR_texture_transform": {"scale": [s, s]}}}
                    pbr["baseColorFactor"] = [round(c / tex.DETAIL_MEAN, 6) for c in col[:3]] + [col[3]]
                    pbr["roughnessFactor"] = round(min(1.0, rough / tex.ROUGH_MEAN), 6)
                    pbr["baseColorTexture"] = info(f"{tset}_color.jpg")
                    pbr["metallicRoughnessTexture"] = info(f"{tset}_mr.jpg")
                    if tex.has_normal(tset):
                        m["normalTexture"] = info(f"{tset}_normal.jpg")
                    m["extras"]["texture_set"] = tset
            self.mat_index[name] = len(self.materials)
            self.materials.append(m)
        return self.mat_index[name]

    def _add(self, arr, comp, typ, target=None, minmax=False):
        data = np.ascontiguousarray(arr).tobytes()
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.views.append(v)
        a = {"bufferView": len(self.views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.accessors.append(a)
        return len(self.accessors) - 1

    def add_mesh(self, name, part, pivot=None, ao=None, merged=None, material=None):
        """Add a Part as a mesh node: one primitive in the `boat` material for every slot but the sails (COLOR_0:
        AO in red, slot id / 255 in green), or with `material` every piece in that material (the shadow proxy).
        With a pivot (boat frame) the geometry is stored relative to it and the node is translated there, so an
        engine can rotate it about that point. Pivot nodes must be children of the (identity) root. `ao` maps a
        material slot to per-vertex ambient occlusion (0..1) of the merged geometry; `merged` is `part.merged()`
        when the caller has it."""
        prims = []
        piv = np.zeros(3) if pivot is None else to_gltf(np.asarray(pivot, dtype=np.float64)[None, :], self.ox)[0]
        groups = {}
        for mat, g in sorted((part.merged() if merged is None else merged).items()):
            for arr, what in ((g.P, "positions"), (g.N, "normals"), (g.uv0, "uv0"), (g.uv1, "uv1")):
                if not np.isfinite(arr).all():
                    raise ValueError(f"{name}/{mat}: non-finite {what}")
            if material is not None:
                key, sid = material, None
            elif mat.split(":")[-1] in OWN_MATERIAL:
                key, sid = mat.split(":")[-1], None
            else:
                key, sid = "boat", atlas_slot(name, mat)
            a = None
            if ao is not None and mat in ao:
                a = np.asarray(ao[mat], dtype=np.float64)
            pid = PART_IDS.get(mat.split(":")[0], 0) if ":" in mat else 0
            groups.setdefault(key, []).append((g, sid, a, pid))
        for key, items in groups.items():
            off, Ps, Ns, U0, U1, Is, C = 0, [], [], [], [], [], []
            for g, sid, a, pid in items:
                Ps.append(g.P)
                Ns.append(g.N)
                U0.append(g.uv0)
                U1.append(g.uv1)
                Is.append(g.I + off)
                off += len(g.P)
                if sid is not None:
                    av = np.ones(len(g.P)) if a is None else a
                    q = np.clip(np.rint(av * 255), 0, 255).astype(np.uint8)
                    C.append(np.stack([q, np.full_like(q, sid), np.full_like(q, pid), np.full_like(q, 255)], -1))
                elif a is not None:
                    q = np.clip(np.rint(a * 255), 0, 255).astype(np.uint8)
                    C.append(np.stack([q, q, q, np.full_like(q, 255)], -1))
            P = (to_gltf(np.vstack(Ps), self.ox) - piv).astype(np.float32)
            N = to_gltf_dir(np.vstack(Ns)).astype(np.float32)
            n = np.linalg.norm(N, axis=1, keepdims=True)
            N = np.where(n > 1e-6, N / np.maximum(n, 1e-9), np.array([0, 1, 0], np.float32)).astype(np.float32)
            attrs = {"POSITION": self._add(P, 5126, "VEC3", 34962, True),
                     "NORMAL": self._add(N, 5126, "VEC3", 34962),
                     "TEXCOORD_0": self._add(np.vstack(U0).astype(np.float32), 5126, "VEC2", 34962),
                     "TEXCOORD_1": self._add(np.vstack(U1).astype(np.float32), 5126, "VEC2", 34962)}
            if C and len(C) == len(items):
                attrs["COLOR_0"] = self._add(np.vstack(C), 5121, "VEC4", 34962)
                self.accessors[-1]["normalized"] = True
            I = np.vstack(Is)
            idx = I.astype(np.uint32 if len(P) > 65535 else np.uint16).reshape(-1)
            ia = self._add(idx, 5125 if idx.dtype == np.uint32 else 5123, "SCALAR", 34963)
            prims.append({"attributes": attrs, "indices": ia, "material": self._mat(key)})
        if not prims:
            return None
        self.meshes.append({"name": name, "primitives": prims})
        node = {"name": name, "mesh": len(self.meshes) - 1}
        if pivot is not None:
            node["translation"] = [float(v) for v in piv]
        return node

    def write(self, path, root_name, children, extras=None):
        nodes = []

        def add_node(n):
            kids = n.pop("children", [])
            nodes.append(n)
            i = len(nodes) - 1
            if kids:
                n["children"] = [add_node(k) for k in kids if k is not None]
            return i

        root = {"name": root_name, "children": [c for c in children if c is not None]}
        if extras:
            root["extras"] = extras
        ri = add_node(root)
        while len(self.bin) % 4:
            self.bin.append(0)
        doc = {"asset": {"version": "2.0", "generator": "windmark boatgen"},
               "scene": 0, "scenes": [{"nodes": [ri]}], "nodes": nodes, "meshes": self.meshes,
               "materials": self.materials, "accessors": self.accessors, "bufferViews": self.views,
               "buffers": [{"byteLength": len(self.bin)}]}
        if self.images:
            doc["images"] = self.images
            doc["textures"] = self.gltf_textures
            # linear, trilinear mipmaps, repeat
            doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
            if any("extensions" in i for m in self.materials for i in m["pbrMetallicRoughness"].values()
                   if isinstance(i, dict)):
                doc["extensionsUsed"] = ["KHR_texture_transform"]
        js = json.dumps(doc, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942))
            f.write(bytes(self.bin))


def read_glb(path, expand=True):
    """Returns a list of (node name, material name, world-space P, N, uv0, uv1, I, ao) in the glTF frame (ao: the
    COLOR_0 red as 0..1, or None), and the glTF document with the binary chunk as `doc["_bin"]`. With `expand` a
    primitive in the `boat` material comes back as one entry per slot, named after the slot's base material
    (gelcoat, metal, ...), and `doc["materials"]` gains a plain material of that name with its tiling set (images
    by path), as the GLB was before the boat material; `doc["_slots"]` lists (node, slot name, triangles) and `doc["_prim_slots"]` the slot name of each returned entry
    (None outside the boat material)."""
    with open(path, "rb") as f:
        data = f.read()
    jl = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jl])
    bin_off = 20 + jl + 8
    buf = data[bin_off:]
    comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

    def acc(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        return np.frombuffer(buf, comp[a["componentType"]], a["count"] * ncomp[a["type"]],
                             v["byteOffset"]).reshape(a["count"], -1)

    out = []
    doc["_slots"] = []
    doc["_prim_slots"] = []
    plain = {}

    def plain_mat(base):
        if base not in plain:
            col, met, rough = MATERIALS[base]
            tset, tiling = tex.SLOTS[base]
            pbr = {"baseColorFactor": list(col), "metallicFactor": met, "roughnessFactor": rough}
            m = {"name": base, "pbrMetallicRoughness": pbr, "extras": {"tiling_m": tiling}}
            if tset:
                doc.setdefault("images", [])
                doc.setdefault("textures", [])

                def info(k):
                    doc["images"].append({"name": f"{tset}_{k}", "_path": tex.paths(tset)[k]})
                    doc["textures"].append({"sampler": 0, "source": len(doc["images"]) - 1})
                    return {"index": len(doc["textures"]) - 1, "texCoord": 0,
                            "extensions": {"KHR_texture_transform": {"scale": [1 / tiling] * 2}}}
                pbr["baseColorFactor"] = [c / tex.DETAIL_MEAN for c in col[:3]] + [col[3]]
                pbr["roughnessFactor"] = min(1.0, rough / tex.ROUGH_MEAN)
                pbr["baseColorTexture"] = info("color")
                pbr["metallicRoughnessTexture"] = info("mr")
                if tex.has_normal(tset):
                    m["normalTexture"] = info("normal")
                m["extras"]["texture_set"] = tset
            plain[base] = m
        return base

    def walk(ni, T):
        n = doc["nodes"][ni]
        T = T + np.asarray(n.get("translation", [0, 0, 0]), dtype=np.float64)
        if "mesh" in n:
            for p in doc["meshes"][n["mesh"]]["primitives"]:
                at = p["attributes"]
                mname = doc["materials"][p["material"]]["name"]
                P = acc(at["POSITION"]).astype(np.float64) + T
                Nn = acc(at["NORMAL"]).astype(np.float64)
                u0 = acc(at["TEXCOORD_0"]).astype(np.float64)
                u1 = acc(at["TEXCOORD_1"]).astype(np.float64)
                I = acc(p["indices"]).reshape(-1, 3).astype(np.int64)
                C = acc(at["COLOR_0"]) if "COLOR_0" in at else None
                ao = C[:, 0] / 255.0 if C is not None else None
                if mname == "boat" and expand and C is not None:
                    sid = C[:, 1].astype(int)
                    tsid = sid[I[:, 0]]
                    for k in np.unique(tsid):
                        It = I[tsid == k]
                        used = np.unique(It)
                        remap = np.full(len(P), -1, np.int64)
                        remap[used] = np.arange(len(used))
                        sname, base, _ = ATLAS_SLOTS[k]
                        doc["_slots"].append((n["name"], sname, len(It)))
                        doc["_prim_slots"].append(sname)
                        out.append((n["name"], plain_mat(base), P[used], Nn[used], u0[used], u1[used], remap[It],
                                    ao[used]))
                    continue
                out.append((n["name"], mname, P, Nn, u0, u1, I, ao))
                doc["_prim_slots"].append(None)
        for c in n.get("children", []):
            walk(c, T)

    for r in doc["scenes"][0]["nodes"]:
        walk(r, np.zeros(3))
    doc["materials"] = doc["materials"] + list(plain.values())
    doc["_bin"] = buf
    return out, doc
