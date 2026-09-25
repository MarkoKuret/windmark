"""Reusable deck-hardware parts and the rules that place them.

Every part is built in a local frame (x forward, y port, z along the surface normal, origin on the surface) from a
few size parameters, then placed with `on_surface()`, which reads height and normal from the deck, cabin roof or
cockpit floor. Placement rules scale with the boat and read positions from the hull, deck and rig.
"""
import numpy as np

from .mesh import (Part, revolve, tube, sweep, superellipsoid_box, box, rounded_rect, circle, normalize, translate,
                   rot_axis, frame_z, merge, extrude)


# ---------------------------------------------------------------------------------------------------------
# parts (local frame)

def winch(d):
    """Self-tailing winch, d = drum diameter."""
    p = Part()
    r = d / 2
    base = [(0, 0), (r * 1.35, 0), (r * 1.35, 0.06 * d), (r * 1.15, 0.2 * d), (r * 1.05, 0.28 * d)]
    p.add("metal", revolve(base + [(0, 0.28 * d)], 28, sharp=(1, 2)))
    drum = [(r * 1.02, 0.26 * d), (r * 0.98, 0.34 * d), (r * 0.9, 0.62 * d), (r * 0.92, 0.68 * d)]
    p.add("metal", revolve(drum, 28, cap_ends=False))
    tailer = [(r * 0.92, 0.66 * d), (r * 1.08, 0.70 * d), (r * 1.08, 0.80 * d), (r * 0.80, 0.86 * d),
              (r * 0.80, 0.88 * d)]
    p.add("rubber", revolve(tailer, 28, cap_ends=False, sharp=(1, 2, 3)))
    cap = [(r * 0.80, 0.87 * d), (r * 0.82, 0.93 * d), (r * 0.55, 0.99 * d), (r * 0.18, 1.0 * d), (0, 1.0 * d)]
    p.add("metal", revolve(cap, 28, cap_ends=False))
    # stripper arm
    p.add("rubber", superellipsoid_box((r * 0.9, r * 0.35, 0.05 * d), 0.3, 8, 4, center=(r * 1.0, 0, 0.72 * d)))
    return p


def horn_cleat(length):
    p = Part()
    h = 0.28 * length
    t = np.linspace(-1, 1, 15)
    path = np.stack([t * length / 2, np.zeros_like(t), h * (0.55 + 0.45 * (1 - t ** 2) ** 0.3)], -1)
    sc = 0.55 + 0.45 * (1 - np.abs(t)) ** 0.5
    p.add("metal", sweep(path, rounded_rect(0.16 * length, 0.1 * length, 0.04 * length, 3), scale_along=sc,
                         up=np.array([0, 0, 1.0])))
    for sx in (-0.18, 0.18):
        post = [(0, 0), (0.07 * length, 0), (0.05 * length, h * 0.75), (0, h * 0.75)]
        p.add("metal", revolve(post, 12).transformed(translate([sx * length, 0, 0])))
    return p


def cam_cleat(length):
    p = Part()
    p.add("rubber", superellipsoid_box((length, 0.55 * length, 0.12 * length), 0.25, 10, 5, center=(0, 0, 0.06 * length)))
    for sy in (-1, 1):
        p.add("metal", superellipsoid_box((0.55 * length, 0.14 * length, 0.3 * length), 0.3, 8, 5,
                                          center=(0.05 * length, sy * 0.17 * length, 0.25 * length)))
    return p


def clutch_bank(n, pitch):
    """Row of rope clutches along y, levers pointing aft."""
    p = Part()
    w = pitch * n
    p.add("rubber", superellipsoid_box((0.9 * pitch * 2.2, w, 0.6 * pitch), 0.3, 10, 5, center=(0, 0, 0.3 * pitch)))
    for i in range(n):
        y = (i - (n - 1) / 2) * pitch
        p.add("metal", superellipsoid_box((1.4 * pitch, 0.55 * pitch, 0.35 * pitch), 0.35, 8, 5,
                                          center=(-0.9 * pitch, y, 0.75 * pitch)))
    return p


def block(d):
    """Single block with a becket, standing on a short post."""
    p = Part()
    p.add("rubber", revolve([(0, -0.18 * d), (0.5 * d, -0.18 * d), (0.5 * d, 0.18 * d), (0, 0.18 * d)], 18)
          .transformed(rot_axis([1, 0, 0], np.pi / 2) @ translate([0, 0.62 * d, 0])))
    p.add("metal", tube(np.array([[0, 0, 0], [0, 0, 0.14 * d]]), 0.12 * d, 8))
    return p


def track(length, width):
    p = Part()
    prof = np.array([[-width / 2, 0], [width / 2, 0], [width / 2, 0.35 * width], [width * 0.25, 0.45 * width],
                     [width * 0.25, 0.75 * width], [-width * 0.25, 0.75 * width], [-width * 0.25, 0.45 * width],
                     [-width / 2, 0.35 * width]])
    path = np.array([[-length / 2, 0, 0], [length / 2, 0, 0]])
    g = sweep(path, prof[:, [1, 0]], up=np.array([0, 0, 1.0]))
    p.add("metal", g)
    return p


def track_car(length, width):
    p = Part()
    p.add("metal", superellipsoid_box((length, width * 1.6, width * 1.0), 0.3, 10, 5, center=(0, 0, width * 0.9)))
    return p


def stanchion(h, r=0.0125):
    p = Part()
    p.add("metal", tube(np.array([[0, 0, 0.02], [0, 0, h]]), r, 10))
    p.add("metal", superellipsoid_box((0.10, 0.07, 0.02), 0.3, 8, 4, center=(0, 0, 0.01)))
    p.add("metal", superellipsoid_box((0.035, 0.035, 0.03), 0.6, 8, 5, center=(0, 0, h)))
    p.add("metal", superellipsoid_box((0.03, 0.03, 0.025), 0.6, 8, 5, center=(0, 0, h * 0.55)))
    return p


def rounded_path(pts, r, n=6):
    """Polyline with its inner corners rounded by radius r (for bent tube frames)."""
    pts = np.asarray(pts, dtype=np.float64)
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        d1, d2 = normalize(a - b), normalize(c - b)
        rr = min(r, 0.45 * np.linalg.norm(a - b), 0.45 * np.linalg.norm(c - b))
        p1, p2 = b + d1 * rr, b + d2 * rr
        for t in np.linspace(0, 1, n):
            q = (1 - t) ** 2 * p1 + 2 * (1 - t) * t * b + t ** 2 * p2
            out.append(q)
    out.append(pts[-1])
    return np.array(out)


def wheel(d):
    """Destroyer wheel in the local frame, axis along x (forward), centre at the origin."""
    p = Part()
    R = d / 2
    th = np.linspace(0, 2 * np.pi, 49)[:-1]
    ring = np.stack([np.zeros_like(th), R * np.cos(th), R * np.sin(th)], -1)
    rim = sweep(np.vstack([ring, ring[:1]]), circle(0.018 * d / 0.9, 10), caps=False)
    p.add("carbon", rim)
    for k in range(5):
        a = 2 * np.pi * k / 5
        p.add("carbon", tube(np.array([[0, 0, 0], [0, R * np.cos(a), R * np.sin(a)]]), 0.012, 8))
    p.add("metal", revolve([(0, -0.05), (0.06, -0.05), (0.06, 0.05), (0, 0.05)], 16)
          .transformed(rot_axis([0, 1, 0], np.pi / 2)))
    return p


def hatch(lx, ly):
    p = Part()
    p.add("rubber", superellipsoid_box((lx, ly, 0.05), 0.12, 16, 6, center=(0, 0, 0.02)))
    p.add("glass", superellipsoid_box((lx * 0.92, ly * 0.92, 0.02), 0.1, 16, 5, center=(0, 0, 0.05)))
    return p


def mooring_chock(length):
    p = Part()
    p.add("metal", superellipsoid_box((length, 0.35 * length, 0.18 * length), 0.4, 10, 5, center=(0, 0, 0.06 * length)))
    return p


# ---------------------------------------------------------------------------------------------------------
# placement

def on_surface(deck, part, x, y, yaw=0.0, surface=None, lift=0.0):
    if surface is None:
        z, n, _ = deck.surface(x, y)
    else:
        z, n = surface
    M = frame_z(np.array([x, y, z + lift]), n, np.array([np.cos(yaw), np.sin(yaw), 0.0]))
    out = Part()
    out.extend(part, M)
    return out


def place_all(cls, hull, deck, rig):
    """Returns named Parts: hardware (static), helm (wheel, turns about helm_pivot), boom_hardware (goes with the
    boom) and mainsheet (tackle between boom and traveller, for the engine to rebuild as the boom moves)."""
    L = hull.L
    s = (L / 12.0) ** 0.7
    hw = Part()
    d = cls["deck"]
    small = L < 9.0

    # --- winches: primaries on the deck beside the cockpit, halyard winches on the cabin top
    x_prim = deck.xc1 - 0.42 * (deck.xc1 - deck.xc0)
    d_prim = 0.14 * s if not small else 0.10 * s
    y_prim = float(deck.yc(x_prim)) + 0.11 * s + d_prim * 0.55
    for side in (1, -1):
        hw.extend(on_surface(deck, winch(d_prim), x_prim, side * y_prim))
    if not small:
        x_sec = deck.xc1 - 0.8 * s
        y_sec = float(deck.yc(x_sec)) + 0.12 * s + 0.4 * d_prim
        for side in (1, -1):
            hw.extend(on_surface(deck, winch(d_prim * 0.8), x_sec, side * y_sec))
    if deck.has_cabin and deck.cab_h > 0.15:
        x_h = deck.xk0 + 0.35 * s
        y_h = float(deck.yk(x_h)) - deck.cab_h * deck.cab_slope - 0.2 * s
        for side in (1, -1):
            hw.extend(on_surface(deck, winch(d_prim * 0.72), x_h, side * y_h))
            hw.extend(on_surface(deck, clutch_bank(4, 0.045 * s), x_h + 0.38 * s, side * (y_h - 0.08 * s), yaw=0.0))
    elif deck.has_cabin:
        # low cabin: clutches and cam cleats on the coachroof aft edge
        x_h = deck.xk0 + 0.25 * s
        y_h = float(deck.yk(x_h)) * 0.45
        for side in (1, -1):
            hw.extend(on_surface(deck, clutch_bank(3, 0.05 * s), x_h, side * y_h))
    # cam cleats for the sportsboat's sheets on the cockpit coaming
    if small:
        for side in (1, -1):
            for dx in (-0.35, 0.35):
                hw.extend(on_surface(deck, cam_cleat(0.10 * s), x_prim + dx * s,
                                     side * (float(deck.yc(x_prim)) + 0.06 * s), yaw=np.pi))

    # --- jib sheet tracks and cars, at the jib clew's fore-and-aft position, inboard of the sheer
    jib_clew_x = rig.jib_clew[0] if hasattr(rig, "jib_clew") else rig.x_mast - 1.0
    x_t = jib_clew_x - 0.45 * s
    for side in (1, -1):
        y_t = 0.62 * float(hull.bs(np.array([x_t]))[0])
        if deck.in_cabin_roof(x_t, y_t):
            y_t = float(deck.yk(x_t)) + 0.08 * s
        tl = 0.9 * s
        hw.extend(on_surface(deck, track(tl, 0.032 * s), x_t, side * y_t))
        car = Part().extend(track_car(0.14 * s, 0.032 * s)).extend(block(0.07 * s), translate([0, 0, 0.05 * s]))
        hw.extend(on_surface(deck, car, x_t + 0.12 * s, side * y_t))

    # --- traveller across the cockpit under the boom, with the mainsheet tackle
    x_tr = rig.gooseneck[0] - 0.82 * rig.E
    x_tr = float(np.clip(x_tr, deck.xc0 + 0.25, deck.xc1 - 0.2))
    zf = float(deck.floor_z(x_tr))
    w_tr = 2 * float(deck.yc(x_tr)) * 0.96
    trav = Part().extend(track(w_tr, 0.04 * s), rot_axis([0, 0, 1], np.pi / 2))
    hw.extend(trav, translate([x_tr, 0, zf + 0.004]))
    hw.extend(track_car(0.12 * s, 0.045 * s), translate([x_tr, 0.1 * s, zf]))
    boom_z = rig.gooseneck[2] - 0.1 * s
    lower = np.array([x_tr, 0.1 * s, zf + 0.1 * s])
    upper = np.array([x_tr, 0.0, boom_z - 0.08 * s])
    hw.extend(block(0.09 * s), translate(lower))
    # upper block hangs under the boom (goes with the boom); the tackle is a separate dynamic node
    boom_hw = Part().extend(block(0.09 * s), translate(upper) @ rot_axis([1, 0, 0], np.pi))
    sheet = mainsheet_tackle(lower, upper, s)

    # --- mooring cleats and chocks at the bow and quarters
    for side in (1, -1):
        for x in (L - 0.55 * s, 0.35 * s):
            y = 0.62 * float(hull.bs(np.array([x]))[0])
            if deck.in_cockpit(x, y):
                y = float(deck.yc(x)) + 0.5 * (float(hull.bs(np.array([x]))[0]) - float(deck.yc(x)))
            hw.extend(on_surface(deck, horn_cleat(0.2 * s), x, side * y))

    # --- hatches
    if deck.has_cabin:
        x_fh = max(deck.xk1 + 0.55 * s, rig.x_mast + 0.55 * s)
        if x_fh < L - 1.2 * s:
            hw.extend(on_surface(deck, hatch(0.6 * s, 0.6 * s), x_fh, 0.0))
        if d.get("hatches", 1) > 1:
            x_rh = deck.xk0 + 0.6 * (deck.xk1 - deck.xk0)
            if deck.in_cabin_roof(x_rh, 0.0):
                hw.extend(on_surface(deck, hatch(0.5 * s, 0.5 * s), x_rh, 0.0))

    # --- deck organisers near the mast foot
    for side in (1, -1):
        hw.extend(on_surface(deck, block(0.06 * s), rig.x_mast - 0.28 * s, side * 0.16 * s))

    # --- lifelines, pulpit and pushpit
    if d.get("lifelines"):
        _lifelines(hw, hull, deck, s)

    # --- helm: wheel on a pedestal, or a tiller on the rudder head
    helm = Part()
    if d.get("steering") == "wheel":
        x_w = min(deck.xc0 + 1.25 * s, deck.xc1 - 0.8)
        zf = float(deck.floor_z(x_w))
        dw = min(1.9 * float(deck.yc(x_w)) * 0.9, 1.35 * s)
        hub = np.array([x_w, 0.0, zf + dw / 2 + 0.12])
        hw.add("carbon", tube(np.array([[x_w + 0.12, 0, zf], [x_w + 0.12, 0, hub[2] - 0.05]]), 0.06 * s, 14))
        hw.add("carbon", superellipsoid_box((0.22 * s, 0.26 * s, 0.2 * s), 0.35, 12, 6, center=[x_w + 0.14, 0, hub[2]]))
        hw.add("metal", tube(np.array([[x_w + 0.02, 0, hub[2]], [x_w + 0.14, 0, hub[2]]]), 0.02, 10))
        helm.extend(wheel(dw), translate(hub))
        helm_pivot = hub
    else:
        helm_pivot = None
    return {"hardware": hw, "helm": helm, "helm_pivot": helm_pivot, "boom_hardware": boom_hw, "mainsheet": sheet,
            "mainsheet_ends": (lower, upper, w_tr, s)}


def mainsheet_tackle(lower, upper, s):
    sheet = Part()
    for k in range(4):
        off = np.array([0, (k - 1.5) * 0.012 * s, 0])
        sheet.add("rope", tube(np.array([lower + off + [0, 0, 0.08 * s], upper + off - [0, 0, 0.08 * s]]), 0.005 * s, 5))
    return sheet


def tiller(app, deck, hull, s):
    """Tiller and extension in the boat frame, attached to the rudder head (moves with the rudder)."""
    p = Part()
    st = app.rud_stock
    if app.transom_hung:
        head = st + [0.0, 0, 0.12]
    else:
        head = np.array([st[0], 0, float(deck.surface(st[0], 0.0)[0]) + 0.06])
        p.add("metal", tube(np.array([head - [0, 0, 0.1], head + [0, 0, 0.05]]), 0.045 * s, 12))
    length = 1.25 * s * (1.0 if app.transom_hung else 1.1)
    end = head + np.array([length, 0, 0.18 * s])
    t = np.linspace(0, 1, 10)
    path = head[None] + t[:, None] * (end - head)[None] + np.array([0, 0, 1.0])[None] * (0.08 * s * np.sin(np.pi * t))[:, None]
    p.add("carbon", sweep(path, rounded_rect(0.06 * s, 0.045 * s, 0.015 * s, 3), scale_along=1.0 - 0.35 * t,
                          up=np.array([0, 0, 1.0])))
    # extension lying along the tiller, universal joint at the end
    p.add("rubber", superellipsoid_box((0.05, 0.04, 0.04), 0.6, 8, 5, center=end))
    ext_end = end + np.array([-0.95 * s, 0.05, 0.06])
    p.add("carbon", tube(np.array([end, ext_end]), 0.013 * s, 8))
    p.add("rubber", tube(np.array([ext_end + [0.12, 0, 0], ext_end]), 0.018 * s, 8))
    return p


def _lifelines(hw, hull, deck, s):
    L = hull.L
    h = 0.62 * s ** 0.5
    x_aft, x_fwd = 0.9 * s, L - 1.35 * s
    n = int(np.ceil((x_fwd - x_aft) / 2.1))
    xs = np.linspace(x_aft, x_fwd, n + 1)
    tops = {1: [], -1: []}
    for side in (1, -1):
        for x in xs:
            y = float(hull.bs(np.array([x]))[0]) - 0.07 * s
            z, nrm, _ = deck.surface(x, y)
            base = np.array([x, side * y, z])
            # stanchions stand vertical (slightly raked outboard) regardless of the deck crown
            hw.extend(stanchion(h), frame_z(base, np.array([0, side * 0.08, 1.0]), np.array([1.0, 0, 0])))
            tops[side].append(base + normalize(np.array([0, side * 0.08, 1.0])) * h)
    # pulpit: bent tube around the bow, legs to the deck
    xb = L - 0.25 * s
    pts = []
    for side in (1, -1):
        y0 = float(hull.bs(np.array([x_fwd - 0.1]))[0]) - 0.07 * s
        pts.append((side, y0))
    zb = float(deck.deck_z(xb, 0.0))
    top_p = rounded_path([[x_fwd + 0.05, 0.9 * pts[0][1], zb + h * 0.95], [xb, 0.35 * pts[0][1], zb + h],
                          [xb, -0.35 * pts[0][1], zb + h], [x_fwd + 0.05, -0.9 * pts[0][1], zb + h * 0.95]], 0.18 * s)
    hw.add("metal", tube(top_p, 0.013, 10))
    for side in (1, -1):
        for xl, fr in ((x_fwd + 0.05, 0.9), (xb - 0.05, 0.35)):
            yl = side * fr * pts[0][1]
            zt = float(deck.deck_z(xl, yl))
            hw.add("metal", tube(np.array([[xl, yl, zt], [xl, yl, zb + h * (0.95 if fr > 0.5 else 1.0)]]), 0.012, 8))
    # pushpit: two quarter frames (open transom between them)
    for side in (1, -1):
        y0 = float(hull.bs(np.array([0.1]))[0]) - 0.08 * s
        yi = y0 * 0.55
        zt = float(deck.deck_z(0.1, y0))
        frame = rounded_path([[0.1, side * yi, zt + h], [0.1, side * y0, zt + h], [x_aft - 0.05, side * y0, zt + h]], 0.12)
        hw.add("metal", tube(frame, 0.013, 10))
        for p0 in ([0.1, side * yi], [0.1, side * y0], [x_aft - 0.3, side * y0]):
            zz = float(deck.deck_z(p0[0], p0[1]))
            hw.add("metal", tube(np.array([[p0[0], p0[1], zz], [p0[0], p0[1], zz + h]]), 0.012, 8))
    # lifelines: two tiers from the pushpit through the stanchions to the pulpit
    for side in (1, -1):
        y0 = float(hull.bs(np.array([0.1]))[0]) - 0.08 * s
        zt = float(deck.deck_z(0.1, y0))
        start = np.array([x_aft - 0.05, side * y0, zt + h])
        chain = [start] + tops[side][1:] + [np.array([x_fwd + 0.05, side * 0.9 * pts[0][1], zb + h * 0.95])]
        for tier in (1.0, 0.55):
            for a, b in zip(chain[:-1], chain[1:]):
                za = a.copy()
                zb2 = b.copy()
                if tier < 1:
                    za[2] = a[2] - h * (1 - tier)
                    zb2[2] = b[2] - h * (1 - tier)
                hw.add("rope", tube(np.array([za, zb2]), 0.0035, 5, caps=False))
