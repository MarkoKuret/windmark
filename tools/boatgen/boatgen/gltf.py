"""Minimal binary glTF 2.0 (GLB) writer and reader.

Frame conversion: the boat frame (x forward, y port, z up) maps to glTF (+X port, +Y up, +Z forward) by the
cyclic permutation (x, y, z) -> (Z, X, Y) - a rotation, so triangle winding is kept. The origin is shifted to the
centreline, on the DWL, at mid LWL.
"""
import json
import struct

import numpy as np

# name -> (base colour RGBA linear, metallic, roughness, extras)
MATERIALS = {
    "gelcoat":     ((0.86, 0.87, 0.88, 1.0), 0.0, 0.18, {"tiling_m": 1.0}),
    "nonslip":     ((0.62, 0.64, 0.65, 1.0), 0.0, 0.85, {"tiling_m": 0.25}),
    "antifouling": ((0.035, 0.045, 0.07, 1.0), 0.0, 0.75, {"tiling_m": 1.0}),
    "boottop":     ((0.50, 0.03, 0.03, 1.0), 0.0, 0.25, {"tiling_m": 1.0}),
    "carbon":      ((0.035, 0.035, 0.038, 1.0), 0.1, 0.30, {"tiling_m": 0.05}),
    "metal":       ((0.80, 0.80, 0.82, 1.0), 1.0, 0.28, {"tiling_m": 0.2}),
    "sailcloth":   ((0.80, 0.80, 0.78, 1.0), 0.0, 0.55, {"tiling_m": 1.0}),
    "glass":       ((0.02, 0.025, 0.03, 1.0), 0.0, 0.05, {"tiling_m": 1.0}),
    "rope":        ((0.30, 0.30, 0.30, 1.0), 0.0, 0.80, {"tiling_m": 0.05}),
    "rubber":      ((0.04, 0.04, 0.04, 1.0), 0.0, 0.70, {"tiling_m": 0.1}),
}


def to_gltf(P, origin_x):
    P = np.asarray(P, dtype=np.float64)
    return np.stack([P[..., 1], P[..., 2], P[..., 0] - origin_x], -1)


def to_gltf_dir(N):
    N = np.asarray(N, dtype=np.float64)
    return np.stack([N[..., 1], N[..., 2], N[..., 0]], -1)


class GLBWriter:
    def __init__(self, origin_x):
        self.ox = origin_x
        self.bin = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.mat_index = {}
        self.materials = []

    def _mat(self, name):
        if name not in self.mat_index:
            col, met, rough, extras = MATERIALS[name]
            self.mat_index[name] = len(self.materials)
            m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": list(col), "metallicFactor": met,
                                                        "roughnessFactor": rough}, "extras": dict(extras)}
            if name == "glass":
                m["alphaMode"] = "OPAQUE"
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

    def add_mesh(self, name, part, pivot=None):
        """Add a Part as a mesh node. With a pivot (boat frame) the geometry is stored relative to it and the node
        is translated there, so an engine can rotate it about that point. Pivot nodes must be children of the
        (identity) root."""
        prims = []
        piv = np.zeros(3) if pivot is None else to_gltf(np.asarray(pivot, dtype=np.float64)[None, :], self.ox)[0]
        for mat, g in sorted(part.merged().items()):
            P = (to_gltf(g.P, self.ox) - piv).astype(np.float32)
            N = to_gltf_dir(g.N).astype(np.float32)
            n = np.linalg.norm(N, axis=1, keepdims=True)
            N = np.where(n > 1e-6, N / np.maximum(n, 1e-9), np.array([0, 1, 0], np.float32)).astype(np.float32)
            attrs = {"POSITION": self._add(P, 5126, "VEC3", 34962, True),
                     "NORMAL": self._add(N, 5126, "VEC3", 34962),
                     "TEXCOORD_0": self._add(g.uv0.astype(np.float32), 5126, "VEC2", 34962),
                     "TEXCOORD_1": self._add(g.uv1.astype(np.float32), 5126, "VEC2", 34962)}
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
    """Returns a list of (node name, material name, world-space P, N, uv0, uv1, I) in the glTF frame."""
    with open(path, "rb") as f:
        data = f.read()
    jl = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jl])
    bin_off = 20 + jl + 8
    buf = data[bin_off:]
    comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}

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
                            acc(p["indices"]).reshape(-1, 3).astype(np.int64)))
        for c in n.get("children", []):
            walk(c, T)

    for r in doc["scenes"][0]["nodes"]:
        walk(r, np.zeros(3))
    return out, doc
