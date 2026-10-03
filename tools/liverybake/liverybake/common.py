"""Shared helpers: repository paths, colour conversion, deterministic noise, image output, the ownership rule.

Everything works on float32 NumPy arrays in linear light; images are written as 8-bit PNG (sRGB for colour maps,
linear for normal and ORM maps).
"""
import hashlib
import os
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parents[1]          # tools/liverybake
REPO = HERE.parents[1]
DATA = REPO / "data" / "liveries"
CLASSES = REPO / "data" / "classes"
GAME = REPO / "game"
STAGE = GAME / "generated" / "liveries"
FONT = GAME / "fonts" / "barlow" / "BarlowSemiCondensed-Bold.ttf"
BOATGEN = REPO / "tools" / "boatgen"

# data_format.md §3.7 and §8: no albedo above 0.8 linear (sRGB 231)
ALBEDO_MAX = 0.8

F32 = np.float32


# ----------------------------------------------------------------------------------------------------------------
# colour

def srgb_to_lin(c):
    c = np.asarray(c, dtype=F32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(F32)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=F32), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055).astype(F32)


def hex_lin(s):
    """'#rrggbb' (sRGB) -> linear RGB (3,)."""
    s = s.lstrip("#")
    return srgb_to_lin(np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=F32))


def luminance(c):
    return float(np.dot(np.asarray(c, dtype=F32), [0.2126, 0.7152, 0.0722]))


def mix(a, b, t):
    """Per-pixel blend of colour images or colours; t broadcasts over the last axis."""
    t = np.asarray(t, dtype=F32)
    if t.ndim and np.ndim(a) == t.ndim + 1 or (t.ndim and np.ndim(b) == t.ndim + 1):
        t = t[..., None]
    return (np.asarray(a, dtype=F32) * (1 - t) + np.asarray(b, dtype=F32) * t).astype(F32)


# ----------------------------------------------------------------------------------------------------------------
# anti-aliased coverage over a pixel footprint px (the same box filter as the game's shaders)

def inside(d, px):
    """Share of a pixel inside d < 0."""
    return np.clip(0.5 - d / np.maximum(px, 1e-6), 0.0, 1.0).astype(F32)


def band(d, hw, px):
    """Share of a pixel inside |d| < hw (box filtered, exact for thin bands)."""
    lo = np.maximum(d - 0.5 * px, -hw)
    hi = np.minimum(d + 0.5 * px, hw)
    return np.clip((hi - lo) / np.maximum(px, 1e-6), 0.0, 1.0).astype(F32)


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=F32) - e0) / (e1 - e0), 0.0, 1.0)
    return (t * t * (3 - 2 * t)).astype(F32)


# ----------------------------------------------------------------------------------------------------------------
# deterministic noise (seeded; the same seed always gives the same texture)

def seed_of(*parts):
    """A 31-bit seed from text parts (class, livery, layer)."""
    h = hashlib.sha256(":".join(str(p) for p in parts).encode()).digest()
    return int.from_bytes(h[:4], "little") & 0x7FFFFFFF


def _hash(ix, iy, seed):
    h = (ix * np.int64(374761393) + iy * np.int64(668265263) + np.int64(seed) * np.int64(974634521)) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * np.int64(1274126177)) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


def perlin(x, y, seed=0):
    """2D gradient noise in about [-1, 1] at the float arrays x, y (unit = one lattice cell)."""
    x = np.asarray(x, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx = (x - x0).astype(F32)
    fy = (y - y0).astype(F32)
    ix = x0.astype(np.int64)
    iy = y0.astype(np.int64)

    def grad(i, j, dx, dy):
        a = _hash(i, j, seed).astype(F32) * F32(2 * np.pi / 4294967296.0)
        return np.cos(a) * dx + np.sin(a) * dy

    n00 = grad(ix, iy, fx, fy)
    n10 = grad(ix + 1, iy, fx - 1, fy)
    n01 = grad(ix, iy + 1, fx, fy - 1)
    n11 = grad(ix + 1, iy + 1, fx - 1, fy - 1)
    u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    a = n00 + (n10 - n00) * u
    b = n01 + (n11 - n01) * u
    return ((a + (b - a) * v) * F32(1.41)).astype(F32)


def fbm(x, y, seed=0, octaves=4, gain=0.5, lac=2.03):
    """Fractal sum of `octaves` gradient noises, normalised to about [-1, 1]."""
    s = np.zeros(np.shape(x), dtype=F32)
    a = 1.0
    tot = 0.0
    f = 1.0
    for o in range(octaves):
        s += F32(a) * perlin(np.asarray(x) * f + 17.3 * o, np.asarray(y) * f - 9.1 * o, seed + 101 * o)
        tot += a
        a *= gain
        f *= lac
    return (s / F32(tot)).astype(F32)


def hash01(*keys):
    """A float in [0, 1) from integer keys (per panel, per mark)."""
    h = np.int64(2166136261)
    for k in keys:
        h = _hash(np.int64(int(k) & 0x7FFFFFFF), h, 7)
    return float(h) / 4294967296.0


class Rng:
    """numpy Generator with a text seed."""

    def __init__(self, *parts):
        self.g = np.random.default_rng(seed_of(*parts))

    def __getattr__(self, k):
        return getattr(self.g, k)


# ----------------------------------------------------------------------------------------------------------------
# image helpers

def blur(a, r):
    """Separable box blur (three passes, about Gaussian) of radius r pixels along both image axes."""
    if r <= 0:
        return a
    out = np.asarray(a, dtype=F32)
    k = int(max(1, round(r)))
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.pad(out, [(k + 1, k) if i == ax else (0, 0) for i in range(out.ndim)], mode="edge"),
                          axis=ax, dtype=np.float64)
            n = out.shape[ax]
            hi = np.take(c, np.arange(2 * k + 1, 2 * k + 1 + n), axis=ax)
            lo = np.take(c, np.arange(0, n), axis=ax)
            out = ((hi - lo) / (2 * k + 1)).astype(F32)
    return out


def push_pull(img, valid):
    """Fills the texels outside `valid` (H, W bool) with the nearest valid texel (smoothed a little), so mipmaps
    and filtering never bleed the background into the surface and a painter sees the surface run on past its
    edge."""
    from scipy import ndimage
    img = np.asarray(img, dtype=F32)
    if valid.all():
        return img
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    fill = img[idx[0], idx[1]]
    fill = blur(fill, 2)
    v = valid[..., None] if img.ndim == 3 else valid
    return np.where(v, img, fill).astype(F32)


def normal_from_height(h, px_x, px_y, strength=1.0):
    """Tangent-space normal map (OpenGL convention: +x to the image right, +y to the image top) of the height
    field h (metres, rows top to bottom) with texels px_x by px_y metres. Returns (H, W, 3) unit vectors."""
    hx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * px_x)
    hy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2 * px_y)       # down the image
    hx[:, 0] = hx[:, -1] = 0
    hy[0, :] = hy[-1, :] = 0
    n = np.stack([-hx * strength, hy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n.astype(F32)


def save_png(path, rgb01, srgb):
    """Writes an (H, W, 3) image in [0, 1] as an 8-bit RGB PNG; `srgb`: rgb01 is linear and is encoded to sRGB."""
    a = lin_to_srgb(rgb01) if srgb else np.clip(rgb01, 0, 1)
    img = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True, compress_level=9)


def save_normal(path, n):
    save_png(path, n * 0.5 + 0.5, srgb=False)


def save_orm(path, occ, rough, third):
    save_png(path, np.stack([occ, rough, third], -1), srgb=False)


def sample_bilinear(img, x, y):
    """Samples a 2D array at fractional pixel coordinates (x right, y down; pixel centres at .5), clamped."""
    h, w = img.shape[:2]
    xf = np.clip(np.asarray(x, dtype=np.float64) - 0.5, 0, w - 1)
    yf = np.clip(np.asarray(y, dtype=np.float64) - 0.5, 0, h - 1)
    x0 = np.floor(xf).astype(np.int64)
    y0 = np.floor(yf).astype(np.int64)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    tx = (xf - x0).astype(F32)
    ty = (yf - y0).astype(F32)
    a = img[y0, x0] * (1 - tx) + img[y0, x1] * tx
    b = img[y1, x0] * (1 - tx) + img[y1, x1] * tx
    return (a * (1 - ty) + b * ty).astype(F32)


# ----------------------------------------------------------------------------------------------------------------
# the ownership rule (data_format.md §8.6): hand-owned files are written only when their folder is new, or with
# --force (everything selected) or --only (the named parts)

class Writer:
    def __init__(self, force=False, only=()):
        self.force = force
        self.only = set(only)
        self.written = []
        self.kept = []

    def may_write(self, folder, part):
        """Whether the part's files in `folder` may be (re)written."""
        if self.force or part in self.only:
            return True
        if self.only:
            return False
        return not Path(folder).exists() or not any(Path(folder).iterdir())

    def note(self, paths, wrote):
        (self.written if wrote else self.kept).extend(str(p) for p in paths)
