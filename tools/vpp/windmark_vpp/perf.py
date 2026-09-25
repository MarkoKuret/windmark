"""Performance file (`windmark.perf/1`, docs/specs/data_format.md section 4) from a boat class.

Per config (main alone, main + each front sail), on the spec's axes:

* ``polar``: VPP boat speed at optimal trim and depowering; below the no-go edge the steady sternway the windage
  drives, with a step up to +0.1 m/s at the edge (boat.md 7.4);
* ``heel``: equilibrium heel;
* ``accel``: the constant acceleration that reproduces the time to build speed from 50 % to 95 % of the polar,
  integrating (drive - resistance) / (mass + added mass) with the heel in equilibrium at each speed;
* ``trim_speed``, ``trim_heel``: equilibrium speed and heel with every sail sheeted eps away from its optimum
  (the single manual sheet of sails.md 5.2), relative to the trimmed values;
* ``optimal_angle``: best sheet angle of the main and the front sail against the apparent wind.

``dynamics`` values are derived from the design where the VPP has the physics (turn radius, deceleration, heel
and pitch springs, rudder drag, speed loss with heel, collision outline, wind-shadow geometry) and use the
reference values of boat.md and wind_shadow.md scaled with the waterline length otherwise; class-file
``handling`` overrides win. The ``vpp`` block (ignored by the core) records assumptions, VMG optima and
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
from .solver import FLATS, REEFS, Rig, Solver, added_mass_coefficient, make_rig

SCHEMA = "windmark.perf/1"
TWS = np.array([0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20.6])
TWA_SAIL = np.concatenate([np.arange(20, 60, 2), np.arange(60, 180.01, 5)]) * DEG
AWA = np.concatenate([[0, 5], np.arange(10, 180.01, 5)]) * DEG
EPS = np.array([-60, -20, -10, -5, -2, -0.5, 0, 0.5, 2, 5, 10, 20, 60, 120]) * DEG
NF, NR = len(FLATS), len(REEFS)

# reference archetypes of boat.md 4 (S = sportsboat, L = large monohull) by waterline length
L_S, L_L = 6.4, 19.5


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
            "dynamics": dyn,
            "sails": sails,
            "configs": configs,
            "start": {"front_sail": b.start.get("front_sail") if b.start else None},
            "vpp": {"notes": self.notes, "vmg": vmg, "added_mass_coefficient": self.ca,
                    "righting_moment": {"heel": list(np.radians([0, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90])),
                                        "moment": list(self.hydro.righting_moment(
                                            np.radians([0, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90])))}},
        }
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
        return ConfigResult(front=front, rig=rig, V=np.where(ok, take(st.V), 0.0),
                            heel=np.where(ok, take(st.heel), 0.0), awa=take(st.awa), aws=take(st.aws),
                            fi=k // NR, reef=REEFS[k % NR], valid=ok, deltas=[take(d) for d in st.deltas],
                            fh=np.where(ok, take(st.fh), 0.0))

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
        pol = np.zeros((T, len(twa_axis)))
        heel = np.zeros_like(pol)
        accel = np.zeros_like(pol)
        pol[1:, :3] = drift
        pol[1:, 3] = 0.1
        pol[1:, 4:] = np.maximum(r.V[:, keep], 0.0)
        heel[1:, 4:] = r.heel[:, keep]
        accel[1:, :] = 0.005
        accel[1:, 4:] = np.maximum(acc[:, keep], 0.005)
        ts, th = self._trim_tables(r)
        opt = {}
        for k, s in enumerate(rig.sails):
            opt[s.id] = table([("tws", TWS), ("awa_abs", AWA)], "rad", self._opt_angle(r, k))
        out = {
            "front_sail": r.front,
            "polar": table([("tws", TWS), ("twa_abs", twa_axis)], "m/s", pol),
            "heel": table([("tws", TWS), ("twa_abs", twa_axis)], "rad", np.clip(heel, 0, math.pi / 2)),
            "accel": table([("tws", TWS), ("twa_abs", twa_axis)], "m/s2", accel),
            "trim_speed": table([("tws", TWS), ("awa_abs", AWA), ("trim_error", EPS)], "1", ts),
            "trim_heel": table([("tws", TWS), ("awa_abs", AWA), ("trim_error", EPS)], "1", th),
            "optimal_angle": opt,
            "vpp": {
                "flat": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "1", FLATS[r.fi]),
                "reef": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "1", r.reef),
                "awa": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "rad", r.awa),
                "leeway": table([("tws", TWS[1:]), ("twa_abs", self.twa)], "rad", self._leeway(r)),
            },
        }
        return out

    def _accel(self, r: ConfigResult):
        S = self.solver
        rig = r.rig
        tws = self.tws[:, None, None]
        twa = self.twa[None, :, None]
        x, w = np.polynomial.legendre.leggauss(8)
        f0, f1 = 0.5, 0.95
        frac = f0 + (f1 - f0) * (x + 1) / 2
        Vn = r.V[..., None] * frac[None, None, :]
        fi = r.fi[..., None]
        rf = r.reef[..., None]
        heel, _ = S.solve_heel(rig, fi, rf, tws, twa, Vn)
        f, _ = S.net_force(rig, fi, rf, tws, twa, Vn, heel)
        f = np.maximum(f, 1e-3 * self.boat.mass)
        t = np.sum(w[None, None, :] * self.mass_eff / f, axis=-1) * (f1 - f0) * r.V / 2
        return np.where(r.V > 0.05, (f1 - f0) * r.V / np.maximum(t, 1e-6), 0.0)

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
        return np.clip(o, s.sheet_min, s.sheet_max)

    def _trim_tables(self, r: ConfigResult):
        S = self.solver
        T, A = r.V.shape
        E = len(EPS)
        shp = (T, A, E)
        fi = np.broadcast_to(r.fi[..., None], shp)
        rf = np.broadcast_to(r.reef[..., None], shp)
        st = S.solve(r.rig, fi, rf, self.tws[:, None, None], self.twa[None, :, None], outer=5,
                     eps=EPS[None, None, :])
        i0 = int(np.argmin(np.abs(EPS)))
        V, H = st.V, st.heel
        v0 = V[..., i0:i0 + 1]
        h0 = H[..., i0:i0 + 1]
        sf = np.where(v0 > 0.05, np.clip(V / np.maximum(v0, 1e-6), 0, 1.0), 1.0)
        hf = np.where(h0 > 0.2 * DEG, np.clip(H / np.maximum(h0, 1e-6), 0, 3.0), 1.0)
        return self._to_awa(r, sf, 1.0), self._to_awa(r, hf, 1.0)

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
        a_keel, a_rud = b.keel.area, b.rudder.area

        # turning: radius from the lateral plane balance; helm speed scales with size
        turn_full = 0.35 * lwl * math.sqrt((a_keel + a_rud) / a_rud)
        helm_rate = float(np.clip(_by_size(lwl, 1.65, 1.0), 0.6, 2.2))

        # deceleration: linear rate from the resistance/drive slope at the polar, constant = coasting in irons
        rates = []
        for r in self.results:
            dv = np.maximum(0.03 * r.V, 0.03)
            tws = self.tws[:, None]
            twa = self.twa[None, :]
            fp, _ = self.solver.net_force(r.rig, r.fi, r.reef, tws, twa, r.V + dv, r.heel)
            fm, _ = self.solver.net_force(r.rig, r.fi, r.reef, tws, twa, np.maximum(r.V - dv, 0), r.heel)
            k = -(fp - fm) / (2 * dv) / me
            sel = r.valid & (self.tws[:, None] >= 3.0) & (self.tws[:, None] <= 8.5) \
                & (self.twa[None, :] >= 40 * DEG) & (self.twa[None, :] <= 150 * DEG)
            rates.extend(k[sel].tolist())
        decel_linear = float(np.median(rates)) if rates else 0.05
        rig0 = self.results[0].rig
        aws = np.array([5.0])
        drag = rig0.windage_force(aws, np.zeros(1)) + self.hull.resistance(np.array([1.0]), np.zeros(1), np.zeros(1))
        decel_const = float(drag[0] / me)

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
            "turn_radius_offset": 3.07,
            "decel_linear": decel_linear,
            "decel_const": decel_const,
            "heel_speed_factor": table([("heel_abs", hk)], "1", hsf),
            "rudder_drag_luff": self._rudder_drag(turn_full, 0.0),
            "rudder_drag_bear": self._rudder_drag(turn_full, 0.75),
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
        for k, v in (b.handling or {}).items():
            if k in dyn:
                dyn[k] = v
            else:
                self.notes.append(f"handling.{k}: not a dynamics key, ignored")
        return dyn

    def _rudder_drag(self, turn_full, shift):
        """Speed loss (m/s^2) from the rudder and the keel's turning side force, per boat speed and helm."""
        b = self.boat
        v = np.array([0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 20.0])
        hh = np.array([0, 0.2, 0.3, 0.4, 0.6, 1.0])
        V = np.maximum(v[:, None] - shift, 0.0) + 0 * hh[None, :]
        q = 0.5 * RHO_WATER * V * V
        rd = b.rudder
        a1 = rd.span * rd.chord
        ar = 2 * rd.span ** 2 / a1
        cla = 2 * math.pi * ar / (ar + 2)
        delta = hh[None, :] * b.rudder_max
        cl_max = 1.1
        cl = np.minimum(cla * delta, cl_max)
        stalled = np.clip((cla * delta - cl_max) / cl_max, 0, 1)
        cd = 0.012 + cl ** 2 / (math.pi * ar * 0.9) + stalled * 1.2 * np.sin(delta) ** 2
        d_rudder = q * a1 * rd.count * cd
        R = (turn_full + 3.07) / np.maximum(hh[None, :], 1e-6) - 3.07
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


def generate(boat: Boat, thin_ship: Optional[bool] = None, physics: Optional[Dict] = None) -> Dict:
    return Generator(boat, thin_ship=thin_ship, physics=physics).run()


# -------------------------------------------------------------------------------------------------------------
# validation of the written file (data_format.md 5)

RANGES = {"polar": (-5, 40), "heel": (0, math.pi / 2), "accel": (0, None), "trim_speed": (0, 3),
          "trim_heel": (0, 3), "heel_speed_factor": (0, 3), "optimal_angle": (0, math.pi)}


def validate_table(t: Dict, path: str):
    axes = t["axes"]
    if not 1 <= len(axes) <= 3:
        raise ValueError(f"{path}: 1-3 axes")
    n = 1
    for a in axes:
        p = a["points"]
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
