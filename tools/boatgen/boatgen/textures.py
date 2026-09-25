"""Tiling PBR texture set for the material slots.

The generator's material slots keep their colour and roughness in the glTF factors; the textures only add
detail around a mean of one, so a slot's average look does not depend on the texture. Each set has three
512 x 512 tiling images in `tools/boatgen/textures/`:

- `<set>_color.jpg`: grey detail, sRGB, linear mean `DETAIL_MEAN` (the factor is the slot colour / that mean)
- `<set>_mr.jpg`: glTF metallic-roughness (G roughness around `ROUGH_MEAN`, B metallic 1, R unused)
- `<set>_normal.jpg`: tangent-space normal map, OpenGL convention (+Y up), as glTF expects

The images are made from CC0 materials of ambientCG (docs/THIRD_PARTY.md) by `python3 -m boatgen.textures`, which
downloads the 1K sources and writes the processed files. The build only reads the processed files.
"""
import io
import os
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(HERE, "textures")
SIZE = 512
DETAIL_MEAN = 0.92
ROUGH_MEAN = 0.80

# set -> (ambientCG asset, colour detail contrast, roughness contrast, normal strength)
SETS = {
    "orange_peel": ("Plastic013A", 0.15, 0.4, 1.0),   # gelcoat and paint: slight orange peel
    "pebble": ("Leather026", 0.35, 0.6, 1.4),         # moulded non-slip grain
    "grain": ("Rubber004", 0.35, 0.5, 0.8),           # rolled antifouling, rubber
    "carbon_twill": ("Fabric004", 1.0, 0.6, 1.0),     # carbon twill weave
    "brushed": ("Metal009", 0.4, 0.6, 0.6),           # brushed stainless and aluminium
    "weave": ("Fabric062", 0.35, 0.3, 0.0),           # sailcloth (no normal map, sail_visuals.md 9)
    "braid": ("Rope002", 0.8, 0.4, 1.0),              # braided rope
}

# slot -> (set or None, tile size in metres: one image covers tiling_m x tiling_m of uv0)
SLOTS = {
    "gelcoat": ("orange_peel", 0.5),
    "boottop": ("orange_peel", 0.5),
    "nonslip": ("pebble", 0.25),
    "antifouling": ("grain", 0.5),
    "rubber": ("grain", 0.1),
    "carbon": ("carbon_twill", 0.05),
    "metal": ("brushed", 0.2),
    "sailcloth": ("weave", 0.5),
    "rope": ("braid", 0.05),
    "glass": (None, 1.0),
}


def paths(set_name):
    return {k: os.path.join(TEX_DIR, f"{set_name}_{k}.jpg") for k in ("color", "mr", "normal")}


def has_normal(set_name):
    return SETS[set_name][3] > 0


def _srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def _load(z, suffix):
    name = next((n for n in z.namelist() if n.endswith(suffix)), None)
    if name is None:
        return None
    im = Image.open(io.BytesIO(z.read(name))).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255.0


def _detail(x, mean, contrast):
    """Rescale a map to the given mean with its variation scaled by contrast, clipped to [0, 1]."""
    return np.clip(mean * (1 + contrast * (x / max(x.mean(), 1e-6) - 1)), 0, 1)


def process(set_name, zip_bytes):
    asset, c_col, c_rough, n_str = SETS[set_name]
    z = zipfile.ZipFile(io.BytesIO(zip_bytes))
    col = _srgb_to_lin(_load(z, "_Color.jpg"))
    lum = col @ np.array([0.2126, 0.7152, 0.0722])
    grey = _lin_to_srgb(_detail(lum, DETAIL_MEAN, c_col))
    rough = _load(z, "_Roughness.jpg")[..., 1]
    mr = np.stack([np.ones_like(rough), _detail(rough, ROUGH_MEAN, c_rough), np.ones_like(rough)], -1)
    p = paths(set_name)
    os.makedirs(TEX_DIR, exist_ok=True)
    Image.fromarray((np.repeat(grey[..., None], 3, -1) * 255 + 0.5).astype(np.uint8)).save(p["color"], quality=92)
    Image.fromarray((mr * 255 + 0.5).astype(np.uint8)).save(p["mr"], quality=92)
    if n_str > 0:
        n = _load(z, "_NormalGL.jpg") * 2 - 1
        n[..., :2] *= n_str
        n[..., 2] = np.maximum(n[..., 2], 1e-3)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(p["normal"], quality=95)
    elif os.path.exists(p["normal"]):
        os.remove(p["normal"])


def fetch(set_names=None, cache=None):
    for s in set_names or SETS:
        asset = SETS[s][0]
        url = f"https://ambientcg.com/get?file={asset}_1K-JPG.zip"
        local = os.path.join(cache, f"{asset}.zip") if cache else None
        if local and os.path.exists(local):
            data = open(local, "rb").read()
        else:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = urllib.request.urlopen(req, timeout=120).read()
            if local:
                with open(local, "wb") as f:
                    f.write(data)
        process(s, data)
        print(f"{s}: {asset} -> {', '.join(os.path.basename(v) for v in paths(s).values() if os.path.exists(v))}")


if __name__ == "__main__":
    # python3 -m boatgen.textures [--cache DIR]: download the ambientCG sources and rewrite textures/
    np.seterr(all="ignore")   # spurious BLAS flags in matmul on some platforms
    args = sys.argv[1:]
    cache = args[args.index("--cache") + 1] if "--cache" in args else None
    fetch(cache=cache)
