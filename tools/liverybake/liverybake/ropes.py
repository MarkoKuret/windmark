"""The class rope set (data_format.md §8.7): one seamless tile of a 16-carrier braid per rope function, 0.05 m
along the rope (one lay length) by one turn round it, in the function's colours, plus the braid's shared relief
and ORM maps. Image x runs along the rope, image y round it.

The braid: 8 carriers each way (S: t - s constant, Z: t + s constant, s along and t round in tile units), each a
flat ribbon of three yarns, interlaced 2 over 2 under, so the carriers cross in a diamond pattern and dip where
they pass under. `fleck` colours one carrier of each direction in the fleck colour, `tracer` one S carrier, `twill`
alternate pairs both ways, `solid` none.
"""
import numpy as np

from .common import ALBEDO_MAX, F32, Rng, hex_lin, normal_from_height

SIZE = 512
TILE_M = 0.05
CARRIERS = 8          # per direction
SS = 2                # supersampling
FUNCTIONS = ("mainsheet", "sheet", "kite_sheet", "halyard_main", "halyard_jib", "halyard_kite", "halyard_code", "control")
DEFAULTS = {
    "mainsheet": ("#b5652f", "#2a3348"),
    "sheet": ("#2f7d80", "#d6d6ce"),
    "kite_sheet": ("#97406a", "#d6d6ce"),
    "halyard_main": ("#a2383a", "#d6d6ce"),
    "halyard_jib": ("#355f98", "#d6d6ce"),
    "halyard_kite": ("#3f7a4a", "#d6d6ce"),
    "halyard_code": ("#bf9a42", "#2a2b2e"),
    "control": ("#674f8c", "#d6d6ce"),
}
PATTERNS = ("fleck", "tracer", "twill", "solid")
# relief: carrier crown height (m) and the typical rope circumference the tile wraps (for the normal map's scale)
CROWN_M = 0.0006
CIRC_M = 0.03


def rope_set(liv):
    """The livery file's `ropes` with every function's defaults filled in: {function: (color, fleck, pattern)}."""
    rs = liv.get("ropes", {}) or {}
    out = {}
    for fn in FUNCTIONS:
        e = rs.get(fn, {}) or {}
        c, f = DEFAULTS[fn]
        pat = e.get("pattern", "fleck")
        if pat not in PATTERNS:
            raise ValueError(f"ropes.{fn}.pattern: one of {', '.join(PATTERNS)}")
        out[fn] = (e.get("color", c), e.get("fleck", f), pat)
    for k in rs:
        if k not in FUNCTIONS:
            raise ValueError(f"ropes.{k}: one of {', '.join(FUNCTIONS)}")
    return out


def _structure(n):
    """The braid at n x n: per pixel the visible carrier (direction 0 = S, 1 = Z), its index, its height (0..1)
    and the yarn index across it."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    s = (x + 0.5) / n
    t = (y + 0.5) / n
    a = CARRIERS * np.mod(t - s, 1.0)
    b = CARRIERS * np.mod(t + s, 1.0)
    i_s = np.floor(a).astype(np.int64)
    i_z = np.floor(b).astype(np.int64)
    fa = a - i_s
    fb = b - i_z
    m = np.mod(i_z - i_s, 4)
    s_top = m < 2

    def over_s(iz, is_):
        return np.mod(iz - is_, 4) < 2

    def smooth(e0, e1, v):
        k = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
        return k * k * (3 - 2 * k)

    # elevation along the carrier on top: it dips toward a cell edge where it passes under next
    e_s = (1.0 - 0.55 * np.where(~over_s(i_z + 1, i_s), smooth(0.45, 1.0, fb), 0.0)
           - 0.55 * np.where(~over_s(i_z - 1, i_s), smooth(0.45, 1.0, 1.0 - fb), 0.0))
    e_z = (1.0 - 0.55 * np.where(over_s(i_z, i_s + 1), smooth(0.45, 1.0, fa), 0.0)
           - 0.55 * np.where(over_s(i_z, i_s - 1), smooth(0.45, 1.0, 1.0 - fa), 0.0))
    across = np.where(s_top, fa, fb)
    elev = np.where(s_top, e_s, e_z)
    yarn = np.minimum(np.floor(across * 3).astype(np.int64), 2)
    fy = across * 3 - yarn
    # a flat ribbon: rounded at its edges, three yarns with shallow grooves between them
    prof = np.sin(np.pi * np.clip(across, 0, 1)) ** 0.5 * (0.78 + 0.22 * np.sin(np.pi * fy) ** 0.6)
    h = elev * prof
    return {"dir": np.where(s_top, 0, 1), "idx": np.where(s_top, i_s, i_z), "h": h, "yarn": yarn,
            "along": np.where(s_top, fb, fa), "across": across}


def _down(img):
    n = img.shape[0] // SS
    return img.reshape(n, SS, n, SS, *img.shape[2:]).mean(axis=(1, 3)).astype(F32)


def _fleck_mask(st, pattern):
    d, i = st["dir"], st["idx"]
    if pattern == "fleck":
        return ((d == 0) & (i == 0)) | ((d == 1) & (i == CARRIERS // 2))
    if pattern == "tracer":
        return (d == 0) & (i == 0)
    if pattern == "twill":
        return (i // 2) % 2 == 1
    return np.zeros_like(d, dtype=bool)


def bake_ropes(liv, size=SIZE, key=""):
    """{"albedo": {function: (H, W, 3) linear}, "normal": (H, W, 3) unit, "orm": (H, W, 3)} of a livery file."""
    n = size * SS
    st = _structure(n)
    rng = Rng("ropes", key)
    # fibre streaks along each carrier and a per-yarn and per-carrier tone, the same for every function
    phase = rng.uniform(0, 2 * np.pi, (2, CARRIERS, 3))
    tone = 1.0 + 0.035 * np.sin(2 * np.pi * 9 * st["across"] + phase[st["dir"], st["idx"], st["yarn"]]) \
        + 0.03 * (rng.uniform(-1, 1, (2, CARRIERS, 3))[st["dir"], st["idx"], st["yarn"]])
    shade = 0.62 + 0.38 * np.clip(st["h"], 0, 1)
    out = {"albedo": {}}
    for fn, (c, f, pat) in rope_set(liv).items():
        main = hex_lin(c)
        fleck = hex_lin(f)
        mask = _fleck_mask(st, pat)
        col = np.where(mask[..., None], fleck[None, None, :], main[None, None, :])
        alb = col * (tone * shade)[..., None]
        out["albedo"][fn] = np.clip(_down(alb), 0.0, ALBEDO_MAX)
    h = _down(st["h"] * CROWN_M)
    out["normal"] = normal_from_height(np.pad(h, 1, mode="wrap"), TILE_M / size, CIRC_M / size)[1:-1, 1:-1]
    hn = _down(np.clip(st["h"], 0, 1))
    occ = 0.45 + 0.55 * hn ** 0.7
    rough = 0.86 - 0.12 * hn
    out["orm"] = np.stack([occ, rough, np.zeros_like(hn)], -1).astype(F32)
    return out

# every file of the class rope set (data_format.md 8.7), for the ownership rule
FILES = tuple(f"rope_{fn}_albedo.png" for fn in FUNCTIONS) + ("rope_normal.png", "rope_orm.png")
