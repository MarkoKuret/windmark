"""Boat-class file (`windmark.boatclass/1`, docs/specs/data_format.md section 3): loading, defaults, validation.

SI units and radians throughout, body frame x forward / y port / z up with the origin at mid-waterline on the
design waterline. Optional fields get the spec default or a documented VPP estimate; every estimate is reported
in ``Boat.notes`` so a generated file always says what was assumed.

VPP extensions (not yet in the spec; readers ignore unknown keys):

* ``hull.type``: ``"monohull"`` (default) | ``"trimaran"`` | ``"catamaran"``;
* ``hull.floats`` (trimaran): ``lwl``, ``bwl``, ``draft``, ``prismatic``, ``section_shape``, ``freeboard``,
  ``beam_max``, ``transom_width``, ``rocker``, ``spacing`` (float centreline from the boat centreline),
  ``clearance`` (float keel above the DWL at rest), ``x`` (body x of the float's mid-waterline);
* ``hull.hull_spacing`` (catamaran): centreline distance of the two hulls;
* ``boards``: daggerboard of a multihull, the ``keel`` fields without the bulb, plus ``count`` in the water;
* ``rudder.count``: rudders in the water at once [1];
* ``vpp.max_heel``: heel the equilibrium may not exceed [0.56 rad monohull, 0.28 multihull].
"""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass, field
from typing import List, Optional

from .constants import RHO_WATER

LEAD_DENSITY = 11300.0   # kg/m^3, bulb material when only the bulb mass is given
SCHEMA = "windmark.boatclass/1"

SAIL_TYPES = ("main", "jib", "genoa", "code_zero", "spinnaker_sym", "spinnaker_asym")
FRONT_TYPES = SAIL_TYPES[1:]
SPINNAKER_TYPES = ("spinnaker_sym", "spinnaker_asym")

# Sheeting limits per sail type (rad from the aft centreline): chord as far in and out as a typical deck layout
# allows (outboard leads for headsails off the wind, the spreaders for the boom, pole or clew for the kites).
SHEET_LIMITS = {
    "main": (0.0, math.radians(74.0)),
    "jib": (math.radians(8.0), math.radians(68.0)),
    "genoa": (math.radians(9.0), math.radians(68.0)),
    "code_zero": (math.radians(12.0), math.radians(55.0)),
    "spinnaker_sym": (math.radians(20.0), math.radians(79.0)),
    "spinnaker_asym": (math.radians(15.0), math.radians(50.0)),
}


class ClassFileError(ValueError):
    pass


@dataclass
class HullBody:
    """One buoyant body (the main hull, or one float of a multihull)."""
    name: str
    lwl: float
    bwl: float
    draft: float              # canoe-body depth below its design waterline, m
    cp: float                 # prismatic coefficient the loft is built to
    cm: float                 # midship section coefficient (0.5 V, 0.785 ellipse, 1 box)
    freeboard: tuple          # sheer height above the DWL at bow, mid, stern, m
    beam_deck: float          # maximum beam at the sheer, m
    rocker_fwd: float         # keel line above its lowest point at the forward end of the waterline, m
    rocker_aft: float         # the same at the aft end, m
    transom_wl: float         # waterline beam at the aft end of the waterline, m
    max_section: float        # position of the maximum section, fraction of LWL from the forward end
    y: float = 0.0            # lateral offset of the body centreline (starboard +, VPP-internal), m
    z: float = 0.0            # height of the body's design waterline above the static waterline, m
    x: float = 0.0            # longitudinal offset of the body's forward waterline end from the main one (aft +)
    lcb: Optional[float] = None   # target centre of buoyancy, fraction of LWL from the forward end

    @property
    def freeboard_mid(self) -> float:
        return self.freeboard[1]


@dataclass
class Foil:
    """Keel fin, daggerboard or rudder below the hull."""
    span: float               # wetted span below the canoe body, m
    chord: float              # mean chord, m
    thickness: float = 0.10   # thickness/chord
    taper: float = 0.7        # tip chord / root chord
    count: int = 1            # foils in the water at once
    x: float = 0.0            # body x of the quarter chord

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
    ce_x: float               # body x of the centre of effort, m
    sheet_min: float          # rad
    sheet_max: float          # rad
    foot: float               # m
    furling: bool = False
    handling: dict = field(default_factory=dict)

    @property
    def coeff_type(self) -> str:
        """Key of the aerodynamic coefficient set (sails.COEFFS)."""
        return {"code_zero": "code0", "spinnaker_sym": "spinnaker", "spinnaker_asym": "gennaker"}.get(self.type,
                                                                                                         self.type)


@dataclass
class Boat:
    id: str
    name: str
    version: int
    kind: str                 # monohull | catamaran | trimaran
    loa: float
    lwl: float
    bwl: float
    beam_max: float
    stem_x: float
    transom_x: float
    transom_width: float      # at the sheer
    max_beam_station: float   # fraction of LOA from the transom
    bodies: List[HullBody]
    main_index: Optional[int]  # index of the central hull (monohull, trimaran), None for a catamaran
    mass_boat: float          # sailing mass without crew, kg
    mass_crew: float
    crew_count: int
    crew_arm: float           # crew CG lateral distance from the centreline when hiked, m
    vcg: float                # CG height of the boat without crew above the DWL, m
    rig_mass: float
    keel: Foil
    bulb: Optional[Bulb]
    rudder: Foil
    rudder_max: float
    draft_total: float        # deepest point below the DWL, m
    rig_I: float
    rig_J: float
    rig_P: float
    rig_E: float
    mast_height: float        # masthead above the DWL, m
    mast_x: float
    boom_height: float        # boom above the DWL, m
    mast_chord: float
    bowsprit: float
    pole: float
    freeboard: float          # mid-length freeboard (windage, rig mirror effect), m
    app_volume: float         # displaced volume of keel fin, bulb and rudder, m^3
    app_depth: float          # depth of its centroid below the DWL, m
    sails: List[Sail]
    heel_max: float           # rad, the equilibrium never settles beyond this
    start: dict = field(default_factory=dict)
    handling: dict = field(default_factory=dict)
    notes: List[str] = field(default_factory=list)
    source: dict = field(default_factory=dict)
    sha256: str = ""

    @property
    def mass(self) -> float:
        return self.mass_boat + self.mass_crew

    @property
    def volume(self) -> float:
        return self.mass / RHO_WATER

    @property
    def main_sail(self) -> Sail:
        return next(s for s in self.sails if s.type == "main")

    def configs(self):
        """(front sail id or None, [sails]) for the main alone and the main with each front sail."""
        main = self.main_sail
        out = [(None, [main])]
        for s in self.sails:
            if s.type != "main":
                out.append((s.id, [main, s]))
        return out


# -------------------------------------------------------------------------------------------------------------

def _num(d: dict, key: str, where: str, default=None, required: bool = False, positive: bool = False):
    v = d.get(key) if isinstance(d, dict) else None
    if v is None:
        if required:
            raise ClassFileError(f"{where}.{key}: required")
        return default
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ClassFileError(f"{where}.{key}: must be a number")
    if positive and not v > 0:
        raise ClassFileError(f"{where}.{key}: must be positive")
    return float(v)


def superellipse_cm(n: float) -> float:
    """Area coefficient of the half-section |y/b|^n + |z/t|^n <= 1 (z <= 0) relative to the b x t box."""
    return math.gamma(1 + 1 / n) ** 2 / math.gamma(1 + 2 / n)


def _section_cm(d: dict, where: str) -> Optional[float]:
    s = d.get("section_shape")
    if s is None:
        return None
    if isinstance(s, (int, float)):
        return float(s)
    if not isinstance(s, dict):
        raise ClassFileError(f"{where}.section_shape: must be an object")
    t = s.get("type", "round")
    if t not in ("round", "u", "v", "flat", "chined"):
        raise ClassFileError(f"{where}.section_shape.type: unknown {t!r}")
    return _num(s, "midship_coefficient", f"{where}.section_shape", required=True, positive=True)


def _pair(d: dict, key: str, where: str, names, default):
    v = d.get(key)
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return tuple(float(v) for _ in names)
    if not isinstance(v, dict):
        raise ClassFileError(f"{where}.{key}: must be an object")
    return tuple(_num(v, n, f"{where}.{key}", required=True) for n in names)


def _body(d: dict, where: str, notes: List[str], name: str, volume: Optional[float]) -> HullBody:
    lwl = _num(d, "lwl", where, required=True, positive=True)
    bwl = _num(d, "bwl", where, required=True, positive=True)
    cp = _num(d, "prismatic", where, required=True, positive=True)
    if not 0.45 <= cp <= 0.80:
        raise ClassFileError(f"{where}.prismatic: {cp} outside 0.45..0.80")
    draft = _num(d, "draft_canoe", where, _num(d, "draft", where), positive=True)
    cm_decl = _section_cm(d, where)
    if volume is not None:
        if draft is None and cm_decl is None:
            raise ClassFileError(f"{where}: needs draft_canoe")
        if draft is None:
            draft = volume / (cp * lwl * bwl * cm_decl)
            notes.append(f"{where}: canoe draft {draft:.3f} m from the displacement and section_shape")
        cm = volume / (cp * lwl * bwl * draft)
        if cm_decl is not None and abs(cm_decl - cm) > 0.03:
            notes.append(f"{where}: midship coefficient {cm:.3f} from displacement, draft, bwl and prismatic "
                         f"(hint {cm_decl:.3f})")
    else:
        if draft is None:
            raise ClassFileError(f"{where}: needs draft")
        cm = cm_decl if cm_decl is not None else 0.70
    if not 0.45 <= cm <= 0.98:
        raise ClassFileError(f"{where}: midship coefficient {cm:.3f} outside 0.45..0.98; check displacement, "
                             "draft_canoe, bwl and prismatic")
    fb = _pair(d, "freeboard", where, ("bow", "mid", "stern"), None)
    if fb is None:
        f = 0.09 * lwl
        fb = (1.3 * f, f, 0.85 * f)
        notes.append(f"{where}.freeboard estimated {f:.2f} m at mid-length")
    beam = _num(d, "beam_max", where, bwl * 1.15, positive=True)
    rk = _pair(d, "rocker", where, ("fwd", "aft"), None)
    if rk is None:
        rk = (draft, 0.6 * draft)
        notes.append(f"{where}.rocker estimated (fwd {rk[0]:.2f}, aft {rk[1]:.2f}) m")
    rf = min(max(rk[0], 0.0), draft)
    ra = min(max(rk[1], 0.0), draft)
    tw_sheer = _num(d, "transom_width", where, 0.5 * beam)
    # waterline beam at the aft end: the sheer width scaled to the waterline, narrower as the run lifts clear
    twl = tw_sheer * (bwl / beam) * math.sqrt(max(1.0 - ra / draft, 0.04))
    twl = min(max(twl, 0.0), 0.95 * bwl)
    return HullBody(name=name, lwl=lwl, bwl=bwl, draft=draft, cp=cp, cm=cm, freeboard=fb, beam_deck=max(beam, bwl),
                    rocker_fwd=rf, rocker_aft=ra, transom_wl=twl, max_section=0.46)


def _foil(d: dict, where: str, canoe_draft: float, thickness: float) -> Foil:
    depth = _num(d, "depth", where, required=True, positive=True)
    cr = _num(d, "chord_root", where, _num(d, "chord", where))
    if cr is None:
        raise ClassFileError(f"{where}.chord_root: required")
    ct = _num(d, "chord_tip", where, cr)
    span = depth - 0.85 * canoe_draft
    if span <= 0.05:
        raise ClassFileError(f"{where}.depth: {depth} leaves no span below the canoe body")
    return Foil(span=span, chord=0.5 * (cr + ct), thickness=_num(d, "thickness", where, thickness),
                taper=ct / cr, count=int(d.get("count", 1)), x=_num(d, "x", where, 0.0))


def load(path: str) -> Boat:
    with open(path, "rb") as f:
        data = f.read()
    try:
        raw = json.loads(data)
    except json.JSONDecodeError as e:
        raise ClassFileError(f"{path}: not valid JSON ({e})")
    b = from_dict(raw)
    b.sha256 = hashlib.sha256(data).hexdigest()
    return b


def from_dict(raw: dict) -> Boat:
    if raw.get("schema") != SCHEMA:
        raise ClassFileError(f"schema: expected {SCHEMA!r}")
    notes: List[str] = []
    cid = raw.get("id")
    if not isinstance(cid, str) or not cid or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_" for c in cid):
        raise ClassFileError("id: lowercase [a-z0-9_] required")
    h = raw.get("hull")
    if not isinstance(h, dict):
        raise ClassFileError("hull: required")
    kind = h.get("type", "monohull")
    if kind not in ("monohull", "catamaran", "trimaran"):
        raise ClassFileError(f"hull.type: unknown {kind!r}")
    crew = raw.get("crew") or {}
    mass_boat = _num(h, "displacement", "hull", required=True, positive=True)
    mass_crew = _num(crew, "weight", "crew", 0.0)
    crew_count = int(crew.get("count", 0))
    volume = (mass_boat + mass_crew) / RHO_WATER

    # appendage buoyancy (fin, bulb, rudder): the canoe body displaces the rest
    app_v, app_m = 0.0, 0.0
    if kind == "monohull":
        tc0 = _num(h, "draft_canoe", "hull", 0.0) or 0.0
        for key, ft in (("keel", 0.10), ("rudder", 0.11)):
            d = raw.get(key) or {}
            if not isinstance(d, dict) or d.get("depth") is None or d.get("chord_root") is None:
                continue
            span = max(float(d["depth"]) - (0.85 if key == "keel" else 0.425) * tc0, 0.0)
            c = 0.5 * (float(d["chord_root"]) + float(d.get("chord_tip", d["chord_root"])))
            v = span * c * c * float(d.get("thickness", ft)) * 0.68
            app_v += v
            app_m += v * (tc0 + 0.45 * span)
            if key == "keel" and d.get("bulb_mass"):
                vb = float(d["bulb_mass"]) / LEAD_DENSITY
                app_v += vb
                app_m += vb * float(d["depth"]) * 0.93
    app_depth = app_m / app_v if app_v > 0 else 0.0

    loa = _num(h, "loa", "hull", required=True, positive=True)
    lwl = _num(h, "lwl", "hull", required=True, positive=True)
    beam_max = _num(h, "beam_max", "hull", required=True, positive=True)
    stem_x = _num(h, "stem_x", "hull", 0.5 * lwl + 0.6 * (loa - lwl))
    transom_x = _num(h, "transom_x", "hull", stem_x - loa)
    if abs((stem_x - transom_x) - loa) > 0.02 * loa:
        notes.append("hull: stem_x - transom_x differs from loa")
    s_m = _num(h, "max_beam_station", "hull", 0.45)

    bodies: List[HullBody] = []
    main_index: Optional[int] = None
    if kind == "catamaran":
        spacing = _num(h, "hull_spacing", "hull", required=True, positive=True)
        half = _body(h, "hull", notes, "hull", volume / 2.0)
        for sgn, nm in ((-1.0, "hull_port"), (1.0, "hull_stbd")):
            bodies.append(HullBody(**{**half.__dict__, "name": nm, "y": sgn * spacing / 2.0}))
    else:
        bodies.append(_body(h, "hull", notes, "main", volume - app_v))
        main_index = 0
        if kind == "trimaran":
            fl = h.get("floats")
            if not isinstance(fl, dict):
                raise ClassFileError("hull.floats: required for a trimaran")
            where = "hull.floats"
            spacing = _num(fl, "spacing", where, required=True, positive=True)
            fb = _body(fl, where, notes, "float", None)
            clearance = _num(fl, "clearance", where, 0.0)
            fx = _num(fl, "x", where, -0.05 * lwl)
            x_off = (lwl / 2 - fx) - fb.lwl / 2          # float's forward waterline end aft of the main's
            for sgn, nm in ((-1.0, "float_port"), (1.0, "float_stbd")):
                bodies.append(HullBody(**{**fb.__dict__, "name": nm, "y": sgn * spacing,
                                          "z": clearance + fb.draft, "x": x_off}))

    # maximum section: between mid-waterline and the station of maximum beam (given from the transom as a
    # fraction of LOA); a declared lcb_x wins
    x_mb = transom_x + s_m * loa
    xm = min(max(0.7 * 0.50 + 0.3 * (lwl / 2 - x_mb) / lwl, 0.35), 0.70)
    # LCB target shared with the boat generator: 53.5 % of LWL aft of the forward end when absent
    lcb_x = _num(h, "lcb_x", "hull", None)
    for b in bodies:
        if b.name in ("main", "hull_port", "hull_stbd"):
            b.max_section = xm
            b.lcb = (lwl / 2 - lcb_x) / lwl if lcb_x is not None else 0.535
    main_body = bodies[main_index if main_index is not None else 0]
    if kind != "monohull":
        beam_max = max(beam_max, max(abs(b.y) + b.beam_deck / 2 for b in bodies) * 2)

    # appendages
    kd = raw.get("keel")
    bulb = None
    if kind == "monohull":
        if not isinstance(kd, dict):
            raise ClassFileError("keel: required")
        keel = _foil(kd, "keel", main_body.draft, 0.10)
        fin_only = kd.get("type") == "fin"
        bm = _num(kd, "bulb_mass", "keel", 0.0 if fin_only else None, required=not fin_only)
        if bm and bm > 0:
            bl = _num(kd, "bulb_length", "keel")
            bd = _num(kd, "bulb_diameter", "keel")
            vol = bm / LEAD_DENSITY
            if bl is None and bd is None:
                bd = (6 * vol / (math.pi * 5.0)) ** (1 / 3)   # prolate spheroid with length/diameter 5
                bl = 5.0 * bd
                notes.append(f"keel bulb {bl:.2f} x {bd:.2f} m estimated from its mass")
            elif bd is None:
                bd = math.sqrt(6 * vol / (math.pi * bl))
            elif bl is None:
                bl = 6 * vol / (math.pi * bd * bd)
            depth = _num(kd, "depth", "keel")
            bulb = Bulb(mass=bm, length=bl, diameter=bd, depth=depth - 0.5 * bd)
        draft_total = _num(kd, "depth", "keel")
        fin_mass = _num(kd, "fin_mass", "keel", None)
    else:
        bd_ = raw.get("boards") or kd
        if not isinstance(bd_, dict):
            raise ClassFileError("boards: required for a multihull")
        keel = _foil(bd_, "boards", main_body.draft, 0.12)
        draft_total = _num(bd_, "depth", "boards")
        fin_mass = 0.0
    rd = raw.get("rudder")
    if not isinstance(rd, dict):
        raise ClassFileError("rudder: required")
    rudder = _foil(rd, "rudder", 0.5 * main_body.draft, 0.11)
    rudder_max = _num(rd, "max_angle", "rudder", 0.61)

    # rig
    r = raw.get("rig")
    if not isinstance(r, dict):
        raise ClassFileError("rig: required")
    I = _num(r, "I", "rig", required=True, positive=True)
    J = _num(r, "J", "rig", required=True, positive=True)
    P = _num(r, "P", "rig", required=True, positive=True)
    E = _num(r, "E", "rig", required=True, positive=True)
    mast_height = _num(r, "mast_height", "rig", required=True, positive=True)
    mast_x = _num(r, "mast_x", "rig", 0.1 * lwl)
    frac = _num(r, "fractional", "rig", 0.8)
    freeboard = main_body.freeboard_mid
    boom_height = _num(r, "boom_height", "rig", None)
    if boom_height is None:
        # data_format.md 3.4 default, shared with the boat generator
        boom_height = mast_height - P - 0.25 * (loa / 12.0) ** 0.6
        notes.append(f"rig.boom_height defaulted to {boom_height:.2f} m")
    mast_chord = 0.012 * mast_height + 0.03
    bowsprit = _num(r, "bowsprit", "rig", 0.0)
    pole = _num(r, "pole", "rig", 0.0)
    rig_mass = _num(r, "rig_mass", "rig", None)
    if rig_mass is None:
        rig_mass = 0.06 * mass_boat
        notes.append(f"rig.rig_mass estimated {rig_mass:.0f} kg")

    sd = raw.get("sails")
    if not isinstance(sd, list) or not sd:
        raise ClassFileError("sails: at least the main is required")
    sails: List[Sail] = []
    seen = set()
    for i, s in enumerate(sd):
        where = f"sails[{i}]"
        t = s.get("type")
        if t not in SAIL_TYPES:
            raise ClassFileError(f"{where}.type: {t!r} not one of {SAIL_TYPES}")
        sid = s.get("id")
        if not isinstance(sid, str) or not sid or sid in seen:
            raise ClassFileError(f"{where}.id: missing or duplicate")
        seen.add(sid)
        area = _num(s, "area", where, required=True, positive=True)
        forestay_x = mast_x + J
        if t == "main":
            ce, cx, foot = boom_height + 0.39 * P, mast_x - 0.39 * E, E
        elif t in ("jib", "genoa"):
            foot = _num(s, "foot", where, 2 * area / (I * 0.95))
            ce, cx = freeboard + 0.39 * I, forestay_x - 0.45 * foot
        elif t == "code_zero":
            foot = _num(s, "foot", where, 2 * area / (I / frac * 0.95))
            ce, cx = freeboard + 0.45 * I / frac, forestay_x + bowsprit - 0.45 * foot
        else:
            foot = _num(s, "foot", where, area / (0.9 * I))
            ce, cx = freeboard + 0.59 * I, forestay_x + bowsprit + pole * 0.3 - 0.3 * foot
        lo, hi = SHEET_LIMITS[t]
        sails.append(Sail(id=sid, type=t, area=area, ce_height=ce, ce_x=cx, sheet_min=lo, sheet_max=hi, foot=foot,
                          furling=bool(s.get("furling", False)), handling=dict(s.get("handling") or {})))
    if sum(1 for s in sails if s.type == "main") != 1:
        raise ClassFileError("sails: exactly one main is required")

    crew_arm = _num(crew, "hiking_arm", "crew", 0.45 * beam_max if kind == "monohull" else 0.3 * beam_max)

    vcg = _num(h, "hull_mass_z", "hull", None)
    if vcg is None:
        m_rest = mass_boat - rig_mass - (bulb.mass if bulb else 0.0)
        if kind == "monohull" and fin_mass is None:
            fin_mass = min(0.25 * m_rest, keel.area * keel.chord * keel.thickness * 0.68 * 7850.0)
        fin_mass = fin_mass or 0.0
        m_rest -= fin_mass
        if m_rest <= 0:
            raise ClassFileError("hull.displacement: lighter than the bulb, fin and rig")
        num = rig_mass * 0.45 * mast_height + m_rest * 0.25 * freeboard
        if bulb:
            num -= bulb.mass * bulb.depth
        num -= fin_mass * (main_body.draft + 0.45 * keel.span)
        vcg = num / mass_boat
        notes.append(f"VCG estimated {vcg:+.2f} m (bulb, fin, rig at 0.45 mast height, rest at 0.25 freeboard)")
    vd = raw.get("vpp") or {}
    heel_max = _num(vd, "max_heel", "vpp", 0.56 if kind == "monohull" else 0.28)

    return Boat(id=cid, name=str(raw.get("name", cid)), version=int(raw.get("version", 1)), kind=kind, loa=loa,
                lwl=lwl, bwl=main_body.bwl, beam_max=beam_max, stem_x=stem_x, transom_x=transom_x,
                transom_width=_num(h, "transom_width", "hull", 0.5 * beam_max), max_beam_station=s_m,
                bodies=bodies, main_index=main_index, mass_boat=mass_boat, mass_crew=mass_crew,
                crew_count=crew_count, crew_arm=crew_arm, vcg=vcg, rig_mass=rig_mass, keel=keel, bulb=bulb,
                rudder=rudder, rudder_max=rudder_max, draft_total=draft_total, rig_I=I, rig_J=J, rig_P=P, rig_E=E,
                mast_height=mast_height, mast_x=mast_x, boom_height=boom_height, mast_chord=mast_chord,
                bowsprit=bowsprit, pole=pole, freeboard=freeboard, app_volume=app_v, app_depth=app_depth,
                sails=sails, heel_max=heel_max,
                start=dict(raw.get("start") or {}), handling=dict(raw.get("handling") or {}), notes=notes,
                source=raw,
                sha256=hashlib.sha256(json.dumps(raw, sort_keys=True).encode()).hexdigest())
