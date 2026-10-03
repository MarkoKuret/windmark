"""Sail textures of a class (data_format.md §8.5, sail_visuals.md §11.2): one set per sail, shared by the fleet.

Each sail is drawn in its flat cloth plan (sail_visuals.md §11.1: the generator's uv0 sheared so the luff runs
straight up), a rectangle around the sail with square texels. The port albedo shows the sail as seen from port
(luff on the left), the starboard albedo as seen from starboard (luff on the right); the normal and ORM maps are in
the port view and serve both sides.

The cloth follows sail_visuals.md §11.1 (cross-cut woven polyester, tri-radial laminate with load-path yarns and
an X-ply scrim, tri-radial nylon), with what a sailmaker adds: seams of two plies with two rows of stitching,
edge tapes, layered corner patches with radial fingers, webbing straps and stainless rings, a headboard and batten
pockets on the main, draft stripes, tell-tales on headsails, the class insignia as stuck-on sailcloth, fold creases
from flaking, stress wrinkles at the corners and a little dirt along the foot. The sail number and nation letters
are per boat and drawn by the game over these textures in the slots of layout.json.
"""
import numpy as np
from PIL import Image, ImageDraw

from . import text as txt
from .common import (ALBEDO_MAX, F32, Rng, band, blur, fbm, hash01, hex_lin, inside, luminance, mix,
                     normal_from_height, perlin, push_pull, sample_bilinear, seed_of, smoothstep)
from .geometry import sail_plan

CLOTHS = ["dacron", "laminate", "nylon"]
STYLE_ROUGH = [0.55, 0.38, 0.45]
STYLE_BACKLIGHT = [0.30, 0.20, 0.50]


def role_of(sail_type):
    if sail_type in ("jib", "genoa"):
        return "headsail"
    if sail_type == "code_zero":
        return "code_zero"
    if sail_type.startswith("spinnaker"):
        return "spinnaker"
    return "main"


def sail_entry(liv, sail_type):
    """The class sail set's entry for a sail type, with the defaults of data_format.md §8.3."""
    e = dict(liv.get("sails", {}).get(role_of(sail_type), {}))
    e.setdefault("color", "#e4e4de")
    e.setdefault("fibre", "#1e1f21")
    e.setdefault("number", "#14213d")
    e.setdefault("design", "plain")
    e.setdefault("colors", [])
    return e


# ----------------------------------------------------------------------------------------------------------------
# texture frame

def frame(pl, long_side, margin=0.02):
    """The texture rectangle of a sail in its plan: (x0, y_top, width, height) in metres, the texture size and the
    texel size (square texels; the sail's bounding box plus a margin, centred)."""
    pts = pl["plan"].reshape(-1, 2)
    lo, hi = pts.min(0), pts.max(0)
    ext = hi - lo
    m = margin * float(ext.max())
    ext = ext + 2 * m
    px = float(ext.max()) / long_side
    W = int(np.ceil(ext[0] / px / 4) * 4)
    H = int(np.ceil(ext[1] / px / 4) * 4)
    c = 0.5 * (lo + hi)
    rect = (float(c[0] - 0.5 * W * px), float(c[1] + 0.5 * H * px), float(W * px), float(H * px))
    return rect, (W, H), px


def _polyline_dist(PX, PY, pts):
    d = np.full(PX.shape, np.inf, F32)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        l2 = max(float(ab @ ab), 1e-12)
        t = np.clip(((PX - a[0]) * ab[0] + (PY - a[1]) * ab[1]) / l2, 0, 1)
        dd = np.hypot(PX - (a[0] + t * ab[0]), PY - (a[1] + t * ab[1]))
        d = np.minimum(d, dd)
    return d.astype(F32)


def _polygon_cov(poly, rect, size, ss=4):
    x0, yt, w, h = rect
    W, H = size
    img = Image.new("L", (W * ss, H * ss), 0)
    ImageDraw.Draw(img).polygon([((p[0] - x0) / w * W * ss, (yt - p[1]) / h * H * ss) for p in poly], fill=255)
    return np.asarray(img.resize((W, H), Image.BOX), dtype=F32) / 255.0


def _norm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(np.linalg.norm(v), 1e-12)


def _corner_angle(QX, QY, into):
    b = _norm(into)
    return np.arctan2(QX * -b[1] + QY * b[0], QX * b[0] + QY * b[1]).astype(F32)


def _period(s, w):
    return ((s / w + 0.5) - np.floor(s / w + 0.5) - 0.5) * w


# ----------------------------------------------------------------------------------------------------------------
# Appendix G layout (sail_visuals.md §11.2), a port of BoatLivery.sail_layout

def number_height(loa):
    if loa < 3.5:
        return 0.23
    if loa <= 8.5:
        return 0.30
    if loa <= 11.0:
        return 0.375
    return 0.45


def _slice(poly, y):
    lo, hi = np.inf, -np.inf
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a[1] - y) * (b[1] - y) > 0 or a[1] == b[1]:
            continue
        x = a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1])
        lo, hi = min(lo, x), max(hi, x)
    return lo, hi


def _fit(poly, cy, hw, hh, h):
    xa, xb = -np.inf, np.inf
    for y in (cy - hh - 0.4 * h, cy - hh, cy, cy + hh):
        lo, hi = _slice(poly, y)
        if lo > hi:
            return None
        xa, xb = max(xa, lo + 0.6 * h), min(xb, hi - 0.4 * h)
    if xb - xa < 2 * hw:
        return None
    return 0.5 * (xa + xb)


def _min_dist(c, hw, hh, p):
    return min(np.hypot(c[0] + hw * sx - p[0], c[1] + hh * sy - p[1]) for sx in (-1, 1) for sy in (-1, 1))


def _stack(poly, head, rows, h, r_min):
    """Starboard stack then port stack, top down: boxes (cx, cy, hw, hh) or None when they do not fit."""
    res = []
    gap = 0.2 * h
    y = head[1] - (r_min if r_min > 0 else 0.3 * h)
    for side in range(2):
        for kind, fac, asp in rows:
            bh = h * fac
            bw = bh * asp
            cy = y - 0.5 * bh
            placed = False
            while cy - 0.5 * bh > 0.4 * h:
                cx = _fit(poly, cy, 0.5 * bw, 0.5 * bh, h)
                if cx is not None and (r_min <= 0 or _min_dist((cx, cy), 0.5 * bw, 0.5 * bh, head) >= r_min):
                    res.append((cx, cy, 0.5 * bw, 0.5 * bh))
                    y = cy - 0.5 * bh - gap
                    placed = True
                    break
                cy -= 0.02
            if not placed:
                return None
    return res


def sail_rows(sail_type, insignia, nation_asp, number_asp):
    """(kind, height factor, aspect) top to bottom: the main carries the insignia, nation and number; genoas,
    code zeros and spinnakers nation and number; a jib none (Appendix G1.1, G1.3)."""
    if sail_type == "jib":
        return []
    out = []
    if sail_type == "main" and insignia:
        out.append(("insignia", 1.5, txt.aspect(insignia, insignia=True)))
    if nation_asp > 0:
        out.append(("nation", 1.0, nation_asp))
    out.append(("number", 1.0, number_asp))
    return out


def layout(pl, sail_type, loa, insignia, nation_asp, number_asp):
    """The text frame and the row boxes of both sides: {"axis", "up", "tack", "h", "rows": [{"kind", "port",
    "stbd"}], "arc_ok"}. Boxes are (centre along, centre up, half width, half height) in metres from the tack."""
    tack, clew, head = pl["tack"], pl["clew"], pl["head"]
    axis = _norm(clew - tack)
    up = np.array([-axis[1], axis[0]])
    if up @ (head - tack) < 0:
        up = -up
    fr = lambda p: np.array([(p - tack) @ axis, (p - tack) @ up])  # noqa: E731
    plan = pl["plan"]
    poly = [fr(p) for p in plan[:, 0]] + [fr(p) for p in plan[::-1, -1]]
    hf = fr(head)
    out = {"axis": axis.tolist(), "up": up.tolist(), "tack": tack.tolist(), "h": 0.0, "rows": [], "arc_ok": True}
    rows = sail_rows(sail_type, insignia, nation_asp, number_asp)
    if not rows:
        return out
    luff_len = float(np.linalg.norm(head - tack))
    r_min, r_max = 0.0, np.inf
    if sail_type == "main":
        leech = float(np.sum(np.linalg.norm(np.diff(plan[:, -1], axis=0), axis=-1)))
        r_max = 0.6 * leech
    elif sail_type.startswith("spinnaker"):
        r_min = 0.4 * float(np.linalg.norm(head - 0.5 * (tack + clew)))
    else:
        r_min = 0.5 * luff_len
    h = number_height(loa)
    for attempt in range(6):
        res = _stack(poly, hf, rows, h, r_min)
        if res is not None:
            n = len(rows)
            out["h"] = h
            for k, (kind, fac, asp) in enumerate(rows):
                st, po = res[k], res[n + k]
                out["rows"].append({"kind": kind, "stbd": [float(v) for v in st], "port": [float(v) for v in po]})
                for b in (st, po):
                    for sx in (-1, 1):
                        for sy in (-1, 1):
                            if np.hypot(b[0] + sx * b[2] - hf[0], b[1] + sy * b[3] - hf[1]) > r_max:
                                out["arc_ok"] = False
            return out
        h *= 0.9
    return out


# ----------------------------------------------------------------------------------------------------------------
# the cloth

def bake_sail(sail, liv, loa, insignia, nation_asp, number_asp, long_side=2048, key=""):
    pl = sail_plan(sail, loa)
    rect, (W, H), px = frame(pl, long_side)
    x0, yt, _, _ = rect
    PX, PY = np.meshgrid((x0 + (np.arange(W) + 0.5) * px).astype(F32), (yt - (np.arange(H) + 0.5) * px).astype(F32))
    e = sail_entry(liv, pl["type"])
    style = CLOTHS.index(e["cloth"]) if e.get("cloth") in CLOTHS else pl["style"]
    kind = pl["kind"]
    S = seed_of(key, sail["id"])
    rng = Rng(key, sail["id"])
    tack, clew, head, head_aft = pl["tack"], pl["clew"], pl["head"], pl["head_aft"]
    cs, sn = pl["shear"]

    cov = _polygon_cov(pl["outline"], rect, (W, H))
    valid = cov > 0.5
    d_luff = _polyline_dist(PX, PY, pl["luff_line"])
    d_leech = _polyline_dist(PX, PY, pl["leech_line"])
    d_foot = _polyline_dist(PX, PY, pl["foot_line"])
    d_head = _polyline_dist(PX, PY, pl["head_line"]) if pl["square_top"] else np.full_like(PX, 1e3)

    layers = np.zeros((H, W), F32)        # extra plies over the single cloth
    stitch = np.zeros((H, W), F32)        # thread lines
    hgt = np.zeros((H, W), F32)           # metres, for the normal map

    # ---- panels and seams (sail_visuals.md §11.1)
    hd = 0.5 * (head + head_aft)
    mid = (tack + clew + hd) / 3
    dl = _norm(head_aft - clew)
    w = pl["panel"]
    hw = 0.005 if style == 2 else (0.009 if style == 1 else 0.008)

    def seam(dist, half):
        nonlocal layers, stitch
        layers += band(dist, half, px)
        # two rows of zigzag stitching (the zigzag about 3 mm wide reads as a grey line)
        stitch += 0.55 * band(np.abs(dist) - 0.6 * half, 0.0014, px)
        # the top panel's edge: a hairline shadow on one side of the overlap
        stitch += 0.5 * band(dist - half, 0.0007, px)

    perp_dl = np.array([-dl[1], dl[0]])
    if style == 0:
        s = (PX - clew[0]) * dl[0] + (PY - clew[1]) * dl[1]
        pid = np.floor(s / w)
        seam(_period(s, w), hw)
        gx_, gy_ = np.full_like(PX, perp_dl[0]), np.full_like(PX, perp_dl[1])
        radial = np.zeros_like(PX)
    else:
        fm = 0.5 * (tack + clew)
        foot = float(np.linalg.norm(clew - tack))
        ca = [hd, tack, clew]
        cr = [0.56 * float(np.linalg.norm(hd - fm)), 0.40 * foot, 0.52 * foot]
        D = np.stack([np.ones_like(PX)] + [np.hypot(PX - a[0], PY - a[1]) / r for a, r in zip(ca, cr)])
        ids = np.array([3, 0, 1, 2])
        order = np.argsort(D, axis=0, kind="stable")
        zmin = ids[order[0]]
        zsec = ids[order[1]]
        dmin = np.take_along_axis(D, order[:1], 0)[0]
        dsec = np.take_along_axis(D, order[1:2], 0)[0]

        def gvec(z):
            gxv = np.zeros_like(PX)
            gyv = np.zeros_like(PX)
            for k in range(3):
                m = z == k
                qx, qy = PX - ca[k][0], PY - ca[k][1]
                r = np.maximum(np.hypot(qx, qy), 1e-4)
                gxv = np.where(m, qx / r / cr[k], gxv)
                gyv = np.where(m, qy / r / cr[k], gyv)
            return gxv, gyv

        g1 = gvec(zmin)
        g2 = gvec(zsec)
        bd = (np.minimum(dsec, 4.0) - dmin) / np.maximum(np.hypot(g2[0] - g1[0], g2[1] - g1[1]), 1e-3)
        seam(bd, 1.25 * hw)
        s = (PX - clew[0]) * dl[0] + (PY - clew[1]) * dl[1]
        pid = 200.0 + np.floor(s / w)
        rad_seam = _period(s, w)
        gx_, gy_ = np.full_like(PX, perp_dl[0]), np.full_like(PX, perp_dl[1])
        radial = (PX * dl[0] + PY * dl[1]).astype(F32)
        for k in range(3):
            m = zmin == k
            a = ca[k]
            qx, qy = PX - a[0], PY - a[1]
            ang = _corner_angle(qx, qy, mid - a)
            dphi = w / cr[k]
            r = np.hypot(qx, qy)
            pid = np.where(m, k * 64.0 + np.floor(ang / dphi), pid)
            rad_seam = np.where(m, _period(ang, dphi) * r, rad_seam)
            rr = np.maximum(r, 1e-4)
            gx_ = np.where(m, qx / rr, gx_)
            gy_ = np.where(m, qy / rr, gy_)
            radial = np.where(m, ang * cr[k], radial)
        seam(rad_seam, hw)
    pid = pid.astype(F32)
    seam_cov = np.clip(layers, 0, 1)

    # ---- edge tapes
    t_luff = 0.02 if kind == 2 else (0.045 if kind == 1 else 0.035)
    t_leech = 0.02 if kind == 2 else 0.025
    t_foot = 0.02 if kind == 2 else 0.03
    tape = np.maximum.reduce([inside(d_luff - t_luff, px), inside(d_leech - t_leech, px), inside(d_foot - t_foot, px),
                              inside(d_head - 0.03, px)])
    layers += 1.2 * tape
    for dd, tw in ((d_luff, t_luff), (d_leech, t_leech), (d_foot, t_foot), (d_head, 0.03)):
        stitch += 0.7 * band(dd - tw + 0.004, 0.0006, px) + 0.5 * band(dd - 0.006, 0.0006, px)

    # ---- corner patches: layered, with radial fingers of staggered length
    rp = pl["patch"]

    def patch(a, into, r0, seed):
        nonlocal layers, stitch
        qx, qy = PX - a[0], PY - a[1]
        r = np.hypot(qx, qy)
        ang = _corner_angle(qx, qy, into)
        f = np.floor(ang / 0.26)
        hh_ = np.sin((f + seed) * 12.9898) * 43758.5453
        rf = r0 * (0.75 + 0.25 * (hh_ - np.floor(hh_)))
        k1 = inside(r - 0.42 * r0, px)
        k2 = inside(r - 0.68 * r0, px)
        k3 = inside(r - rf, px)
        layers += 0.9 * (k1 + k2) + 0.7 * k3
        stitch += 0.7 * (band(r - 0.42 * r0, 0.0006, px) + band(r - 0.68 * r0, 0.0006, px) + band(r - rf, 0.0006, px) * 0.6)
        side = _period(ang, 0.26) * r
        stitch += 0.5 * band(side, 0.0006, px) * k3 * (1 - k2)

    corners = [(tack, 0.8 * rp, 11.0), (clew, rp, 23.0), (head, rp, 37.0)]
    if pl["square_top"]:
        corners.append((head_aft, 0.6 * rp, 41.0))
    for a, r0, sd in corners:
        patch(a, mid - a, r0, sd)

    # ---- webbing straps and stainless rings at the corners
    metal = np.zeros((H, W), F32)        # ring coverage
    hole = np.zeros((H, W), F32)
    webbing = np.zeros((H, W), F32)
    ring_h = np.zeros((H, W), F32)
    ring_r = 0.012 + 0.0018 * loa
    for a, r0, sd in corners:
        into = _norm(mid - a)
        c = a + into * (ring_r * 1.8 + 0.01)
        qx, qy = PX - c[0], PY - c[1]
        r = np.hypot(qx, qy)
        ring = band(r - 0.72 * ring_r, 0.28 * ring_r, px)
        metal = np.maximum(metal, ring)
        hole = np.maximum(hole, inside(r - 0.44 * ring_r, px))
        ring_h += 0.003 * np.clip(1 - np.abs(r - 0.72 * ring_r) / (0.28 * ring_r), 0, 1) ** 0.5 * (r < ring_r)
        # webbing: 3 straps through the ring fanning into the sail
        for k, da in enumerate((-0.45, 0.0, 0.45)):
            ca_, sa_ = np.cos(da), np.sin(da)
            dvec = np.array([into[0] * ca_ - into[1] * sa_, into[0] * sa_ + into[1] * ca_])
            along = qx * dvec[0] + qy * dvec[1]
            across = -qx * dvec[1] + qy * dvec[0]
            ln = r0 * (0.5 if k != 1 else 0.62)
            strap = band(across, 0.5 * (0.022 + 0.0015 * loa), px) * inside(-along, px) * inside(along - ln, px)
            webbing = np.maximum(webbing, strap)
            stitch += 0.6 * band(along - ln + 0.012, 0.0006, px) * strap
    layers += 2.0 * webbing

    # ---- the main: headboard and batten pockets
    batten = np.zeros((H, W), F32)
    headboard = np.zeros((H, W), F32)
    if kind == 0:
        # an aluminium headboard at the top of the luff
        hb_w = 0.10 + 0.012 * loa
        hb_h = 0.12 + 0.012 * loa
        qx, qy = PX - head[0], PY - head[1]
        headboard = inside(qx - hb_w, px) * inside(-qx - 0.004, px) * inside(-qy - 0.004, px) * inside(qy + hb_h, px)
        # rounded lower corner
        headboard *= inside(np.hypot(np.maximum(qx - (hb_w - 0.03), 0), np.maximum(-(qy + hb_h - 0.03), 0)) - 0.03, px)
        ll = float(np.linalg.norm(head_aft - clew))
        nf = np.array([-dl[1], dl[0]])
        if nf[0] > 0:
            nf = -nf
        nb = pl["battens"]
        for k in range(1, nb + 1):
            f = k / (nb + 1)
            b = clew + dl * ll * f
            full = b[0] / max(-nf[0], 0.2)
            lb = full - 0.06 if k == nb else (0.22 + 0.10 * f) * full
            # t: metres forward of the leech's chord line (the roach reaches up to about 0.8 m aft of it)
            t = (PX - b[0]) * nf[0] + (PY - b[1]) * nf[1]
            across = (PX - b[0]) * dl[0] + (PY - b[1]) * dl[1]
            along = inside(t - lb, px) * inside(-0.8 - t, px)
            pocket = band(across, 0.028, px) * along
            bat = band(across, 0.009, px) * inside(t - (lb - 0.04), px) * inside(0.05 - d_leech, px) * along
            layers += 2.5 * pocket
            batten = np.maximum(batten, bat)
            stitch += 0.8 * band(np.abs(across) - 0.028, 0.0012, px) * along
            # the pocket's end patch at the leech (where the batten goes in)
            endp = band(across, 0.05, px) * inside(d_leech - 0.16, px) * along
            layers += 0.8 * endp
            stitch += 0.5 * band(d_leech - 0.16, 0.0006, px) * band(across, 0.05, px) * along
            hgt += 0.0035 * blur(bat, 1.0) * np.clip(1 - np.abs(across) / 0.012, 0, 1)
    layers += 3.0 * batten

    # ---- tell-tales (headsails): three at 1/4, 1/2, 3/4 of the luff, 0.27 to 0.44 m aft of it, red on port and
    # green on starboard, each on a small round sticker
    tt = np.zeros((H, W), F32)
    sticker = np.zeros((H, W), F32)
    if pl["telltales"]:
        lux = _norm(head - tack)
        lun = np.array([lux[1], -lux[0]])
        if lun @ (clew - tack) < 0:
            lun = -lun
        for k in (1, 2, 3):
            base = tack + lux * pl["luff_len"] * k / 4 + lun * 0.27
            qx, qy = PX - base[0], PY - base[1]
            along = qx * lun[0] + qy * lun[1]
            across = -qx * lun[1] + qy * lun[0] + 0.12 * along
            strip = band(across, 0.006, px) * inside(-along, px) * inside(along - 0.17, px)
            tt = np.maximum(tt, strip)
            sticker = np.maximum(sticker, inside(np.hypot(qx, qy) - 0.022, px))

    # ---- draft stripes on the main and the headsails: thin dark tape along three rows
    draft = np.zeros((H, W), F32)
    if kind in (0, 1) and pl["type"] != "code_zero":
        plan = pl["plan"]
        for f in (0.25, 0.5, 0.75):
            i = f * (pl["rows"] - 1)
            i0 = int(np.floor(i))
            row = plan[i0] * (1 - (i - i0)) + plan[min(i0 + 1, pl["rows"] - 1)] * (i - i0)
            row = row[1:-1] if len(row) > 4 else row
            dd = _polyline_dist(PX, PY, row)
            draft = np.maximum(draft, band(dd, 0.5 * (0.018 + 0.0012 * loa), px))
        # they stop short of the luff and run to the leech tape
        draft *= inside(t_luff + 0.04 - d_luff, px) * inside(t_leech + 0.01 - d_leech, px)

    # ---- the cloth: colour by design, panel variation, fine structure
    base_col = hex_lin(e["color"])
    cols = [hex_lin(c) for c in e.get("colors", [])]
    c0 = cols[0] if cols else base_col
    c1 = cols[1] if len(cols) > 1 else c0
    axis = _norm(clew - tack)
    up = np.array([-axis[1], axis[0]])
    if up @ (head - tack) < 0:
        up = -up
    fx = (PX - tack[0]) * axis[0] + (PY - tack[1]) * axis[1]
    fy = (PX - tack[0]) * up[0] + (PY - tack[1]) * up[1]
    height = float(max((p - tack) @ up for p in pl["outline"]))
    hfrac = fy / max(height, 0.1)
    col = np.broadcast_to(base_col, (H, W, 3)).astype(F32).copy()
    design = e.get("design", "plain")
    luff_len = pl["luff_len"]
    if design == "bands":
        stops = e.get("stops", [0.35, 0.7])
        col = mix(col, c0, inside(stops[0] - hfrac, px / height))
        if len(cols) > 1 and len(stops) > 1:
            col = mix(col, c1, inside(stops[1] - hfrac, px / height))
    elif design == "head":
        rad = float(e.get("radius", 0.3))
        col = mix(col, c0, inside(np.hypot(PX - head[0], PY - head[1]) - rad * luff_len, px))
        rc = float(e.get("corner", 0.0)) * luff_len
        if rc > 0 and len(cols) > 1:
            cor = np.maximum(inside(np.hypot(PX - tack[0], PY - tack[1]) - rc, px),
                             inside(np.hypot(PX - clew[0], PY - clew[1]) - rc, px))
            col = mix(col, c1, cor)
    elif design == "panels":
        n = 1 + min(len(cols), 2)
        k = np.mod(pid, n)
        col = np.where((k > 0.5)[..., None] & (k < 1.5)[..., None], c0, col)
        col = np.where((k >= 1.5)[..., None], c1, col)
    elif design == "diagonal":
        a = tack + (head - tack) * float(e.get("luff", 0.25))
        b = clew + (head_aft - clew) * float(e.get("leech", 0.75))
        dln = _norm(b - a)
        nl = np.array([-dln[1], dln[0]])
        if (head - a) @ nl < 0:
            nl = -nl
        sd = (PX - a[0]) * nl[0] + (PY - a[1]) * nl[1]
        col = mix(col, c0, inside(-sd, px))
        if len(cols) > 1:
            col = mix(col, c1, band(sd, 0.5 * float(e.get("band", 0.25)), px))
    elif design == "gores":
        t_ = _norm(tack - head)
        k_ = _norm(clew - head)
        spread = np.arccos(np.clip(t_ @ k_, -1, 1))
        qx, qy = PX - head[0] + 1e-5, PY - head[1]
        ang = np.arccos(np.clip((qx * t_[0] + qy * t_[1]) / np.maximum(np.hypot(qx, qy), 1e-6), -1, 1))
        g = np.floor(ang / max(spread / max(float(e.get("count", 9)), 1), 1e-3))
        m = np.mod(g, 1 + min(len(cols), 2))
        col = np.where((m > 0.5)[..., None] & (m < 1.5)[..., None], c0, col)
        col = np.where((m >= 1.5)[..., None], c1, col)
    col = np.minimum(col, ALBEDO_MAX)

    # panel to panel: each panel's cloth differs a little (weave direction, batch)
    hp = np.sin((pid + 7.0 * kind) * 12.9898 + 78.233) * 43758.5453
    pv = (hp - np.floor(hp)).astype(F32)
    alb = col * (1.0 + 0.07 * (pv - 0.5))[..., None]
    rough = STYLE_ROUGH[style] + 0.1 * (pv - 0.5)
    # a slow drift across each panel (cloth off a roll is never perfectly even)
    alb *= (1.0 + 0.012 * fbm(PX / 1.5, PY / 1.5, S + 1, 2))[..., None]
    fibre_cov = np.zeros((H, W), F32)
    fib = hex_lin(e["fibre"])
    if style == 0:
        # woven polyester: a faint warm cast and the odd thicker thread (the weave itself is the game's tiling detail)
        alb = mix(alb, alb * np.array([1.0, 0.985, 0.95], F32), 0.6)
        across_grain = PX * gy_ - PY * gx_
        along_grain = PX * gx_ + PY * gy_
        slub = np.clip(fbm(across_grain / 0.012, along_grain / 0.8, S + 2, 2) * 3.0 - 1.6, 0, 1)
        alb *= (1.0 - 0.03 * slub)[..., None]
    elif style == 1:
        # laminate: load-path yarns along each panel's grain and an X-ply scrim between the films
        s1 = PX * (gx_ * 0.866 - gy_ * 0.5) + PY * (gy_ * 0.866 + gx_ * 0.5)
        s2 = PX * (gx_ * 0.866 + gy_ * 0.5) + PY * (gy_ * 0.866 - gx_ * 0.5)
        # yarns about 5 cm apart along the grain (a little wavy, as laid), every fourth a heavier bundle
        wav = 0.004 * perlin(radial / 0.5, (PX * gx_ + PY * gy_) / 1.2, S + 3)
        sp_ = max(0.05, 2.2 * px)
        yarn = band(_period(radial + wav, sp_), 0.0013, px)
        yarn = np.maximum(yarn, band(_period(radial + wav + 0.5 * sp_, 4 * sp_), 0.0035, px))
        xply = 0.6 * np.maximum(band(_period(s1, 0.12), 0.0008, px), band(_period(s2, 0.12), 0.0008, px))
        # where the load is highest the yarns lie densest: darker bands fanning from the corners
        dens = smoothstep(0.1, 0.8, fbm(radial / 0.35, (PX * gx_ + PY * gy_) / 3.0, S + 12, 2) + 0.3)
        fibre_cov = np.clip(np.maximum(yarn * (0.6 + 0.6 * dens), xply), 0, 1)
        alb = mix(alb, fib, 0.9 * fibre_cov)
        alb = mix(alb, fib, 0.12 * dens)
        # the film's sheen differs where the yarns run
        rough += 0.08 * fibre_cov
    else:
        # nylon: the ripstop grid is the game's tiling detail; a soft mottle from the coating
        alb *= (1.0 + 0.02 * fbm(PX / 0.3, PY / 0.3, S + 4, 2))[..., None]

    # seams, tapes and patches read greyer per ply; stitching as thread lines
    alb *= (1.0 - 0.045 * np.minimum(layers, 4.0))[..., None] * (1.0 - 0.42 * np.clip(stitch, 0, 1))[..., None]
    rough += 0.04 * np.minimum(layers, 3.0)
    # webbing: woven polyester tape, a little darker and matt
    web_col = alb * 0.82 if luminance(base_col) > 0.3 else np.maximum(alb * 1.15, 0.05)
    alb = mix(alb, web_col, webbing)
    rough = rough * (1 - webbing) + 0.7 * webbing
    # draft stripes in the number colour
    num_col = hex_lin(e["number"])
    alb = mix(alb, num_col, 0.92 * draft)
    rough = rough * (1 - draft) + 0.42 * draft
    # the headboard: anodised aluminium plate with rivets
    if kind == 0:
        qx, qy = PX - head[0], PY - head[1]
        riv = np.zeros_like(PX)
        for rx in (0.03, 0.065):
            for ry in (-0.03, -0.065, -0.10):
                riv = np.maximum(riv, inside(np.hypot(qx - rx, qy - ry) - 0.005, px))
        alb = mix(alb, np.array([0.42, 0.43, 0.45], F32), headboard)
        alb = mix(alb, np.array([0.18, 0.18, 0.19], F32), riv * headboard)
        rough = rough * (1 - headboard) + 0.35 * headboard
        hgt += 0.002 * blur(headboard, 1.0)
    # rings: polished stainless, the hole dark
    alb = mix(alb, np.array([0.55, 0.56, 0.58], F32), metal)
    alb = mix(alb, np.array([0.06, 0.06, 0.065], F32), hole)
    rough = rough * (1 - metal) + 0.22 * metal
    hgt += ring_h

    # ---- folds and wrinkles (height, metres): creases from flaking, stress wrinkles at the corners, crinkle
    crease_h = np.zeros((H, W), F32)
    crease_w = np.zeros((H, W), F32)        # a light line where the cloth was folded hard
    if kind < 2:
        # flaked sails: creases roughly parallel to the foot, 0.4 to 0.7 m apart, a little wavy, fading out
        y = 0.25
        while y < height:
            ang = rng.normal(0.0, 0.06)
            ca_, sa_ = np.cos(ang), np.sin(ang)
            dist = (fy - y) * ca_ - (fx - rng.uniform(0, 3)) * sa_ + 0.02 * fbm(fx / 0.7, fy * 0 + y, S + 5 + int(y * 10), 2)
            strength = 0.55 + 0.45 * fbm(fx / 1.2, np.full_like(fx, y), S + 6 + int(y * 10), 2)
            sharp = 0.004 if style == 1 else 0.012
            crease_h += (0.0012 if style == 1 else 0.0013) * np.exp(-np.abs(dist) / sharp) * strength
            crease_w = np.maximum(crease_w, band(dist, 0.0012, px) * np.clip(strength, 0, 1))
            y += rng.uniform(0.40, 0.70)
    else:
        # a kite is stuffed into its bag: short random creases in every direction
        for k in range(int(30 + 2.5 * height)):
            cx, cy = rng.uniform(PX.min(), PX.max()), rng.uniform(PY.min(), PY.max())
            ang = rng.uniform(0, np.pi)
            ln = rng.uniform(0.3, 1.2)
            ca_, sa_ = np.cos(ang), np.sin(ang)
            along = (PX - cx) * ca_ + (PY - cy) * sa_
            across = -(PX - cx) * sa_ + (PY - cy) * ca_
            env = np.clip(1 - np.abs(along) / ln, 0, 1)
            crease_h += 0.0007 * np.exp(-np.abs(across) / 0.01) * env * rng.uniform(0.4, 1.0)
    # stress wrinkles radiating from the clew and the head
    wr = np.zeros((H, W), F32)
    for a, reach, amp in ((clew, 0.9 if kind == 1 else 0.6, 0.0016), (head, 0.5, 0.0010), (tack, 0.35, 0.0008)):
        qx, qy = PX - a[0], PY - a[1]
        r = np.hypot(qx, qy)
        ang = _corner_angle(qx, qy, mid - a)
        lam = 0.06 + 0.04 * np.clip(r / reach, 0, 1)
        env = smoothstep(0.05, 0.18, r) * np.exp(-r / reach)
        wr += amp * env * np.sin(ang * r / lam * 2 * np.pi * 0.5 + 2.0 * perlin(r / 0.3, ang * 3.0, S + 7))
    crinkle = (0.00025 if style == 1 else 0.00015) * fbm(PX / 0.05, PY / 0.05, S + 8, 3)
    hgt += crease_h + wr + crinkle
    hgt += 0.00028 * blur(np.minimum(layers, 6.0), 0.7) - 0.00012 * np.clip(stitch, 0, 1)

    # creases show in the albedo as faint lines (stress-whitened film on a laminate, a soft fold on woven cloth)
    alb = mix(alb, np.minimum(alb * 1.25 + 0.03, ALBEDO_MAX), (0.35 if style == 1 else 0.12) * crease_w)

    # ---- dirt: a little grime along the foot and at the tack, handled and dragged across the deck
    foot_d = smoothstep(0.55, 0.0, d_foot) * (0.6 + 0.4 * fbm(PX / 0.4, PY / 0.25, S + 9, 3))
    smudges = np.zeros((H, W), F32)
    for k in range(int(rng.integers(4, 8))):
        t = rng.uniform(0.1, 0.9)
        c = tack + (clew - tack) * t + up * rng.uniform(0.05, 0.6)
        sx, sy = rng.uniform(0.1, 0.35), rng.uniform(0.05, 0.15)
        smudges = np.maximum(smudges, np.exp(-(((fx - (c - tack) @ axis) / sx) ** 2 + ((fy - (c - tack) @ up) / sy) ** 2))
                             * rng.uniform(0.3, 0.8))
    dirt = np.clip(0.55 * foot_d + smudges * np.clip(0.5 + fbm(PX / 0.06, PY / 0.06, S + 10, 2), 0, 1), 0, 1)
    grime = np.array([0.20, 0.18, 0.14], F32) * max(luminance(base_col) * 1.2, 0.05)
    alb = mix(alb, grime, 0.16 * dirt)

    # ---- the light through the cloth (ORM blue): fewer plies, fibres, marks and stuck-on cloth let less through
    trans = STYLE_BACKLIGHT[style] * np.exp(-0.8 * layers) * (1 - 0.6 * fibre_cov * (0.35 if style == 1 else 0.0))
    trans *= (1 - 0.95 * metal) * (1 - headboard) * (1 - 0.6 * webbing) * (1 - 0.6 * draft)
    occ = np.clip(1.0 - 0.6 * np.maximum(crease_h - 0.0003, 0) / 0.001 * 0.1 - 0.08 * np.clip(stitch, 0, 1), 0.7, 1.0)

    # ---- the insignia (stuck-on sailcloth in the number colour) and the side-dependent parts
    lay = layout(pl, pl["type"], loa, insignia, nation_asp, number_asp)
    ins = {"port": np.zeros((H, W), F32), "stbd": np.zeros((H, W), F32)}
    for row in lay["rows"]:
        if row["kind"] != "insignia":
            continue
        cx, cy, bw, bh = row["port"]
        m = txt.mask(insignia, insignia=True, scale=4)
        texels = max(4, int(round(2 * bh / px)))
        mw = max(4, int(round(texels * m.shape[1] / m.shape[0])))
        m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((mw, texels), Image.LANCZOS),
                       dtype=F32) / 255.0
        for sd in ("port", "stbd"):
            cx, cy, bw, bh = row[sd]
            qx = (fx - (cx - bw)) / (2 * bw) if sd == "port" else (cx + bw - fx) / (2 * bw)
            qy = (cy + bh - fy) / (2 * bh)
            inb = (qx >= 0) & (qx <= 1) & (qy >= 0) & (qy <= 1)
            c = sample_bilinear(m, qx * mw, qy * texels) * inb
            ins[sd] = np.maximum(ins[sd], c)
    ins_both = np.maximum(ins["port"], ins["stbd"])
    hgt += 0.00022 * blur(ins_both, 0.6)
    trans *= (1 - 0.85 * ins["port"]) * (1 - 0.85 * ins["stbd"])
    rough = np.clip(rough, 0.05, 1.0)

    out = {}
    for sd in ("port", "stbd"):
        a = alb.copy()
        ib = blur(ins[sd], 0.7)
        edge = np.clip(4 * ib * (1 - ib), 0, 1)
        a = mix(a, num_col, ins[sd])
        a *= (1 - 0.12 * edge)[..., None]
        tcol = np.array([0.55, 0.05, 0.04], F32) if sd == "port" else np.array([0.04, 0.32, 0.08], F32)
        a = mix(a, np.minimum(alb * 1.08 + 0.04, ALBEDO_MAX), 0.8 * sticker)
        a = mix(a, tcol, tt)
        a = np.minimum(a, ALBEDO_MAX)
        a = push_pull(a, valid)
        out[sd] = a if sd == "port" else a[:, ::-1].copy()
    trans *= (1 - 0.5 * tt) * (1 - 0.3 * sticker)
    nrm = normal_from_height(hgt, px, px)
    nrm = push_pull(nrm, valid)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    rough = np.where(ins_both > 0.5, 0.40, rough)
    orm = push_pull(np.stack([occ, rough, np.clip(trans, 0, 1)], -1), valid)
    info = {"id": sail["id"], "type": pl["type"], "cloth": CLOTHS[style], "shear": [cs, sn], "rect": list(rect),
            "size": [W, H], "texel_m": px, "text": {k: v for k, v in lay.items() if k != "arc_ok"},
            "arc_ok": lay["arc_ok"]}
    return {"albedo_port": out["port"], "albedo_stbd": out["stbd"], "normal": nrm, "orm": orm, "info": info,
            "valid": valid}
