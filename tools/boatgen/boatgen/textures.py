"""Tiling PBR texture set for the material slots.

The generator's material slots keep their colour and roughness in the glTF factors; the textures only add
detail around a mean of one, so a slot's average look does not depend on the texture. Each set has three
512 x 512 tiling images in `tools/boatgen/textures/`:

- `<set>_color.jpg`: grey detail, sRGB, linear mean `DETAIL_MEAN` (the factor is the slot colour / that mean)
- `<set>_mr.jpg`: glTF metallic-roughness (G roughness around `ROUGH_MEAN`, B metallic 1, R unused)
- `<set>_normal.jpg`: tangent-space normal map, OpenGL convention (+Y up), as glTF expects

The images are made from CC0 materials of ambientCG (docs/THIRD_PARTY.md) by `python3 -m boatgen.textures`, which
downloads the 1K sources and writes the processed files; sets without a source asset (the moulded non-slip) are
drawn here (`--procedural` rewrites only those). The build only reads the processed files.
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
    "grain": ("Rubber004", 0.35, 0.5, 0.8),           # rolled antifouling, rubber
    "carbon_twill": ("Fabric004", 1.0, 0.6, 1.0),     # carbon twill weave
    "brushed": ("Metal009", 0.4, 0.6, 0.6),           # brushed stainless and aluminium
    "weave": ("Fabric062", 0.35, 0.3, 0.0),           # sailcloth (no normal map, sail_visuals.md 9)
    "braid": ("Rope002", 0.8, 0.4, 1.0),              # braided rope
    "diamond": (None, 0.25, 0.35, 1.0),               # moulded non-slip: raised diamond pattern (procedural)
}

# slot -> (set or None, tile size in metres: one image covers tiling_m x tiling_m of uv0)
SLOTS = {
    "gelcoat": ("orange_peel", 0.5),
    "transom": ("orange_peel", 0.5),
    "boottop": ("orange_peel", 0.5),
    "nonslip": ("diamond", 0.1),
    "antifouling": ("grain", 0.5),
    "rubber": ("grain", 0.1),
    "carbon": ("carbon_twill", 0.05),
    "metal": ("brushed", 0.2),
    "sailcloth": ("weave", 0.5),
    "rope": ("braid", 0.05),
    "rope_mainsheet": ("braid", 0.05),
    "rope_sheet": ("braid", 0.05),
    "rope_kite_sheet": ("braid", 0.05),
    "rope_halyard": ("braid", 0.05),
    "rope_control": ("braid", 0.05),
    "glass": (None, 1.0),
    "shadow": (None, 1.0),
}


# The shared tiling atlas of the boat material (gltf.py "boat"): every set's 512 x 512 tile side by side, 4 x 2,
# per map (colour, metallic-roughness, normal), plus a flat tile (the mean, for slots without a set: glass). The
# game samples a tile with its own wrap (shaders/boat_atlas.gdshader). Written once per output folder as
# `_tex/tiles_<map>.png` and referenced by URI from every GLB, so every class and level of detail shares one copy.
ATLAS_SETS = ("orange_peel", "diamond", "grain", "carbon_twill", "brushed", "braid", "weave", "flat")
ATLAS_COLS, ATLAS_ROWS = 4, 2
ATLAS_FILES = {"color": "tiles_color.png", "mr": "tiles_mr.png", "normal": "tiles_normal.png"}
# the sails keep their own material on the weave set
OWN_FILES = ("weave_color.jpg", "weave_mr.jpg")

# Godot import settings for the shared textures: VRAM-compressed with mipmaps (colour BPTC, normal RGTC)
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def _tile(set_name, k):
    if set_name == "flat":
        v = {"color": [_lin_to_srgb(np.array(DETAIL_MEAN))] * 3, "mr": [1.0, ROUGH_MEAN, 1.0],
             "normal": [0.5, 0.5, 1.0]}[k]
        return np.broadcast_to((np.asarray(v, dtype=np.float64) * 255 + 0.5).astype(np.uint8), (SIZE, SIZE, 3))
    p = paths(set_name)[k]
    if k == "normal" and not has_normal(set_name):
        return _tile("flat", "normal")
    return np.asarray(Image.open(p).convert("RGB").resize((SIZE, SIZE)))


def atlas_image(k):
    """The atlas of map k (color, mr, normal) as an RGB uint8 array."""
    img = np.zeros((ATLAS_ROWS * SIZE, ATLAS_COLS * SIZE, 3), np.uint8)
    for i, sname in enumerate(ATLAS_SETS):
        r, c = divmod(i, ATLAS_COLS)
        img[r * SIZE:(r + 1) * SIZE, c * SIZE:(c + 1) * SIZE] = _tile(sname, k)
    return img


_bytes = {}


def image_bytes(name):
    """The encoded bytes of a shared texture file (an atlas PNG or a set's JPEG)."""
    if name not in _bytes:
        k = next((k for k, f in ATLAS_FILES.items() if f == name), None)
        if k is not None:
            buf = io.BytesIO()
            Image.fromarray(atlas_image(k)).save(buf, "PNG", optimize=False, compress_level=6)
            _bytes[name] = buf.getvalue()
        else:
            with open(os.path.join(TEX_DIR, name), "rb") as f:
                _bytes[name] = f.read()
    return _bytes[name]


def write_shared(out_dir):
    """Writes `<out_dir>/_tex/` (the atlas images and the sails' set) with Godot import settings, only where
    changed. Returns the folder."""
    d = os.path.join(out_dir, "_tex")
    os.makedirs(d, exist_ok=True)
    for name in list(ATLAS_FILES.values()) + list(OWN_FILES):
        path = os.path.join(d, name)
        data = image_bytes(name)
        if not os.path.exists(path) or open(path, "rb").read() != data:
            with open(path, "wb") as f:
                f.write(data)
        imp = path + ".import"
        want = IMPORT.format(hq="true" if "color" in name else "false", normal=1 if "normal" in name else 2)
        if not os.path.exists(imp) or "compress/mode=2" not in open(imp).read():
            with open(imp, "w") as f:
                f.write(want)
    return d


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


def diamond(period_px=32, seed=7):
    """Moulded non-slip, made here (no source asset): a grid of raised, flat-topped pyramids turned 45 degrees,
    repeating every `period_px` along each image axis (16 across the tile, about 6 mm at the 0.1 m tile), with a
    little moulding noise. The grooves are darker (dirt, occlusion) and rougher than the worn tops. Seamless."""
    rng = np.random.default_rng(seed)
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    a, b = (u + v) / period_px, (u - v) / period_px
    # distance to the nearest groove line in each direction, 0 at a groove, 0.5 at a pyramid centre
    da, db = np.abs(a - np.round(a)), np.abs(b - np.round(b))
    h = np.clip(np.minimum(da, db) / 0.32, 0, 1)            # pyramid flanks, flat top above 0.32
    # periodic low-frequency noise: a few waves with whole numbers of cycles across the tile
    noise = np.zeros_like(h)
    for _ in range(12):
        fu, fv = rng.integers(1, 9, 2)
        noise += np.cos(2 * np.pi * (fu * u + fv * v) / SIZE + rng.uniform(0, 2 * np.pi))
    noise /= 12 ** 0.5 * 2
    h = h + 0.06 * noise
    # normal from the height gradient (wrapping, so the tile repeats), OpenGL convention
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    k = 2.2
    n = np.stack([-k * gx, k * gy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    col = _detail(0.75 + 0.25 * h, DETAIL_MEAN, 1.0)
    rough = _detail(1.15 - 0.3 * h, ROUGH_MEAN, 1.0)
    return col, rough, n


def process_procedural(set_name):
    col, rough, n = {"diamond": diamond}[set_name]()
    p = paths(set_name)
    grey = _lin_to_srgb(col)
    mr = np.stack([np.ones_like(rough), rough, np.ones_like(rough)], -1)
    Image.fromarray((np.repeat(grey[..., None], 3, -1) * 255 + 0.5).astype(np.uint8)).save(p["color"], quality=92)
    Image.fromarray((mr * 255 + 0.5).astype(np.uint8)).save(p["mr"], quality=92)
    Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(p["normal"], quality=95)


def fetch(set_names=None, cache=None):
    for s in set_names or SETS:
        asset = SETS[s][0]
        if asset is None:
            process_procedural(s)
            print(f"{s}: procedural -> {', '.join(os.path.basename(v) for v in paths(s).values())}")
            continue
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
    fetch([s for s in SETS if SETS[s][0] is None] if "--procedural" in args else None, cache=cache)
