"""Boat-class file: loading, defaults, validation and derived quantities.

The class file is JSON (format "windmark-boat-class", version 1). Lengths in m, masses in kg, areas in m^2 and
angles in degrees (keys ending in ``_deg``); the VPP converts to radians internally. See README.md for the field
reference. Missing optional fields get documented estimates; every estimate is reported in ``Boat.notes`` so a
generated table always says what was assumed.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from typing import List, Optional

from .constants import DEG, RHO_WATER

LEAD_DENSITY = 11300.0   # kg/m^3, bulb material when only the bulb mass is given
FORMAT = "windmark-boat-class"

SAIL_TYPES = ("main", "jib", "genoa", "staysail", "code0", "spinnaker", "gennaker")
HEADSAIL_TYPES = SAIL_TYPES[1:]
DOWNWIND_TYPES = ("spinnaker", "gennaker")

# Sheeting limits per sail type (deg from the centreline): chord as far in and out as a typical deck layout allows
# (outboard leads for headsails off the wind, spreaders for the boom, pole or clew for the spinnakers).
SHEET_LIMITS_DEG = {
    "main": (0.0, 74.0),
    "jib": (8.0, 68.0),
    "genoa": (9.0, 68.0),
    "staysail": (10.0, 60.0),
    "code0": (12.0, 55.0),
    "spinnaker": (20.0, 79.0),
    "gennaker": (15.0, 50.0),
}


class ClassFileError(ValueError):
    pass


@dataclass
class HullBody:
    """One buoyant body (the main hull, or one float of a multihull)."""
    name: str
    lwl: float
    bwl: float
    draft: float              # canoe-body draft below its design waterline, m
    cp: float                 # prismatic coefficient
    cm: float                 # midship section coefficient (0.5 V, 0.785 ellipse, 1 box)
    freeboard: float          # at the maximum section, m
    beam_deck: float          # maximum beam at the sheer, m
    rocker: float             # rise of the keel line at the aft end of the waterline, m
    transom_width: float      # waterline beam at the aft end of the waterline, m
    max_section: float        # position of the maximum section, fraction of LWL from the bow
    y: float = 0.0            # lateral offset of the body centreline (starboard +), m
    z: float = 0.0            # height of the body's design waterline above the static waterline, m
    x: float = 0.0            # longitudinal offset of the body's bow from the main bow (aft +), m


@dataclass
class Foil:
    """Keel fin, daggerboard or rudder, below the hull."""
    span: float               # wetted span below the canoe body, m
    chord: float              # mean chord, m
    thickness: float = 0.12   # thickness/chord
    taper: float = 0.7        # tip chord / root chord
    count: int = 1            # foils in the water at once

    @property
    def area(self) -> float:
        return self.span * self.chord * self.count

    @property
    def wetted(self) -> float:
        # both faces plus the curvature allowance of a foil section (Hoerner)
        return 2.0 * 1.02 * self.area


@dataclass
class Bulb:
    mass: float
    length: float
    diameter: float
    depth: float              # centroid depth below the static waterline, m


@dataclass
class Sail:
    id: str
    type: str
    area: float
    ce_height: float          # centre of effort above the waterline, m
    sheet_min: float          # rad
    sheet_max: float          # rad


@dataclass
class Boat:
    id: str
    name: str
    kind: str                 # monohull | catamaran | trimaran
    loa: float
    beam_max: float
    bodies: List[HullBody]
    main_index: Optional[int]  # index of the central hull (monohull, trimaran), None for a catamaran
    mass_boat: float          # sailing mass without crew, kg
    mass_crew: float
    crew_arm: float           # crew CG lateral distance from the centreline when sitting out, m
    vcg: float                # CG height of the boat without crew above the static waterline, m
    keel: Optional[Foil]
    bulb: Optional[Bulb]
    rudder: Optional[Foil]
    draft_total: float        # deepest point below the static waterline, m
    rig_I: float
    rig_J: float
    rig_P: float
    rig_E: float
    mast_height: float        # masthead above the waterline, m
    boom_height: float        # boom above the waterline, m
    mast_chord: float
    freeboard: float          # average freeboard used for windage and the rig's mirror effect, m
    sails: List[Sail]
    heel_max: float           # rad, the VPP never settles beyond this
    notes: List[str] = field(default_factory=list)
    source: dict = field(default_factory=dict)

    @property
    def mass(self) -> float:
        return self.mass_boat + self.mass_crew

    @property
    def volume(self) -> float:
        return self.mass / RHO_WATER

    def sail(self, sid: str) -> Sail:
        for s in self.sails:
            if s.id == sid:
                return s
        raise KeyError(sid)

    @property
    def main_sail(self) -> Optional[Sail]:
        for s in self.sails:
            if s.type == "main":
                return s
        return None

    def configs(self):
        """Sail combinations the game can hoist: the mainsail alone and the mainsail with each headsail."""
        main = self.main_sail
        out = []
        if main is not None:
            out.append((main.id, [main]))
            for s in self.sails:
                if s.type in HEADSAIL_TYPES:
                    out.append((s.id, [main, s]))
        else:
            for s in self.sails:
                out.append((s.id, [s]))
        return out


def _req(d: dict, key: str, where: str) -> float:
    if key not in d or d[key] is None:
        raise ClassFileError(f"{where}.{key} is required")
    v = d[key]
    if not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ClassFileError(f"{where}.{key} must be a number")
    return float(v)


def _opt(d: dict, key: str, default, notes: List[str], note: str):
    v = d.get(key)
    if v is None:
        if note:
            notes.append(note.format(v=default))
        return default
    return float(v)


def _positive(name: str, v: float):
    if not v > 0:
        raise ClassFileError(f"{name} must be positive (got {v})")


def superellipse_cm(n: float) -> float:
    """Area coefficient of the half-section |y/b|^n + |z/t|^n <= 1 (z <= 0) relative to the b x t box."""
    return math.gamma(1 + 1 / n) ** 2 / math.gamma(1 + 2 / n)


def _body(d: dict, where: str, notes: List[str], name: str, volume: Optional[float]) -> HullBody:
    lwl = _req(d, "lwl", where)
    bwl = _req(d, "bwl", where)
    cp = _req(d, "cp", where)
    for k, v in (("lwl", lwl), ("bwl", bwl)):
        _positive(f"{where}.{k}", v)
    if not 0.45 <= cp <= 0.80:
        raise ClassFileError(f"{where}.cp = {cp} outside 0.45..0.80")
    draft = d.get("draft_canoe", d.get("draft"))
    shape = d.get("section_shape")
    if volume is not None and draft is not None:
        draft = float(draft)
        cm = volume / (cp * lwl * bwl * draft)
        if shape is not None and abs(float(shape) - cm) > 0.05:
            notes.append(f"{where}: section_shape {shape} disagrees with displacement/draft (Cm {cm:.3f}); "
                         "the displacement wins")
    elif volume is not None and shape is not None:
        cm = float(shape)
        draft = volume / (cp * lwl * bwl * cm)
        notes.append(f"{where}: canoe draft {draft:.3f} m from displacement and section_shape")
    elif volume is None and draft is not None:
        draft = float(draft)
        cm = float(shape) if shape is not None else 0.72
        if shape is None:
            notes.append(f"{where}: section_shape defaulted to 0.72")
    else:
        raise ClassFileError(f"{where}: needs draft_canoe or section_shape")
    if not 0.45 <= cm <= 0.98:
        raise ClassFileError(f"{where}: midship coefficient {cm:.3f} outside 0.45..0.98; check displacement, "
                             "draft_canoe, bwl and cp")
    freeboard = _opt(d, "freeboard", 0.09 * lwl, notes, f"{where}.freeboard defaulted to {{v:.2f}} m")
    beam_deck = _opt(d, "beam_max", bwl * 1.15, notes, f"{where}.beam_max defaulted to {{v:.2f}} m")
    rocker = _opt(d, "rocker", 0.6 * draft, notes, f"{where}.rocker defaulted to {{v:.3f}} m")
    rocker = min(max(rocker, 0.0), draft)
    transom = _opt(d, "transom_width", 0.45 * bwl, notes, f"{where}.transom_width defaulted to {{v:.2f}} m")
    transom = min(max(transom, 0.0), 0.95 * bwl)
    xm = _opt(d, "max_section", 0.46, notes, "")
    return HullBody(name=name, lwl=lwl, bwl=bwl, draft=draft, cp=cp, cm=cm, freeboard=freeboard,
                    beam_deck=max(beam_deck, bwl), rocker=rocker, transom_width=transom,
                    max_section=min(max(xm, 0.35), 0.75))


def _foil(d: Optional[dict], where: str, canoe_draft: float, notes: List[str]) -> Optional[Foil]:
    if not d:
        return None
    depth = _req(d, "depth", where)
    chord = _req(d, "chord", where)
    span = depth - 0.85 * canoe_draft if "span" not in d else float(d["span"])
    if span <= 0.05:
        raise ClassFileError(f"{where}: depth {depth} leaves no span below the canoe body")
    return Foil(span=span, chord=chord, thickness=float(d.get("thickness", 0.12)),
                taper=float(d.get("taper", 0.7)), count=int(d.get("count", 1)))


def load(path: str) -> Boat:
    with open(path) as f:
        raw = json.load(f)
    return from_dict(raw)


def from_dict(raw: dict) -> Boat:
    if raw.get("format") != FORMAT:
        raise ClassFileError(f"not a {FORMAT} file")
    if int(raw.get("version", 0)) != 1:
        raise ClassFileError("unsupported class file version")
    notes: List[str] = []
    h = raw.get("hull") or {}
    kind = h.get("type", "monohull")
    if kind not in ("monohull", "catamaran", "trimaran"):
        raise ClassFileError(f"hull.type {kind!r} unknown")
    crew = raw.get("crew") or {}
    mass_boat = _req(h, "displacement", "hull")
    _positive("hull.displacement", mass_boat)
    mass_crew = float(crew.get("mass", 0.0))
    volume = (mass_boat + mass_crew) / RHO_WATER

    bodies: List[HullBody] = []
    main_index: Optional[int] = None
    if kind == "catamaran":
        spacing = _req(h, "hull_spacing", "hull")
        half = _body(h, "hull", notes, "hull", volume / 2.0)
        for sgn, nm in ((-1.0, "hull_port"), (1.0, "hull_stbd")):
            b = HullBody(**{**half.__dict__, "name": nm, "y": sgn * spacing / 2.0})
            bodies.append(b)
    else:
        main = _body(h, "hull", notes, "main", volume)
        bodies.append(main)
        main_index = 0
        if kind == "trimaran":
            fl = h.get("floats") or {}
            where = "hull.floats"
            spacing = _req(fl, "spacing", where)
            fb = _body(fl, where, notes, "float", None)
            clearance = float(fl.get("clearance", 0.0))
            x_off = float(fl.get("x_offset", (main.lwl - fb.lwl) * 0.6))
            for sgn, nm in ((-1.0, "float_port"), (1.0, "float_stbd")):
                bodies.append(HullBody(**{**fb.__dict__, "name": nm, "y": sgn * spacing,
                                          "z": clearance + fb.draft, "x": x_off}))

    main_body = bodies[main_index] if main_index is not None else bodies[0]
    loa = _opt(h, "loa", main_body.lwl * 1.1, notes, "hull.loa defaulted to {v:.2f} m")
    beam_max = _opt(h, "beam_max", main_body.beam_deck, notes, "")
    if kind != "monohull":
        beam_max = max(beam_max, max(abs(b.y) + b.beam_deck / 2 for b in bodies) * 2)

    kd = raw.get("keel")
    keel = _foil(kd, "keel", main_body.draft, notes)
    bulb = None
    if kd and kd.get("bulb_mass"):
        bm = float(kd["bulb_mass"])
        bl = float(kd.get("bulb_length", 0.0)) or None
        bd = float(kd.get("bulb_diameter", 0.0)) or None
        vol = bm / LEAD_DENSITY
        if bl is None and bd is None:
            bd = (6 * vol / (math.pi * 5.0)) ** (1 / 3)   # prolate spheroid with length/diameter 5
            bl = 5.0 * bd
            notes.append(f"keel bulb {bl:.2f} x {bd:.2f} m estimated from its mass")
        elif bd is None:
            bd = math.sqrt(6 * vol / (math.pi * bl))
        elif bl is None:
            bl = 6 * vol / (math.pi * bd * bd)
        depth = _req(kd, "depth", "keel")
        bulb = Bulb(mass=bm, length=bl, diameter=bd, depth=depth - 0.5 * bd)
    if kind == "monohull" and keel is None:
        raise ClassFileError("a monohull needs a keel")
    if kind != "monohull" and keel is None:
        bd = raw.get("boards")
        keel = _foil(bd, "boards", main_body.draft, notes)
        if keel is None:
            raise ClassFileError("a multihull needs boards (or a keel)")
    rudder = _foil(raw.get("rudder"), "rudder", main_body.draft * 0.5, notes)
    if rudder is None:
        raise ClassFileError("rudder is required")
    draft_total = float(kd["depth"]) if kd else float((raw.get("boards") or {})["depth"])

    r = raw.get("rig") or {}
    I = _req(r, "I", "rig")
    J = _req(r, "J", "rig")
    P = _req(r, "P", "rig")
    E = _req(r, "E", "rig")
    freeboard = main_body.freeboard
    mast_height = _opt(r, "mast_height", I * 1.12 + freeboard, notes, "rig.mast_height defaulted to {v:.2f} m")
    boom_height = _opt(r, "boom_height", max(mast_height - P - 0.03 * mast_height, freeboard + 0.5), notes,
                       "rig.boom_height defaulted to {v:.2f} m")
    mast_chord = _opt(r, "mast_chord", 0.012 * mast_height + 0.03, notes, "")

    sails: List[Sail] = []
    seen = set()
    for i, s in enumerate(raw.get("sails") or []):
        where = f"sails[{i}]"
        t = s.get("type")
        if t not in SAIL_TYPES:
            raise ClassFileError(f"{where}.type {t!r} not one of {SAIL_TYPES}")
        sid = s.get("id") or t
        if sid in seen:
            raise ClassFileError(f"{where}: duplicate sail id {sid!r}")
        seen.add(sid)
        area = s.get("area")
        if area is None:
            if t == "main":
                area = 0.5 * P * E * 1.25
            elif t in ("jib", "genoa", "staysail"):
                area = 0.5 * I * J * {"jib": 1.0, "genoa": 1.45, "staysail": 0.7}[t]
            elif t == "code0":
                area = 0.5 * I * J * 2.4
            else:
                area = 1.15 * 0.95 * math.hypot(I, J) * 1.8 * J
            notes.append(f"{where}: area estimated {area:.1f} m^2")
        area = float(area)
        _positive(f"{where}.area", area)
        if s.get("ce_height") is not None:
            ce = float(s["ce_height"])
        elif t == "main":
            ce = boom_height + 0.39 * P             # ORC/Hazen centre of effort heights
        elif t in ("jib", "genoa", "staysail"):
            ce = freeboard + 0.39 * I * (0.85 if t == "staysail" else 1.0)
        elif t == "code0":
            ce = freeboard + 0.45 * I
        else:
            ce = freeboard + 0.59 * I
        lo, hi = SHEET_LIMITS_DEG[t]
        lo = float(s.get("sheet_min_deg", lo))
        hi = float(s.get("sheet_max_deg", hi))
        sails.append(Sail(id=sid, type=t, area=area, ce_height=ce, sheet_min=lo * DEG, sheet_max=hi * DEG))
    if not sails:
        raise ClassFileError("sails: at least one sail is required")

    crew_arm = _opt(crew, "arm", max(beam_max / 2.0 - 0.35, 0.3) if kind == "monohull" else beam_max * 0.3,
                    notes, "crew.arm defaulted to {v:.2f} m" if mass_crew > 0 else "")

    md = raw.get("mass") or {}
    if md.get("vcg") is not None:
        vcg = float(md["vcg"])
    else:
        rig_mass = float(md.get("rig", 0.06 * mass_boat))
        m_rest = mass_boat - rig_mass - (bulb.mass if bulb else 0.0)
        fin_mass = 0.0
        if kind == "monohull":
            fin_mass = float(md.get("fin", min(0.25 * m_rest, keel.area * keel.chord * keel.thickness * 0.68
                                               * 7850.0)))
            m_rest -= fin_mass
        if m_rest <= 0:
            raise ClassFileError("displacement is lighter than the bulb and rig")
        z_rest = 0.25 * freeboard
        num = rig_mass * 0.45 * mast_height + m_rest * z_rest
        if bulb:
            num -= bulb.mass * bulb.depth
        num -= fin_mass * (main_body.draft + 0.45 * keel.span)
        vcg = num / mass_boat
        notes.append(f"VCG estimated {vcg:+.2f} m (bulb, fin, rig {rig_mass:.0f} kg at 0.45 mast height, "
                     "rest at 0.25 freeboard)")
    heel_max = float(raw.get("heel_max_deg", 32.0 if kind == "monohull" else 15.0)) * DEG

    return Boat(id=str(raw.get("id", "boat")), name=str(raw.get("name", raw.get("id", "boat"))), kind=kind,
                loa=loa, beam_max=beam_max, bodies=bodies, main_index=main_index, mass_boat=mass_boat,
                mass_crew=mass_crew, crew_arm=crew_arm, vcg=vcg, keel=keel, bulb=bulb, rudder=rudder,
                draft_total=draft_total, rig_I=I, rig_J=J, rig_P=P, rig_E=E, mast_height=mast_height,
                boom_height=boom_height, mast_chord=mast_chord, freeboard=freeboard, sails=sails,
                heel_max=heel_max, notes=notes, source=raw)
