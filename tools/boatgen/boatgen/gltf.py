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
    "carbon":      ((0.035, 0.035, 0.038, 1.0), 0.1, 0.30),
    "metal":       ((0.62, 0.62, 0.64, 1.0), 1.0, 0.22),
    "sailcloth":   ((0.80, 0.80, 0.78, 1.0), 0.0, 0.55),
    "glass":       ((0.02, 0.025, 0.03, 1.0), 0.0, 0.05),
    "rope":        ((0.34, 0.33, 0.31, 1.0), 0.0, 0.85),
    "rubber":      ((0.05, 0.05, 0.05, 1.0), 0.0, 0.80),
}

# The running rigging by function (docs/specs/data_format.md 8.7): braid colour and fleck colour (sRGB), the
# generator's look of the class rope set's defaults. A slot's mean colour is the braid's: 14 of 16 carriers in the
# main colour and 2 in the fleck. `rope` stays the grey of the lifelines and anything else.
ROPES = {
    "mainsheet": ("#1f2b45", "#d8d8d2"),
    "sheet": ("#d2d2cb", "#b3242a"),
    "kite_sheet": ("#2b62a6", "#dadad4"),
    "halyard": ("#d4d4cd", "#2d7a40"),
    "control": ("#1d1e21", "#c9a227"),
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


class GLBWriter:
    def __init__(self, origin_x, textures=True):
        self.ox = origin_x
        self.textures = textures
        self.bin = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.mat_index = {}
        self.materials = []
        self.images, self.gltf_textures, self.tex_index = [], [], {}

    def _texture(self, path):
        """Embed a JPEG once and return its texture index (one repeating, mipmapped sampler for all)."""
        if path not in self.tex_index:
            with open(path, "rb") as f:
                data = f.read()
            while len(self.bin) % 4:
                self.bin.append(0)
            self.views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)})
            self.bin += data
            self.images.append({"name": path.rsplit("/", 1)[-1].rsplit(".", 1)[0], "bufferView": len(self.views) - 1,
                                "mimeType": "image/jpeg"})
            self.gltf_textures.append({"sampler": 0, "source": len(self.images) - 1})
            self.tex_index[path] = len(self.gltf_textures) - 1
        return self.tex_index[path]

    def _mat(self, name):
        if name not in self.mat_index:
            col, met, rough = MATERIALS[name]
            tset, tiling = tex.SLOTS[name]
            pbr = {"baseColorFactor": list(col), "metallicFactor": met, "roughnessFactor": rough}
            m = {"name": name, "pbrMetallicRoughness": pbr, "extras": {"tiling_m": tiling}}
            if self.textures and tset:
                s = 1.0 / tiling
                info = lambda path: {"index": self._texture(path), "texCoord": 0,
                                     "extensions": {"KHR_texture_transform": {"scale": [s, s]}}}
                p = tex.paths(tset)
                pbr["baseColorFactor"] = [round(c / tex.DETAIL_MEAN, 6) for c in col[:3]] + [col[3]]
                pbr["roughnessFactor"] = round(min(1.0, rough / tex.ROUGH_MEAN), 6)
                pbr["baseColorTexture"] = info(p["color"])
                pbr["metallicRoughnessTexture"] = info(p["mr"])
                if tex.has_normal(tset):
                    m["normalTexture"] = info(p["normal"])
                m["extras"]["texture_set"] = tset
            if name == "glass":
                m["alphaMode"] = "OPAQUE"
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

    def add_mesh(self, name, part, pivot=None, ao=None, merged=None):
        """Add a Part as a mesh node. With a pivot (boat frame) the geometry is stored relative to it and the node
        is translated there, so an engine can rotate it about that point. Pivot nodes must be children of the
        (identity) root. `ao` maps a material slot to per-vertex ambient occlusion (0..1) of the merged
        geometry, written as COLOR_0 (grey, alpha 1); `merged` is `part.merged()` when the caller has it."""
        prims = []
        piv = np.zeros(3) if pivot is None else to_gltf(np.asarray(pivot, dtype=np.float64)[None, :], self.ox)[0]
        for mat, g in sorted((part.merged() if merged is None else merged).items()):
            for arr, what in ((g.P, "positions"), (g.N, "normals"), (g.uv0, "uv0"), (g.uv1, "uv1")):
                if not np.isfinite(arr).all():
                    raise ValueError(f"{name}/{mat}: non-finite {what}")
            P = (to_gltf(g.P, self.ox) - piv).astype(np.float32)
            N = to_gltf_dir(g.N).astype(np.float32)
            n = np.linalg.norm(N, axis=1, keepdims=True)
            N = np.where(n > 1e-6, N / np.maximum(n, 1e-9), np.array([0, 1, 0], np.float32)).astype(np.float32)
            attrs = {"POSITION": self._add(P, 5126, "VEC3", 34962, True),
                     "NORMAL": self._add(N, 5126, "VEC3", 34962),
                     "TEXCOORD_0": self._add(g.uv0.astype(np.float32), 5126, "VEC2", 34962),
                     "TEXCOORD_1": self._add(g.uv1.astype(np.float32), 5126, "VEC2", 34962)}
            if ao is not None and mat in ao:
                a = np.clip(np.rint(np.asarray(ao[mat]) * 255), 0, 255).astype(np.uint8)
                C = np.stack([a, a, a, np.full_like(a, 255)], -1)
                attrs["COLOR_0"] = self._add(C, 5121, "VEC4", 34962)
                self.accessors[-1]["normalized"] = True
            idx = g.I.astype(np.uint32 if len(P) > 65535 else np.uint16).reshape(-1)
            ia = self._add(idx, 5125 if idx.dtype == np.uint32 else 5123, "SCALAR", 34963)
            prims.append({"attributes": attrs, "indices": ia, "material": self._mat(mat)})
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


def read_glb(path):
    """Returns a list of (node name, material name, world-space P, N, uv0, uv1, I, ao) in the glTF frame (ao: the
    COLOR_0 grey as 0..1, or None), and the glTF document with the binary chunk as `doc["_bin"]`."""
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

    def walk(ni, T):
        n = doc["nodes"][ni]
        T = T + np.asarray(n.get("translation", [0, 0, 0]), dtype=np.float64)
        if "mesh" in n:
            for p in doc["meshes"][n["mesh"]]["primitives"]:
                at = p["attributes"]
                out.append((n["name"], doc["materials"][p["material"]]["name"],
                            acc(at["POSITION"]).astype(np.float64) + T, acc(at["NORMAL"]).astype(np.float64),
                            acc(at["TEXCOORD_0"]).astype(np.float64), acc(at["TEXCOORD_1"]).astype(np.float64),
                            acc(p["indices"]).reshape(-1, 3).astype(np.int64),
                            acc(at["COLOR_0"])[:, 0] / 255.0 if "COLOR_0" in at else None))
        for c in n.get("children", []):
            walk(c, T)

    for r in doc["scenes"][0]["nodes"]:
        walk(r, np.zeros(3))
    doc["_bin"] = buf
    return out, doc
