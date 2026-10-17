"""Hull, transom and keel textures of a livery (data_format.md §8.5); the deck is in deck.py.

Hull: one atlas on the generator's uv1 (starboard band on top, port band below, sheer at the top of each band, bow
to the right on starboard and to the left on port: each band as seen from its own side). Per texel the bake knows
the point of the hull it covers (station interpolation of the generator's skin grid), so every feature is laid out
in metres on the real hull: the boot stripe and the waterline at their heights above the DWL, graphics in the
topsides coordinates of data_format.md §8.2, wear where boats wear.

Every random choice is seeded from the class and livery ids, so a bake is repeatable.
"""
import numpy as np
from PIL import Image, ImageDraw

from .common import (ALBEDO_MAX, F32, Rng, band, blur, fbm, hex_lin, inside, luminance, mix, normal_from_height,
                     perlin, push_pull, seed_of, smoothstep)


# ----------------------------------------------------------------------------------------------------------------
# the atlas: hull point of every texel

def atlas(geo, W, H):
    """Per texel of the W x H hull atlas: x (m from the transom), girth g (m from the keel line), z (m above the
    DWL), the girths at the sheer, the antifouling top, the boot stripe top and the DWL at that x, the side (0
    starboard, 1 port) and whether the texel is on the hull."""
    L, G = geo["L"], geo["girth_max"]
    xs, skin, girth = geo["skin_xs"], geo["skin"], geo["girth"]
    z_af, z_bt = geo["boot_top"]
    n_st = len(xs)
    hb = H // 2
    u = (np.arange(W) + 0.5) / W
    v = (np.arange(hb) + 0.5) / H              # 0..0.5 within a band
    g_row = (1.0 - 2.0 * v) * G                # girth from the keel at each band row
    out = {k: np.zeros((H, W), F32) for k in ("x", "g", "z", "y", "gs", "gaf", "gbt", "gwl", "side")}
    # per station: girth at the sheer, and at z = z_af, z_bt, 0 (the station's z rises along its girth)
    def g_at(i, zz):
        z = skin[i, :, 2]
        zm = np.maximum.accumulate(z)
        return float(np.interp(zz, zm, girth[i]))
    st_gs = girth[:, -1]
    st_af = np.array([g_at(i, z_af) for i in range(n_st)])
    st_bt = np.array([g_at(i, z_bt) for i in range(n_st)])
    st_wl = np.array([g_at(i, 0.0) for i in range(n_st)])
    for side in (0, 1):
        x_col = u * L if side == 0 else (1.0 - u) * L
        i0 = np.clip(np.searchsorted(xs, x_col) - 1, 0, n_st - 2)
        w = np.clip((x_col - xs[i0]) / np.maximum(xs[i0 + 1] - xs[i0], 1e-9), 0, 1)
        rs = slice(side * hb, side * hb + hb)
        for c in range(W):
            i, ww = i0[c], w[c]
            za = np.interp(g_row, girth[i], skin[i, :, 2])
            zb = np.interp(g_row, girth[i + 1], skin[i + 1, :, 2])
            ya = np.interp(g_row, girth[i], skin[i, :, 1])
            yb = np.interp(g_row, girth[i + 1], skin[i + 1, :, 1])
            out["z"][rs, c] = za * (1 - ww) + zb * ww
            out["y"][rs, c] = ya * (1 - ww) + yb * ww
            for k, arr in (("gs", st_gs), ("gaf", st_af), ("gbt", st_bt), ("gwl", st_wl)):
                out[k][rs, c] = arr[i] * (1 - ww) + arr[i + 1] * ww
        out["x"][rs] = x_col[None, :]
        out["g"][rs] = g_row[:, None]
        out["side"][rs] = side
    out["valid"] = (out["g"] <= out["gs"] + 1e-6) & (out["x"] >= 0) & (out["x"] <= L)
    out["px_x"] = L / W
    out["px_g"] = 2.0 * G / H
    return out


# ----------------------------------------------------------------------------------------------------------------
# hull graphic (data_format.md §8.2) as vinyl layers: [(coverage, colour, index of the colour in `colors`)]

def graphic_layers(gr, xf, d, th, px_g, px_x, L):
    t = d / th
    pxx = px_x / L                   # the texel along the hull as a fraction of L
    typ = gr.get("type", "none")
    cols = [hex_lin(c) for c in gr.get("colors", [])]
    out = []
    if typ == "stripes":
        dep = gr.get("depth", [0.08, 0.17])
        wid = gr.get("width", [0.05, 0.02])
        f0, f1 = gr.get("from", 0.04), gr.get("to", 0.96)
        lean = d / L                 # the ends' cut leans aft toward the boot stripe
        span = inside(f0 - lean - xf, pxx) * inside(xf - (f1 - lean), pxx)
        for k in range(min(len(cols), len(dep), len(wid))):
            out.append((band(d - dep[k], 0.5 * wid[k], px_g) * span, cols[k], k))
    elif typ == "two_tone":
        split, rise, pin = gr.get("split", 0.45), gr.get("rise", -0.15), gr.get("pinstripe", 0.025)
        ds = (split + rise * (xf - 0.5)) * th
        if cols:
            out.append((inside(ds - d, px_g), cols[0], 0))
        if len(cols) > 1 and pin > 0:
            out.append((band(d - ds, 0.5 * pin, px_g), cols[1], 1))
    elif typ == "swoosh":
        a, f = gr.get("aft", [0.04, 0.8]), gr.get("fwd", [0.96, 0.1])
        wd = gr.get("width", [0.24, 0.03])
        s = (xf - a[0]) / max(f[0] - a[0], 1e-3)
        sc = np.clip(s, 0, 1)
        dc = (a[1] + (f[1] - a[1]) * sc ** 2.2) * th
        w = (wd[0] + (wd[1] - wd[0]) * sc) * smoothstep(0.0, 0.08, s) * (1 - smoothstep(0.97, 1.0, s))
        inx = ((s >= 0) & (s <= 1)).astype(F32)
        if cols:
            out.append((band(d - dc, 0.5 * w, px_g) * inx, cols[0], 0))
        if len(cols) > 1:
            out.append((band(d - (dc - 0.5 * w - 0.03), 0.012 * np.minimum(1.0, w / 0.04), px_g) * inx
                        * (w > 0.004), cols[1], 1))
    elif typ == "gradient":
        f0, f1, sl = gr.get("from", 0.25), gr.get("to", 0.85), gr.get("slant", 0.12)
        xs_ = xf + sl * (1 - np.clip(t, 0, 1))
        if cols:
            out.append((smoothstep(f0, f1, xs_), cols[0], 0))
    elif typ == "bow":
        at, sl, ln = gr.get("at", 0.78), gr.get("slant", 0.10), gr.get("line", 0.03)
        xe = at - sl * np.clip(t, 0, 1)
        if cols:
            out.append((inside(xe - xf, pxx), cols[0], 0))
        if len(cols) > 1 and ln > 0:
            out.append((band((xf - xe) * L + 0.5 * ln + 0.02, 0.5 * ln, px_x), cols[1], 1))
    return out


# ----------------------------------------------------------------------------------------------------------------
# colour masks of the staged atlas (data_format.md §8.5 "Staged boat atlas"), for the tinted liveries

ZONE_ANTIFOULING, ZONE_BOOT, ZONE_GRAPHIC0, ZONE_GRAPHIC1 = 0, 1, 2, 3


def _spread_zones(zone, paint):
    """Each zone spread across the paint to the nearest zone texel (so a compressed block never mixes far-apart
    zone values where the paint coverage is partial)."""
    from scipy import ndimage
    other = paint < 0.5
    if not other.any():
        return zone
    idx = ndimage.distance_transform_edt(~other, return_distances=False, return_indices=True)
    return zone[idx[0], idx[1]]


def hull_masks(geo, lv, W, H):
    """The colour masks of a livery's hull image at W x H: `paint`, the topsides paint coverage (1 on the paint,
    name and number panels included, 0 on the graphic's vinyl, the boot stripe and the antifouling, fractional on
    their edges), and `zone`, the colour zone of what is not paint (ZONE_ANTIFOULING, ZONE_BOOT, ZONE_GRAPHIC0,
    ZONE_GRAPHIC1), spread across the paint. The same zones as bake_hull lays its colours."""
    A = atlas(geo, W, H)
    L = geo["L"]
    x, g, px_x, px_g = A["x"], A["g"], A["px_x"], A["px_g"]
    xf = x / L
    d = A["gs"] - g
    th = np.maximum(A["gs"] - A["gbt"], 0.05)
    m_af = inside(g - A["gaf"], px_g)
    m_below_bt = inside(g - A["gbt"], px_g)
    m_bt = np.clip(m_below_bt - m_af, 0, 1)
    m_top = 1.0 - m_below_bt
    zone = np.where(m_af > 0.5, ZONE_ANTIFOULING, ZONE_BOOT).astype(np.uint8)
    vinyl = np.zeros((H, W), F32)
    for cov, _col, k in graphic_layers(lv["hull"].get("graphic") or {"type": "none"}, xf, d, th, px_g, px_x, L):
        cov = cov * m_top
        zone = np.where(cov > 0.5, ZONE_GRAPHIC0 + k, zone)
        vinyl = np.maximum(vinyl, cov)
    paint = np.clip(m_top * (1.0 - vinyl), 0, 1).astype(F32)
    return {"paint": paint, "zone": _spread_zones(zone, paint)}


def transom_masks(geo, lv, W, H):
    """The colour masks of a livery's transom image at W x H (as hull_masks): the paint coverage and the zone of
    the stripes' return, the boot stripe and the antifouling, as bake_transom lays them."""
    T = geo["transom"]
    h, top, bot = T["rect"]
    px_y, px_z = 2 * h / W, (top - bot) / H
    px = 0.5 * (px_y + px_z)
    y1 = h - (np.arange(W) + 0.5) * px_y
    z1 = top - (np.arange(H) + 0.5) * px_z
    Yv = np.broadcast_to(y1[None, :], (H, W)).astype(F32)
    Z = np.broadcast_to(z1[:, None], (H, W)).astype(F32)
    ay = np.abs(Yv)
    z_af, z_bt = geo["boot_top"]
    yc, bs, zf = T["yc"], T["bs"], T["floor_z"]
    is_open = T["open"]
    quarter = (ay >= yc) if is_open else np.ones_like(ay, bool)
    top_e = np.where(quarter, np.interp(ay, T["top_y"], T["top_z"]), zf).astype(F32)
    d = top_e - Z
    gr = lv["hull"].get("graphic") or {"type": "none"}
    ncol = len(gr.get("colors", []))
    vinyl = np.zeros((H, W), F32)
    zone = np.full((H, W), ZONE_BOOT, np.uint8)
    if gr.get("type") == "stripes" and gr.get("from", 0.04) <= 1e-3:
        dep, wid = gr.get("depth", [0.08, 0.17]), gr.get("width", [0.05, 0.02])
        y_end = (yc + 0.5 * (bs - yc)) if is_open else (2.0 / 3.0) * bs
        for k in range(min(ncol, len(dep), len(wid))):
            span = inside(y_end + 0.6 * (d - dep[k]) - ay, px)
            c = band(d - dep[k], 0.5 * wid[k], px) * span * quarter
            zone = np.where(c > 0.5, ZONE_GRAPHIC0 + k, zone)
            vinyl = np.maximum(vinyl, c)
    elif gr.get("type") == "two_tone" and ncol:
        split, rise, pin = gr.get("split", 0.45), gr.get("rise", -0.15), gr.get("pinstripe", 0.025)
        zs0 = float(np.interp(bs, T["top_y"], T["top_z"]))
        ds = (split - 0.5 * rise) * max(zs0 - z_bt, 0.05)
        dd = zs0 - Z
        c = inside(ds - dd, px)
        zone = np.where(c > 0.5, ZONE_GRAPHIC0, zone)
        vinyl = np.maximum(vinyl, c)
        if ncol > 1 and pin > 0:
            c = band(dd - ds, 0.5 * pin, px)
            zone = np.where(c > 0.5, ZONE_GRAPHIC1, zone)
            vinyl = np.maximum(vinyl, c)
    m_af = inside(Z - z_af, px)
    m_bt = np.clip(inside(Z - z_bt, px) - m_af, 0, 1)
    zone = np.where(m_bt > 0.5, ZONE_BOOT, zone)
    zone = np.where(m_af > 0.5, ZONE_ANTIFOULING, zone)
    paint = np.clip((1.0 - vinyl) * (1.0 - m_bt) * (1.0 - m_af), 0, 1).astype(F32)
    return {"paint": paint, "zone": _spread_zones(zone, paint)}


def _segments(H, W, px_x, px_g, segs, rng=None):
    """Coverage and a 0..1 strength map of thin line segments [(x0, g0, x1, g1, width_m, strength)] in atlas
    pixel space, stamped into local windows."""
    cov = np.zeros((H, W), F32)
    for (c0, r0, c1, r1, wpx, s) in segs:
        lo_c = int(max(min(c0, c1) - 3 - wpx, 0))
        hi_c = int(min(max(c0, c1) + 4 + wpx, W))
        lo_r = int(max(min(r0, r1) - 3 - wpx, 0))
        hi_r = int(min(max(r0, r1) + 4 + wpx, H))
        if hi_c <= lo_c or hi_r <= lo_r:
            continue
        rr, cc = np.mgrid[lo_r:hi_r, lo_c:hi_c].astype(F32) + 0.5
        dx, dy = c1 - c0, r1 - r0
        ln2 = max(dx * dx + dy * dy, 1e-6)
        t = np.clip(((cc - c0) * dx + (rr - r0) * dy) / ln2, 0, 1)
        dist = np.hypot(cc - (c0 + t * dx), rr - (r0 + t * dy))
        taper = np.sin(np.pi * np.clip(t, 0, 1)) ** 0.5
        c = band(dist, 0.5 * wpx * taper + 1e-3, 1.0) * s
        cov[lo_r:hi_r, lo_c:hi_c] = np.maximum(cov[lo_r:hi_r, lo_c:hi_c], c)
    return cov


def bake_hull(geo, lv, W=4096, H=2048, key=""):
    """The hull albedo (linear RGB), normal (unit vectors) and ORM (occlusion, roughness, metallic) of a livery."""
    A = atlas(geo, W, H)
    L = geo["L"]
    x, g, z, valid, side = A["x"], A["g"], A["z"], A["valid"], A["side"]
    px_x, px_g = A["px_x"], A["px_g"]
    z_af, z_bt = geo["boot_top"]
    hull = lv["hull"]
    top = hex_lin(hull["topsides"])
    boot = hex_lin(hull.get("boot_stripe", "#e0e0dc"))
    afc = hex_lin(hull.get("antifouling", "#1a1d24"))
    dark = float(np.clip(1.0 - luminance(top) / 0.45, 0.0, 1.0))      # 1 on a dark hull, 0 on a white one
    rng = Rng(key, "hull")
    S = seed_of(key, "hull")
    xf = x / L
    d = A["gs"] - g                         # metres below the sheer, along the surface
    th = np.maximum(A["gs"] - A["gbt"], 0.05)
    # a second coordinate that continues across both bands without a seam at the keel (noise lookups)
    gx = np.where(side > 0, g + 7.31, g)
    xn = x + side * 13.7

    m_af = inside(g - A["gaf"], px_g)                       # below the antifouling's top edge
    m_below_bt = inside(g - A["gbt"], px_g)
    m_bt = np.clip(m_below_bt - m_af, 0, 1)                 # the boot stripe
    m_top = 1.0 - m_below_bt                                # topsides

    alb = np.zeros((H, W, 3), F32)
    rough = np.zeros((H, W), F32)
    hgt = np.zeros((H, W), F32)

    # ---- topsides: painted or gelcoat, polished; a little batch and fade variation, sun-faded toward the sheer
    var = fbm(xn / 2.2, gx / 2.2, S + 1, 3)
    tops = top[None, None, :] * (1.0 + 0.018 * var)[..., None]
    grey = luminance(top)
    fade = (0.05 * dark) * smoothstep(0.45, 0.0, d) * (0.6 + 0.4 * fbm(xn / 1.5, gx / 0.4, S + 2, 2))
    tops = mix(tops, np.full(3, grey * 1.35 + 0.004, F32), fade)
    r_top = 0.14 + 0.035 * fbm(xn / 0.9, gx / 0.9, S + 3, 3) + 0.02 * fbm(xn / 0.15, gx / 0.15, S + 4, 2)
    # fairing waviness: long, low waves, visible only in reflections
    h_top = 0.0007 * fbm(xn / 0.6, gx / 0.9, S + 5, 3) + 0.00012 * fbm(xn / 0.12, gx / 0.12, S + 6, 2)

    # ---- graphics: cut vinyl with crisp edges, a hairline of dirt along them and a 0.1 mm step
    vinyl = np.zeros((H, W), F32)
    for cov, col, _k in graphic_layers(hull.get("graphic") or {"type": "none"}, xf, d, th, px_g, px_x, L):
        cov = cov * m_top
        tops = mix(tops, col[None, None, :] * (1.0 + 0.01 * var)[..., None], cov)
        vinyl = np.maximum(vinyl, cov)
    vb = blur(vinyl, 0.8)
    v_edge = np.clip(4.0 * vb * (1.0 - vb), 0, 1)
    tops *= (1.0 - 0.10 * v_edge)[..., None]
    r_top = r_top * (1 - vinyl) + (0.24 + 0.03 * var) * vinyl
    h_top = h_top + 0.00012 * vb

    # ---- boot stripe: vinyl tape at constant height above the DWL
    bt_col = boot[None, None, :] * (1.0 + 0.012 * var)[..., None]
    bb = blur(m_bt, 0.8)
    bt_edge = np.clip(4.0 * bb * (1.0 - bb), 0, 1)
    r_bt = 0.22 + 0.03 * var

    # ---- antifouling: rolled, roller laps across the bottom, brushed cut-in under the tape, faded and chalky
    # near the waterline where it dries and gets scrubbed
    lap_w = 0.17
    xj = x + 0.035 * fbm(xn / 0.7, gx / 0.7, S + 7, 2) + side * 0.071
    lap_id = np.floor(xj / lap_w)
    lap_f = xj / lap_w - lap_id
    h1 = np.sin(lap_id * 12.9898 + 78.233) * 43758.5453
    lap_tone = (h1 - np.floor(h1) - 0.5).astype(F32)
    lap_edge = band(np.minimum(lap_f, 1 - lap_f) * lap_w, 0.004, px_x)
    stip = fbm(xn / 0.012, gx / 0.012, S + 8, 2)
    brush = fbm(xn / 0.35, gx / 0.0035, S + 9, 2) * smoothstep(0.07, 0.0, A["gaf"] - g)
    fade_af = smoothstep(z_af - 0.30, z_af, z) * (0.7 + 0.3 * fbm(xn / 0.8, gx / 0.3, S + 10, 2))
    afv = afc[None, None, :] * (1.0 + 0.05 * lap_tone + 0.035 * stip - 0.06 * lap_edge + 0.04 * brush)[..., None]
    chalk = np.full(3, luminance(afc) * 1.6 + 0.012, F32)
    afv = mix(afv, chalk, 0.32 * fade_af)
    r_af = 0.80 + 0.05 * lap_tone + 0.05 * stip - 0.06 * fade_af
    h_af = 0.00008 * lap_edge + 0.00018 * fbm(xn / 0.02, gx / 0.02, S + 11, 2)

    # ---- waterline: a scum line of olive-brown film just at the DWL, heavier at the bow and the quarters, and a
    # yellow-brown stain on the boot stripe at the bow from the bow wave
    wl_top = 0.022 + 0.008 * fbm(xn / 0.5, gx * 0.0 + side, S + 12, 3)
    zz = z
    scum = smoothstep(wl_top + 0.003, wl_top - 0.003, zz) * smoothstep(-0.004, 0.006, zz)
    where = 0.45 + 0.55 * np.maximum(smoothstep(0.62, 0.95, xf), smoothstep(0.35, 0.05, xf))
    scum *= where * (0.75 + 0.25 * fbm(xn / 0.08, gx / 0.03, S + 13, 2))
    scum_col = np.array([0.10, 0.085, 0.045], F32)
    stain = np.exp(-np.maximum(zz - z_af, 0) / 0.035) * smoothstep(0.70, 0.97, xf) * (zz > z_af - 0.01)
    stain *= 0.6 + 0.4 * fbm(xn / 0.15, gx / 0.02, S + 14, 2)
    stain_col = np.array([0.42, 0.33, 0.17], F32)

    # ---- compose the zones
    alb = (tops * m_top[..., None] + bt_col * m_bt[..., None] + afv * m_af[..., None])
    alb *= (1.0 - 0.08 * bt_edge * (1 - m_af))[..., None]
    rough = r_top * m_top + r_bt * m_bt + r_af * m_af
    hgt = h_top * m_top + (0.00012 * bb) + h_af * m_af
    alb = mix(alb, scum_col, 0.35 * scum * m_af + 0.2 * scum * (1 - m_af))
    rough = rough * (1 - 0.5 * scum) + 0.55 * 0.5 * scum
    alb = mix(alb, stain_col * np.maximum(alb.mean(-1, keepdims=True), 0.05) * 1.5, 0.35 * stain * m_bt)

    # ---- spray and salt on dark topsides forward: faint dried spots and streaks
    # lower forward topsides only, fine streaks running aft (spray), fading up
    salt = smoothstep(0.62, 0.95, xf) * smoothstep(0.35, 1.0, d / th) * m_top
    salt *= smoothstep(0.35, 0.75, fbm(xn / 0.12, gx / 0.012, S + 15, 3) + 0.3 * fbm(xn / 0.03, gx / 0.03, S + 16, 2))
    alb = mix(alb, alb + 0.02, 0.5 * dark * salt)
    rough += 0.08 * salt * dark

    # ---- fender marks: rubber smudges near the sheer amidships, both sides
    fend = np.zeros((H, W), F32)
    for s in (0, 1):
        for k in range(int(rng.integers(2, 4))):
            xc = rng.uniform(0.33, 0.66) * L
            dc = rng.uniform(0.13, 0.30) * geo["freeboard"]["mid"] / 0.7
            sx, sy = rng.uniform(0.18, 0.32), rng.uniform(0.05, 0.09)
            e = ((x - xc) / sx) ** 2 + ((d - dc) / sy) ** 2
            m = np.exp(-1.6 * e) * (side == s)
            fend = np.maximum(fend, m * rng.uniform(0.6, 1.0))
    fend *= np.clip(0.55 + 0.6 * fbm(xn / 0.05, gx / 0.025, S + 17, 3), 0, 1)
    streak = np.clip(fbm(xn / 0.25, gx / 0.003, S + 18, 2) * 2.0, 0, 1)
    fend = np.clip(fend * (0.6 + 0.6 * streak), 0, 1) * m_top
    fend_col = np.full(3, 0.03 + 0.07 * dark, F32)
    alb = mix(alb, fend_col, 0.45 * fend)
    rough += 0.35 * fend

    # ---- scuffs: short fine scratches near the sheer, at the bow and on the transom quarters
    segs = []
    for s in (0, 1):
        n = int(rng.integers(90, 140))
        for k in range(n):
            zone = rng.uniform()
            if zone < 0.55:
                xc, dc, ang = rng.uniform(0.05, 0.95), rng.uniform(0.0, 0.22), rng.normal(0, 0.12)
            elif zone < 0.8:
                xc, dc, ang = rng.uniform(0.0, 0.07), rng.uniform(0.0, 0.5), rng.normal(0, 0.5)
            else:
                xc, dc, ang = rng.uniform(0.86, 0.99), rng.uniform(0.0, 0.35), rng.normal(0, 0.3)
            ln = rng.uniform(0.02, 0.22) * (1.0 if zone < 0.55 else 0.7)
            xm = xc * L
            # atlas pixel position: column along u, row along v of the side's band
            gm = np.interp(xm, geo["skin_xs"], geo["girth"][:, -1]) - dc
            u0 = xm / L if s == 0 else 1.0 - xm / L
            c0 = u0 * W
            r0 = (0.5 * (1.0 - gm / geo["girth_max"]) + 0.5 * s) * H
            dc_ = ln / px_x * np.cos(ang) * (1 if s == 0 else -1)
            dr_ = ln / px_g * np.sin(ang)
            wpx = rng.uniform(0.0006, 0.0016) / px_g
            segs.append((c0 - 0.5 * dc_, r0 - 0.5 * dr_, c0 + 0.5 * dc_, r0 + 0.5 * dr_, wpx, rng.uniform(0.3, 1.0)))
    scr = _segments(H, W, px_x, px_g, segs) * m_top
    scr_col = alb * (0.92 - 0.1 * dark) + (0.02 + 0.10 * dark)
    alb = mix(alb, scr_col, 0.6 * scr)
    rough += 0.3 * scr
    hgt -= 0.00004 * scr

    # ---- drips: faint streaks running down from the sheer at the stanchion bases and the chainplates
    drips = np.zeros((H, W), F32)
    for s in (0, 1):
        for k in range(int(rng.integers(5, 9))):
            xc = rng.uniform(0.08, 0.9) * L
            wdt = rng.uniform(0.008, 0.025)
            ln = rng.uniform(0.12, 0.45)
            m = np.exp(-((x - xc - 0.04 * d) / wdt) ** 2) * np.exp(-d / ln) * (side == s)
            drips = np.maximum(drips, m * rng.uniform(0.4, 1.0))
    drips *= m_top * np.clip(0.6 + 0.5 * fbm(xn / 0.01, gx / 0.08, S + 19, 2), 0, 1)
    drip_col = mix(np.array([0.30, 0.28, 0.24], F32) * luminance(top) * 2.2, np.full(3, 0.10, F32), dark)
    alb = mix(alb, drip_col, 0.12 * drips)

    # ---- polish swirls: faint rings in the gloss, seen only in the sun's reflection
    sw = []
    for s in (0, 1):
        for k in range(36):
            xc = rng.uniform(0.05, 0.95) * L
            dc = rng.uniform(0.03, 0.55) * geo["freeboard"]["mid"]
            r = rng.uniform(0.07, 0.18)
            sw.append((s, xc, dc, r))
    swirl = np.zeros((H, W), F32)
    for s, xc, dc, r in sw:
        gcc = np.interp(xc, geo["skin_xs"], geo["girth"][:, -1]) - dc
        c = int((xc / L if s == 0 else 1 - xc / L) * W)
        rr = int((0.5 * (1 - gcc / geo["girth_max"]) + 0.5 * s) * H)
        rc, rg = int(r / px_x) + 3, int(r / px_g) + 3
        r0, r1, c0, c1 = max(rr - rg, 0), min(rr + rg, H), max(c - rc, 0), min(c + rc, W)
        if r1 <= r0 or c1 <= c0:
            continue
        dd = np.hypot((x[r0:r1, c0:c1] - xc), (g[r0:r1, c0:c1] - gcc))
        swirl[r0:r1, c0:c1] = np.maximum(swirl[r0:r1, c0:c1], band(dd - r, 0.006, px_g) * 0.7)
    rough += 0.02 * swirl * m_top

    alb = np.minimum(alb, ALBEDO_MAX)
    rough = np.clip(rough, 0.04, 1.0)
    nrm = normal_from_height(hgt, px_x, px_g)
    occ = np.ones((H, W), F32)
    alb = push_pull(alb, valid)
    nrm = push_pull(nrm, valid)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    orm = push_pull(np.stack([occ, rough, np.zeros_like(rough)], -1), valid)
    return {"albedo": alb, "normal": nrm, "orm": orm, "valid": valid, "atlas": A}


# ----------------------------------------------------------------------------------------------------------------
# keel: side view as seen from starboard (bow to the right), the keel mesh's bounding box plus a margin

def keel_rect(geo, margin=0.02):
    k = geo["keel"]
    x0, x1 = k["min"][0], k["max"][0]
    z0, z1 = k["min"][2], k["max"][2]
    m = margin * max(x1 - x0, z1 - z0)
    return x0 - m, z0 - m, x1 + m, z1 + m


def bake_keel(geo, lv, size=1024, key=""):
    """Albedo (linear RGB) of the keel fin and bulb in side view: antifouling, roller laps, fairing patches, chips
    on the leading edge and the bulb nose, grounding scratches under the bulb."""
    x0, z0, x1, z1 = keel_rect(geo)
    w, h = x1 - x0, z1 - z0
    W = size if w >= h else int(np.ceil(size * w / h / 4) * 4)
    H = size if h > w else int(np.ceil(size * h / w / 4) * 4)
    px = max(w / W, h / H)
    xs = x0 + (np.arange(W) + 0.5) / W * w
    zs = z1 - (np.arange(H) + 0.5) / H * h
    X, Z = np.meshgrid(xs, zs)
    X = X.astype(F32)
    Z = Z.astype(F32)
    # coverage from the mesh's triangles, drawn at 4x and averaged
    ss = 4
    img = Image.new("L", (W * ss, H * ss), 0)
    dr = ImageDraw.Draw(img)
    for tri in geo["keel_tris"]:
        pts = [((p[0] - x0) / w * W * ss, (z1 - p[1]) / h * H * ss) for p in tri]
        dr.polygon(pts, fill=255)
    cov = np.asarray(img.resize((W, H), Image.BOX), dtype=F32) / 255.0
    valid = cov > 0.02
    k = geo["keel"]
    S = seed_of(key, "keel")
    rng = Rng(key, "keel")
    col = hex_lin(lv["hull"].get("keel", lv["hull"].get("antifouling", "#1a1d24")))
    # leading edge of the fin at height z, and the bulb's nose
    le_r, le_t = np.array(k["le_root"]), np.array(k["le_tip"])
    tz = np.clip((Z - le_r[2]) / (le_t[2] - le_r[2]), 0, 1)
    le_x = le_r[0] + tz * (le_t[0] - le_r[0])
    d_le = le_x - X                                            # metres aft of the leading edge
    on_fin = (Z > le_t[2] - 0.02)
    lap = np.floor((Z + 0.02 * fbm(X / 0.5, Z / 0.5, S, 2)) / 0.16)
    hh = np.sin(lap * 12.9898 + 4.1) * 43758.5453
    lap_tone = (hh - np.floor(hh) - 0.5).astype(F32)
    alb = col[None, None, :] * (1 + 0.05 * lap_tone + 0.03 * fbm(X / 0.012, Z / 0.012, S + 1, 2))[..., None]
    # fairing patches: slightly different shade where filler was sanded through the last coat
    patch = smoothstep(0.35, 0.6, fbm(X / 0.25, Z / 0.25, S + 2, 3)) * 0.5
    alb = mix(alb, alb * 1.25 + 0.01, patch * 0.35)
    # chips: along the leading edge (and the bulb's nose), small irregular spots down to primer and white undercoat
    chips = np.zeros((H, W), F32)
    core = np.zeros((H, W), F32)
    spots = []
    span_top, span_bot = le_r[2], le_t[2]
    for i in range(int(rng.integers(14, 22))):
        zc = rng.uniform(span_bot, span_top)
        tt = (zc - le_r[2]) / (le_t[2] - le_r[2])
        xc = le_r[0] + tt * (le_t[0] - le_r[0]) - abs(rng.normal(0, 0.012))
        spots.append((xc, zc, rng.uniform(0.003, 0.011)))
    if k["bulb"]:
        b = k["bulb"]
        for i in range(int(rng.integers(6, 11))):
            s = abs(rng.normal(0, 0.05))
            xc = b["nose_x"] - s * b["len"]
            hh_ = np.interp(s, b["s"], b["half_h"])
            zc = b["zc"] + rng.uniform(-0.8, 0.8) * hh_
            spots.append((xc, zc, rng.uniform(0.004, 0.014)))
    for xc, zc, r in spots:
        n = 0.35 * perlin((X - xc) / (r * 0.8), (Z - zc) / (r * 0.8), S + 3)
        dd = np.hypot(X - xc, Z - zc) / r + n
        chips = np.maximum(chips, inside(dd - 1.0, px / r))
        core = np.maximum(core, inside(dd - 0.55, px / r))
    # through the antifouling to the grey epoxy primer, here and there to the fairing compound
    primer = np.array([0.20, 0.21, 0.19], F32)
    under = np.array([0.12, 0.125, 0.12], F32)
    alb = mix(alb, under, chips * 0.85)
    alb = mix(alb, primer, core)
    # grounding: scratches along the bottom of the bulb (or the fin tip) down to grey lead
    if k["bulb"]:
        b = k["bulb"]
        s = np.clip((b["nose_x"] - X) / b["len"], 0, 1)
        bot = b["zc"] - np.interp(s, b["s"], b["half_h"])
        near = smoothstep(0.05, 0.0, Z - bot) * ((X < b["nose_x"]) & (X > b["nose_x"] - b["len"]))
        scr = np.clip(fbm(X / 0.4, Z / 0.0025, S + 4, 2) * 2.2 - 0.4, 0, 1) * near
        alb = mix(alb, np.array([0.20, 0.205, 0.215], F32), 0.7 * scr)
    alb = np.minimum(alb, ALBEDO_MAX)
    alb = push_pull(alb, valid)
    return {"albedo": alb, "rect": (x0, z0, x1, z1), "size": (W, H), "valid": valid}


# ----------------------------------------------------------------------------------------------------------------
# transom: seen from astern on the generator's transom uv1 (port on the left, its top at the top)

def transom_size(geo, W):
    h, top, bot = geo["transom"]["rect"]
    return W, int(np.ceil(W * (top - bot) / (2 * h) / 4) * 4)


def bake_transom(geo, lv, width=2048, key=""):
    """Albedo (linear RGB), normal and ORM of the transom: the topsides' paint, the graphic's return round the
    quarters, the boot stripe where its height reaches, and light wear (boarding scuffs at the cockpit opening and
    the quarters, fine scratches, faint drain streaks below the cockpit floor's edge, sealant round the rudder
    fittings). The name panel is left clear."""
    from scipy import ndimage
    T = geo["transom"]
    h, top, bot = T["rect"]
    W, H = transom_size(geo, width)
    px_y, px_z = 2 * h / W, (top - bot) / H
    px = 0.5 * (px_y + px_z)
    y1 = h - (np.arange(W) + 0.5) * px_y
    z1 = top - (np.arange(H) + 0.5) * px_z
    Yv = np.broadcast_to(y1[None, :], (H, W)).astype(F32)
    Z = np.broadcast_to(z1[:, None], (H, W)).astype(F32)
    ay = np.abs(Yv)

    def to_px(y, z):
        return (h - y) / px_y, (top - z) / px_z

    def poly_cov(pts):
        im = Image.new("L", (W * 4, H * 4), 0)
        ImageDraw.Draw(im).polygon([(to_px(q[0], q[1])[0] * 4, to_px(q[0], q[1])[1] * 4) for q in pts], fill=255)
        return np.asarray(im.resize((W, H), Image.BOX), dtype=F32) / 255.0

    valid = poly_cov(T["outline"]) > 0.02
    hull = lv["hull"]
    topc = hex_lin(hull["topsides"])
    boot = hex_lin(hull.get("boot_stripe", "#e0e0dc"))
    afc = hex_lin(hull.get("antifouling", "#1a1d24"))
    dark = float(np.clip(1.0 - luminance(topc) / 0.45, 0.0, 1.0))
    z_af, z_bt = geo["boot_top"]
    rng = Rng(key, "transom")
    S = seed_of(key, "transom")
    yc, bs, zf = T["yc"], T["bs"], T["floor_z"]
    is_open = T["open"]
    # depth below the top edge: the deck edge on the quarters, the cockpit floor's edge in the opening
    quarter = (ay >= yc) if is_open else np.ones_like(ay, bool)
    top_e = np.where(quarter, np.interp(ay, T["top_y"], T["top_z"]), zf).astype(F32)
    d = top_e - Z
    yn, zn = Yv + 31.7, Z + 5.3                 # noise coordinates

    # ---- paint: as the topsides (batch variation, sun fade toward the top on a dark hull)
    var = fbm(yn / 2.2, zn / 2.2, S + 1, 3)
    alb = topc[None, None, :] * (1.0 + 0.018 * var)[..., None]
    fade = (0.05 * dark) * smoothstep(0.3, 0.0, d) * (0.6 + 0.4 * fbm(yn / 1.5, zn / 0.4, S + 2, 2))
    alb = mix(alb, np.full(3, luminance(topc) * 1.35 + 0.004, F32), fade)
    rough = 0.14 + 0.035 * fbm(yn / 0.9, zn / 0.9, S + 3, 3) + 0.02 * fbm(yn / 0.15, zn / 0.15, S + 4, 2)
    hgt = 0.0007 * fbm(yn / 0.9, zn / 0.6, S + 5, 3) + 0.00012 * fbm(yn / 0.12, zn / 0.12, S + 6, 2)

    # ---- the graphic's return (data_format.md §8.2): stripes round the quarters ending with a slanted cut half
    # way to the cockpit opening (a third of the way in on a closed transom); a two-tone split continues across
    gr = hull.get("graphic") or {"type": "none"}
    cols = [hex_lin(c) for c in gr.get("colors", [])]
    vinyl = np.zeros((H, W), F32)
    if gr.get("type") == "stripes" and gr.get("from", 0.04) <= 1e-3:
        dep, wid = gr.get("depth", [0.08, 0.17]), gr.get("width", [0.05, 0.02])
        y_end = (yc + 0.5 * (bs - yc)) if is_open else (2.0 / 3.0) * bs
        for k in range(min(len(cols), len(dep), len(wid))):
            span = inside(y_end + 0.6 * (d - dep[k]) - ay, px)
            c = band(d - dep[k], 0.5 * wid[k], px) * span * quarter
            alb = mix(alb, cols[k][None, None, :] * (1.0 + 0.01 * var)[..., None], c)
            vinyl = np.maximum(vinyl, c)
    elif gr.get("type") == "two_tone" and cols:
        split, rise, pin = gr.get("split", 0.45), gr.get("rise", -0.15), gr.get("pinstripe", 0.025)
        zs0 = float(np.interp(bs, T["top_y"], T["top_z"]))
        ds = (split - 0.5 * rise) * max(zs0 - z_bt, 0.05)
        dd = zs0 - Z
        c = inside(ds - dd, px)
        alb = mix(alb, cols[0][None, None, :], c)
        vinyl = np.maximum(vinyl, c)
        if len(cols) > 1 and pin > 0:
            c = band(dd - ds, 0.5 * pin, px)
            alb = mix(alb, cols[1][None, None, :], c)
            vinyl = np.maximum(vinyl, c)
    vb = blur(vinyl, 0.8)
    alb = alb * (1.0 - 0.10 * np.clip(4.0 * vb * (1.0 - vb), 0, 1))[..., None]
    rough = rough * (1 - vinyl) + 0.24 * vinyl
    hgt = hgt + 0.00012 * vb

    # ---- boot stripe and antifouling where their heights reach the transom's foot
    m_af = inside(Z - z_af, px)
    m_bt = np.clip(inside(Z - z_bt, px) - m_af, 0, 1)
    alb = mix(alb, boot[None, None, :] * (1.0 + 0.012 * var)[..., None], m_bt)
    alb = mix(alb, afc[None, None, :], m_af)
    rough = rough * (1 - m_bt - m_af) + 0.22 * m_bt + 0.8 * m_af
    bb = blur(m_bt, 0.8)
    alb = alb * (1.0 - 0.08 * np.clip(4.0 * bb * (1.0 - bb), 0, 1))[..., None]
    hgt = hgt + 0.00012 * bb
    # the stern wave's stain on the boot stripe's lower edge
    stain = m_bt * np.exp(-np.maximum(Z - z_af, 0) / 0.03) * (0.5 + 0.5 * fbm(yn / 0.2, zn / 0.02, S + 7, 2))
    alb = mix(alb, np.array([0.42, 0.33, 0.17], F32) * np.maximum(alb.mean(-1, keepdims=True), 0.05) * 1.5, 0.3 * stain)

    # ---- wear: boarding scuffs at the cockpit opening and on the quarters, fine scratches all over
    pan = T["panel"]["uv1"]
    p_top = top - pan[1] * (top - bot)
    segs = []
    for k in range(int(rng.integers(35, 55))):
        if is_open and rng.uniform() < 0.6:
            yy = rng.normal(0, 0.35) * yc
            zz = max(zf - abs(rng.normal(0, 0.03)), p_top + 0.005)
            ang = rng.uniform(0, np.pi)
        else:
            yy = rng.choice([-1, 1]) * rng.uniform(yc if is_open else 0.2 * bs, bs)
            zz = float(np.interp(abs(yy), T["top_y"], T["top_z"])) - abs(rng.normal(0, 0.05))
            ang = rng.normal(0, 0.5)
        ln = rng.uniform(0.01, 0.045)
        c0, r0 = to_px(yy, zz)
        dc, dr = ln / px_y * np.cos(ang), ln / px_z * np.sin(ang)
        segs.append((c0 - 0.5 * dc, r0 - 0.5 * dr, c0 + 0.5 * dc, r0 + 0.5 * dr, rng.uniform(0.0005, 0.0018) / px,
                     rng.uniform(0.3, 1.0)))
    for k in range(int(rng.integers(40, 70))):
        yy, zz = rng.uniform(-bs, bs), rng.uniform(bot + 0.05, top)
        ln, ang = rng.uniform(0.02, 0.15), rng.normal(0, 0.4)
        c0, r0 = to_px(yy, zz)
        dc, dr = ln / px_y * np.cos(ang), ln / px_z * np.sin(ang)
        segs.append((c0 - 0.5 * dc, r0 - 0.5 * dr, c0 + 0.5 * dc, r0 + 0.5 * dr, rng.uniform(0.0005, 0.0012) / px,
                     rng.uniform(0.2, 0.7)))
    scr = _segments(H, W, px_y, px_z, segs) * valid
    alb = mix(alb, alb * (0.92 - 0.1 * dark) + (0.02 + 0.10 * dark), 0.6 * scr)
    rough += 0.3 * scr
    hgt -= 0.00004 * scr
    if is_open:
        # shoe-rubber smudges on the lip of the opening
        sm = np.exp(-((Z - (zf - 0.02)) / 0.03) ** 2) * np.exp(-(ay / (0.6 * yc)) ** 2)
        sm *= np.clip(fbm(yn / 0.06, zn / 0.03, S + 8, 3) * 1.8, 0, 1)
        alb = mix(alb, np.full(3, 0.025, F32), 0.35 * sm)
        rough += 0.2 * sm
        # the cockpit drains over the lip: faint dried streaks running down below the floor's edge
        streak = np.clip(fbm(yn / 0.006, zn / 0.25, S + 9, 2) * 2.2 - 0.2, 0, 1)
        streak *= np.exp(-np.maximum(zf - Z, 0) / 0.12) * (ay < yc) * (Z < zf)
        streak *= 0.5 + 0.5 * fbm(yn / 0.2, zn * 0.0, S + 10, 2)
        alb = mix(alb, alb + 0.02 + 0.015 * dark, 0.5 * streak)
        rough += 0.08 * streak

    # ---- the rudder fittings: sealant round each plate, a faint streak below it
    for f in geo.get("transom_fittings", []):
        q = f["poly"]
        fm = poly_cov(q)
        dist = ndimage.distance_transform_edt(fm < 0.5).astype(F32) * px
        bead = band(dist - 0.0025, 0.0015, px) * (fm < 0.5)
        alb = mix(alb, np.full(3, 0.03, F32), 0.7 * bead)
        hgt = hgt + 0.0006 * bead
        rough = mix(rough, 0.45, bead)
        below = ((Yv > q[:, 0].min()) & (Yv < q[:, 0].max()) & (Z < q[:, 1].min())).astype(F32)
        below *= np.exp(-np.maximum(q[:, 1].min() - Z, 0) / 0.08)
        below *= np.clip(fbm(yn / 0.008, zn / 0.3, S + 11, 2) + 0.4, 0, 1)
        alb = mix(alb, alb + 0.015 * dark, 0.4 * below)

    # ---- polish swirls in the gloss
    for k in range(10):
        yy, zz, r = rng.uniform(-bs, bs), rng.uniform(bot + 0.1, top), rng.uniform(0.07, 0.15)
        rough = rough + 0.014 * band(np.hypot(Yv - yy, Z - zz) - r, 0.006, px)

    alb = np.minimum(alb, ALBEDO_MAX)
    nrm = normal_from_height(hgt, px_y, px_z)
    alb = push_pull(alb, valid)
    nrm = push_pull(nrm, valid)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    orm = push_pull(np.stack([np.ones((H, W), F32), np.clip(rough, 0.04, 1.0), np.zeros((H, W), F32)], -1), valid)
    return {"albedo": alb, "normal": nrm, "orm": orm, "valid": valid, "size": (W, H), "rect": T["rect"]}


