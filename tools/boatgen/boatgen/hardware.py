"""Reusable deck-hardware parts and the rules that place them.

Every part is built in a local frame (x forward, y port, z along the surface normal, origin on the surface) from a
few size parameters, then placed with `on_surface()`, which reads height and normal from the deck, cabin roof or
cockpit floor. Placement rules scale with the boat and read positions from the hull, deck and rig.
"""
import numpy as np

from .mesh import (Part, revolve, tube, sweep, superellipsoid_box, box, rounded_rect, circle, normalize, translate,
                   rot_axis, frame_z, merge, extrude, seg)


# ---------------------------------------------------------------------------------------------------------
# parts (local frame)

def winch(d, handle=False):
    """Self-tailing winch, d = drum diameter: base flange, ribbed drum, rubber tailer jaws, top cap with the
    handle socket; `handle` puts a winch handle in the socket (arm pointing aft)."""
    p = Part()
    r = d / 2
    base = [(0, 0), (r * 1.38, 0), (r * 1.38, 0.04 * d), (r * 1.3, 0.07 * d), (r * 1.15, 0.2 * d), (r * 1.05, 0.28 * d)]
    p.add("metal", revolve(base + [(0, 0.28 * d)], 28, sharp=(1, 2, 3)))
    # drum with shallow grip ribs
    drum = [(r * 1.02, 0.26 * d)]
    for k in range(7):
        z = 0.30 * d + k * 0.045 * d
        drum += [(r * (0.99 - 0.012 * k), z), (r * (0.965 - 0.012 * k), z + 0.022 * d)]
    drum += [(r * 0.9, 0.62 * d), (r * 0.92, 0.68 * d)]
    p.add("metal", revolve(drum, 28, cap_ends=False))
    tailer = [(r * 0.92, 0.66 * d), (r * 1.1, 0.70 * d), (r * 1.1, 0.75 * d), (r * 0.86, 0.78 * d),
              (r * 1.1, 0.81 * d), (r * 1.08, 0.84 * d), (r * 0.80, 0.87 * d), (r * 0.80, 0.88 * d)]
    p.add("rubber", revolve(tailer, 28, cap_ends=False, sharp=(1, 2, 4, 5)))
    cap = [(r * 0.80, 0.87 * d), (r * 0.82, 0.93 * d), (r * 0.55, 0.99 * d), (r * 0.2, 1.0 * d), (r * 0.2, 0.985 * d),
           (0, 0.985 * d)]
    p.add("metal", revolve(cap, 28, cap_ends=False, sharp=(3, 4)))
    p.add("rubber", revolve([(r * 0.19, 0.93 * d), (r * 0.19, 0.99 * d), (0, 0.99 * d)], 8, cap_ends=False))
    # stripper arm and its feeder horn
    p.add("rubber", superellipsoid_box((r * 0.9, r * 0.35, 0.05 * d), 0.3, 8, 4, center=(r * 1.05, 0, 0.73 * d)))
    p.add("metal", superellipsoid_box((r * 0.35, r * 0.28, 0.12 * d), 0.4, 6, 4, center=(r * 1.45, 0, 0.72 * d)))
    if handle:
        p.extend(winch_handle(d), translate([0, 0, 0.99 * d]))
    return p


def winch_handle(d):
    """Winch handle standing in the socket: square shank, arm aft, grip up (local origin on the socket)."""
    p = Part()
    arm = 2.1 * d
    p.add("metal", tube(np.array([[0, 0, -0.04 * d], [0, 0, 0.1 * d]]), 0.06 * d, 8))
    path = np.array([[0.0, 0, 0.12 * d], [-arm, 0, 0.12 * d]])
    p.add("metal", sweep(path, rounded_rect(0.07 * d, 0.16 * d, 0.03 * d, 2), up=np.array([0, 0, 1.0])))
    p.add("metal", superellipsoid_box((0.26 * d, 0.24 * d, 0.14 * d), 0.4, 8, 5, center=(0, 0, 0.12 * d)))
    p.add("rubber", tube(np.array([[-arm, 0, 0.16 * d], [-arm, 0, 0.72 * d]]), 0.085 * d, 10))
    p.add("rubber", superellipsoid_box((0.2 * d, 0.2 * d, 0.06 * d), 0.6, 8, 4, center=(-arm, 0, 0.73 * d)))
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
    """Cam cleat on a base with a wire fairlead at its aft end (the line leads in from -x)."""
    p = Part()
    L = length
    p.add("rubber", superellipsoid_box((L, 0.55 * L, 0.10 * L), 0.25, 10, 5, center=(0, 0, 0.05 * L)))
    for sy in (-1, 1):
        cam = revolve([(0, 0), (0.2 * L, 0), (0.22 * L, 0.05 * L), (0.2 * L, 0.26 * L), (0, 0.26 * L)], 12,
                      sharp=(1,))
        p.add("metal", cam.transformed(translate([0.08 * L, sy * 0.15 * L, 0.08 * L])))
    loop = rounded_path([[-0.45 * L, -0.15 * L, 0.08 * L], [-0.62 * L, -0.15 * L, 0.3 * L],
                         [-0.62 * L, 0.15 * L, 0.3 * L], [-0.45 * L, 0.15 * L, 0.08 * L]], 0.08 * L, 3)
    p.add("metal", tube(loop, 0.03 * L, 6))
    return p


def clutch(pitch):
    """One rope clutch, line along x (lever points aft, -x)."""
    p = Part()
    w = 0.82 * pitch
    p.add("rubber", superellipsoid_box((2.4 * pitch, w, 0.62 * pitch), 0.3, 10, 5, center=(0, 0, 0.31 * pitch)))
    p.add("metal", superellipsoid_box((1.3 * pitch, w * 0.9, 0.24 * pitch), 0.35, 8, 4, center=(0.25 * pitch, 0, 0.66 * pitch)))
    lever = np.array([[0.2 * pitch, 0, 0.72 * pitch], [-0.7 * pitch, 0, 0.86 * pitch], [-1.5 * pitch, 0, 0.8 * pitch]])
    p.add("metal", sweep(lever, rounded_rect(0.12 * pitch, 0.5 * pitch, 0.05 * pitch, 2), up=np.array([0, 0, 1.0])))
    p.add("rubber", superellipsoid_box((0.35 * pitch, 0.56 * pitch, 0.16 * pitch), 0.5, 8, 4, center=(-1.5 * pitch, 0, 0.8 * pitch)))
    # line entry bushes
    for x in (1.2 * pitch, -1.2 * pitch):
        p.add("metal", revolve([(0.2 * pitch, 0), (0.2 * pitch, 0.08 * pitch), (0.12 * pitch, 0.08 * pitch)], 10,
                               cap_ends=False).transformed(translate([x, 0, 0.31 * pitch]) @ rot_axis([0, 1, 0], np.pi / 2 * np.sign(x))))
    return p


def clutch_bank(n, pitch):
    """Row of rope clutches along y on a common base plate, levers pointing aft."""
    p = Part()
    w = pitch * n
    p.add("metal", superellipsoid_box((2.7 * pitch, w + 0.3 * pitch, 0.06 * pitch), 0.2, 10, 4, center=(0, 0, 0.03 * pitch)))
    for i in range(n):
        y = (i - (n - 1) / 2) * pitch
        p.extend(clutch(pitch), translate([0, y, 0.05 * pitch]))
    return p


def organiser(n, pitch):
    """Deck organiser: n sheaves side by side (axes vertical) between two plates, lines run along x."""
    p = Part()
    w = pitch * n
    for z in (0.02 * pitch, 0.58 * pitch):
        p.add("metal", superellipsoid_box((1.3 * pitch, w + 0.2 * pitch, 0.08 * pitch), 0.3, 10, 4, center=(0, 0, z)))
    for i in range(n):
        y = (i - (n - 1) / 2) * pitch
        p.add("rubber", revolve([(0, 0.06 * pitch), (0.42 * pitch, 0.06 * pitch), (0.36 * pitch, 0.3 * pitch),
                                 (0.42 * pitch, 0.54 * pitch), (0, 0.54 * pitch)], 14).transformed(translate([0.1 * pitch, y, 0])))
    return p


def track(length, width, stops=True):
    """T-track with end stops."""
    p = Part()
    prof = np.array([[-width / 2, 0], [width / 2, 0], [width / 2, 0.35 * width], [width * 0.25, 0.45 * width],
                     [width * 0.25, 0.75 * width], [-width * 0.25, 0.75 * width], [-width * 0.25, 0.45 * width],
                     [-width / 2, 0.35 * width]])
    path = np.array([[-length / 2, 0, 0], [length / 2, 0, 0]])
    g = sweep(path, prof[::-1, ::-1], up=np.array([0, 0, 1.0]))   # (height, width), counter-clockwise
    p.add("metal", g)
    if stops:
        for sx in (-1, 1):
            p.add("rubber", superellipsoid_box((0.9 * width, 1.25 * width, 1.0 * width), 0.35, 8, 5,
                                               center=(sx * (length / 2 + 0.3 * width), 0, 0.45 * width)))
    return p


def track_car(length, width, sheave=False):
    """Track car; `sheave` adds a lead block standing on it (for a sheet car)."""
    p = Part()
    p.add("metal", superellipsoid_box((length, width * 1.6, width * 0.9), 0.3, 10, 5, center=(0, 0, width * 0.85)))
    # pin-stop plunger knob at the forward end
    p.add("rubber", tube(np.array([[0.42 * length, 0, width * 1.2], [0.42 * length, 0, width * 1.9]]), 0.16 * width, 8))
    p.add("rubber", superellipsoid_box((0.5 * width, 0.5 * width, 0.3 * width), 0.6, 8, 4, center=(0.42 * length, 0, width * 1.95)))
    if sheave:
        p.extend(block(0.55 * length), translate([-0.1 * length, 0, width * 1.25]))
    return p


def block(d, swivel=True):
    """Single block standing on its base (local z up): two cheek plates round a sheave (axis along y), a head
    shackle on a swivel."""
    p = Part()
    c = 0.62 * d
    for sy in (-1, 1):
        cheek = revolve([(0, -0.03 * d), (0.52 * d, -0.03 * d), (0.52 * d, 0.03 * d), (0, 0.03 * d)], 16, sharp=(1, 2))
        p.add("metal", cheek.transformed(translate([0, sy * 0.16 * d, c]) @ rot_axis([1, 0, 0], np.pi / 2)))
    sheave = revolve([(0, -0.12 * d), (0.46 * d, -0.12 * d), (0.40 * d, 0.0), (0.46 * d, 0.12 * d), (0, 0.12 * d)], 16)
    p.add("rubber", sheave.transformed(translate([0, 0, c]) @ rot_axis([1, 0, 0], np.pi / 2)))
    p.add("metal", tube(np.array([[0, -0.22 * d, c], [0, 0.22 * d, c]]), 0.09 * d, 8))
    if swivel:
        p.add("metal", tube(np.array([[0, 0, 0], [0, 0, 0.14 * d]]), 0.12 * d, 8))
        p.add("metal", superellipsoid_box((0.3 * d, 0.36 * d, 0.1 * d), 0.4, 8, 4, center=(0, 0, 0.13 * d)))
    return p


def padeye_block(d):
    """Turning block lying on the deck (sheave axis vertical), on a padeye: for halyards at the mast foot."""
    p = Part()
    p.add("metal", superellipsoid_box((0.9 * d, 0.6 * d, 0.1 * d), 0.3, 8, 4, center=(0, 0, 0.05 * d)))
    b = block(d, swivel=False)
    p.extend(b, translate([0.62 * d, 0, 0.22 * d]) @ rot_axis([1, 0, 0], np.pi / 2) @ translate([0, 0, -0.62 * d]))
    p.add("metal", tube(rounded_path([[0.0, -0.15 * d, 0.08 * d], [0.05 * d, -0.15 * d, 0.3 * d],
                                      [0.05 * d, 0.15 * d, 0.3 * d], [0.0, 0.15 * d, 0.08 * d]], 0.08 * d, 3), 0.05 * d, 6))
    return p


def turnbuckle(length, r):
    """Rigging screw along +z from the origin (toggle, open body, two threaded studs)."""
    p = Part()
    L = length
    p.add("metal", superellipsoid_box((2.6 * r, 1.6 * r, 0.18 * L), 0.4, 8, 5, center=(0, 0, 0.09 * L)))
    p.add("metal", tube(np.array([[0, 0, 0.12 * L], [0, 0, 0.3 * L]]), 1.1 * r, 8))
    for sx in (-1, 1):
        p.add("metal", tube(np.array([[sx * 1.3 * r, 0, 0.3 * L], [sx * 1.3 * r, 0, 0.7 * L]]), 0.5 * r, 6))
    for z0, z1 in ((0.28 * L, 0.34 * L), (0.66 * L, 0.72 * L)):
        p.add("metal", tube(np.array([[0, 0, z0], [0, 0, z1]]), 1.9 * r, 10))
    p.add("metal", tube(np.array([[0, 0, 0.7 * L], [0, 0, L]]), 1.1 * r, 8))
    return p


def instrument(w, h, t):
    """Instrument display (local x out of the face): carbon housing, dark glass face."""
    p = Part()
    p.add("carbon", superellipsoid_box((t, w, h), 0.2, 12, 5, center=(t / 2, 0, 0)))
    p.add("glass", superellipsoid_box((0.2 * t, 0.84 * w, 0.8 * h), 0.12, 12, 4, center=(t * 1.0, 0, 0)))
    return p


# one rope texture tile: 0.05 m along the rope (one lay length of the braid) and one turn round it
ROPE_TILE = 0.05


def rope_tube(path, r, sides=6, caps=True):
    """A rope: uv0 = (metres along, fraction of the turn x ROPE_TILE), a seamless texture turn round it."""
    return tube(path, r, sides, caps=caps, turn_uv=ROPE_TILE)


def rope_coil(r, turns=3, rr=0.006, slot="rope"):
    """Flaked line lying on a surface: a few loose flattened turns."""
    p = Part()
    th = np.linspace(0, 2 * np.pi * turns, 24 * turns)
    rad = r * (1 - 0.08 * th / (2 * np.pi)) * (1 + 0.08 * np.sin(3.1 * th))
    path = np.stack([rad * np.cos(th) * 1.25, rad * np.sin(th), rr + rr * 1.6 * th / th[-1]], -1)
    p.add(slot, rope_tube(path, rr, 6))
    return p


def rope(points, r, sag=0.0, n=12):
    """A line through the given points; with `sag` each span hangs by that fraction of its length."""
    pts = [np.asarray(points[0], dtype=np.float64)]
    for a, b in zip(points[:-1], points[1:]):
        a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
        L = np.linalg.norm(b - a)
        k = n if sag > 0 else 1
        for t in np.linspace(0, 1, k + 1)[1:]:
            q = a + (b - a) * t
            q[2] -= sag * L * 4 * t * (1 - t)
            pts.append(q)
    return rope_tube(np.array(pts), r, 6)


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


def wheel(d, grip=True):
    """Racing wheel in the local frame, axis along x (forward), centre at the origin: carbon rim with a rubber
    grip cover (`grip`), five spokes, hub."""
    p = Part()
    R = d / 2
    th = np.linspace(0, 2 * np.pi, seg(49, 16))[:-1]
    ring = np.stack([np.zeros_like(th), R * np.cos(th), R * np.sin(th)], -1)
    rim = sweep(np.vstack([ring, ring[:1]]), circle(0.018 * d / 0.9, 10), caps=False)
    p.add("rubber" if grip else "carbon", rim)
    if grip:
        # inner carbon rim the spokes run into
        ring2 = ring * (1 - 0.05)
        p.add("carbon", sweep(np.vstack([ring2, ring2[:1]]), circle(0.009 * d / 0.9, 8), caps=False))
    for k in range(5):
        a = 2 * np.pi * k / 5
        p.add("carbon", tube(np.array([[0, 0, 0], [0, R * np.cos(a), R * np.sin(a)]]), 0.012, 8))
    p.add("metal", revolve([(0, -0.05), (0.06, -0.05), (0.06, 0.05), (0, 0.05)], 16)
          .transformed(rot_axis([0, 1, 0], np.pi / 2)))
    return p


def hatch(lx, ly):
    """Deck hatch: low aluminium frame, tinted lens, two handles and two hinges (aft edge)."""
    p = Part()
    p.add("metal", superellipsoid_box((lx, ly, 0.04), 0.12, 16, 6, center=(0, 0, 0.018)))
    p.add("rubber", superellipsoid_box((lx * 0.95, ly * 0.95, 0.03), 0.12, 16, 5, center=(0, 0, 0.035)))
    p.add("glass", superellipsoid_box((lx * 0.9, ly * 0.9, 0.02), 0.1, 16, 5, center=(0, 0, 0.048)))
    for sy in (-0.3, 0.3):
        p.add("metal", superellipsoid_box((0.05, 0.07, 0.03), 0.4, 8, 4, center=(-lx / 2 + 0.01, sy * ly, 0.045)))
        p.add("rubber", superellipsoid_box((0.035, 0.09, 0.018), 0.4, 8, 4, center=(lx * 0.38, sy * ly, 0.062)))
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


def lead(deck, pts, r, lift=None, step=0.12):
    """A line led over the deck through plan points (x, y[, z]): points without z lie `lift` above the surface,
    and every span is re-sampled so it never dips into the deck, cabin roof or cockpit floor between them."""
    lift = 1.2 * r if lift is None else lift
    P = []
    for q in pts:
        q = np.asarray(q, dtype=np.float64)
        P.append(q if len(q) == 3 else np.array([q[0], q[1], deck.surface(q[0], q[1])[0] + lift]))
    out = [P[0]]
    for a, b in zip(P[:-1], P[1:]):
        n = max(1, int(np.linalg.norm(b[:2] - a[:2]) / step))
        for t in np.linspace(0, 1, n + 1)[1:]:
            q = a + (b - a) * t
            if 0 < t < 1:
                q[2] = max(q[2], deck.surface(q[0], q[1])[0] + lift)
            out.append(q)
    return rope_tube(np.array(out), r, 6)


def place_all(cls, hull, deck, rig, lod=0):
    """Returns named Parts: hardware (static), helm (wheel, turns about helm_pivot), boom_hardware (goes with the
    boom), mainsheet (tackle between boom and traveller, for the engine to rebuild as the boom moves) and the
    lead points of the running rigging (`leads`, for the posed sheets of running.py).

    `lod` 0 is the full model; 1 drops the small fittings (handles, plungers, coils, halyard tails); 2 keeps only
    what reads at a distance (winches, tracks, traveller, hatches, pulpit and pushpit, the helm)."""
    L = hull.L
    s = (L / 12.0) ** 0.7
    hw = Part()
    d = cls["deck"]
    small = L < 9.0
    leads = {}
    fine, mid = lod == 0, lod <= 1
    r_line = max(0.004, 0.0048 * s)

    # --- winches: primaries on the deck beside the cockpit (a handle in the starboard one), halyard winches on the
    # cabin top
    x_prim = deck.xc1 - 0.42 * (deck.xc1 - deck.xc0)
    d_prim = 0.14 * s if not small else 0.10 * s
    y_prim = float(deck.yc(x_prim)) + 0.11 * s + d_prim * 0.55
    for side in (1, -1):
        hw.extend(on_surface(deck, winch(d_prim, handle=fine and side < 0), x_prim, side * y_prim, yaw=np.pi / 2 * side),
                  tag=f"winch_primary_{side}")
        hw.attach(f"winch_primary_{side}", "deck")
    leads["primary"] = (x_prim, y_prim, float(deck.surface(x_prim, y_prim)[0]), d_prim)
    if not small:
        x_sec = deck.xc1 - 0.8 * s
        y_sec = float(deck.yc(x_sec)) + 0.12 * s + 0.4 * d_prim
        for side in (1, -1):
            hw.extend(on_surface(deck, winch(d_prim * 0.8), x_sec, side * y_sec), tag=f"winch_secondary_{side}")
            hw.attach(f"winch_secondary_{side}", "deck")
        leads["secondary"] = (x_sec, y_sec, float(deck.surface(x_sec, y_sec)[0]), d_prim * 0.8)
    # halyard leads: exits low on the mast sides, turning blocks at the mast foot, organisers, clutches aft
    n_hal = 4 if not small else 3
    hal_pitch = (0.045 if not small else 0.05) * s
    if deck.has_cabin and deck.cab_h > 0.15:
        x_cl = deck.xk0 + 0.35 * s + 0.38 * s
        y_cl = float(deck.yk(deck.xk0 + 0.35 * s)) - deck.cab_h * deck.cab_slope - 0.28 * s
        x_h = deck.xk0 + 0.35 * s
        y_h = float(deck.yk(x_h)) - deck.cab_h * deck.cab_slope - 0.2 * s
        for side in (1, -1):
            hw.extend(on_surface(deck, winch(d_prim * 0.72), x_h, side * y_h), tag=f"winch_halyard_{side}")
            hw.attach(f"winch_halyard_{side}", "deck")
    else:
        x_cl = deck.xk0 + 0.25 * s if deck.has_cabin else deck.xc1 + 0.25 * s
        y_cl = (float(deck.yk(x_cl)) * 0.45) if deck.has_cabin else 0.25 * s
    x_org = min(x_cl + 0.55 * s, rig.x_mast - 0.45 * s)
    for side in (1, -1):
        hw.extend(on_surface(deck, clutch_bank(n_hal, hal_pitch), x_cl, side * y_cl), tag=f"clutches_{side}")
        hw.attach(f"clutches_{side}", "deck")
        if mid:
            hw.extend(on_surface(deck, organiser(n_hal, hal_pitch), x_org, side * y_cl), tag=f"organiser_{side}")
            hw.attach(f"organiser_{side}", "deck")
    # turning blocks round the mast foot and the halyards themselves
    z_exit = rig.z_step + 0.42 * s
    for side in (1, -1):
        for k in range(n_hal):
            # beside the mast foot, in a fan, so they sit on the deck even where the cabin starts at the mast
            fy = side * (0.5 * rig.width + 0.06 * s + 0.05 * s * k)
            xb = rig.x_mast + 0.02 * s - 0.035 * s * k
            if mid:
                hw.extend(on_surface(deck, padeye_block(0.045 * s), xb, fy, yaw=np.pi), tag=f"mast_block_{side}_{k}")
                hw.attach(f"mast_block_{side}_{k}", "deck")
            if fine:
                y_c = side * y_cl + (k - (n_hal - 1) / 2) * hal_pitch
                zc = float(deck.surface(x_cl, y_c)[0]) + 0.36 * hal_pitch
                z_b = float(deck.surface(xb, fy)[0]) + 0.02 * s
                top = np.array([rig.x_mast, side * 0.5 * rig.width, z_exit + 0.05 * s * k])
                hw.add("rope_halyard", lead(deck, [top, np.array([xb + 0.03 * s, fy, z_b]),
                                           (x_org, y_c), np.array([x_cl + 1.2 * hal_pitch, y_c, zc]),
                                           np.array([x_cl - 1.2 * hal_pitch, y_c, zc]),
                                           (x_cl - 0.3 * s, y_c + side * 0.02 * s)], r_line * 0.9), tag=f"halyard_{side}_{k}")
                hw.attach(f"halyard_{side}_{k}", f"halyard_exit_{side}_{k}")
                hw.attach(f"halyard_{side}_{k}", f"clutches_{side}")
        if fine:
            hw.extend(on_surface(deck, rope_coil(0.13 * s, 3, r_line, "rope_halyard"), x_cl - 0.42 * s, side * y_cl * 0.9, yaw=0.4 * side),
                      tag=f"halyard_coil_{side}")
            hw.attach(f"halyard_coil_{side}", "deck")
            # halyard exit plates on the mast
            for k in range(n_hal):
                hw.add("metal", superellipsoid_box((0.05 * s, 0.012, 0.09 * s), 0.3, 8, 4,
                                                   center=[rig.x_mast, side * 0.5 * rig.width, z_exit + 0.05 * s * k]),
                       tag=f"halyard_exit_{side}_{k}")
                hw.attach(f"halyard_exit_{side}_{k}", "mast")
    # cam cleats for the sportsboat's sheets on the cockpit coaming
    if small and mid:
        for side in (1, -1):
            for dx in (-0.35, 0.35):
                hw.extend(on_surface(deck, cam_cleat(0.10 * s), x_prim + dx * s,
                                     side * (float(deck.yc(x_prim)) + 0.06 * s), yaw=np.pi), tag=f"cam_cleat_{side}_{dx}")
                hw.attach(f"cam_cleat_{side}_{dx}", "deck")

    # --- jib sheet tracks and cars, at the jib clew's fore-and-aft position, inboard of the sheer
    jib_clew_x = rig.jib_clew[0] if hasattr(rig, "jib_clew") else rig.x_mast - 1.0
    x_t = jib_clew_x - 0.45 * s
    for side in (1, -1):
        y_t = 0.62 * float(hull.bs(np.array([x_t]))[0])
        if deck.in_cabin_roof(x_t, y_t):
            y_t = float(deck.yk(x_t)) + 0.08 * s
        tl = 0.9 * s
        hw.extend(on_surface(deck, track(tl, 0.032 * s), x_t, side * y_t), tag=f"jib_track_{side}")
        hw.attach(f"jib_track_{side}", "deck")
        hw.extend(on_surface(deck, track_car(0.14 * s, 0.032 * s, sheave=True), x_t + 0.12 * s, side * y_t),
                  tag=f"jib_car_{side}")
        hw.attach(f"jib_car_{side}", f"jib_track_{side}")
        z_car = float(deck.surface(x_t + 0.12 * s, y_t)[0])
        leads["jib_car"] = np.array([x_t + 0.1 * s, y_t, z_car + 0.032 * s * 1.25 + 0.62 * 0.077 * s])

    # --- traveller across the cockpit under the boom, with the mainsheet tackle, end stops and control lines
    x_tr = rig.gooseneck[0] - 0.82 * rig.E
    x_tr = float(np.clip(x_tr, deck.xc0 + 0.25, deck.xc1 - 0.2))
    zf = float(deck.floor_z(x_tr))
    w_tr = 2 * float(deck.yc(x_tr)) * 0.96
    floor = lambda x, y: float(deck.surface(x, y)[0])
    trav = Part().extend(track(w_tr - 0.12 * s, 0.04 * s), rot_axis([0, 0, 1], np.pi / 2))
    hw.extend(trav, translate([x_tr, 0, zf]), tag="traveller")
    hw.attach("traveller", "deck")
    # the car runs along the track (its length across the boat)
    w_car, l_car, y_car = 0.045 * s, 0.12 * s, 0.1 * s
    hw.extend(track_car(l_car, w_car), translate([x_tr, y_car, zf]) @ rot_axis([0, 0, 1], np.pi / 2), tag="traveller_car")
    hw.attach("traveller_car", "traveller")
    if mid:
        for side in (1, -1):
            ye = side * (w_tr / 2 - 0.03 * s)
            hw.extend(block(0.05 * s), translate([x_tr, ye, zf]) @ rot_axis([0, 0, 1], np.pi / 2),
                      tag=f"traveller_block_{side}")
            hw.attach(f"traveller_block_{side}", "deck", "traveller")
            xc, yc_ = x_tr - 0.12 * s, ye - side * 0.06 * s
            hw.extend(cam_cleat(0.08 * s), translate([xc, yc_, floor(xc, yc_)]), tag=f"traveller_cleat_{side}")
            hw.attach(f"traveller_cleat_{side}", "deck")
            if fine:
                # control line: from the car's end, round the end block's sheave, through the cleat, tail on the floor
                xt, yt = xc - 0.2 * s, yc_ - side * 0.03 * s
                hw.add("rope_control", rope_tube(np.array([[x_tr, y_car + side * 0.45 * l_car, zf + 0.85 * w_car],
                                              [x_tr, ye, zf + 0.62 * 0.05 * s],
                                              [xc, yc_, floor(xc, yc_) + 0.02 * s],
                                              [xt, yt, floor(xt, yt) + 0.8 * r_line]]), r_line * 0.8, 6),
                       tag=f"traveller_line_{side}")
                hw.attach(f"traveller_line_{side}", "traveller_car")
                hw.attach(f"traveller_line_{side}", f"traveller_block_{side}")
                hw.attach(f"traveller_line_{side}", f"traveller_cleat_{side}")
                hw.attach(f"traveller_line_{side}", "deck")
    # mainsheet: a block standing on the car and one hanging from a bail under the boom (goes with the boom); the
    # tackle between their sheaves is a separate dynamic node. `lower` and `upper` are the sheave centres.
    d_blk = 0.09 * s
    z_lb = zf + 1.3 * w_car - 0.004
    lower = np.array([x_tr, y_car, z_lb + 0.62 * d_blk])
    hw.extend(block(d_blk), translate([x_tr, y_car, z_lb]), tag="mainsheet_lower")
    hw.attach("mainsheet_lower", "traveller_car")
    zb = float(rig.boom_bottom(x_tr))
    boom_hw = Part().add("metal", superellipsoid_box((0.1 * s, 0.05 * s, 0.03 * s), 0.35, 8, 5, center=[x_tr, 0, zb]),
                         tag="mainsheet_bail")
    boom_hw.attach("mainsheet_bail", "boom")
    z_ub = zb - 0.012 * s
    upper = np.array([x_tr, 0.0, z_ub - 0.62 * d_blk])
    boom_hw.extend(block(d_blk), translate([x_tr, 0, z_ub]) @ rot_axis([1, 0, 0], np.pi), tag="mainsheet_upper")
    boom_hw.attach("mainsheet_upper", "mainsheet_bail")
    sheet = mainsheet_tackle(lower, upper, s)
    if fine:
        # mainsheet tail out of the lower block, down to the floor and flaked there
        x1, y1 = x_tr - 0.35 * s, y_car + 0.15 * s
        x2, y2 = x_tr - 0.5 * s, y_car + 0.15 * s
        hw.add("rope_mainsheet", rope_tube(np.array([lower + [-0.2 * d_blk, 0.04 * d_blk, 0],
                                                     lower + [-0.15 * s, 0.1 * s, -0.04 * s],
                                                     [x1, y1, floor(x1, y1) + r_line],
                                                     [x2 + 0.1 * s, y2, floor(x2, y2) + r_line]]), r_line, 6),
               tag="mainsheet_tail")
        hw.attach("mainsheet_tail", "mainsheet_lower")
        hw.attach("mainsheet_tail", "deck")
        hw.extend(on_surface(deck, rope_coil(0.12 * s, 3, r_line, "rope_mainsheet"), x2, y2), tag="mainsheet_coil")
        hw.attach("mainsheet_coil", "deck")

    # --- mooring cleats and chocks at the bow and quarters
    if mid:
        for side in (1, -1):
            for x in (L - 0.55 * s, 0.35 * s):
                y = 0.62 * float(hull.bs(np.array([x]))[0])
                if deck.in_cockpit(x, y):
                    y = float(deck.yc(x)) + 0.5 * (float(hull.bs(np.array([x]))[0]) - float(deck.yc(x)))
                hw.extend(on_surface(deck, horn_cleat(0.2 * s), x, side * y), tag=f"horn_cleat_{side}_{x:.2f}")
                hw.attach(f"horn_cleat_{side}_{x:.2f}", "deck")

    # --- hatches
    if deck.has_cabin:
        x_fh = max(deck.xk1 + 0.55 * s, rig.x_mast + 0.55 * s)
        if x_fh < L - 1.2 * s:
            hw.extend(on_surface(deck, hatch(0.6 * s, 0.6 * s), x_fh, 0.0), tag="hatch_fore")
            hw.attach("hatch_fore", "deck")
        if d.get("hatches", 1) > 1:
            x_rh = deck.xk0 + 0.6 * (deck.xk1 - deck.xk0)
            if deck.in_cabin_roof(x_rh, 0.0):
                hw.extend(on_surface(deck, hatch(0.5 * s, 0.5 * s), x_rh, 0.0), tag="hatch_cabin")
                hw.attach("hatch_cabin", "deck")

    # --- lifelines, pulpit and pushpit
    if d.get("lifelines"):
        _lifelines(hw, hull, deck, s, lod)

    # --- helm: wheel on a pedestal with a guard and an instrument pod, or a tiller on the rudder head
    helm = Part()
    if d.get("steering") == "wheel":
        x_w = min(deck.xc0 + 1.25 * s, deck.xc1 - 0.8)
        zf = float(deck.floor_z(x_w))
        dw = min(1.9 * float(deck.yc(x_w)) * 0.9, 1.35 * s)
        hub = np.array([x_w, 0.0, zf + dw / 2 + 0.12])
        xp = x_w + 0.12
        hw.add("carbon", revolve([(0, 0), (0.13 * s, 0), (0.12 * s, 0.03 * s), (0.065 * s, 0.1 * s), (0.06 * s, hub[2] - zf - 0.05),
                                  (0, hub[2] - zf - 0.05)], 16, sharp=(1,)).transformed(translate([xp, 0, zf])), tag="pedestal")
        hw.attach("pedestal", "deck")
        hw.add("carbon", superellipsoid_box((0.22 * s, 0.26 * s, 0.2 * s), 0.35, 12, 6, center=[x_w + 0.14, 0, hub[2]]),
               tag="binnacle")
        hw.attach("binnacle", "pedestal")
        hw.add("metal", tube(np.array([[x_w + 0.02, 0, hub[2]], [x_w + 0.14, 0, hub[2]]]), 0.02, 10), tag="wheel_shaft")
        hw.attach("wheel_shaft", "binnacle")
        if mid:
            # pedestal guard: a bent tube hoop over the binnacle, and a compass / display pod on top
            gz = hub[2] + 0.16 * s
            guard = rounded_path([[xp + 0.22 * s, 0.2 * s, zf], [xp + 0.22 * s, 0.2 * s, gz], [xp + 0.22 * s, -0.2 * s, gz],
                                  [xp + 0.22 * s, -0.2 * s, zf]], 0.1 * s, 4)
            hw.add("metal", tube(guard, 0.014 * s, 8), tag="pedestal_guard")
            hw.attach("pedestal_guard", "deck")
            # the pod on two arms from the guard, the arms ending in the pod's side faces
            w_pod, t_pod = 0.26 * s, 0.05 * s
            M_pod = translate([xp + 0.08 * s, 0, hub[2] + 0.17 * s]) @ rot_axis([0, 1, 0], -1.25) @ rot_axis([0, 0, 1], np.pi)
            hw.extend(instrument(w_pod, 0.14 * s, t_pod), M_pod, tag="pod")
            hw.attach("pod", "pod_arm_1")
            for sy in (1, -1):
                tip = (M_pod @ np.array([0.5 * t_pod, sy * (0.5 * w_pod - 0.01 * s), 0.0, 1.0]))[:3]
                hw.add("metal", tube(np.array([[xp + 0.22 * s, sy * 0.2 * s, gz - 0.02], tip]), 0.01 * s, 6),
                       tag=f"pod_arm_{sy}")
                hw.attach(f"pod_arm_{sy}", "pedestal_guard")
                hw.attach(f"pod_arm_{sy}", "pod")
        helm.extend(wheel(dw, grip=mid), translate(hub), tag="wheel")
        helm.attach("wheel", "wheel_shaft")
        helm_pivot = hub
    else:
        helm_pivot = None
    return {"hardware": hw, "helm": helm, "helm_pivot": helm_pivot, "boom_hardware": boom_hw, "mainsheet": sheet,
            "mainsheet_ends": (lower, upper, w_tr, s), "leads": leads}


def mainsheet_tackle(lower, upper, s):
    sheet = Part()
    for k in range(4):
        off = np.array([0, (k - 1.5) * 0.0065 * s, 0])        # within the sheaves (block(0.09 s))
        sheet.add("rope_mainsheet", rope_tube(np.array([lower + off, upper + off]), 0.0045 * s, 5),
                  tag=f"mainsheet_part_{k}")
        sheet.attach(f"mainsheet_part_{k}", "mainsheet_lower")
        sheet.attach(f"mainsheet_part_{k}", "mainsheet_upper")
    return sheet


def tiller(app, deck, hull, s):
    """Tiller and extension in the boat frame (moves with the rudder). On a transom rudder the tiller butt sits
    between the rudder-head cheeks on the head's horizontal bolt (`app.tiller_pivot`), sized to the cheek gap; on a
    spade rudder it is clamped on top of the stock where it comes through the deck."""
    p = Part()
    st = app.rud_stock
    wt, ht = app.tiller_size
    if app.transom_hung:
        pv = np.asarray(app.tiller_pivot, dtype=np.float64)
        gap, th = app.head_gap, app.head_cheek
        x0, x1 = pv[0] - 0.05, app.head_front + 0.04 * s
        p.add("metal", superellipsoid_box((x1 - x0, gap + 0.002, 1.15 * ht), 0.3, 10, 5,
                                          center=[0.5 * (x0 + x1), 0, pv[2]]), tag="tiller_socket")
        p.attach("tiller_socket", "rudder_head")
        w = 0.5 * gap + th + 0.008
        p.add("metal", tube(np.array([pv - [0, w, 0], pv + [0, w, 0]]), 0.009 * s ** 0.5, 10), tag="tiller_bolt")
        for sy in (-1, 1):                                      # bolt head and nut on the cheek faces
            p.add("metal", revolve([(0, 0), (0.016 * s ** 0.5, 0), (0.016 * s ** 0.5, 0.006), (0, 0.008)], 6, sharp=(1, 2))
                  .transformed(translate(pv + [0, sy * (w - 0.009), 0]) @ rot_axis([1, 0, 0], -sy * np.pi / 2)),
                  tag="tiller_bolt")
        p.attach("tiller_bolt", "rudder_head")
        head = pv + [0.02, 0, 0]
    else:
        head = np.array([st[0], 0, float(deck.surface(st[0], 0.0)[0]) + 0.06])
        p.add("metal", tube(np.array([head - [0, 0, 0.1], head + [0, 0, 0.05]]), 0.045 * s, 12), tag="tiller_stock")
        p.attach("tiller_stock", "rudder_bearing", "deck")
        p.add("metal", superellipsoid_box((0.16 * s, 0.07 * s, 0.07 * s), 0.35, 10, 5, center=head + [0.06 * s, 0, 0.0]),
              tag="tiller_socket")
        p.attach("tiller_socket", "tiller_stock")
    length = 1.25 * s * (1.0 if app.transom_hung else 1.1)
    end = head + np.array([length, 0, 0.18 * s])
    t = np.linspace(0, 1, 12)
    # straight out of the head, then a gentle rise to the hand
    path = head[None] + t[:, None] * (end - head)[None]
    path[:, 2] = head[2] + (end[2] - head[2]) * t ** 1.6 + 0.06 * s * np.sin(np.pi * t)
    p.add("carbon", sweep(path, rounded_rect(ht, wt, 0.3 * wt, 3), scale_along=1.0 - 0.35 * t,
                          up=np.array([0, 0, 1.0])), tag="tiller")
    p.attach("tiller", "tiller_socket")
    # extension lying along the tiller, universal joint at the end
    p.add("rubber", superellipsoid_box((0.05, 0.04, 0.04), 0.6, 8, 5, center=end), tag="tiller_joint")
    p.attach("tiller_joint", "tiller")
    ext_end = end + np.array([-0.95 * s, 0.05, 0.06])
    p.add("carbon", tube(np.array([end, ext_end]), 0.013 * s, 8), tag="tiller_extension")
    p.attach("tiller_extension", "tiller_joint")
    p.add("rubber", tube(np.array([ext_end + [0.12, 0, 0], ext_end]), 0.018 * s, 8), tag="tiller_grip")
    p.attach("tiller_grip", "tiller_extension")
    return p


def rudder_fittings(app, deck, hull, s):
    """Static rudder hardware: gudgeons on the transom for a transom-hung rudder (the pintles turn with it), or
    the stock's bearing cap on the deck or cockpit floor for a spade rudder."""
    p = Part()
    st = app.rud_stock
    if app.transom_hung:
        # each gudgeon: a plate bolted flat on the transom face and two arms reaching aft either side of the blade
        # to the stock axis, clasping the rudder's pintle strap between them (same height; the pin is inside the blade)
        t = app.head_gap
        for i, zz in enumerate(app.pintle_z()):
            p.add("metal", superellipsoid_box((0.012, t + 0.07 * s, 0.075 * s), 0.25, 8, 4, center=[-0.005, 0, zz]),
                  tag=f"gudgeon_plate_{i}")
            p.attach(f"gudgeon_plate_{i}", "deck", "hull")
            for sy in (-1, 1):
                p.add("metal", superellipsoid_box((abs(st[0]) + 0.03, 0.01, 0.045 * s), 0.3, 8, 4,
                                                  center=[st[0] / 2 - 0.005, sy * (0.5 * t + 0.0105), zz]),
                      tag=f"gudgeon_{i}")
            p.attach(f"gudgeon_{i}", f"gudgeon_plate_{i}")
    else:
        z, n, _ = deck.surface(st[0], 0.0)
        ring = revolve([(0.0, 0.0), (0.11 * s, 0.0), (0.105 * s, 0.015), (0.07 * s, 0.03), (0.0, 0.03)], 20, sharp=(1,))
        p.extend(_one("metal", ring), frame_z(np.array([st[0], 0, z]), n, np.array([1.0, 0, 0])), tag="rudder_bearing")
        p.attach("rudder_bearing", "deck")
    return p


def _one(mat, g):
    p = Part()
    p.add(mat, g)
    return p


def _lifelines(hw, hull, deck, s, lod=0):
    """Stanchions, pulpit, pushpit and two tiers of lifelines. Every leg stands on the deck (outboard of the cockpit,
    inside the sheer) and meets its rail; the lifelines run from the pushpit's forward leg through the stanchions
    (the lower tier at the height along each raked stanchion) to the pulpit's aft legs."""
    L = hull.L
    h = 0.62 * s ** 0.5
    r_rail, r_leg = 0.013, 0.012
    x_aft, x_fwd = 0.9 * s, L - 1.35 * s
    n = int(np.ceil((x_fwd - x_aft) / 2.1))
    xs = np.linspace(x_aft, x_fwd, n + 1)
    bs = lambda x: float(hull.bs(np.array([x]))[0])
    rake = {side: normalize(np.array([0, side * 0.08, 1.0])) for side in (1, -1)}
    bases = {1: [], -1: []}
    for side in (1, -1):
        for i, x in enumerate(xs):
            y = bs(x) - 0.07 * s
            z, nrm, _ = deck.surface(x, y)
            base = np.array([x, side * y, z])
            # stanchions stand vertical (slightly raked outboard) regardless of the deck crown
            hw.extend(stanchion(h), frame_z(base, rake[side], np.array([1.0, 0, 0])), tag=f"stanchion_{side}_{i}")
            hw.attach(f"stanchion_{side}_{i}", "deck")
            bases[side].append(base)

    def leg(name, top, rail):
        """A vertical leg from the deck under `top` up into the rail."""
        zz = float(deck.surface(top[0], top[1])[0])
        hw.add("metal", tube(np.array([[top[0], top[1], zz - 0.004], top + [0, 0, 0.3 * r_rail]]), r_leg, 8), tag=name)
        hw.add("metal", superellipsoid_box((0.07, 0.07, 0.012), 0.3, 8, 4, center=[top[0], top[1], zz + 0.002]), tag=name)
        hw.attach(name, "deck")
        hw.attach(name, rail)

    def on_path(path, q):
        """The point of a rail's centre line nearest to q (so a leg meets the bent tube where it really is)."""
        return path[int(np.argmin(np.linalg.norm(path[:, :2] - np.asarray(q)[:2], axis=1)))].copy()

    # pulpit: bent tube round the bow, its forward corners inside the narrowing deck
    xb = L - 0.25 * s
    y_aft = 0.9 * (bs(x_fwd - 0.1) - 0.07 * s)
    y_fr = min(0.35 * y_aft / 0.9, 0.6 * bs(xb - 0.05))
    zb = float(deck.deck_z(xb, 0.0))
    top_p = rounded_path([[x_fwd + 0.05, y_aft, zb + h * 0.95], [xb, y_fr, zb + h],
                          [xb, -y_fr, zb + h], [x_fwd + 0.05, -y_aft, zb + h * 0.95]], 0.18 * s)
    hw.add("metal", tube(top_p, r_rail, 10), tag="pulpit")
    for side in (1, -1):
        leg(f"pulpit_leg_{side}_aft", on_path(top_p, [x_fwd + 0.05, side * y_aft]), "pulpit")
        leg(f"pulpit_leg_{side}_fwd", on_path(top_p, [xb - 0.05, side * y_fr]), "pulpit")
    # pushpit: a quarter frame each side, from beside the open cockpit out to the sheer and forward
    x_p = 0.1
    for side in (1, -1):
        y0 = bs(x_p) - 0.08 * s
        yi = min(max(0.55 * y0, float(deck.yc(x_p)) + 0.1 * s), y0 - 0.15) if deck.open_transom else 0.55 * y0
        zt = float(deck.deck_z(x_p, y0))
        frame = rounded_path([[x_p, side * yi, zt + h], [x_p, side * y0, zt + h], [x_aft - 0.05, side * y0, zt + h]], 0.12)
        hw.add("metal", tube(frame, r_rail, 10), tag=f"pushpit_{side}")
        for k, q in enumerate(([x_p, side * yi], [x_p + 0.12, side * y0], [x_aft - 0.05, side * y0])):
            leg(f"pushpit_leg_{side}_{k}", on_path(frame, q), f"pushpit_{side}")
    # lifelines: two tiers from the pushpit's forward leg through the stanchions to the pulpit's aft leg
    for side in (1, -1):
        y0 = bs(x_p) - 0.08 * s
        zt = float(deck.deck_z(x_p, y0))
        start = np.array([x_aft - 0.05, side * y0, zt + h])
        end = on_path(top_p, [x_fwd + 0.05, side * y_aft])
        for tier in ((1.0, 0.55) if lod < 2 else ()):
            a0 = start - [0, 0, h * (1 - tier)]
            b0 = end - [0, 0, (end[2] - float(deck.surface(end[0], end[1])[0])) * (1 - tier)]
            chain = [a0] + [base + rake[side] * h * tier for base in bases[side][1:]] + [b0]
            ends = [f"pushpit_leg_{side}_2" if tier < 1 else f"pushpit_{side}"]
            ends += [f"stanchion_{side}_{i}" for i in range(1, len(bases[side]))]
            ends += [f"pulpit_leg_{side}_aft" if tier < 1 else "pulpit"]
            for k, (a, b) in enumerate(zip(chain[:-1], chain[1:])):
                name = f"lifeline_{side}_{tier}_{k}"
                hw.add("rope", rope_tube(np.array([a, b]), 0.0035, 5, caps=False), tag=name)
                hw.attach(name, ends[k])
                hw.attach(name, ends[k + 1])
