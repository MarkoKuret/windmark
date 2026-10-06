"""Physics sidecar: hydrostatics, waterline, buoyancy samples, collision shapes, rig and sail data, and the
geometric inputs the performance file takes from the generator.

Positions are in the boat body frame (docs/specs/conventions.md 3): x forward, y port, z up, origin on the
centreline in the DWL plane at mid LWL. The GLB uses the same origin in glTF axes: (X, Y, Z) = (y, z, x).
"""
import numpy as np

from .classfile import RHO_SEA, RHO_LEAD
from .gltf import GLBWriter
from .mesh import Geom, Part, grid, mesh_volume, mesh_area, split_by_plane_z, normalize, merge, box, foil


def to_body(P, ox):
    """Internal frame (x from the transom) to the body frame."""
    P = np.asarray(P, dtype=np.float64)
    return P - np.array([ox, 0.0, 0.0])


def _r(v, n=4):
    if isinstance(v, (list, tuple, np.ndarray)):
        return [_r(x, n) for x in np.asarray(v).tolist()]
    return round(float(v), n)


def hydrostatics(boat):
    h, hull, app, cls = boat.hydro, boat.hull, boat.app, boat.cls
    ox = boat.origin_x()
    vols = app.volumes()
    V_c = h["V"]
    V_app = sum(v for v, _ in vols.values())
    V = V_c + V_app
    lcb_x = (V_c * h["lcb_x"] + sum(v * c[0] for v, c in vols.values())) / V
    # vertical centre: canoe from the section moments, appendages from their mesh centroids
    vcb = (V_c * h["vcb_z"] + sum(v * c[2] for v, c in vols.values())) / V
    disp_target = cls["hull"]["dwl_mass"]
    disp = V * RHO_SEA
    lwl, bwl, Tc = h["lwl"], h["bwl"], h["Tc"]
    Amax = h["Amax"]
    Cp = V_c / (Amax * hull.Lwl)
    Cm = Amax / (bwl * Tc)
    Cb = V_c / (hull.Lwl * bwl * Tc)
    Cwp = h["Aw"] / (hull.Lwl * bwl)
    # wetted surface of the canoe body and the appendages
    wet = 0.0
    for g in boat.skin:
        below, _ = split_by_plane_z(g, 0.0)
        wet += mesh_area(below) if below is not None else 0.0
    wet_app = mesh_area(app.fin_geom) + mesh_area(app.bulb)
    rb, _ = split_by_plane_z(app.rudder_geom, 0.0)
    wet_app += mesh_area(rb) if rb is not None else 0.0
    crew = cls["crew"]["weight"]
    tpc = RHO_SEA * h["Aw"] * 0.01
    A_fin, A_rud = app.lateral_areas()
    return {
        "rho_water": RHO_SEA,
        "dwl_mass_kg": disp_target,
        "dwl_mass_note": "class displacement (no crew) plus crew weight: the DWL floats the boat in sailing trim",
        "displaced_mass_generated_kg": _r(disp, 1),
        "displacement_error_pct": _r(100 * (disp - disp_target) / disp_target, 3),
        "volume_m3": {"total": _r(V), "canoe_body": _r(V_c), "fin": _r(vols["fin"][0]), "bulb": _r(vols["bulb"][0]),
                      "rudder_immersed": _r(vols["rudder"][0])},
        "lcb_x": _r(lcb_x - ox), "lcb_pct_lwl_aft_of_fwd_end": _r(100 * (hull.x_fwl - lcb_x) / hull.Lwl, 2),
        "lcb_x_canoe_body": _r(h["lcb_x"] - ox),
        "vcb_z": _r(vcb),
        "lwl_m": _r(lwl, 3), "bwl_m": _r(bwl, 3), "canoe_draft_m": _r(Tc, 3),
        "draft_total_m": _r(app.draft, 3),
        "waterplane_area_m2": _r(h["Aw"], 3), "lcf_x": _r(h["lcf_x"] - ox),
        "bm_transverse_m": _r(h["It"] / V), "bm_longitudinal_m": _r(h["Il"] / V),
        "kb_below_dwl_m": _r(-vcb),
        "prismatic": _r(Cp), "midship": _r(Cm), "block": _r(Cb), "waterplane": _r(Cwp),
        "max_section_area_m2": _r(Amax), "max_section_x": _r(h["x_Amax"] - ox),
        "midship_requested": cls["hull"]["midship_target"],
        "wetted_surface_m2": {"canoe_body": _r(wet, 3), "appendages": _r(wet_app, 3), "total": _r(wet + wet_app, 3)},
        "kg_per_cm_immersion": _r(tpc, 1),
        "crew_weight_kg": crew, "lightship_rise_m": _r(crew / (RHO_SEA * h["Aw"]), 4),
        "bulb": {"mass_kg": app.bulb_mass, "lead_volume_m3": _r(app.bulb_mass / RHO_LEAD),
                 "mesh_volume_m3": _r(vols["bulb"][0]),
                 "ballast_ratio": _r(app.bulb_mass / cls["hull"]["displacement"], 3)},
        "lateral_area_m2": {"fin": _r(A_fin, 3), "rudder": _r(A_rud, 3)},
        "fit": {"section_exponent": _r(hull.n, 3), "entrance_fullness": _r(hull.phi_f, 3),
                "run_fullness": _r(hull.phi_a, 3), "bilge_half_breadth": _r(hull.W, 3),
                "at_limit": bool(getattr(hull, "n_clamped", False))},
    }


def waterline(boat, n=64):
    hull = boat.hull
    ox = boat.origin_x()
    xs = np.linspace(hull.x_awl, hull.x_fwl, n)
    ys = np.array([hull.half_breadth_at(x, 0.0) for x in xs])
    pts = np.stack([xs, ys, np.zeros_like(xs)], -1)
    port = to_body(pts, ox)
    stbd = to_body(pts * [1, -1, 1], ox)
    return {"port": _r(port, 4), "starboard": _r(stbd, 4)}


def buoyancy_samples(boat, step_x=4, step_g=3):
    """Surface samples on the hull skin up to the sheer (both sides): cell centre, outward normal and area, from a
    coarsened copy of the skin grid. Summing pressure over the immersed samples gives buoyancy and the righting
    and trimming moments at any heel, trim and sinkage."""
    hull = boat.hull
    ox = boat.origin_x()
    G = hull.skin_grid[::step_x]
    cols = list(range(0, G.shape[1], step_g))
    if cols[-1] != G.shape[1] - 1:
        cols.append(G.shape[1] - 1)
    G = G[:, cols]
    a, b, c, d = G[:-1, :-1], G[1:, :-1], G[1:, 1:], G[:-1, 1:]
    ctr = 0.25 * (a + b + c + d)
    cr = np.cross(c - a, d - b)
    area = 0.5 * np.linalg.norm(cr, axis=-1)
    n = normalize(cr)
    # outward: away from the centreline at the cell's height
    inward = np.stack([np.zeros_like(ctr[..., 0]), -ctr[..., 1], np.zeros_like(ctr[..., 2])], -1)
    flip = np.sum(n * inward, -1) > 0
    n[flip] *= -1
    ok = area > 1e-6
    P, N, A = ctr[ok], n[ok], area[ok]
    P = np.vstack([P, P * [1, -1, 1]])
    N = np.vstack([N, N * [1, -1, 1]])
    A = np.concatenate([A, A])
    # divergence theorem with F = (0, 0, z): V = sum of z n_z dA over the immersed skin
    V_check = np.sum(A * N[:, 2] * P[:, 2] * (P[:, 2] < 0))
    return {"count": int(len(P)), "position": _r(to_body(P, ox), 4),
            "normal": _r(N, 4), "area_m2": _r(A, 5),
            "canoe_volume_check_m3": _r(V_check, 3)}


def collision(boat, n_st=14, n_g=4):
    """Low-poly closed hull (canoe body plus deck plane), keel fin box, bulb and rudder boxes."""
    hull, deck, app = boat.hull, boat.deck, boat.app
    xs = np.linspace(0.0, hull.L, n_st)
    rings = []
    for x in xs:
        y, z, _ = hull.station(x, n_g + 1, n_g)
        half = np.stack([y, z], -1)
        # port side keel -> sheer, then across the deck crown to starboard sheer -> keel
        crown = [0.0, float(deck.deck_z(x, 0.0))]
        # starboard sheer down to the keel, up the port side, across the deck crown
        loop = np.vstack([half[:0:-1] * [-1, 1], half, [crown]])
        rings.append(np.c_[np.full(len(loop), x), loop])
    R = np.array(rings)   # (n_st, m, 3)
    m = R.shape[1]
    g = grid(R, close_v=True)
    # end caps: transom and bow fans (orientation fixed below by the volume sign)
    caps = []
    for ring, sgn in ((R[0], 1), (R[-1], -1)):
        Pc = np.vstack([ring.mean(0), ring])
        I = np.array([[0, 1 + (i + 1) % m, 1 + i] if sgn > 0 else [0, 1 + i, 1 + (i + 1) % m] for i in range(m)])
        caps.append(Geom(Pc, I))
    col = merge([g] + caps)
    V, _ = mesh_volume(col)
    if V < 0:
        col = col.flipped()
    parts = {"hull": col}
    # keel fin as a box in its mid plane, bulb and rudder as boxes
    le_r, le_t = app.fin_le_root, app.fin_le_tip
    fin_pts = np.array([le_r, le_t, le_t - [app.fin_ct, 0, 0], le_r - [app.fin_cr, 0, 0]])
    th = app.fin_tc * app.fin_cr
    parts["fin"] = _slab(fin_pts, th)
    if app.has_bulb:
        b0 = app.bulb.P.min(0)
        b1 = app.bulb.P.max(0)
        parts["bulb"] = box(b1 - b0, 0.5 * (b0 + b1))
    rp = np.array([app.rud_le_root, app.rud_le_tip, app.rud_le_tip - [app.rud_ct, 0, 0],
                   app.rud_le_root - [app.rud_cr, 0, 0]])
    parts["rudder"] = _slab(rp, app.rud_tc * app.rud_cr)
    return parts


def _slab(quad, t):
    """Closed thin slab from a quad in the x-z plane, thickness t across y."""
    top = quad + [0, t / 2, 0]
    bot = quad - [0, t / 2, 0]
    P = np.vstack([top, bot])
    I = [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6]]
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
        I += [[a, b + 4, b], [a, a + 4, b + 4]]
    g = Geom(P, I)
    if mesh_volume(g)[0] < 0:
        g = g.flipped()
    return g


def write_collision_glb(boat, parts, path):
    """Collision shapes as a separate GLB. Node names carry Godot's import suffix for convex collision shapes."""
    w = GLBWriter(boat.origin_x(), textures=False)   # invisible shapes: no texture set
    kids = []
    for name, g in parts.items():
        p = Part()
        p.add("rubber", g)
        kids.append(w.add_mesh(f"{name}-convcolonly", p))
    w.write(path, boat.cls["id"] + "_collision", kids)


def rig_data(boat):
    rig, ox = boat.rig, boat.origin_x()
    g = lambda p: _r(to_body(np.asarray(p, dtype=np.float64)[None], ox)[0], 4)
    d = {
        "mast_step": g([rig.x_mast, 0, rig.z_step]), "masthead": g([rig.x_mast, 0, rig.z_top]),
        "hounds": g([rig.x_mast + rig.chord / 2, 0, rig.z_hounds]),
        "forestay_tack": g([rig.x_tack, 0, rig.z_tack]),
        "boom_pivot": g(rig.gooseneck), "boom_axis": [0.0, 0.0, 1.0], "boom_length": _r(rig.boom_len, 3),
        "bowsprit_end": g(rig.sprit_end) if rig.sprit > 0 else None,
        "rudder_stock": g(boat.app.rud_stock), "rudder_axis": [0.0, 0.0, 1.0],
        "mast_chord": _r(rig.chord, 3), "mast_width": _r(rig.width, 3),
        "spreaders": [g(t) for _, t in rig.spreaders],
    }
    if rig.pole_flown:
        # pivot on the mast axis at the heel height; at rest the pole points forward and its end is the tack
        d["pole_pivot"] = g(rig.pole_pivot)
        d["pole_axis"] = [0.0, 0.0, 1.0]
        d["pole_length"] = _r(rig.pole_len, 3)
        d["pole_end"] = g(rig.pole_end)
    if "wheel" in boat.pivots:
        d["wheel_hub"] = g(boat.pivots["wheel"])
        d["wheel_axis"] = [1.0, 0.0, 0.0]
    # sheet leads for the engine to draw the sheets of the set sails (starboard side; mirror y for port):
    # headsails clew -> car block -> primary winch, flying sails clew -> quarter block -> winch
    from .running import sheet_leads
    d["sheet_leads"] = {k: {"lead": g(v["lead"]), "winch": g(v["winch"]), "drum_diameter": _r(v["drum"], 3)}
                        for k, v in sheet_leads(boat).items()}
    return d


def sail_data(boat):
    ox = boat.origin_x()
    out = {}
    for name, s in boat.sails.items():
        nv, nu = s.P.shape[:2]
        target = next(sp["area"] for sp in boat.cls["sails"] if sp["id"] == name)
        corners = {k: {"row": int(i), "col": int(j), "position": _r(to_body(s.P[i, j][None], ox)[0], 4)}
                   for k, (i, j) in s.corners.items()}
        out[name] = {"node": "sail_" + name, "type": s.type, "grid_rows": nv, "grid_cols": nu,
                     "vertex_order": "in the GLB file: row-major from the foot (row 0) to the head, luff (col 0) "
                                     "to leech; port layer first, then starboard layer. Engines may re-index on "
                                     "import: the stable key is uv1 = (col / (cols - 1), 1 - row / (rows - 1)), "
                                     "u mirrored on the starboard layer, plus the layer side (port layer on +y)",
                     "area_m2": _r(s.area, 3), "area_target_m2": target, "centroid": _r(to_body(s.centroid()[None], ox)[0], 4),
                     "corners": corners, "look": s.look(boat.hull.L)}
        if s.measure:
            out[name]["rule"] = {"luff": _r(s.measure["luff"], 3), "leech": _r(s.measure["leech"], 3),
                                 "foot": _r(s.measure["foot"], 3), "mid_girth": _r(s.measure["mid_girth"], 3),
                                 "area_m2": _r(s.measure["rule_area"], 2)}
    return out


def collision_outline(boat):
    """Hull outline for the core's 2-D collisions, by the reference construction of docs/specs/collisions.md 2.1
    (the generated sheer uses the same plan-view rule). Counter-clockwise in (x, y), body frame."""
    h = boat.cls["hull"]
    xs_, xb = h["transom_x"], h["stem_x"]
    L, B, T, sm = xb - xs_, h["beam_max"], h["transom_width"], h["max_beam_station"]
    f = h["bow_fineness"]

    def b(s):
        if s <= sm:
            return T / 2 + (B / 2 - T / 2) * (1 - (1 - s / sm) ** 2)
        u = (s - sm) / (1 - sm)
        return B / 2 * (1 - u ** f)
    ss = sorted({0.0, 0.15, 0.3, sm, 0.6, 0.75, 0.87, 0.95})
    stbd = [(xs_ + s * L, -b(s)) for s in ss]
    port = [(xs_ + s * L, b(s)) for s in ss[::-1]]
    poly = stbd + [(xb, 0.0)] + port
    # checks the core applies at load: strictly convex, counter-clockwise, containing the origin
    P = np.array(poly)
    e = np.roll(P, -1, 0) - P
    cr = e[:, 0] * np.roll(e, -1, 0)[:, 1] - e[:, 1] * np.roll(e, -1, 0)[:, 0]
    ok = bool((cr > 0).all())
    return {"outline": _r(P, 4), "vertices": len(P), "convex_ccw": ok}


def cockpit_data(boat):
    """The cockpit well for the sea renderer's dry mask (water_render.md 4.8): from the aft end x0 forward over len,
    the half width, floor and rim (deck at the cockpit edge) at the aft end, middle and forward end, body frame."""
    d, ox = boat.deck, boat.origin_x()
    xs = [d.xc0, 0.5 * (d.xc0 + d.xc1), d.xc1]
    w = [float(d.yc(x)) for x in xs]
    return {
        "x0": _r(d.xc0 - ox, 4), "len": _r(d.xc1 - d.xc0, 4), "open_transom": d.open_transom,
        "half_width": _r(w, 4),
        "floor_z": _r([float(d.floor_z(x)) for x in xs], 4),
        "rim_z": _r([float(d.deck_z(x, wi)) for x, wi in zip(xs, w)], 4),
    }


def heel_attitude(boat, heels_deg=tuple(range(0, 36, 5)), samples=None):
    """How the free-floating hull sits when heeled (docs/specs/boat.md 5.6): at each heel the rise (m, + up) and the
    trim (rad, + bow up) that keep the immersed volume and the longitudinal centre of buoyancy of the upright DWL,
    from the skin samples (the weight, its line of action and the displacement unchanged). Heel to port; the hull is
    symmetric. Up to 35 deg, below where the sheer immerses and the open skin stops holding water."""
    b = samples or buoyancy_samples(boat)
    P = np.asarray(b["position"], dtype=np.float64)
    N = np.asarray(b["normal"], dtype=np.float64)
    A = np.asarray(b["area_m2"], dtype=np.float64)

    def rot(phi, th):
        cp, sp, ct, st = np.cos(phi), np.sin(phi), np.cos(th), np.sin(th)
        rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
        ry = np.array([[ct, 0, -st], [0, 1, 0], [st, 0, ct]])
        return ry @ rx

    def buoy(phi, th, rise):
        R = rot(phi, th)
        W = P @ R.T
        W[:, 2] += rise
        fz = -np.clip(-W[:, 2], 0, None) * A * (N @ R.T)[:, 2]     # vertical pressure force per rho g
        V = fz.sum()
        return V, (fz * W[:, 0]).sum() / V

    V0, x0 = buoy(0.0, 0.0, 0.0)

    def res(phi, v):
        V, xb = buoy(phi, v[0], v[1])
        return np.array([V / V0 - 1.0, xb - (rot(phi, v[0]) @ np.array([x0, 0.0, 0.0]))[0]])

    rise, trim = [], []
    v = np.zeros(2)
    for d in heels_deg:
        phi = -np.radians(d)
        for _ in range(40):
            f = res(phi, v)
            if np.max(np.abs(f)) < 1e-9:
                break
            J = np.empty((2, 2))
            for k in range(2):
                dv = v.copy()
                dv[k] += 1e-6
                J[:, k] = (res(phi, dv) - f) / 1e-6
            v = v - np.linalg.solve(J, f)
        trim.append(float(v[0]))
        rise.append(float(v[1]))
    return {"heel": _r(np.radians(heels_deg), 5), "rise": _r(rise, 4), "trim": _r(trim, 5)}


def perf_inputs(boat):
    """Geometric values the performance file takes from the generator (data_format.md 4.2, sea.md 5.1,
    wind_shadow.md 2), for the VPP to copy."""
    h = boat.hydro
    cls, rig, hull = boat.cls, boat.rig, boat.hull
    ox = boat.origin_x()
    lwl, bwl = float(h["lwl"]), float(h["bwl"])
    # hull points on the actual waterline, in the order of sea.md 5.1
    def yw(xb):
        return hull.half_breadth_at(xb + ox, 0.0)
    pts = [(0.45 * lwl, 0.0), (-0.45 * lwl, 0.0)]
    for xb in (0.25 * lwl, 0.0, -0.25 * lwl):
        y = 0.7 * yw(xb)   # same share of the local waterline half-breadth as the reference 0.35 bwl
        pts += [(xb, y), (xb, -y)]
    main = next(s for s in boat.sails.values() if s.type == "main")
    heads = [s for s in boat.sails.values() if s.type in ("jib", "genoa")]
    plan = [main] + heads[:1]
    A = sum(s.area for s in plan)
    ce = sum(s.centroid() * s.area for s in plan) / A
    spin = [s for s in boat.sails.values() if s.type.startswith("spinnaker")]
    spin_foot = float(np.linalg.norm(spin[0].P[0, -1] - spin[0].P[0, 0])) if spin else 0.0
    return {
        "loa": _r(hull.L, 4), "lwl": _r(lwl, 4), "bwl": _r(bwl, 4),
        "hull_points": _r(pts, 4),
        "collision": collision_outline(boat),
        "wind_shadow": {"height": _r(rig.z_top, 3), "ce_x": _r(ce[0] - ox, 3), "stern_x": _r(-ox, 3),
                        "chord": _r(cls["rig"]["J"] + cls["rig"]["E"], 3), "width_min": _r(1.5 * cls["rig"]["E"], 3),
                        "width_spinnaker": _r(spin_foot + cls["rig"]["E"], 3) if spin else None,
                        "turb_width": _r(cls["hull"]["beam_max"], 3)},
        "sail_plan_ce": _r(to_body(ce[None], ox)[0], 3),
        "heel_attitude": heel_attitude(boat),
    }
