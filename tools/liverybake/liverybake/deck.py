"""Deck textures of a livery (data_format.md §8.5): the deck seen from above on the generator's deck uv1 (the plan
view, bow to the right, port at the top), as albedo, normal and ORM maps; the ORM's blue channel is the non-slip
mask (1 moulded non-slip pattern, 0 smooth gelcoat), so the game lays the matching tiling relief.

What a moulded sportsboat deck shows, laid out in metres on the real deck (geometry.deck_info, footprints):
- moulded non-slip on the walking surfaces (side decks, foredeck, cabin top, cockpit sole), inside smooth gelcoat
  margins along the sheer, the coamings, the cabin and the sole's edges, a smooth strip down the foredeck's
  centreline, and smooth pads under every fitting;
- sealant beads round every fitting's base, with dirt caught in them, and a little contact shadow;
- foot traffic: the sole's pattern worn smoother and darker down the middle and toward the companionway, the side
  decks' walkway from the cockpit to the shrouds, the roof beside the sliding hatch, round the mast foot;
- dirt in the corners where the sole meets the coamings and the cabin front, along the cabin's base and inboard of
  the toe rail;
- rope and rubber scuffs round the winches (on the sheet's side), aft of the clutches and organisers along the line
  tails, round the cam cleats and the traveller;
- sun-faded, slightly chalky patches on the exposed horizontal surfaces, and tea-stain specks at the stanchion and
  chainplate bases.

Vertical faces (coaming and cabin sides) take the texels of their footprint, a line in the plan: the texels next to
every boundary between surfaces stay plain gelcoat, so those faces show clean gelcoat.

Every random choice is seeded from the class and livery ids, so a bake is repeatable.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from .common import ALBEDO_MAX, F32, Rng, band, blur, fbm, hex_lin, mix, normal_from_height, push_pull, seed_of, \
    smoothstep

# smooth pad round each kind of fitting (m), rope or rubber scuffs about it
PAD = {"winch": 0.035, "clutch": 0.03, "organiser": 0.025, "block": 0.02, "cleat": 0.025, "track": 0.025,
       "hatch": 0.035, "stanchion": 0.022, "chainplate": 0.03, "mast": 0.045, "pedestal": 0.035, "stemhead": 0.03,
       "fitting": 0.02}


def plan_size(geo, W):
    x0, yt, w, h = geo["deck"]["plan"]
    return W, int(np.ceil(W * h / w / 4) * 4)


def _poly_mask(polys, x0, yt, px_x, px_y, W, H, ss=2):
    """Coverage (H, W) of plan polygons [(n, 2) x, y], drawn at ss x and averaged."""
    img = Image.new("L", (W * ss, H * ss), 0)
    dr = ImageDraw.Draw(img)
    for p in polys:
        pts = [((q[0] - x0) / px_x * ss, (yt - q[1]) / px_y * ss) for q in p]
        if len(pts) >= 3:
            dr.polygon(pts, fill=255)
    return np.asarray(img.resize((W, H), Image.BOX), dtype=F32) / 255.0


def _strokes(H, W, segs):
    """Coverage of soft line strokes [(c0, r0, c1, r1, width_px, strength)] in pixel space."""
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
        taper = np.sin(np.pi * np.clip(t, 0, 1)) ** 0.6
        c = band(dist, 0.5 * wpx * taper + 1e-3, 1.0) * s
        cov[lo_r:hi_r, lo_c:hi_c] = np.maximum(cov[lo_r:hi_r, lo_c:hi_c], c)
    return cov


def _hash01(k, seed):
    """A repeatable value in [0, 1) per integer k (array)."""
    v = np.sin(np.asarray(k, dtype=np.float64) * 12.9898 + seed * 78.233) * 43758.5453
    return (v - np.floor(v)).astype(F32)


def _teak(tk, X, Y, ay, bs, deck, floor, roof, d_deck, d_floor, d_roof, edge, dk, m, px, S):
    """Laid teak planking with dark caulked seams: on the deck the planks follow the sheer inboard of the smooth
    covering board (`m`), nibbed into a king plank on the centreline forward of the cockpit and the coachroof and
    aft of the cockpit; on the cockpit sole and the coachroof top they run straight fore and aft. Butt joints are
    staggered from plank to plank. Returns (coverage 0..1, albedo, roughness, height)."""
    wood = hex_lin(tk.get("wood", "#9c6a3c"))
    caulk = hex_lin(tk.get("caulk", "#1e1b18"))
    pw = float(tk.get("plank", 0.055))          # plank width, m
    sw = float(tk.get("seam", 0.005))           # caulked seam width, m
    king = float(tk.get("king", 0.12))          # king plank width, m
    lp = float(tk.get("length", 2.4))           # plank length between butt joints, m
    area = ((deck & (d_deck > m)) | (floor & (d_floor > 0.03)) | (roof & (d_roof > 0.04))) & ~edge
    cp = dk.get("companion")
    if cp:      # the sliding hatch and the roof it slides over stay gelcoat
        hx0 = cp["hatch_x"] - 0.5 * cp["hatch_len"] - 0.03
        hx1 = cp["hatch_x"] + 0.9 * cp["hatch_len"]
        area &= ~((X > hx0) & (X < hx1) & (ay < 0.5 * cp["hatch_width"] + 0.035))
    cov = blur(area.astype(F32), 0.004 / px)
    cov = smoothstep(0.3, 0.7, cov)
    # plank coordinate across (t) and its index; the deck's planks follow the sheer, the rest run straight
    on_deck = deck & ~(floor | roof)
    kingz = on_deck & (ay < 0.5 * king) & ((X > max(dk["xc1"], dk["xk1"] if dk["has_cabin"] else dk["xc1"]))
                                           | (X < dk["xc0"]))
    t = np.where(on_deck, bs - m - ay, Y + 0.5 * pw).astype(F32)
    k = np.floor(t / pw)
    fr = t - k * pw                                       # across the plank, 0..pw
    k = np.where(on_deck, k, k + 1000 * (1 + floor))      # the sole's and the roof's planks are their own
    k = np.where(kingz, -7, k)
    side = np.where(Y >= 0, 1, -1)
    kk = k * 2 + (side > 0)
    # butt joints, staggered per plank
    ph = _hash01(kk, S % 997) * lp
    xb = np.mod(X - ph, lp)
    seam_d = np.minimum(fr, pw - fr)                      # distance to the long seams
    seam_d = np.where(kingz, np.abs(ay - 0.5 * king), seam_d)
    butt_d = np.minimum(xb, lp - xb)
    dseam = np.minimum(seam_d, butt_d)
    seam = band(dseam, 0.5 * sw, px)
    # the wood: per-plank tone, grain along the plank, a few darker streaks
    tone = 0.86 + 0.24 * _hash01(kk, S % 991 + 5)
    gx = X / 0.6
    gy = np.where(on_deck & ~kingz, t, Y) / 0.0035
    grain = fbm(gx, gy + 37.0 * _hash01(kk, 3), S + 21, 3)
    streak = smoothstep(0.35, 0.8, fbm(X / 1.4, gy / 6.0, S + 22, 2))
    alb = wood[None, None, :] * (tone * (1.0 + 0.10 * grain - 0.12 * streak))[..., None]
    alb = mix(alb, caulk, seam)
    rough = (0.66 + 0.06 * grain - 0.1 * seam).astype(F32)
    hgt = (0.00025 * (1.0 - np.exp(-(dseam / (0.25 * pw)) ** 2)) - 0.0004 * seam + 0.00004 * grain).astype(F32)
    return cov, alb.astype(F32), rough, hgt


def bake_deck(geo, lv, width=4096, key=""):
    """Albedo (linear RGB), normal (unit vectors) and ORM (occlusion, roughness, non-slip mask) of the deck."""
    dk = geo["deck"]
    x0, yt, w, h = dk["plan"]
    W, H = plan_size(geo, width)
    px_x, px_y = w / W, h / H
    px = 0.5 * (px_x + px_y)
    L = geo["L"]
    S = seed_of(key, "deck")
    rng = Rng(key, "deck")
    xs1 = x0 + (np.arange(W) + 0.5) * px_x
    ys1 = yt - (np.arange(H) + 0.5) * px_y
    X = np.broadcast_to(xs1[None, :], (H, W)).astype(F32)
    Y = np.broadcast_to(ys1[:, None], (H, W)).astype(F32)
    ay = np.abs(Y)
    col = lambda a: np.interp(xs1, dk["xs"], a)[None, :].astype(F32)
    bs, yc, yk = col(dk["bs"]), col(dk["yc"]), col(dk["yk"])
    yr = col(dk["yk_roof"])
    m = dk["margin"]

    # ---- the surfaces in plan
    on = (X >= 0) & (X <= L) & (ay <= bs)
    floor = on & (ay < yc)
    # the coachroof where it stands proud (its nose, faired into the deck, is laid out as deck): the top inside the
    # edge radius, and the raked sides between that and the base
    cab = on & (ay < yk) & (yr > 0)
    roof = cab & (ay < yr)
    wall = cab & ~roof
    deck = on & ~floor & ~cab
    edt = lambda a: ndimage.distance_transform_edt(a).astype(F32) * px
    d_deck, d_floor, d_roof = edt(deck), edt(floor), edt(roof)
    d_cab_out = edt(~cab)                           # outside the cabin: distance to its base
    # texels on a boundary between surfaces stay plain (vertical faces sample them)
    edge = (d_deck < 2.5 * px) & deck | (d_floor < 2.5 * px) & floor | (d_roof < 2.5 * px) & roof | wall

    # ---- fittings: plan outlines, a smooth pad round each, sealant beads, contact shadows
    fps = geo.get("footprints", [])
    fmask = _poly_mask([f["poly"] for f in fps], x0, yt, px_x, px_y, W, H)
    d_fit = edt(fmask < 0.5)
    pad = np.zeros((H, W), bool)
    for kind in set(f["kind"] for f in fps):
        mk = _poly_mask([f["poly"] for f in fps if f["kind"] == kind], x0, yt, px_x, px_y, W, H, ss=1)
        pad |= edt(mk < 0.5) < PAD.get(kind, 0.02)
    bead = band(d_fit - 0.0028, 0.0016, px) * (fmask < 0.5)
    contact = np.exp(-d_fit / 0.006) * (fmask < 0.5)

    # ---- the moulded non-slip areas
    ns = (deck & (d_deck > m)) | (floor & (d_floor > 0.04)) | (roof & (d_roof > 0.05))
    x_fd = dk["xk1"] if dk["has_cabin"] else dk["xc1"]
    ns &= ~((X > x_fd) & (ay < 0.035))              # smooth strip down the foredeck's centreline
    cp = dk.get("companion")
    if cp:
        # the sliding hatch and the roof it slides over stay smooth
        hx0 = cp["hatch_x"] - 0.5 * cp["hatch_len"] - 0.03
        hx1 = cp["hatch_x"] + 0.9 * cp["hatch_len"]
        ns &= ~((X > hx0) & (X < hx1) & (ay < 0.5 * cp["hatch_width"] + 0.035))
    ns &= ~pad
    ns_f = blur(ns.astype(F32), 0.01 / px)          # rounded panel corners, a soft moulded edge
    ns_f = smoothstep(0.35, 0.65, ns_f)
    ns_f *= ~edge

    # ---- wear and dirt maps (0..1)
    n1 = fbm(X / 0.35, Y / 0.35, S + 1, 3)
    n2 = fbm(X / 0.08, Y / 0.08, S + 2, 2)
    patch = np.clip(0.55 + 0.6 * n1 + 0.25 * n2, 0, 1)
    traffic = np.zeros((H, W), F32)
    # cockpit sole: down the middle and toward the companionway
    if dk["xc1"] > dk["xc0"]:
        mid = np.exp(-(ay / np.maximum(0.55 * yc, 0.05)) ** 2)
        traffic += floor * (0.45 + 0.4 * mid)
        if cp:
            near = np.exp(-np.maximum(cp["x"] - X, 0) / 0.7) * np.exp(-(ay / (cp["half_width"] + 0.2)) ** 4)
            traffic += floor * 0.6 * near
    # side decks: the walkway from the cockpit forward to the shrouds, and round the mast foot
    xm = dk["mast"]["x"]
    yw = 0.5 * (bs + np.maximum(np.maximum(yc, yk), 0.0))
    walk = np.exp(-((ay - yw) / 0.16) ** 2) * smoothstep(dk["xc0"] + 0.3, dk["xc1"], X) * smoothstep(xm + 0.8, xm, X)
    traffic += 0.45 * deck * walk
    rm = np.hypot(X - xm, Y)
    traffic += 0.4 * (deck | roof) * np.exp(-((rm - 0.25) / 0.2) ** 2)
    if cp:
        side = (np.abs(X - (cp["x"] + 0.35)) < 0.4) & (ay > 0.5 * cp["hatch_width"]) & (ay < 0.5 * cp["hatch_width"] + 0.3)
        traffic += 0.5 * roof * blur(side.astype(F32), 0.08 / px)
    traffic = np.clip(traffic * patch, 0, 1) * ~edge
    # dirt in the corners: the sole at the coamings and the cabin front, the deck at the cabin's base, inboard of
    # the toe rail
    tr = dk["toe_rail"]
    grime = floor * np.exp(-np.maximum(d_floor - 2.5 * px, 0) / 0.014)
    grime = np.maximum(grime, deck * np.exp(-np.maximum(d_cab_out - 2.5 * px, 0) / 0.012) * (d_cab_out < 0.15))
    grime = np.maximum(grime, deck * 0.7 * np.exp(-np.abs(bs - ay - 1.35 * tr) / 0.006))
    grime *= np.clip(0.5 + 0.7 * fbm(X / 0.12, Y / 0.12, S + 3, 3), 0, 1) * ~edge
    # sun fade: patchy, on the exposed horizontal surfaces
    fade = smoothstep(0.0, 0.6, fbm(X / 1.3, Y / 1.3, S + 4, 3) + 0.15) * (deck | roof) * (0.6 + 0.4 * roof)
    fade = fade + 0.3 * floor * smoothstep(0.1, 0.7, fbm(X / 1.0, Y / 1.0, S + 5, 2))

    # ---- scuffs: rope and rubber marks round the winches, aft of the clutches and organisers, round the cleats
    segs, tail_segs = [], []
    smudge = np.zeros((H, W), F32)
    tail_sm = np.zeros((H, W), F32)
    for f in fps:
        p = f["poly"]
        c = p.mean(0)
        r = 0.5 * float(np.max(np.ptp(p, axis=0)))
        k = f["kind"]
        if k == "winch":
            lead = np.arctan2(-np.sign(c[1]) * 0.6, 1.0)      # the sheet comes from forward and inboard
            for _ in range(int(rng.integers(26, 40))):
                a = lead + rng.normal(0, 1.1)
                rr = r * rng.uniform(1.15, 1.9)
                da = rng.uniform(0.15, 0.6)
                pa = c + rr * np.array([np.cos(a), np.sin(a)])
                pb = c + rr * np.array([np.cos(a + da), np.sin(a + da)])
                segs.append((pa, pb, rng.uniform(0.002, 0.006), rng.uniform(0.25, 0.8)))
            dd = np.hypot(X - c[0], Y - c[1])
            ang = np.arctan2(Y - c[1], X - c[0])
            smudge = np.maximum(smudge, np.exp(-((dd - 1.4 * r) / (0.45 * r)) ** 2) * (0.5 + 0.5 * np.cos(ang - lead))
                                * 0.55)
        elif k in ("clutch", "organiser"):
            # the tails run aft over the roof: streaks behind the fitting
            wd = 0.5 * float(np.ptp(p[:, 1]))
            for _ in range(int(rng.integers(10, 18))):
                yy = c[1] + rng.uniform(-wd, wd)
                xa = p[:, 0].min() - rng.uniform(0.0, 0.05)
                ln = rng.uniform(0.08, 0.35 if k == "clutch" else 0.2)
                tail_segs.append((np.array([xa, yy]), np.array([xa - ln, yy + rng.normal(0, 0.01)]),
                                  rng.uniform(0.002, 0.005), rng.uniform(0.2, 0.6)))
            box = (X < p[:, 0].min()) & (X > p[:, 0].min() - (0.45 if k == "clutch" else 0.25)) & (np.abs(Y - c[1]) < wd)
            tail_sm = np.maximum(tail_sm, 0.35 * blur(box.astype(F32), 0.02 / px)
                                * np.clip(fbm(X / 0.3, Y / 0.004, S + 6, 2) + 0.5, 0, 1))
        elif k == "cleat" or k == "block":
            for _ in range(int(rng.integers(4, 9))):
                a = rng.uniform(0, 2 * np.pi)
                rr = r * rng.uniform(1.1, 2.2)
                pa = c + rr * np.array([np.cos(a), np.sin(a)])
                segs.append((pa, pa + rng.normal(0, 0.03, 2), rng.uniform(0.0015, 0.004), rng.uniform(0.2, 0.6)))
        elif k == "track" and f["surface"] == "floor":
            # the traveller: scuffs on the sole either side of the track from the car's lines and feet
            for _ in range(int(rng.integers(20, 30))):
                yy = rng.uniform(p[:, 1].min(), p[:, 1].max())
                xa = c[0] + rng.choice([-1, 1]) * rng.uniform(0.04, 0.2)
                segs.append((np.array([xa, yy]), np.array([xa + rng.normal(0, 0.05), yy + rng.normal(0, 0.12)]),
                             rng.uniform(0.002, 0.006), rng.uniform(0.2, 0.6)))
    # foot scuffs (shoe rubber) on the sole and the walkway
    for _ in range(int(rng.integers(30, 45))):
        if dk["xc1"] <= dk["xc0"]:
            break
        xa = rng.uniform(dk["xc0"] + 0.1, dk["xc1"] - 0.05)
        ya = rng.normal(0, 0.35) * float(np.interp(xa, dk["xs"], dk["yc"]))
        a = rng.normal(0, 0.9)
        ln = rng.uniform(0.015, 0.05)
        segs.append((np.array([xa, ya]), np.array([xa + ln * np.cos(a), ya + ln * np.sin(a)]), rng.uniform(0.005, 0.012),
                     rng.uniform(0.08, 0.3)))
    to_px = lambda q: ((q[0] - x0) / px_x, (yt - q[1]) / px_y)
    def strokes(lst):
        out = []
        for pa, pb, wd, s_ in lst:
            a, b = to_px(pa), to_px(pb)
            out.append((a[0], a[1], b[0], b[1], wd / px, s_))
        return _strokes(H, W, out)
    # the line tails' streaks stay on the cabin top or deck they run over
    scuff = strokes(segs) + smudge * patch + (strokes(tail_segs) + tail_sm * patch) * ~floor
    scuff = np.clip(scuff, 0, 1) * on * ~edge * (fmask < 0.5)
    # tea stain: small rust-brown specks at the stainless bases (stanchions, chainplates, pulpit legs)
    tea = np.zeros((H, W), F32)
    for f in fps:
        if f["kind"] in ("stanchion", "chainplate", "stemhead"):
            c = f["poly"].mean(0)
            dd = np.hypot(X - c[0], Y - c[1])
            r = 0.5 * float(np.max(np.ptp(f["poly"], axis=0)))
            tea = np.maximum(tea, np.exp(-np.maximum(dd - r, 0) / 0.012) * (dd > r * 0.9))
    tea *= np.clip(fbm(X / 0.01, Y / 0.01, S + 7, 2) + 0.3, 0, 1) * (fmask < 0.5)

    # ---- colours
    dkc = lv.get("deck", {})
    gel = hex_lin(dkc.get("gelcoat", "#e2e2dc"))
    nsc = hex_lin(dkc.get("nonslip", "#a8a8a0"))
    var = fbm(X / 0.9, Y / 0.9, S + 8, 3)
    mottle = fbm(X / 0.25, Y / 0.25, S + 10, 3)
    alb = mix(gel[None, None, :], nsc[None, None, :], ns_f) * (1.0 + 0.015 * var + 0.035 * ns_f * mottle)[..., None]
    # sun fade: lighter and a touch yellow, chalky
    alb = mix(alb, alb * np.array([1.07, 1.04, 0.95], F32) + 0.015, 0.7 * fade)
    # foot traffic: dirt worked into the pattern, the gelcoat greyed
    dirt = np.array([0.14, 0.13, 0.11], F32)
    alb = mix(alb, dirt, (0.42 * ns_f + 0.15 * (1 - ns_f)) * traffic)
    alb = mix(alb, dirt * 0.8, 0.45 * grime)
    alb = mix(alb, np.array([0.05, 0.05, 0.05], F32), 0.55 * scuff)
    alb = mix(alb, np.array([0.34, 0.20, 0.10], F32), 0.35 * tea)
    # sealant beads: off-white polysulphide with dirt in it
    alb = mix(alb, np.array([0.40, 0.39, 0.36], F32), 0.8 * bead)
    alb = alb * (1.0 - 0.18 * contact)[..., None]

    # ---- non-slip mask: worn smoother where the feet go
    mask = ns_f * (1.0 - 0.4 * traffic) * (1.0 - 0.3 * scuff)

    # ---- roughness and relief
    rough = 0.30 + 0.5 * ns_f + 0.03 * var
    rough += 0.08 * fade * (1 - ns_f) - 0.14 * traffic * ns_f + 0.08 * grime + 0.1 * scuff
    rough = mix(rough, 0.5, bead)
    hgt = 0.0004 * blur(ns_f, 0.0015 / px) + 0.0007 * bead + 0.00012 * fbm(X / 0.5, Y / 0.5, S + 9, 2) \
        - 0.00004 * scuff

    # ---- a laid teak deck (livery deck.teak, data_format.md 8.1) in place of the moulded non-slip
    if isinstance(dkc.get("teak"), dict):
        tk, t_alb, t_rough, t_hgt = _teak(dkc["teak"], X, Y, ay, bs, deck, floor, roof, d_deck, d_floor, d_roof,
                                          edge, dk, m, px, S)
        t_alb = mix(t_alb, t_alb * np.array([1.05, 1.03, 0.97], F32) + 0.01, 0.5 * fade)
        t_alb = mix(t_alb, dirt, 0.3 * traffic)
        t_alb = mix(t_alb, dirt * 0.8, 0.35 * grime)
        t_alb = mix(t_alb, np.array([0.05, 0.05, 0.05], F32), 0.35 * scuff)
        t_alb = mix(t_alb, np.array([0.40, 0.39, 0.36], F32), 0.8 * bead) * (1.0 - 0.18 * contact)[..., None]
        alb = mix(alb, t_alb, tk)
        rough = mix(rough, np.clip(t_rough + 0.06 * grime - 0.08 * traffic, 0.3, 0.95), tk)
        hgt = hgt * (1 - tk) + (t_hgt + 0.0007 * bead) * tk
        mask = mask * (1 - tk)
    occ = 1.0 - 0.25 * grime - 0.3 * contact
    occ = np.clip(occ, 0.4, 1.0)

    valid = on
    alb = push_pull(np.minimum(alb, ALBEDO_MAX), valid)
    nrm = normal_from_height(hgt, px_x, px_y)
    nrm = push_pull(nrm, valid)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    orm = push_pull(np.stack([occ, np.clip(rough, 0.05, 1.0), np.clip(mask, 0, 1)], -1).astype(F32), valid)
    return {"albedo": alb, "normal": nrm, "orm": orm, "valid": valid, "size": (W, H),
            "rect": (x0, yt, w, h), "nonslip": ns_f, "traffic": traffic}
