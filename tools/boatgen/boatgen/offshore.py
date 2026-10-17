"""Shorthanded-offshore deck fittings (data_format.md 3.7.4): the hard dodger over the companionway, foot braces
across the cockpit floor, a liferaft canister at the transom and a stowed autopilot ram by the helm.

Built in the boat frame (x forward from the transom, y port, z up) on the deck's surfaces, few triangles each, in
the material slots of the shared atlas (no new material). Each piece is tagged and attached to what it stands on, so
the attachment checks (attach.py) hold them to the 5 mm look rule.
"""
import numpy as np

from .mesh import Geom, Part, grid, tube, superellipsoid_box, revolve, translate, rot_axis

N_SHELL = 4.0          # superellipse exponent of the dodger's section: a rounded box


def _spow(c, e):
    return np.sign(c) * np.abs(c) ** e


def _subset(g, keep):
    """The triangles `keep` of a geom, its vertices compacted."""
    I = g.I[keep]
    used = np.unique(I)
    remap = -np.ones(len(g.P), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return Geom(g.P[used], remap[I], g.N[used], None if g.uv0 is None else g.uv0[used],
                None if g.uv1 is None else g.uv1[used])


def dodger_frame(deck, spec):
    """(x_aft, x_fwd) of the dodger, boat frame from the transom."""
    x_a = deck.xk0 - float(spec["overhang"])
    return x_a, x_a + float(spec["length"])


def dodger_shell(deck, spec, lod=0):
    """{"outer": (P, mats), "inner": P} grids of the dodger's shell: stations from aft to forward, each a superellipse
    arch from the starboard foot over the crown to the port foot on the coachroof's top. The crown keeps `height`
    over the aft 40 %, then sinks forward along a half cosine to a low lip (the lines on the top pass under it); the
    feet stand on the top at `width` of its half-width; aft of the coachroof's face the canopy overhangs at the top's
    height."""
    x_a, x_f = dodger_frame(deck, spec)
    H, frac, lip, t = float(spec["height"]), float(spec["width"]), float(spec["lip"]), float(spec["thickness"])
    nu, nt = (15, 17) if lod == 0 else (9, 11)
    u = np.linspace(0.0, 1.0, nu)
    th = np.pi * (1.0 - np.linspace(0.0, 1.0, nt))         # starboard foot (y < 0) to port foot
    x = x_a + u * (x_f - x_a)
    xb = np.maximum(x, deck.xk0 + 0.03)
    B = frac * deck.yk_roof(xb) * (1.0 - 0.10 * u ** 2)
    v = np.clip((u - 0.4) / 0.6, 0.0, 1.0)
    Hu = lip + (H - lip) * 0.5 * (1.0 + np.cos(np.pi * v))

    def surf(B, Hu, sink):
        c, sn = np.cos(th), np.sin(th)
        Y = B[:, None] * _spow(c, 2.0 / N_SHELL)[None, :]
        X = np.broadcast_to(xb[:, None], Y.shape)
        Zb = deck.cabin_z(X, Y)
        Z = Zb + Hu[:, None] * np.abs(sn)[None, :] ** (2.0 / N_SHELL) - sink
        return np.stack([np.broadcast_to(x[:, None], Y.shape), Y, Z], -1)

    outer = surf(B, Hu, 0.006)
    inner = surf(B - t, np.maximum(Hu - t, 0.4 * lip), 0.006)
    # dark glazing: a windscreen over the sloping front and a side window each side
    mats = np.full((nu - 1, nt - 1), "gelcoat", dtype=object)
    iu = lambda a: int(round(a * (nu - 1)))
    jt = lambda a: int(round(a * (nt - 1)))
    mats[iu(0.55):iu(0.86), jt(0.32):jt(0.68)] = "glass"
    for j0, j1 in ((jt(0.14), jt(0.27)), (jt(0.73), jt(0.86))):
        mats[iu(0.12):iu(0.50), j0:j1] = "glass"
    return {"outer": outer, "inner": inner, "mats": mats, "crown": (x, Hu, B)}


def dodger(deck, spec, s, lod=0):
    """The hard dodger (spray shelter) over the companionway: a rounded composite canopy open at the back, its outer
    shell in gelcoat with dark windows, the inner shell, and bands closing the aft edge, the front lip and the feet.
    With `solar_panel` a flat panel on its crown."""
    sh = dodger_shell(deck, spec, lod)
    O, I_, mats = sh["outer"], sh["inner"], sh["mats"]
    nu, nt = O.shape[:2]
    p = Part()
    uv = lambda P: np.stack([P[..., 0], np.cumsum(np.r_[0.0, np.linalg.norm(np.diff(P[nu // 2], axis=0), axis=1)])
                             [None, :].repeat(nu, 0)], -1)
    g = grid(O, uv(O), keep_degenerate=True)
    cell = np.tile(np.arange((nu - 1) * (nt - 1)), 2)
    flat = mats.reshape(-1)[cell]
    for m in ("gelcoat", "glass"):
        keep = flat == m
        if keep.any():
            p.add(m, _subset(g, keep), tag="dodger")
    p.add("gelcoat", grid(I_, uv(I_)).flipped(), tag="dodger")
    # aft edge (facing aft), front lip (facing forward), feet (facing down)
    p.add("gelcoat", grid(np.stack([I_[0], O[0]])), tag="dodger")
    p.add("gelcoat", grid(np.stack([O[-1], I_[-1]])), tag="dodger")
    p.add("gelcoat", grid(np.stack([I_[:, 0], O[:, 0]], 1)), tag="dodger")
    p.add("gelcoat", grid(np.stack([O[:, -1], I_[:, -1]], 1)), tag="dodger")
    p.attach("dodger", "deck")
    if spec.get("solar_panel"):
        x, Hu, B = sh["crown"]
        i = int(np.argmin(np.abs(np.linspace(0, 1, nu) - 0.2)))
        xc = float(x[i])
        zc = float(O[i, nt // 2, 2])
        lx, ly = 0.42 * (x[-1] - x[0]), 0.9 * float(B[i])
        p.add("metal", superellipsoid_box((lx, ly, 0.014), 0.12, 8, 4, center=[xc, 0.0, zc + 0.002]),
              tag="solar_panel")
        p.add("glass", superellipsoid_box((lx - 0.03, ly - 0.03, 0.006), 0.08, 6, 3, center=[xc, 0.0, zc + 0.008]),
              tag="solar_cells")
        p.attach("solar_panel", "dodger")
        p.attach("solar_cells", "solar_panel")
    return p


def foot_braces(deck, xs, s):
    """Foot braces across the cockpit floor: a carbon bar wall to wall, 6 cm over the floor, on a low post at the
    middle."""
    p = Part()
    r = 0.018 * s ** 0.5
    for k, x in enumerate(xs):
        zf = float(deck.floor_z(x))
        yc = float(deck.yc(x))
        z = zf + 0.06
        p.add("carbon", tube(np.array([[x, -yc - 0.005, z], [x, yc + 0.005, z]]), r, 10), tag=f"foot_brace_{k}")
        p.attach(f"foot_brace_{k}", "deck")
        p.add("carbon", superellipsoid_box((0.05, 0.05, 0.07), 0.3, 6, 4, center=[x, 0.0, zf + 0.03]),
              tag=f"foot_brace_post_{k}")
        p.attach(f"foot_brace_post_{k}", "deck")
    return p


def liferaft(deck, s, side=-1):
    """A liferaft canister in its cradle on the cockpit floor at the transom, lying fore and aft against the side
    wall: a white two-shell canister with a belly seam and two straps."""
    p = Part()
    R, Lc = 0.17 * s ** 0.5, 0.62 * s ** 0.5
    x0 = deck.xc0 + 0.12
    xm = x0 + 0.5 * Lc
    yc = float(deck.yc(xm))
    y = side * (yc - R - 0.03)
    zf = float(deck.floor_z(xm))
    z = zf + R + 0.03
    prof = [(0, -0.5 * Lc), (0.9 * R, -0.5 * Lc), (R, -0.45 * Lc), (R, 0.45 * Lc), (0.9 * R, 0.5 * Lc), (0, 0.5 * Lc)]
    can = Part().add("gelcoat", revolve([(a, b) for a, b in prof], 16, sharp=(1, 4)))
    M = translate([xm, y, z]) @ rot_axis([0, 1.0, 0], np.pi / 2)
    p.extend(can, M, tag="liferaft")
    for dx in (-0.25, 0.25):
        ring = Part().add("rubber", revolve([(R + 0.003, -0.02), (R + 0.003, 0.02)], 16, cap_ends=False))
        p.extend(ring, translate([xm + dx * Lc, y, z]) @ rot_axis([0, 1.0, 0], np.pi / 2), tag="liferaft_strap")
    p.add("metal", superellipsoid_box((0.75 * Lc, 1.2 * R, 0.035), 0.3, 8, 4, center=[xm, y, zf + 0.017]),
          tag="liferaft_cradle")
    p.attach("liferaft_cradle", "deck")
    p.attach("liferaft", "liferaft_cradle")
    p.attach("liferaft_strap", "liferaft")
    return p


def autopilot_ram(deck, x0, s, side=1):
    """A tiller autopilot's ram stowed in its brackets on the cockpit's side wall, by the helm: motor housing and
    push rod, fore and aft, 0.25 m over the floor."""
    p = Part()
    Lr = 0.62 * s ** 0.5
    r = 0.028 * s ** 0.5
    xm = x0 + 0.5 * Lr
    yc = float(deck.yc(xm))
    y = side * (yc - r - 0.035)
    z = float(deck.floor_z(xm)) + 0.25
    p.add("carbon", tube(np.array([[x0, y, z], [x0 + 0.62 * Lr, y, z]]), r, 12), tag="autopilot")
    p.add("metal", tube(np.array([[x0 + 0.6 * Lr, y, z], [x0 + Lr, y, z]]), 0.42 * r, 8), tag="autopilot")
    p.add("carbon", superellipsoid_box((0.16 * Lr, 2.6 * r, 2.4 * r), 0.35, 8, 4, center=[x0 + 0.12 * Lr, y, z + 0.4 * r]),
          tag="autopilot")
    for k, xb in enumerate((x0 + 0.25 * Lr, x0 + 0.85 * Lr)):
        w = r + 0.04
        ycb = float(deck.yc(xb))            # the wall where this bracket stands
        w += abs(ycb - yc)
        p.add("metal", superellipsoid_box((0.035, w + 0.01, 0.03), 0.3, 6, 4,
                                          center=[xb, side * (ycb - 0.5 * w + 0.004), z - 0.6 * r]),
              tag=f"autopilot_bracket_{k}")
        p.attach(f"autopilot_bracket_{k}", "deck")
    p.attach("autopilot", "autopilot_bracket_0", "autopilot_bracket_1")
    return p
