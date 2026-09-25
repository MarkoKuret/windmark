"""Lines plan drawing (profile, half-breadth plan and body plan) as a PNG, for judging fairness."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def draw(hull, appendages, path, title="", px_per_m=110):
    L = hull.L
    B = hull.h["beam_max"]
    zmin = -appendages.get("draft", hull.Tc) - 0.2
    zmax = float(hull.zs(np.array([L]))[0]) + 0.3
    m = 40
    x_min = min([0.0] + [p[0] for poly in appendages.get("profiles", []) for p in poly]) - 0.1
    W = int((L - x_min) * px_per_m + 2 * m + B * px_per_m * 1.3 + m)
    prof_h = (zmax - zmin) * px_per_m
    H = int(prof_h + B / 2 * px_per_m + 3 * m + 30)
    img = Image.new("RGB", (W, H), (250, 250, 247))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    ink, grey, blue, red = (30, 30, 40), (170, 170, 175), (40, 90, 170), (190, 60, 50)
    oy = m + 20 + zmax * px_per_m     # DWL row of the profile view
    ox = m - x_min * px_per_m

    def P(x, z):
        return (ox + x * px_per_m, oy - z * px_per_m)

    xs = np.linspace(0, L, 400)
    # stations grid
    st = np.linspace(0, L, 11)
    for x in st:
        d.line([P(x, zmin), P(x, zmax)], fill=(225, 225, 228))
    d.line([P(-0.2, 0), P(L + 0.2, 0)], fill=blue, width=2)
    d.text(P(L + 0.25, 0.05), "DWL", fill=blue, font=font)
    # profile: sheer, keel line and buttocks
    d.line([P(x, z) for x, z in zip(xs, hull.zs(xs))], fill=ink, width=2)
    d.line([P(x, z) for x, z in zip(xs, hull.zk(xs))], fill=ink, width=2)
    d.line([P(0, hull.zk(np.array([0.0]))[0]), P(0, hull.zs(np.array([0.0]))[0])], fill=ink, width=2)
    for yb in np.linspace(0.2, 0.8, 4) * B / 2:
        pts = []
        for x in xs[::2]:
            y, z = hull.dense_section(x, 80)
            if y.max() < yb:
                if pts:
                    d.line(pts, fill=grey, width=1)
                pts = []
                continue
            k = np.argmax(y >= yb)
            zb = np.interp(yb, y[:k + 1], z[:k + 1]) if k > 0 else z[0]
            pts.append(P(x, zb))
        if len(pts) > 1:
            d.line(pts, fill=grey, width=1)
    for poly in appendages.get("profiles", []):
        d.polygon([P(x, z) for x, z in poly], outline=ink)
    # half-breadth plan (below the profile)
    oy2 = oy - zmin * px_per_m + m + B / 2 * px_per_m

    def Q(x, y):
        return (ox + x * px_per_m, oy2 - y * px_per_m)

    d.line([Q(0, 0), Q(L, 0)], fill=grey)
    d.line([Q(x, y) for x, y in zip(xs, hull.bs(xs))], fill=ink, width=2)
    for zl, col in ((0.0, blue), (-hull.Tc * 0.33, grey), (-hull.Tc * 0.66, grey), (hull.h["bilge_height"], grey)):
        pts = []
        for x in xs[::2]:
            yv = hull.half_breadth_at(x, zl)
            if yv <= 0:
                if len(pts) > 1:
                    d.line(pts, fill=col, width=2 if col == blue else 1)
                pts = []
                continue
            pts.append(Q(x, yv))
        if len(pts) > 1:
            d.line(pts, fill=col, width=2 if col == blue else 1)
    # body plan (right): aft stations left of the centreline, forward ones right
    cx = ox + L * px_per_m + m + B / 2 * px_per_m * 1.15

    def R(y, z):
        return (cx + y * px_per_m, oy - z * px_per_m)

    d.line([R(0, zmin), R(0, zmax)], fill=grey)
    d.line([R(-B / 2 - 0.1, 0), R(B / 2 + 0.1, 0)], fill=blue, width=2)
    for x in np.linspace(0, L, 21):
        y, z = hull.dense_section(x, 60)
        sgn = 1 if x >= L / 2 else -1
        d.line([R(sgn * a, b) for a, b in zip(y, z)], fill=red if abs(x - hull.x_mw) < L / 40 else ink, width=1)
    d.text((m, 8), title, fill=ink, font=font)
    img.save(path)
