"""Performance file (`windmark.perf/1`, docs/specs/data_format.md section 4) from a boat class.

Per config (main alone, main + each front sail), on the spec's axes:

* ``polar``: VPP boat speed at optimal trim and depowering; below the no-go edge the steady sternway the windage
  drives, with a step up to +0.1 m/s at the edge (boat.md 7.4); where no depowering holds the config, a low
  broached speed (``_broached``);
* ``heel``: equilibrium heel;
* ``accel``: the constant acceleration that reproduces the time to build speed from 50 % to 90 % of the polar,
  integrating (drive - resistance) / (mass + added mass) with the heel in equilibrium at each speed;
* ``trim_speed``, ``trim_heel``: equilibrium speed and heel with every sail sheeted eps away from its optimum
  (the single manual sheet of sails.md 5.2), relative to the trimmed values, 0 with the driving sail on the wind
  line;
* ``fall_off``: turning away from the wind with no way on (boat.md 7.4);
* ``optimal_angle``: best sheet angle of the main and the front sail against the apparent wind.

``dynamics`` values are derived from the design where the VPP has the physics (turn radius and its law's offset,
coasting deceleration, heel and pitch springs, rudder drag, speed loss with heel, collision outline, wind-shadow
geometry) and use the reference values of boat.md and wind_shadow.md scaled with the waterline length otherwise.
The class file's ``handling`` multipliers scale the feel (``apply_handling``) and its other ``handling`` keys
override dynamics values as given. The ``vpp`` block (ignored by the core) records assumptions, VMG optima and
diagnostic tables.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np

from . import __version__
from .boatclass import SPINNAKER_TYPES, Boat
from .constants import DEG, RHO_AIR, RHO_WATER, G
from .geometry import hydrostatics, loft, _plan
from .hydro import build as build_hull
from .solver import CD_FLOG, CD_LUFF, FLATS, REEFS, Rig, Solver, added_mass_coefficient, apparent, make_rig, wind_at

SCHEMA = "windmark.perf/1"
KITE_TYPES = SPINNAKER_TYPES + ("code_zero",)
TWS = np.array([0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20.6])
TWA_SAIL = np.concatenate([np.arange(20, 60, 2), np.arange(60, 180.01, 5)]) * DEG
AWA = np.concatenate([[0, 5], np.arange(10, 180.01, 5)]) * DEG
# trim error: fine round the optimum, then every 5 deg out to where the eased sail reaches the wind line (the
# trim tables are 0 there, and the step before it must be close to the line), then 150 and 180 deg
EPS = np.concatenate([[-60, -20, -10, -6, -3, 0, 0.5, 3], np.arange(5, 131, 5), [150, 180]]) * DEG
# full-drive plateau of the trim tables (sails.md 6): a real sail's drive is flat near its best trim, so the trim
# errors within +-TRIM_PLATEAU are solved at the optimum and the rest of each side is stretched to keep its ends
TRIM_PLATEAU = 3.0 * DEG
NF, NR = len(FLATS), len(REEFS)
# apparent wind speed axis of flog_drag (m/s): the drag grows with its square, so the steps are fine enough that
# the linear interpolation stays within a few per cent of it
AWS_AXIS = np.array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 23, 26, 30, 35, 40.0])

# reference archetypes of boat.md 4 (S = sportsboat, L = large monohull) by waterline length
L_S, L_L = 6.4, 19.5

# Broached speed (README "Output"): where no depowering keeps a config within the heel limit, or the boat cannot
# make way at all at that angle, the polar holds this share of the speed the config made at the same TWA in the
# strongest wind it could still hold, and at least the no-go edge value; the boat wallows instead of stopping.
BROACH_SHARE = 0.4
BROACH_MIN = 0.1            # m/s, the polar's value at the no-go edge

# decel_windage (README "dynamics"): the core charges the windage linearly in its apparent wind, the square law's
# secant through this apparent wind (m/s). The whole square law made a tack in a breeze lose most of its way (the
# coast law has the sails give no drive anywhere in the no-go zone, where real sails still draw until close to head
# to wind); the secant keeps the tack of boat.md 7.2 while a boat head to wind still stops faster in more wind.
WINDAGE_AWS_REF = 3.5
# accel (README "Output"): the constant acceleration that reproduces the time to build speed between these shares
# of the polar (a boat comes out of a tack or a gybe at about half its speed; the tack test measures 90 %)
ACCEL_FROM, ACCEL_TO = 0.5, 0.9
# Turning (README "dynamics"): in a steady turn about this share of the rudder angle reaches the blade as angle of
# attack (the rest is the flow curving round the stern and the drift the turn needs); the rudder stalls at the helm
# where that incidence reaches the stall of its lift line.
RUDDER_AOA_SHARE = 0.5
RUDDER_CL_MAX = 1.1
RUDDER_STALL_RANGE = 5.0 * DEG     # incidence over which a blade's flow separates past its stall (a few degrees)
# weather_helm (README "Output"): the boat balances with the helm centred close-hauled at this TWS (m/s, 12 kn);
# the helm the sail plan asks for is held to +-WH_HELM_MAX (a boat beyond full helm broaches)
WH_BALANCE_TWS = 6.17
WH_HELM_MAX = 3.0
# a config overpowered past its heel limit on a reach or a run (broached cells from this TWA where the heel is
# what failed) broaches: it rounds up at the full-helm turn rate of its broached speed
WH_BROACH_TWA = 45.0 * DEG
# fall_off (README "Output"): turning away from the wind in sternway and at a crawl, reference rate of the S and L
# archetypes, full from 20 to 60 deg TWA, none below 10 deg (a boat right head to wind stays in irons) and from
# 90 deg (a stopped boat lies beam on); fading to 0 at a Froude number of FALL_OFF_FN ahead, where the keel starts
# to hold the heading.
FALL_OFF_RATE = (8.0 * DEG, 5.0 * DEG)
FALL_OFF_FN = 0.05
FALL_OFF_TWA = np.array([0, 10, 20, 60, 90, 180]) * DEG
FALL_OFF_SHAPE = np.array([0, 0, 1, 1, 0, 0.0])


def _by_size(lwl, s, l):
    """Log-log interpolation of a reference value between the S and L archetypes (clamped)."""
    t = min(max(math.log(lwl / L_S) / math.log(L_L / L_S), 0.0), 1.0)
    return s * (l / s) ** t if s > 0 and l > 0 else s + (l - s) * t


# -------------------------------------------------------------------------------------------------------------
# tables


def table(axes, unit, values):
    v = np.asarray(values, float)
    shape = tuple(len(a[1]) for a in axes)
    if v.shape != shape:
        raise ValueError(f"table shape {v.shape} != axes {shape}")
    if not np.all(np.isfinite(v)):
        raise ValueError("non-finite table value")
    return {"axes": [{"q": q, "points": [float(x) for x in p]} for q, p in axes], "unit": unit,
            "values": [float(x) for x in v.ravel()]}


def sig9(o):
    """Round every float to 9 significant digits (data_format.md 1)."""
    if isinstance(o, float):
        return float(f"{o:.9g}")
    if isinstance(o, dict):
        return {k: sig9(v) for k, v in o.items()}
    if isinstance(o, list):
        return [sig9(v) for v in o]
    return o


# -------------------------------------------------------------------------------------------------------------


@dataclass
class ConfigResult:
    front: Optional[str]
    rig: Rig
    V: np.ndarray            # (tws, twa) on TWS[1:], TWA_SAIL
    heel: np.ndarray
    awa: np.ndarray
    aws: np.ndarray
    fi: np.ndarray
    reef: np.ndarray
    valid: np.ndarray
    deltas: List[np.ndarray]
    fh: np.ndarray
    broached: np.ndarray     # no depowering holds the config: the polar holds the broached speed
    src: np.ndarray          # row of the last sailing TWS at that TWA (-1: none), the broached speed's source
    heel_limited: np.ndarray  # some control reached the heel limit


class Generator:
    def __init__(self, boat: Boat, thin_ship: Optional[bool] = None, physics: Optional[Dict] = None):
        self.boat = boat
        self.physics = physics
        self.hydro = hydrostatics(boat)
        self.hull = build_hull(boat, self.hydro, thin_ship=thin_ship)
        self.solver = Solver(boat, self.hull)
        up = self.hydro.upright
        self.ca = added_mass_coefficient(up["lwl"], up["amax"])
        self.mass_eff = boat.mass * (1 + self.ca)
        self.rigs = [(front, make_rig(boat, front or "main", sails)) for front, sails in boat.configs()]
        self.tws = TWS[1:]
        self.twa = TWA_SAIL
        self.notes = list(boat.notes) + list(self.hull.notes)

    # ---------------------------------------------------------------------------------------------------------
    def run(self) -> Dict:
        b = self.boat
        self.results = [self._solve(front, rig) for front, rig in self.rigs]
        configs = [self._config(r) for r in self.results]
        vmg = self._vmg()
        dyn = self._dynamics()
        sails = {s.id: self._sail_block(s) for s in b.sails}
        out = {
            "schema": SCHEMA,
            "class_id": b.id,
            "class_version": b.version,
            "class_sha256": b.sha256,
            "generator": {"tool": "vpp", "version": __version__},
            "handling": dict(b.feel),
            "dynamics": dyn,
            "sails": sails,
            "configs": configs,
            "start": {"front_sail": b.start.get("front_sail") if b.start else None},
            "vpp": {"notes": self.notes, "vmg": vmg, "added_mass_coefficient": self.ca,
                    "righting_moment": {"heel": list(np.radians([0, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90])),
                                        "moment": list(self.hydro.righting_moment(
                                            np.radians([0, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90])))}},
        }
        apply_handling(out, b.feel)
        if any(v != 1.0 for v in b.feel.values()):
            self.notes.append("handling multipliers " + ", ".join(f"{k} {v:g}" for k, v in b.feel.items()))
        for k, v in (b.handling or {}).items():
            if k in dyn:
                dyn[k] = v
            else:
                self.notes.append(f"handling.{k}: not a dynamics key, ignored")
        return sig9(out)

    def _solve(self, front, rig: Rig) -> ConfigResult:
        T, A = len(self.tws), len(self.twa)
        fi = np.repeat(np.arange(NF), NR)[None, None, :]
        rf = np.tile(REEFS, NF)[None, None, :]
        st = self.solver.solve(rig, fi, rf, self.tws[:, None, None], self.twa[None, :, None])
        V = np.where(st.valid, st.V, -1.0).reshape(T, A, NF * NR)
        # fastest valid control; ties go to more power (less flattening, less reefing)
        score = V * (1 + 2e-4 * np.repeat(np.arange(NF), NR) / NF + 2e-4 * np.tile(REEFS, NF))
        k = np.argmax(score, axis=-1)
        take = lambda a: np.take_along_axis(np.asarray(a).reshape(T, A, NF * NR), k[..., None], -1)[..., 0]
        ok = take(st.valid) & (take(st.V) > 0.02)
        limited = (st.heel >= self.solver.heel_top * (1 - 1e-6)).reshape(T, A, NF * NR).any(axis=-1)
        rows = np.where(ok, np.arange(T)[:, None], -1)
        src = np.maximum.accumulate(rows, axis=0)
        return ConfigResult(front=front, rig=rig, V=np.where(ok, take(st.V), 0.0),
                            heel=np.where(ok, take(st.heel), 0.0), awa=take(st.awa), aws=take(st.aws),
                            fi=k // NR, reef=REEFS[k % NR], valid=ok, deltas=[take(d) for d in st.deltas],
                            fh=np.where(ok, take(st.fh), 0.0), broached=~ok, src=src, heel_limited=limited)

    def _broached(self, r: ConfigResult, acc):
        """Speed, heel and acceleration of the broached cells (r.broached), on the (tws, twa) solve grid.

        Speed: BROACH_SHARE of the speed at the same TWA in the strongest wind the config still holds (the row
        r.src), at least BROACH_MIN. Heel: at the heel limit where the heel is what failed, else as in that row.
        Acceleration: as in that row, so the boat settles to its broached speed as quickly as it sailed there.
        """
        cols = np.arange(r.V.shape[1])[None, :]
        s = np.maximum(r.src, 0)
        has = r.src >= 0
        V = np.maximum(np.where(has, BROACH_SHARE * r.V[s, cols], 0.0), BROACH_MIN)
        heel = np.where(r.heel_limited, self.solver.heel_top, np.where(has, r.heel[s, cols], 0.0))
        a = np.where(has, acc[s, cols], 0.005)
        return V, heel, a

    # ---------------------------------------------------------------------------------------------------------
    def _config(self, r: ConfigResult) -> Dict:
        rig = r.rig
        T = len(TWS)
        # no-go edge: just below the first TWA where the config makes way in a moderate breeze; below it the
        # sternway drift, above it the polar rising from 0.1 m/s to the first sailing speed
        moving = r.V[np.searchsorted(self.tws, 4.0):] > 0.1
        j1 = int(np.argmax(moving.any(axis=0))) if moving.any() else 0
        edge = float(max(self.twa[j1] - 1.5 * DEG, 12 * DEG))
        keep = self.twa > edge + 0.25 * DEG
        twa_axis = np.concatenate([[0.0, 7 * DEG, edge, edge], self.twa[keep]])
        # sternway in irons: windage balance, capped at the 0.15 TWS a boat reaches before it falls off
        drift = self.solver.sternway(rig, self.tws[:, None], np.array([0.0, 7 * DEG, edge])[None, :])
        drift = np.maximum(drift, -0.15 * self.tws[:, None])
        acc = self._accel(r)
        acc0 = self._accel_rest(r)
        pol = np.zeros((T, len(twa_axis)))
        heel = np.zeros_like(pol)
        accel = np.zeros_like(pol)
        bV, bh, ba = self._broached(r, acc)
        b = r.broached[:, keep]
        pol[1:, :3] = drift
        pol[1:, 3] = BROACH_MIN
        pol[1:, 4:] = np.where(b, bV[:, keep], np.maximum(r.V[:, keep], 0.0))
        heel[1:, 4:] = np.where(b, bh[:, keep], r.heel[:, keep])
        accel[1:, :] = 0.005
        accel[1:, 4:] = np.maximum(np.where(b, ba[:, keep], acc[:, keep]), 0.005)
        accel0 = np.zeros_like(pol)
        accel0[1:, :] = 0.005
        _, _, ba0 = self._broached(r, acc0)
        accel0[1:, 4:] = np.maximum(np.where(b, ba0[:, keep], acc0[:, keep]), 0.005)
        ts, th = self._trim_tables(r)
        opt = {}
        for k, s in enumerate(rig.sails):
            opt[s.id] = table([("tws", TWS), ("awa_abs", AWA)], "rad", self._opt_angle(r, k))
        out = {
            "front_sail": r.front,
            "polar": table([("tws", TWS), ("twa_abs", twa_axis)], "m/s", pol),
            "heel": table([("tws", TWS), ("twa_abs", twa_axis)], "rad", np.clip(heel, 0, math.pi / 2)),
            "accel": table([("tws", TWS), ("twa_abs", twa_axis)], "m/s2", accel),
            "accel_rest": table([("tws", TWS), ("twa_abs", twa_axis)], "m/s2", accel0),
            "trim_speed": table([("tws", TWS), ("awa_abs", AWA), ("trim_error", EPS)], "1", ts),
            "trim_heel": table([("tws", TWS), ("awa_abs", AWA), ("trim_error", EPS)], "1", th),
            "weather_helm": table([("tws", TWS), ("twa_abs", twa_axis)], "rad/s", self._weather_helm(r, twa_axis)),
            "fall_off": self._fall_off(),
            "flog_drag": self._flog_drag(r),
            "optimal_angle": opt,
            "vpp": {
                "flat": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "1", FLATS[r.fi]),
                "reef": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "1", r.reef),
                "awa": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "rad", r.awa),
                "leeway": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "rad", self._leeway(r)),
                "broached": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "1", r.broached.astype(float)),
            },
        }
        return out

    def _fall_off(self):
        """Turning away from the wind (rad/s) against boat speed and TWA (boat.md 7.4, sails.md 6): the windage
        of the rig and topsides forward of the keel swings the bow of a boat that has no way on; the keel holds the
        heading once the boat moves ahead. The same for every config (the sails are flogging)."""
        b = self.boat
        rate = _by_size(b.lwl, *FALL_OFF_RATE)
        vf = FALL_OFF_FN * math.sqrt(G * b.lwl)
        speed = np.array([-6.0, 0.0, 0.5 * vf, vf])
        fade = np.array([1.0, 1.0, 0.75, 0.0])          # 1 - (v / vf)^2 ahead
        return table([("boat_speed", speed), ("twa_abs", FALL_OFF_TWA)], "rad/s",
                     rate * fade[:, None] * FALL_OFF_SHAPE[None, :])

    def _flog_drag(self, r: ConfigResult):
        """Deceleration (m/s^2, >= 0) from the config's sails flogging on free sheets beyond the drag they have
        luffing with the sheets in (which decel_windage holds), along the heading, against the apparent wind speed
        and angle (boat.md 5.8, sails.md 6). 0 with the apparent wind abaft the beam, where the flogging sails push
        instead (the let-fly share of trim_speed). The core's apparent wind is taken at the tables' 10 m reference
        height; the wind profile factor at the centre of effort is applied to it."""
        rig = r.rig
        k = float(wind_at(1.0, rig.ce_height(1.0))) ** 2
        area = sum(s.area for s in rig.sails)
        ahead = np.where(AWA < 0.5 * math.pi, np.cos(AWA), 0.0)
        d = 0.5 * RHO_AIR * k * AWS_AXIS[:, None] ** 2 * (CD_FLOG - CD_LUFF) * area * ahead[None, :]
        return table([("aws", AWS_AXIS), ("awa_abs", AWA)], "m/s2", np.maximum(d, 0.0) / self.mass_eff)

    # ---------------------------------------------------------------------------------------------------------
    # helm balance (weather_helm)

    def _ce(self, rig: Rig, deltas):
        """Centre of effort of the sail plan trimmed to the sheet angles `deltas` (one per sail): body x and the
        distance out to leeward, each sail's centre of effort swung about its luff, weighted by area."""
        area = sum(s.area for s in rig.sails)
        x = sum(s.area * ((s.luff_x if s.luff_x is not None else s.ce_x)
                          - ((s.luff_x - s.ce_x) if s.luff_x is not None else 0.0) * np.cos(d))
                for s, d in zip(rig.sails, deltas)) / area
        y = sum(s.area * ((s.luff_x - s.ce_x) if s.luff_x is not None else 0.0) * np.sin(d)
                for s, d in zip(rig.sails, deltas)) / area
        return x, y

    def _yaw_moment(self, rig: Rig, fi, reef, tws, twa, V, heel, x_clr):
        """Luffing yaw moment (N m, + = toward the wind) of the sail plan about the centre of lateral resistance:
        the drive acting at the centre of effort, which the sheet angle and the heel carry out to leeward, and the
        side force acting at the centre of effort ahead of (or behind) the centre of lateral resistance."""
        fx, fh, _, _, _, deltas = self.solver.moment(rig, fi, reef, tws, twa, V, heel)
        z = rig.ce_height(reef)
        x, y = self._ce(rig, deltas)
        return fx * (z * np.sin(heel) + y) - fh * (x - x_clr)

    @property
    def x_clr(self) -> float:
        """Centre of lateral resistance of the balanced boat: where the yaw moment of the upwind config (the start
        config) vanishes close-hauled, at the VMG angle, in a moderate breeze of WH_BALANCE_TWS (a racing boat is
        designed, and its rig raked, to sail straight to windward with the helm centred). One point for every
        config: the other sail plans balance about it as their centres of effort and forces fall."""
        if getattr(self, "_x_clr", None) is None:
            front = self.boat.start.get("front_sail") if self.boat.start else None
            r = next((q for q in self.results if q.front == front and q.front is not None),
                     self.results[min(1, len(self.results) - 1)])
            i = int(np.argmin(np.abs(self.tws - WH_BALANCE_TWS)))
            j = int(np.argmax(np.where(r.valid[i], r.V[i] * np.cos(self.twa), -1.0)))
            fx, fh, _, _, _, deltas = self.solver.moment(r.rig, r.fi[i, j], r.reef[i, j], self.tws[i],
                                                        self.twa[j], r.V[i, j], r.heel[i, j])
            z = r.rig.ce_height(r.reef[i, j])
            x, y = self._ce(r.rig, deltas)
            self._x_clr = float(x - fx * (z * math.sin(r.heel[i, j]) + y) / fh)
        return self._x_clr

    def _weather_helm(self, r: ConfigResult, twa_axis):
        """Helm balance (rad/s, + = toward the wind) on the polar's axes (boat.md 5.9, sails.md 6).

        The yaw moment of the sail plan (_yaw_moment) at the polar speed and heel is expressed as the helm h_e the
        rudder needs to hold it at that speed on a straight course: the rudder's yaw moment per unit helm about the
        centre of lateral resistance in its linear range, with the whole rudder angle reaching the blade (the
        boat is not turning, so no flow curvature takes a share of it). The table holds the turn rate that helm
        gives on the radius law, v / R(h_e): with the helm centred the same moment turns the boat at that rate,
        because in a free turn the centred blade meets the turn's cross-flow and damps it by the share of the
        rudder angle that a helm turn loses to it (RUDDER_AOA_SHARE), so the moment is balanced by the same yaw
        damping as the helm turn of h_e. Beyond full helm the rate grows as v h_e / R_full, so a boat overpowered
        past what full helm holds broaches. Broached cells from WH_BROACH_TWA where the heel is what failed are
        overpowered: the boat lies over at its heel limit with the rudder near the surface and rounds up at the
        full-helm turn rate of its broached speed, v_b / R_full (at speed a full helm can still catch it). The
        other broached cells (pinching in a strong breeze) take the value of the last wind the config holds at
        that angle (as the acceleration). 0 in the no-go zone and in no wind."""
        b = self.boat
        tws = self.tws[:, None]
        twa = self.twa[None, :]
        V = r.V
        x_clr = self.x_clr
        N = self._yaw_moment(r.rig, r.fi, r.reef, tws, twa, np.maximum(V, 0.05), r.heel, x_clr)
        a1, _, cla = self._rudder_lift_slope()
        arm = max(x_clr - b.rudder.x, 0.1 * b.lwl)
        per_helm = 0.5 * RHO_WATER * V ** 2 * a1 * b.rudder.count * cla * b.rudder_max * arm
        he = np.clip(np.where(V > 0.1, N / np.maximum(per_helm, 1e-9), 0.0), -WH_HELM_MAX, WH_HELM_MAX)
        n = np.abs(he)
        R = np.maximum((self.turn_full + self.turn_offset) / np.maximum(n, 1e-6) - self.turn_offset, 0.5)
        rate = np.where(V > 0.1, np.where(n <= 1.0, V / R, V * n / self.turn_full) * np.sign(he), 0.0)
        cols = np.arange(V.shape[1])[None, :]
        src = rate[np.maximum(r.src, 0), cols]
        rate = np.where(r.broached, np.where(r.src >= 0, src, 0.0), rate)
        acc = np.zeros_like(r.V)                        # only the broached speed is used
        v_b, _, _ = self._broached(r, acc)
        over = r.broached & r.heel_limited & (twa >= WH_BROACH_TWA - 1e-9)
        rate = np.where(over, v_b / self.turn_full, rate)
        out = np.zeros((len(TWS), len(twa_axis)))
        keep = np.searchsorted(self.twa, twa_axis[4:] - 1e-9)
        out[1:, 4:] = rate[:, keep]
        return out

    def _accel(self, r: ConfigResult):
        S = self.solver
        rig = r.rig
        tws = self.tws[:, None, None]
        twa = self.twa[None, :, None]
        x, w = np.polynomial.legendre.leggauss(8)
        f0, f1 = ACCEL_FROM, ACCEL_TO
        frac = f0 + (f1 - f0) * (x + 1) / 2
        Vn = r.V[..., None] * frac[None, None, :]
        fi = r.fi[..., None]
        rf = r.reef[..., None]
        heel, _ = S.solve_heel(rig, fi, rf, tws, twa, Vn)
        f, _ = S.net_force(rig, fi, rf, tws, twa, Vn, heel)
        f = np.maximum(f, 1e-3 * self.boat.mass)
        t = np.sum(w[None, None, :] * self.mass_eff / f, axis=-1) * (f1 - f0) * r.V / 2
        return np.where(r.V > 0.05, (f1 - f0) * r.V / np.maximum(t, 1e-6), 0.0)

    def _accel_rest(self, r: ConfigResult):
        """Acceleration from rest (m/s^2): the drive of the trimmed sail plan in the true wind over the effective
        mass, with the heel it raises; the hull has no resistance ahead at rest (the keel's side force is taken by
        the boat sliding to leeward until it has way on). The core blends from it to ``accel`` below half the
        target speed (boat.md 5.8)."""
        S = self.solver
        V0 = np.zeros_like(r.V)
        tws = np.broadcast_to(self.tws[:, None], V0.shape)
        twa = np.broadcast_to(self.twa[None, :], V0.shape)
        heel, _ = S.solve_heel(r.rig, r.fi, r.reef, tws, twa, V0)
        fx, _, _, _, _, _ = S.moment(r.rig, r.fi, r.reef, tws, twa, V0, heel)
        return np.where(r.V > 0.05, np.maximum(fx, 0.0) / self.mass_eff, 0.0)

    def _leeway(self, r: ConfigResult):
        b = self.boat
        V = np.maximum(r.V, 0.2)
        q = 0.5 * RHO_WATER * V * V
        te = self.hull.effective_draft(V, r.heel)
        alat = b.keel.area + b.rudder.area
        ar = 2 * te ** 2 / alat
        cla = 2 * math.pi * ar / (ar + 2)
        return np.where(r.V > 0.05, np.clip(r.fh / (q * alat * cla), 0, 0.35), 0.0)

    def _to_awa(self, r: ConfigResult, values, fill):
        """Resample (tws, twa, ...) values onto the AWA axis per TWS row; row 0 (no wind) gets `fill`."""
        extra = values.shape[2:]
        out = np.empty((len(TWS), len(AWA)) + extra)
        out[0] = fill
        for i in range(len(self.tws)):
            ok = r.valid[i]
            if ok.sum() < 2:
                out[i + 1] = fill if i == 0 else out[i]
                continue
            a = r.awa[i][ok]
            order = np.argsort(a, kind="stable")
            a = np.maximum.accumulate(a[order])
            v = values[i][ok][order]
            flat = v.reshape(len(a), -1)
            res = np.stack([np.interp(AWA, a, flat[:, j]) for j in range(flat.shape[1])], axis=-1)
            out[i + 1] = res.reshape((len(AWA),) + extra)
        return out

    def _opt_angle(self, r: ConfigResult, k: int):
        s = r.rig.sails[k]
        o = self._to_awa(r, r.deltas[k], s.sheet_min)
        o[0] = o[1]
        if s.type == "main" and any(f.type in KITE_TYPES for f in r.rig.sails):
            # with a spinnaker or code zero set the main is sailed inside its own best angle (sails.md 5.1)
            o = o - s.kite_sheet_in
        return np.clip(o, s.sheet_min, s.sheet_max)

    @staticmethod
    def _plateau(eps, w):
        """Effective trim error g(eps) of the trim tables (sails.md 6): 0 within +-TRIM_PLATEAU (at most half the
        driving sail's wind-line error w), then linear so that w (eased) and EPS[0] (over-sheeted) map to
        themselves; unchanged beyond the wind line."""
        p = np.minimum(TRIM_PLATEAU, 0.5 * np.maximum(w, 0.0))
        lo = EPS[0]
        over = np.where(eps < -p, (eps + p) * lo / (lo + p), 0.0)
        eased = np.where(eps >= w, eps, np.where(eps > p, (eps - p) * w / np.maximum(w - p, 1e-9), 0.0))
        return np.where(eps < 0, over, eased)

    def _trim_tables(self, r: ConfigResult):
        S = self.solver
        T, A = r.V.shape
        E = len(EPS)
        shp = (T, A, E)
        fi = np.broadcast_to(r.fi[..., None], shp)
        rf = np.broadcast_to(r.reef[..., None], shp)
        tws, twa = self.tws[:, None, None], self.twa[None, :, None]
        drive = len(r.rig.sails) - 1                    # the front sail if the config has one, else the main
        eps = self._plateau(EPS[None, None, :], (r.awa - r.deltas[drive])[..., None])
        # speed: the equilibrium of the mistrimmed boat over the trimmed one
        st = S.solve(r.rig, fi, rf, tws, twa, eps=eps)
        i0 = int(np.argmin(np.abs(EPS)))
        V = st.V
        v0 = V[..., i0:i0 + 1]
        sf = np.where(v0 > 0.05, np.clip(V / np.maximum(v0, 1e-6), 0, 1.0), 1.0)
        # heel: the roll equilibrium of the mistrimmed sails at the trimmed boat's speed and apparent wind over the
        # trimmed heel there, so the core, which looks it up at the boat's own apparent wind, heels an over-sheeted
        # boat by what its stalled sails push at the speed it is making (sails.md 6)
        H, _ = S.solve_heel(r.rig, fi, rf, tws, twa, np.broadcast_to(r.V[..., None], shp), eps=eps)
        h0 = H[..., i0:i0 + 1]
        hf = np.where(h0 > 0.2 * DEG, np.clip(H / np.maximum(h0, 1e-6), 0, 3.0), 1.0)
        ts, th = self._to_awa(r, sf, 1.0), self._to_awa(r, hf, 1.0)
        # On the wind line the driving sail flogs: no drive, no heel from the sails (sails.md 6). The core looks the
        # tables up at the driving sail's error eps = |awa| - m_opt, which on the wind line is w = AWA - m_opt; the
        # tables are 0 from the eps point at or below the smallest w of the neighbouring (tws, AWA) points, so the
        # interpolated value at the wind line is exactly 0 wherever the core looks it up.
        w = AWA[None, :] - self._opt_angle(r, drive)
        wp = np.pad(w, 1, mode="edge")
        wmin = np.min([wp[1 + a:wp.shape[0] - 1 + a, 1 + b:wp.shape[1] - 1 + b]
                       for a in (-1, 0, 1) for b in (-1, 0, 1)], axis=0)
        k = np.clip(np.searchsorted(EPS, wmin, side="right") - 1, i0 + 1, len(EPS) - 1)
        off = np.arange(len(EPS))[None, None, :] >= k[..., None]
        # ... except that with the apparent wind abaft the beam the windage and the flogging sails still push the
        # boat along: trim_speed holds the let-fly speed there, as a share of the polar
        return np.where(off, self._let_fly_share(r)[..., None], ts), np.where(off, 0.0, th)

    def _let_fly_share(self, r: ConfigResult):
        """Let-fly speed (Solver.let_fly_speed) over the polar, on the (TWS, AWA) axes of the trim tables.

        Resampled per TWS row with the apparent wind angle at the let-fly speed as the abscissa, so the core, which
        looks the table up at the boat's own apparent wind, finds the let-fly speed exactly when the boat sails at
        it; 0 wherever the windage holds the boat back (apparent wind forward of about the beam)."""
        V, beta = self.solver.let_fly_speed(r.rig, self.tws[:, None], self.twa[None, :])
        share = np.where(r.valid & (r.V > 0.05), np.clip(V / np.maximum(r.V, 1e-6), 0.0, 1.0), 0.0)
        out = np.zeros((len(TWS), len(AWA)))
        for i in range(len(self.tws)):
            ok = r.valid[i]
            if ok.sum() < 2:
                continue
            a = np.maximum.accumulate(beta[i][ok])
            out[i + 1] = np.interp(AWA, a, share[i][ok], left=0.0)
        return out

    def _start_result(self) -> ConfigResult:
        """The config a race starts with (the class's start front sail), else main + the first front sail."""
        front = self.boat.start.get("front_sail") if self.boat.start else None
        for r in self.results:
            if front is not None and r.front == front:
                return r
        return self.results[min(1, len(self.results) - 1)]

    # ---------------------------------------------------------------------------------------------------------
    def _vmg(self):
        S = self.solver
        T = len(self.tws)
        best = {"upwind": [None] * T, "downwind": [None] * T}
        for r in self.results:
            vm = r.V * np.cos(self.twa)[None, :]
            for side, sign in (("upwind", 1.0), ("downwind", -1.0)):
                j0 = np.argmax(sign * vm, axis=1)
                cand = np.clip(np.stack([self.twa[j0] + d * DEG for d in np.arange(-5.0, 5.01, 0.5)], axis=1),
                               15 * DEG, math.pi)
                C = cand.shape[1]
                d3 = np.array([-1, 0, 1])
                fi = np.clip(r.fi[np.arange(T), j0][:, None, None, None] + d3[None, None, :, None], 0, NF - 1)
                ri = np.clip(np.searchsorted(REEFS, r.reef[np.arange(T), j0] - 1e-9)[:, None, None, None]
                             + d3[None, None, None, :], 0, NR - 1)
                fi, ri = np.broadcast_arrays(fi, ri)
                st = S.solve(r.rig, fi, REEFS[ri], self.tws[:, None, None, None], cand[:, :, None, None])
                V = np.where(st.valid, st.V, 0.0).reshape(T, C, -1).max(axis=-1)
                vmg = sign * V * np.cos(cand)
                k = np.argmax(vmg, axis=1)
                for i in range(T):
                    rec = {"twa": float(cand[i, k[i]]), "speed": float(V[i, k[i]]), "vmg": float(vmg[i, k[i]]),
                           "front_sail": r.front}
                    if best[side][i] is None or rec["vmg"] > best[side][i]["vmg"]:
                        best[side][i] = rec
        return [{"tws": float(self.tws[i]), "upwind": best["upwind"][i], "downwind": best["downwind"][i]}
                for i in range(T)]

    # ---------------------------------------------------------------------------------------------------------
    def _dynamics(self) -> Dict:
        b = self.boat
        H = self.hydro
        up = H.upright
        lwl = b.lwl
        m = b.mass
        me = self.mass_eff

        # turning (run): radius at full helm and the radius law's offset; helm speed scales with size
        turn_full, turn_offset = self.turn_full, self.turn_offset
        helm_rate = float(np.clip(_by_size(lwl, 1.65, 1.0), 0.6, 2.2))
        # yaw inertia: time constant of the hull's yaw rate (boat.md 4 reference by size)
        yaw_time = float(np.clip(_by_size(lwl, 0.35, 0.6), 0.2, 1.0))

        # deceleration: constant = the hull at a crawl; windage = the drag of hull, rig and the start config's
        # sails luffing on their sheets head to wind per m/s of apparent wind, the square law's secant at
        # WINDAGE_AWS_REF (the core's apparent wind is at the 10 m reference height: the profile factor at the
        # centre of effort is applied), charged by the core at its own apparent wind (boat.md 5.8); linear = the
        # rate that reproduces the time the hull coasts from its close-hauled speed to half of it with the drive
        # gone (a tack, a luff, let-fly), median over 6 to 16 kn TWS
        rig0 = self.results[0].rig
        rig_s = self._start_result().rig
        drag = self.hull.resistance(np.array([1.0]), np.zeros(1), np.zeros(1))
        decel_const = float(drag[0] / me)
        k_ce = float(wind_at(1.0, rig_s.ce_height(1.0))) ** 2
        w_ref = np.array([WINDAGE_AWS_REF])
        decel_windage = float(k_ce * rig_s.windage_force(w_ref, np.zeros(1))[0] / (WINDAGE_AWS_REF * me))
        decel_linear = self._coast_rate(decel_const)

        # heel speed factor: 1 up to the VPP heel limit, beyond it the surge equilibrium with the heel held there
        # (rig power falling with the heeled apparent wind, heeled hull and deck-edge drag), relative to the limit;
        # reference condition: the upwind config at 12 kn TWS, 45 deg TWA, as depowered by the VPP
        ref = self.results[min(1, len(self.results) - 1)]
        i12 = int(np.argmin(np.abs(self.tws - 6.2)))
        j45 = int(np.argmin(np.abs(self.twa - 45 * DEG)))
        hk = np.unique(np.concatenate([[0.0, b.heel_max], np.radians(np.arange(5, 91, 5))]))
        hk = hk[(hk <= b.heel_max + 1e-9) | (hk > b.heel_max + 2 * DEG)]
        over = hk[hk > b.heel_max + 1e-9]
        ph = np.concatenate([[b.heel_max], over])
        n = len(ph)
        Vh = self.solver.solve_speed(ref.rig, np.full(n, ref.fi[i12, j45]), np.full(n, ref.reef[i12, j45]),
                                     np.full(n, self.tws[i12]), np.full(n, self.twa[j45]), ph,
                                     np.full(n, 2.2 * self.tws[i12]))
        rel = np.minimum.accumulate(np.clip(Vh / max(Vh[0], 1e-3), 0.05, 1.0))
        hsf = np.concatenate([np.ones(len(hk) - len(over)), rel[1:]])

        # heel spring: roll stiffness and inertia, aerodynamic roll damping of the rig
        rm = H.rm_boat + H.rm_crew
        k_roll = max(float((rm[3] - rm[0]) / H.heel[3]), 1.0) if b.kind == "monohull" else \
            max(float(np.max(np.gradient(rm, H.heel)[:5])), 1.0)
        i_roll = (b.mass_boat * (0.35 * b.beam_max) ** 2 + b.rig_mass * b.mast_height ** 2 / 3
                  + (b.bulb.mass * b.bulb.depth ** 2 if b.bulb else 0.0) + b.mass_crew * b.crew_arm ** 2) * 1.2
        heel_freq = float(np.clip(math.sqrt(k_roll / i_roll), 0.8, 4.0))
        area = sum(s.area for s in rig0.sails)
        z_ce = rig0.ce_height(1.0)
        c_aero = 0.5 * RHO_AIR * 6.0 * 3.8 * area * z_ce ** 2
        heel_damping = float(np.clip(c_aero / (2 * math.sqrt(k_roll * i_roll)), 0.4, 1.6))
        # pitch spring: waterplane stiffness against pitch inertia with added mass
        lf = loft(b.bodies[b.main_index or 0])
        xs = np.linspace(0, 1, 401)
        bw = 2 * _plan(lf.body, xs, lf.p)[0]
        xf = np.trapezoid(bw * xs, xs) / np.trapezoid(bw, xs)
        i_wp = np.trapezoid(bw * ((xs - xf) * lf.body.lwl) ** 2, xs) * lf.body.lwl
        i_pitch = (b.mass_boat * (0.24 * b.loa) ** 2 + b.rig_mass * (0.45 * b.mast_height) ** 2
                   + (b.bulb.mass * b.bulb.depth ** 2 if b.bulb else 0.0)) * 1.8
        pitch_freq = float(np.clip(math.sqrt(RHO_WATER * G * i_wp / i_pitch), 1.0, 6.0))
        heel_rm_max, _ = H.rm_max()

        dyn = {
            "helm_rate": helm_rate,
            "rudder_max": b.rudder_max,
            "turn_radius_full": turn_full,
            "turn_radius_offset": turn_offset,
            "yaw_time": yaw_time,
            "decel_linear": decel_linear,
            "decel_const": decel_const,
            "decel_windage": decel_windage,
            "heel_speed_factor": table([("heel_abs", hk)], "1", hsf),
            "rudder_drag_luff": self._rudder_drag(turn_full, turn_offset, 0.0),
            "rudder_drag_bear": self._rudder_drag(turn_full, turn_offset, 0.75),
            "heel_max": float(min(heel_rm_max, 65 * DEG)),
            "heel_limit": 1.40,
            "heel_freq": heel_freq,
            "heel_damping": heel_damping,
            "pitch_freq": pitch_freq,
            "pitch_damping": _by_size(lwl, 0.63, 0.71),
            "wave_roll_gain": 0.3,
            "wave_pitch_gain": 1.0,
            "wobble_heel": 0.0175,
            "wobble_pitch": 0.0175,
            "wobble_freq": 2.0,
            "heave_time": float(np.clip(0.25 * math.sqrt(lwl / L_S), 0.2, 0.6)),
            "waterline_offset": 0.0,
            "surf_gain": float(np.clip(4.0 * (lwl / L_S) ** -0.5, 1.5, 5.0)),
            "lwl": b.lwl,
            "bwl": b.bwl,
            "loa": b.loa,
            "collision": {"outline": self._outline(), "mass": m, "yaw_gyration": 0.28 * b.loa},
            "wind_shadow": self._wind_shadow(),
        }
        # geometry from the boat generator's physics sidecar wins, copied as is
        pin = (self.physics or {}).get("perf_inputs")
        if pin:
            for k in ("loa", "lwl", "bwl", "hull_points"):
                if pin.get(k) is not None:
                    dyn[k] = pin[k]
            if (pin.get("collision") or {}).get("outline"):
                dyn["collision"]["outline"] = pin["collision"]["outline"]
            for k, v in (pin.get("wind_shadow") or {}).items():
                if v is not None:
                    dyn["wind_shadow"][k] = v
            self.notes.append("collision outline, hull points and wind-shadow geometry from the boat generator")
        return dyn

    @property
    def turn_full(self) -> float:
        """turn_radius_full: the lateral-plane balance (README "dynamics"); weather_helm and rudder drag use it."""
        b = self.boat
        return 0.35 * b.lwl * math.sqrt((b.keel.area + b.rudder.area) / b.rudder.area)

    @property
    def turn_offset(self) -> float:
        return self._turn_offset(self.turn_full)

    def _rudder_lift_slope(self):
        rd = self.boat.rudder
        a1 = rd.span * rd.chord
        ar = 2 * rd.span ** 2 / a1
        return a1, ar, 2 * math.pi * ar / (ar + 2)

    def _turn_offset(self, turn_full):
        """turn_radius_offset of the radius law R = (R_full + offset)/|h| - offset (boat.md 5.9).

        The turn rate grows in proportion to the helm until the rudder stalls, at the helm h_s where
        RUDDER_AOA_SHARE of the rudder angle reaches the stall of the blade's lift line, and little beyond it. The
        offset gives the law the slope of this linear-then-stalled rudder at small helm, where the boat is steered
        and held against its helm balance: R(h) -> h_s R_full / h, so turn_c = h_s R_full and
        offset = -(1 - h_s) R_full: 0 for a rudder that never stalls (radius in proportion to 1/helm), negative
        when it stalls short of full helm (the law then reaches about 80 % of the full-helm rate at h_s). h_s is
        held in [0.6, 1] (turn_c >= 0.6 R_full)."""
        _, _, cla = self._rudder_lift_slope()
        h_s = RUDDER_CL_MAX / (cla * RUDDER_AOA_SHARE * self.boat.rudder_max)
        h_s = float(np.clip(h_s, 0.6, 1.0))
        return -(1.0 - h_s) * turn_full

    def _coast_rate(self, decel_const):
        """decel_linear: the k for which dv/dt = -(k v + decel_const) coasts from the close-hauled VMG speed to half
        of it in the time the upright hull takes with the drive gone, dv/dt = -(R(v)/(m + m_a) + decel_const);
        median over the TWS rows from 6 to 16 kn."""
        rates = []
        for i, tws in enumerate(self.tws):
            if not 3.0 <= tws <= 8.5:
                continue
            best = 0.0
            for r in self.results:
                vm = r.V[i] * np.cos(self.twa)
                j = int(np.argmax(np.where(r.valid[i], vm, -1.0)))
                if r.valid[i, j]:
                    best = max(best, float(r.V[i, j]))
            if best <= 0.1:
                continue
            v = np.linspace(0.5 * best, best, 201)
            dec = self.hull.resistance(v, 0 * v, 0 * v) / self.mass_eff + decel_const
            t_coast = float(np.trapezoid(1.0 / dec, v))
            lo, hi = 1e-5, 5.0
            for _ in range(60):
                k = 0.5 * (lo + hi)
                t = math.log((k * best + decel_const) / (0.5 * k * best + decel_const)) / k
                lo, hi = (k, hi) if t > t_coast else (lo, k)
            rates.append(0.5 * (lo + hi))
        return float(np.median(rates)) if rates else 0.05

    def _rudder_drag(self, turn_full, turn_offset, shift):
        """Speed loss (m/s^2) from the rudder and the keel's turning side force, per boat speed and helm."""
        b = self.boat
        v = np.array([0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 20.0])
        hh = np.array([0, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
        V = np.maximum(v[:, None] - shift, 0.0) + 0 * hh[None, :]
        q = 0.5 * RHO_WATER * V * V
        rd = b.rudder
        a1, ar, cla = self._rudder_lift_slope()
        # the blade's incidence in the turn: the share of the rudder angle the radius law's offset assumes
        alpha = RUDDER_AOA_SHARE * hh[None, :] * b.rudder_max
        cl_max = RUDDER_CL_MAX
        cl = np.minimum(cla * alpha, cl_max)
        # past the stall incidence the flow separates over RUDDER_STALL_RANGE and the blade's force turns into a
        # normal force of about its maximum lift, whose drag component is cl_max sin(alpha)
        stalled = np.clip((alpha - cl_max / cla) / RUDDER_STALL_RANGE, 0, 1)
        cd = 0.012 + cl ** 2 / (math.pi * ar * 0.9) + stalled * cl_max * np.sin(alpha)
        d_rudder = q * a1 * rd.count * cd
        R = (turn_full + turn_offset) / np.maximum(hh[None, :], 1e-6) - turn_offset
        R = np.maximum(R, 0.5)
        fc = np.where(hh[None, :] > 0, b.mass * V ** 2 / R, 0.0)
        d_keel = self.hull.induced(np.maximum(V, 0.05), np.zeros_like(V), fc) * (V > 0)
        return table([("boat_speed_abs", v), ("helm_abs", hh)], "m/s2", (d_rudder + d_keel) / self.mass_eff)

    def _outline(self):
        """Collision hull outline, reference construction of collisions.md 2.1 (ccw in x forward, y port)."""
        b = self.boat
        xs, xb = b.transom_x, b.stem_x
        L = xb - xs
        B = b.beam_max
        T = min(b.transom_width, 0.95 * B)
        sm = b.max_beam_station
        pts = []
        for s in (0, 0.15, 0.3, sm, 0.6, 0.75, 0.87, 0.95):
            if s <= sm:
                hb = T / 2 + (B / 2 - T / 2) * (1 - (1 - s / sm) ** 2)
            else:
                u = (s - sm) / (1 - sm)
                hb = (B / 2) * (1 - u ** 1.8)
            pts.append((xs + s * L, hb))
        pts = sorted(set(pts))
        out = [[xb, 0.0]] + [[x, y] for x, y in reversed(pts)] + [[x, -y] for x, y in pts]
        return out

    def _wind_shadow(self):
        b = self.boat
        main = b.main_sail
        fronts = [s for s in b.sails if s.type in ("jib", "genoa")]
        spins = [s for s in b.sails if s.type in SPINNAKER_TYPES]
        up = [main] + fronts[:1]
        ce_x = sum(s.area * s.ce_x for s in up) / sum(s.area for s in up)
        return {
            "height": b.mast_height, "ce_x": ce_x, "stern_x": b.transom_x, "chord": b.rig_J + b.rig_E,
            "width_min": 1.5 * b.rig_E,
            "width_spinnaker": (max(s.foot for s in spins) if spins else 1.5 * b.rig_E) + b.rig_E,
            "length_coef": 4.5, "length_knee": 4.12, "blanket_depth": 0.22, "blanket_depth_spinnaker": 0.25,
            "blanket_peak": 0.25, "blanket_near": 0.7, "blanket_reach_up": 0.05, "blanket_spread": 0.10,
            "turb_length": 0.4, "turb_depth": 0.15, "turb_width": max(b.beam_max, 1.5), "turb_spread": 0.3,
            "turb_angle": 10 * DEG, "turb_awa_fade": 70 * DEG, "turb_awa_max": 75 * DEG, "header_coef": 0.4,
            "header_max": 3 * DEG,
        }

    # ---------------------------------------------------------------------------------------------------------
    def _sail_block(self, s) -> Dict:
        b = self.boat
        lwl = b.lwl
        t = s.type
        spin = t in SPINNAKER_TYPES
        rates = {"main": (0.55, 0.75), "jib": (0.65, 0.95), "genoa": (0.55, 0.9), "code_zero": (0.4, 0.9),
                 "spinnaker_sym": (0.3, 0.85), "spinnaker_asym": (0.3, 0.85)}[t]
        out = {"type": t, "sheet_min": s.sheet_min, "sheet_max": s.sheet_max, "rate_in": rates[0],
               "rate_out": rates[1], "shiver_free": spin}
        tw = TWS
        if t == "main":
            out["shiver_angle"] = table([("tws", [0, 12, 23])], "rad", np.radians([12, 12, 20]))
            # the boom end reaches the water when heeled: h cos(phi) = E sin(beta) sin(phi)
            ph = np.radians([10, 20, 30, 40, 50, 60, 70, 80])
            lim = np.arcsin(np.clip(b.boom_height * np.cos(ph) / (b.rig_E * np.sin(ph)), 0, 1))
            out["sheet_max_by_heel"] = table([("heel_abs", ph)], "rad", np.clip(lim, 0.1, s.sheet_max))
        elif spin:
            out["shiver_angle"] = table([("tws", [0, 3, 9])], "rad", np.radians([16, 16, 35]))
            awa = AWA
            if t == "spinnaker_asym":
                pole = np.interp(awa, np.radians([0, 60, 150, 180]), np.radians([3, 3, 28, 32]))
            else:
                pole = np.clip(awa - math.pi / 2, 5 * DEG, 85 * DEG)
            out["pole_angle"] = table([("tws", tw), ("awa_abs", awa)], "rad", np.tile(pole, (len(tw), 1)))
            out["pole_rate"] = 0.35
        else:
            out["shiver_angle"] = table([("tws", [0, 20.6])], "rad", np.radians([2, 4]))
        if t != "main":
            f = 0.6 if s.furling else 1.0
            if spin:
                d180 = 4.0
                twa = np.concatenate([[0], np.radians(np.arange(30, 181, 30))])
                drop = d180 * (1 + 2 * (1 - twa / math.pi) ** 2)
                h = {"prepare_hoist_time": 2.0, "hoist_time": _by_size(lwl, 4.0, 6.5),
                     "prepare_drop_time": 0.0,
                     "drop_time": table([("tws", [0, 20.6]), ("twa_abs", twa)], "s", np.tile(drop, (2, 1))),
                     "slow_prepare_hoist": 1.0, "slow_hoist": 0.95, "slow_prepare_drop": 1.0,
                     "slow_drop": float(np.clip(0.1 + (0.65 - 0.1) * (lwl - L_S) / (L_L - L_S), 0.1, 0.65))}
            else:
                h = {"prepare_hoist_time": _by_size(lwl, 0.5, 2.0), "hoist_time": f * _by_size(lwl, 2.5, 7.5),
                     "prepare_drop_time": 2.0, "drop_time": f * _by_size(lwl, 4.0, 7.5),
                     "slow_prepare_hoist": 1.0, "slow_hoist": _by_size(lwl, 0.9, 0.8), "slow_prepare_drop": 1.0,
                     "slow_drop": _by_size(lwl, 0.9, 0.8)}
            h.update(s.handling or {})
            out["handling"] = h
        return out


# -------------------------------------------------------------------------------------------------------------
# handling multipliers (data_format.md 3.7.1): feel only, never the polar


def _stretch_heel_axis(t: Dict, k: float) -> Dict:
    """A Table1D over heel_abs resampled so the value at heel k*phi is the old value at phi."""
    ph = np.array(t["axes"][0]["points"])
    v = np.array(t["values"])
    return table([("heel_abs", ph)], t["unit"], np.interp(ph / k, ph, v))


def apply_handling(out: Dict, feel: Dict[str, float]):
    """Scale the feel of a generated performance file in place; every multiplier 1 leaves it untouched.

    accel: every config's ``accel`` and ``accel_rest`` tables. decel: ``decel_linear``, ``decel_const``,
    ``decel_windage`` and every config's ``flog_drag``. turn_rate: the yaw rate at
    every helm and speed, by dividing ``turn_radius_full`` and ``turn_radius_offset``. heel: every config's
    ``heel`` table and ``heel_max`` (below ``heel_limit``), with ``heel_speed_factor`` and the main's
    ``sheet_max_by_heel`` stretched along their heel axes so the speed at the scaled heel is unchanged. tack_time:
    ``helm_rate`` and every sail's ``rate_in``, ``rate_out`` and ``pole_rate`` divided by it.
    """
    ka, kd, kt, kh, kc = (float(feel.get(k, 1.0)) for k in ("accel", "decel", "turn_rate", "heel", "tack_time"))
    dyn = out["dynamics"]
    if ka != 1.0:
        for c in out["configs"]:
            for k in ("accel", "accel_rest"):
                c[k]["values"] = [x * ka for x in c[k]["values"]]
    if kd != 1.0:
        dyn["decel_linear"] *= kd
        dyn["decel_const"] *= kd
        dyn["decel_windage"] *= kd
        for c in out["configs"]:
            c["flog_drag"]["values"] = [x * kd for x in c["flog_drag"]["values"]]
    if kt != 1.0:
        dyn["turn_radius_full"] /= kt
        dyn["turn_radius_offset"] /= kt
    if kh != 1.0:
        for c in out["configs"]:
            c["heel"]["values"] = [min(x * kh, math.pi / 2) for x in c["heel"]["values"]]
        dyn["heel_max"] = min(dyn["heel_max"] * kh, 0.98 * dyn["heel_limit"])
        dyn["heel_speed_factor"] = _stretch_heel_axis(dyn["heel_speed_factor"], kh)
        for s in out["sails"].values():
            if "sheet_max_by_heel" in s:
                s["sheet_max_by_heel"] = _stretch_heel_axis(s["sheet_max_by_heel"], kh)
    if kc != 1.0:
        dyn["helm_rate"] /= kc
        for s in out["sails"].values():
            for k in ("rate_in", "rate_out", "pole_rate"):
                if k in s:
                    s[k] /= kc


def generate(boat: Boat, thin_ship: Optional[bool] = None, physics: Optional[Dict] = None) -> Dict:
    return Generator(boat, thin_ship=thin_ship, physics=physics).run()


# -------------------------------------------------------------------------------------------------------------
# validation of the written file (data_format.md 5)

RANGES = {"polar": (-5, 40), "heel": (0, math.pi / 2), "accel": (0, None), "accel_rest": (0, None),
          "fall_off": (0, None), "flog_drag": (0, None), "trim_speed": (0, 3), "trim_heel": (0, 3),
          "heel_speed_factor": (0, 3), "optimal_angle": (0, math.pi)}
QUANTITIES = ("tws", "twa_abs", "awa_abs", "trim_error", "boat_speed", "boat_speed_abs", "helm_abs", "heel_abs", "aws")


def validate_table(t: Dict, path: str):
    axes = t["axes"]
    if not 1 <= len(axes) <= 3:
        raise ValueError(f"{path}: 1-3 axes")
    n = 1
    for a in axes:
        p = a["points"]
        if a["q"] not in QUANTITIES:
            raise ValueError(f"{path}: axis quantity {a['q']}")
        if not 1 <= len(p) <= 256:
            raise ValueError(f"{path}: axis {a['q']} has {len(p)} points")
        d = np.diff(p)
        if np.any(d < 0):
            raise ValueError(f"{path}: axis {a['q']} decreasing")
        if np.any((d[:-1] == 0) & (d[1:] == 0)):
            raise ValueError(f"{path}: axis {a['q']} three equal points")
        n *= len(p)
    if len(t["values"]) != n:
        raise ValueError(f"{path}: {len(t['values'])} values for {n}")
    if t["unit"] not in ("m/s", "rad", "m/s2", "rad/s", "s", "1"):
        raise ValueError(f"{path}: unit {t['unit']}")


def validate(perf: Dict):
    if perf.get("schema") != SCHEMA:
        raise ValueError("schema")

    def walk(o, path):
        if isinstance(o, dict):
            if "axes" in o and "values" in o:
                validate_table(o, path)
                key = path.split(".")[-1]
                for name, (lo, hi) in RANGES.items():
                    if key == name or f".{name}." in path + ".":
                        v = np.array(o["values"])
                        if (lo is not None and v.min() < lo - 1e-9) or (hi is not None and v.max() > hi + 1e-9):
                            raise ValueError(f"{path}: values outside [{lo}, {hi}]")
                return
            for k, v in o.items():
                walk(v, f"{path}.{k}")
        elif isinstance(o, list):
            for i, v in enumerate(o):
                walk(v, f"{path}[{i}]")
        elif isinstance(o, float) and not math.isfinite(o):
            raise ValueError(f"{path}: non-finite")

    walk(perf, "")
    for c in perf["configs"]:
        tws = c["polar"]["axes"][0]["points"]
        if tws[0] != 0 or tws[-1] < 20.6:
            raise ValueError("configs: tws axis must cover 0 to 20.6 m/s")
