"""Boat-class file loading: JSON with SI units, missing optional fields filled from rules of thumb.

The field list, units and defaults are documented in tools/boatgen/README.md. Every default here is a rule of
thumb scaled from the base fields, so a class file only needs the base list to produce a boat.
"""
import copy
import json

RHO_SEA = 1025.0     # kg/m^3, sea water
RHO_LEAD = 11340.0   # kg/m^3

SECTION_SHAPES = {   # ratio of transverse to vertical superellipse exponent (see hull.py)
    "v": 0.62, "round": 1.0, "u": 1.45, "flat": 2.0,
}


def _deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def load(path):
    with open(path) as f:
        raw = json.load(f)
    return resolve(raw)


def resolve(raw):
    c = copy.deepcopy(raw)
    h = c["hull"]
    for k in ("loa", "lwl", "beam_max", "bwl", "canoe_draft", "displacement", "prismatic", "freeboard",
              "transom_width"):
        if k not in h:
            raise ValueError(f"hull.{k} is required")
    L, B = h["loa"], h["beam_max"]
    fb = h["freeboard"]
    hull_defaults = {
        "section_shape": "round",
        "rocker": 0.5,
        "freeboard_bow": fb * 1.28,
        "freeboard_stern": fb * 0.86,
        "max_beam_pos": 0.60,          # fraction of LOA aft of the stem head
        "max_bwl_pos": 0.55,           # fraction of LWL aft of the forward waterline end
        "max_draft_pos": 0.55,         # canoe-body deepest point, fraction of LWL aft of the forward end
        "bow_overhang": 0.35 * (L - h["lwl"]),
        "transom_bottom_width": 0.90 * h["transom_width"],
        "bilge_height": 0.18 * fb,     # height of the bilge turn (widest point of the bottom) above DWL
        "topside_flare": 1.7,          # exponent of the topside curve; 1 = straight flare, 2 = strong
        "deck_camber": 0.022,          # deck crown as a fraction of the local beam
        "sheer_spring": 0.0,           # extra sag of the sheer at mid length (m)
        "chine": None,                 # {"start": 0.45, "sharpness": 1.0} or null
        "boot_top": [0.04, 0.10],      # antifouling up to [0], boot-top stripe to [1], m above DWL
        "stem_radius": 0.04,           # forefoot rounding (m)
    }
    c["hull"] = _deep_merge(hull_defaults, h)
    h = c["hull"]
    if isinstance(h["freeboard"], dict):
        raise ValueError("hull.freeboard is the mid-length freeboard in metres; use freeboard_bow/stern")

    deck_defaults = {
        "cockpit": {"length": 0.30 * L, "width": 0.62, "depth": 0.42 * (L / 12) ** 0.5, "open_transom": True,
                    "aft_deck": 0.0},
        "cabin": {"length": 0.28 * L, "height": 0.26 * (L / 12) ** 0.6, "width": 0.58, "side_slope": 0.22,
                  "windows": True},
        "nonslip_margin": 0.05,
        "toe_rail": 0.035 * (L / 12) ** 0.4,
        "lifelines": L >= 9.0,
        "steering": "wheel" if L >= 11.0 else "tiller",
        "hatches": 1 if L < 9.0 else 2,
    }
    c["deck"] = _deep_merge(deck_defaults, c.get("deck", {}))
    if c["deck"]["cabin"] is not None and c["deck"]["cabin"].get("length", 1) <= 0:
        c["deck"]["cabin"] = None

    k = c.get("keel", {})
    if "depth" not in k or "chord" not in k:
        raise ValueError("keel.depth and keel.chord are required")
    keel_defaults = {
        "chord_tip_ratio": 0.72,
        "thickness": 0.11,             # t/c of the fin
        "sweep_deg": 6.0,              # leading-edge sweep
        "position": 0.46,              # fin quarter-chord at the root, fraction of LWL aft of the forward end
        "bulb": {"mass": 0.40 * h["displacement"], "length": 0.24 * h["lwl"], "diameter": None,
                 "flat": 1.25},
    }
    c["keel"] = _deep_merge(keel_defaults, k)
    r = c.get("rudder", {})
    rudder_defaults = {
        "depth": 0.75 * c["keel"]["depth"],   # tip below DWL
        "chord": 0.36 * c["keel"]["chord"] + 0.08,
        "chord_tip_ratio": 0.62,
        "thickness": 0.12,
        "sweep_deg": 7.0,
        "position": 0.085 * L,         # stock distance forward of the transom
    }
    c["rudder"] = _deep_merge(rudder_defaults, r)

    rig = c.get("rig", {})
    for kk in ("I", "J", "P", "E", "mast_height"):
        if kk not in rig:
            raise ValueError(f"rig.{kk} is required")
    rig_defaults = {
        "boom_height": None,           # gooseneck above deck; default from mast_height - P
        "mast_chord": 0.011 * rig["mast_height"] + 0.02,
        "mast_width": 0.62,            # width/chord of the mast section
        "spreaders": 2 if rig["mast_height"] > 12 else 1,
        "spreader_sweep_deg": 20.0,
        "backstay": rig["I"] / rig["mast_height"] > 0.93,
        "bowsprit": 0.0,
        "tack_setback": 0.06 * (L / 12),   # forestay tack aft of the stem head
    }
    c["rig"] = _deep_merge(rig_defaults, rig)
    if c["rig"]["boom_height"] is None:
        c["rig"]["boom_height"] = max(0.55, c["rig"]["mast_height"] - c["rig"]["P"] - 0.25)

    s = c.get("sails", {})
    sail_defaults = {
        "main": {"area": None, "head_width": 0.28, "roach": None},
        "jib": {"area": None, "clew_height": 0.35 * (L / 12) ** 0.5, "luff_frac": 0.96},
        "code0": None,
        "spinnaker": None,
    }
    c["sails"] = _deep_merge(sail_defaults, s)
    crew_defaults = {"weight": 85.0 * max(2, round(L * 0.55)), "count": max(2, round(L * 0.55))}
    c["crew"] = _deep_merge(crew_defaults, c.get("crew", {}))

    sh = h["section_shape"]
    if isinstance(sh, str):
        if sh not in SECTION_SHAPES:
            raise ValueError(f"hull.section_shape must be one of {list(SECTION_SHAPES)} or a number")
        h["section_ratio"] = SECTION_SHAPES[sh]
    else:
        h["section_ratio"] = float(sh)
    return c
