"""Boat-class file loading (`windmark.boatclass/1`, docs/specs/data_format.md section 3).

The class file is in SI units with angles in radians and positions in the boat body frame (x forward, y port,
z up, origin on the centreline at the DWL and mid LWL). Generator-only settings live in the `visual` block
(documented in tools/boatgen/README.md); every one of them has a default scaled from the base fields.

`resolve()` turns the file into the flat internal configuration the generator modules use. Internally x runs
forward from the transom (x = 0) to the stem head (x = LOA); body x = internal x + transom_x.
"""
import copy
import json
import math

RHO_SEA = 1025.0     # kg/m^3, sea water
RHO_LEAD = 11340.0   # kg/m^3

SCHEMA = "windmark.boatclass/1"

# ratio of transverse to vertical superellipse exponent of the bottom sections (see hull.py)
SECTION_RATIO = {"v": 0.62, "round": 1.0, "u": 1.45, "flat": 2.0, "chined": 1.3}

SAIL_TYPES = ("main", "jib", "genoa", "code_zero", "spinnaker_sym", "spinnaker_asym")

# per-sail look parameters of docs/specs/sail_visuals.md section 4 (visual.sails.<id>.look)
LOOK_KEYS = ("fill_gain", "fill_curve", "flutter_amp", "flutter_rate", "flutter_rate_max", "twist_top", "depth",
             "tack_line_max", "furl_radius")


class ClassFileError(ValueError):
    pass


def _deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def _req(block, name, path):
    if name not in block:
        raise ClassFileError(f"{path}.{name} is required")
    return block[name]


def load(path):
    with open(path) as f:
        raw = json.load(f)
    return resolve(raw, path)


def resolve(raw, path="<class>"):
    if raw.get("schema", "").split("/")[0] != SCHEMA.split("/")[0] or not raw.get("schema", "").endswith("/1"):
        raise ClassFileError(f"{path}: schema must be {SCHEMA}")
    vis = raw.get("visual", {}) or {}
    c = {"id": _req(raw, "id", "$"), "name": raw.get("name", raw["id"]), "version": raw.get("version", 1),
         "raw": raw}

    # ---------------------------------------------------------------- hull
    H = _req(raw, "hull", "$")
    for k in ("loa", "lwl", "beam_max", "bwl", "draft_canoe", "displacement", "prismatic", "section_shape",
              "rocker", "freeboard", "transom_width", "stem_x", "transom_x"):
        _req(H, k, "$.hull")
    stem_x, transom_x = float(H["stem_x"]), float(H["transom_x"])
    L = stem_x - transom_x
    if abs(L - float(H["loa"])) > 0.01:
        raise ClassFileError(f"$.hull: stem_x - transom_x = {L:.3f} m but loa = {H['loa']} m")
    lwl = float(H["lwl"])
    if stem_x < lwl / 2 - 1e-6 or transom_x > -lwl / 2 + 1e-6:
        raise ClassFileError("$.hull: the waterline (+-lwl/2) must lie between transom_x and stem_x")
    sec = H["section_shape"]
    stype = sec.get("type", "round")
    if stype not in SECTION_RATIO:
        raise ClassFileError(f"$.hull.section_shape.type must be one of {list(SECTION_RATIO)}")
    ratio = SECTION_RATIO[stype]
    deadrise = float(sec.get("deadrise", 0.2))
    if stype in ("v", "chined"):
        # more deadrise -> more V-shaped bottom (lower transverse exponent)
        ratio = max(0.5, min(2.0, ratio * (0.2 / max(deadrise, 0.05)) ** 0.5))
    fb = H["freeboard"]
    crew = _req(raw, "crew", "$")
    crew_w = float(_req(crew, "weight", "$.crew"))
    tc = float(H["draft_canoe"])
    vh = vis.get("hull", {}) or {}
    hull = {
        "loa": L, "lwl": lwl, "beam_max": float(H["beam_max"]), "bwl": float(H["bwl"]), "canoe_draft": tc,
        "displacement": float(H["displacement"]),
        # the DWL is the flotation plane in sailing trim with the crew aboard
        "dwl_mass": float(H["displacement"]) + crew_w,
        "prismatic": float(H["prismatic"]), "section_type": stype, "section_ratio": ratio,
        "midship_target": sec.get("midship_coefficient"),
        "rocker_fwd": float(H["rocker"]["fwd"]), "rocker_aft": float(H["rocker"]["aft"]),
        "freeboard_bow": float(fb["bow"]), "freeboard": float(fb["mid"]), "freeboard_stern": float(fb["stern"]),
        "transom_width": float(H["transom_width"]), "stem_x": stem_x, "transom_x": transom_x,
        "max_beam_station": float(H.get("max_beam_station", 0.45)),
        "bow_fineness": float(H.get("bow_fineness", 1.8)),
        "bow_overhang": stem_x - lwl / 2, "stern_overhang": -lwl / 2 - transom_x,
        # LCB target as a fraction of LWL aft of the forward waterline end
        "lcb": (lwl / 2 - float(H["lcb_x"])) / lwl if "lcb_x" in H else float(vh.get("lcb_fraction", 0.535)),
        "chine": ({"start": float(vh.get("chine_start", 0.42)), "sharpness": 1.0} if stype == "chined" else None),
    }
    for r in ("rocker_fwd", "rocker_aft"):
        if not 0.0 <= hull[r] <= tc + 1e-9:
            raise ClassFileError(f"$.hull.rocker: {r[7:]} must be between 0 and draft_canoe")
    if hull["rocker_aft"] < tc - 1e-3 and hull["stern_overhang"] > 0.01:
        raise ClassFileError("$.hull.rocker.aft < draft_canoe means an immersed transom: transom_x must then be "
                             "-lwl/2")
    hull_vis_defaults = {
        "max_bwl_pos": 0.55,           # fraction of LWL aft of the forward end: widest waterline
        "max_draft_pos": 0.55,         # fraction of LWL aft of the forward end: deepest canoe body
        "keel_line_exponent": 2.6,     # keel-line fullness: 2 = parabolic, larger = flatter bottom
        "transom_bottom_width": 0.90 * hull["transom_width"],
        "bilge_height": float(sec["chine_height"]) if stype == "chined" and "chine_height" in sec
        else 0.18 * hull["freeboard"],  # height of the bilge turn (widest point of the bottom) above DWL
        "topside_flare": 1.7,          # topside curve exponent: 1 = straight flare, 2 = strong
        "deck_camber": 0.022,          # deck crown as a fraction of the local beam
        "sheer_spring": 0.0,           # extra sag of the sheer at mid length
        "boot_top": [0.04, 0.10],      # antifouling up to [0], boot-top stripe up to [1] above the DWL
        "stem_radius": 0.04,           # forefoot rounding
    }
    hull.update(_deep_merge(hull_vis_defaults, {k: v for k, v in vh.items() if k in hull_vis_defaults}))
    c["hull"] = hull
    to_int = lambda xb: float(xb) - transom_x

    # ---------------------------------------------------------------- deck (visual only)
    deck_defaults = {
        "cockpit": {"length": 0.30 * L, "width": 0.62, "depth": 0.42 * (L / 12) ** 0.5, "open_transom": True,
                    "aft_deck": 0.0},
        "cabin": {"length": 0.28 * L, "height": 0.26 * (L / 12) ** 0.6, "width": 0.58, "side_slope": 0.22,
                  "windows": True},
        "nonslip_margin": 0.05,
        "toe_rail": 0.035 * (L / 12) ** 0.4,
        "lifelines": L >= 9.0,
        "steering": None,
        "hatches": 1 if L < 9.0 else 2,
    }
    deck = _deep_merge(deck_defaults, vis.get("deck", {}))
    if deck["cabin"] is not None and deck["cabin"].get("length", 1) <= 0:
        deck["cabin"] = None
    c["deck"] = deck

    # ---------------------------------------------------------------- keel
    K = _req(raw, "keel", "$")
    for k in ("depth", "chord_root", "chord_tip", "x", "fin_mass", "bulb_mass"):
        _req(K, k, "$.keel")
    vk = vis.get("keel", {}) or {}
    ktype = K.get("type", "fin_bulb")
    bulb = None
    if ktype == "fin_bulb" and float(K["bulb_mass"]) > 0:
        bulb = {"mass": float(K["bulb_mass"]), "length": float(K.get("bulb_length", 0.24 * lwl)),
                "diameter": K.get("bulb_diameter"), "flat": float(vk.get("bulb_flat", 1.25))}
    c["keel"] = {"type": ktype, "depth": float(K["depth"]), "chord_root": float(K["chord_root"]),
                 "chord_tip": float(K["chord_tip"]), "thickness": float(K.get("thickness", 0.10)),
                 "sweep": float(K.get("sweep", 0.1)), "x_qc": to_int(K["x"]), "fin_mass": float(K["fin_mass"]),
                 "bulb": bulb}

    # ---------------------------------------------------------------- rudder
    R = _req(raw, "rudder", "$")
    for k in ("depth", "chord_root", "chord_tip", "x"):
        _req(R, k, "$.rudder")
    vr = vis.get("rudder", {}) or {}
    c["rudder"] = {"type": R.get("type", "spade"), "depth": float(R["depth"]), "chord_root": float(R["chord_root"]),
                   "chord_tip": float(R["chord_tip"]), "thickness": float(R.get("thickness", 0.11)),
                   "x_stock": to_int(R["x"]), "max_angle": float(R.get("max_angle", 0.61)),
                   "sweep": float(vr.get("sweep", 0.10))}

    # ---------------------------------------------------------------- rig
    G = _req(raw, "rig", "$")
    for k in ("I", "J", "P", "E", "mast_height", "mast_x"):
        _req(G, k, "$.rig")
    vg = vis.get("rig", {}) or {}
    mh = float(G["mast_height"])
    rig = {"I": float(G["I"]), "J": float(G["J"]), "P": float(G["P"]), "E": float(G["E"]), "mast_height": mh,
           "mast_x": to_int(G["mast_x"]), "boom_height": G.get("boom_height"),
           "fractional": float(G.get("fractional", 0.8)), "bowsprit": float(G.get("bowsprit", 0.0)),
           "pole": float(G.get("pole", 0.0))}
    rig_vis_defaults = {
        "mast_chord": 0.0105 * mh + 0.02,   # fore-aft size of the mast section
        "mast_width": 0.62,                 # section width / chord
        "spreaders": 2 if mh > 13 else 1,
        "spreader_sweep": 0.35,             # rad
        "backstay": rig["fractional"] > 0.93,
    }
    rig.update(_deep_merge(rig_vis_defaults, {k: v for k, v in vg.items() if k in rig_vis_defaults}))
    c["rig"] = rig

    # ---------------------------------------------------------------- sails
    S = _req(raw, "sails", "$")
    vs = vis.get("sails", {}) or {}
    sails, ids = [], set()
    for i, s in enumerate(S):
        sid, st = _req(s, "id", f"$.sails[{i}]"), _req(s, "type", f"$.sails[{i}]")
        if st not in SAIL_TYPES:
            raise ClassFileError(f"$.sails[{i}].type must be one of {SAIL_TYPES}")
        if sid in ids:
            raise ClassFileError(f"$.sails[{i}].id {sid!r} is not unique")
        ids.add(sid)
        v = vs.get(sid, {}) or {}
        look = v.get("look", {}) or {}
        if not isinstance(look, dict):
            raise ClassFileError(f"$.visual.sails.{sid}.look must be an object")
        for k, x in look.items():
            if k not in LOOK_KEYS:
                raise ClassFileError(f"$.visual.sails.{sid}.look.{k} is not a look parameter ({', '.join(LOOK_KEYS)})")
            if isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) or x < 0:
                raise ClassFileError(f"$.visual.sails.{sid}.look.{k} must be a finite number >= 0")
        sails.append({"id": sid, "type": st, "area": float(_req(s, "area", f"$.sails[{i}]")),
                      "luff": s.get("luff"), "leech": s.get("leech"), "foot": s.get("foot"),
                      "tack_x": None if s.get("tack_x") is None else to_int(s["tack_x"]),
                      "furling": bool(s.get("furling", False)), "visual": v})
    if sum(1 for s in sails if s["type"] == "main") != 1:
        raise ClassFileError("$.sails needs exactly one sail of type main")
    c["sails"] = sails
    c["crew"] = {"count": int(_req(crew, "count", "$.crew")), "weight": crew_w}
    if c["deck"]["steering"] is None:
        c["deck"]["steering"] = "wheel" if L >= 11.0 else "tiller"
    return c
