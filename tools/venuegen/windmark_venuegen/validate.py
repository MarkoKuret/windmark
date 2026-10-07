"""Checks of a venue file against data_format.md §6 and the performance budget of venues.md §4.1.

`validate(doc)` returns a list of "path: reason" problems (empty when the file is good). It mirrors the core's
loader and adds the shipped-venue caps, the conditions table of §6.7 and the briefing rules of §6.8."""

from __future__ import annotations

import json
import math
import re

import numpy as np

from .geo import signed_area
from .simplify import simple_problem

CAPS = {
    "land_vertices_total": 4000,
    "land_vertices_polygon": 1500,
    "obstacles": 64,
    "wind_nodes": 96,
    "field_nodes": 128,
    "min_spacing": 50.0,
    "file_bytes": 3 * 1024 * 1024,
}

SHIFT_PRESETS = ["steady", "stable", "oscillating", "shifty", "unstable"]
PUFF_PRESETS = ["none", "light", "standard", "gusty"]
KN = 0.514444
SPEED_MIN, SPEED_MAX = 2.06, 12.87  # the menu's 4 to 25 kn, as the spec writes them
ID_RE = re.compile(r"^[a-z0-9_]+$")
EM_DASH = "—"


def _f32(v):
    return np.float32(v).item()


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


class _Checker:
    def __init__(self):
        self.problems = []

    def fail(self, path, why):
        self.problems.append(f"{path}: {why}")
        return False

    def need(self, cond, path, why):
        return True if cond else self.fail(path, why)


def _grid(c, g, path, cap):
    ok = isinstance(g, dict)
    if not ok:
        return c.fail(path, "grid missing")
    for k in ("x0", "y0", "dx", "dy"):
        if not _num(g.get(k)):
            return c.fail(f"{path}.{k}", "not a finite number")
    for k in ("nx", "ny"):
        v = g.get(k)
        if not (isinstance(v, int) and not isinstance(v, bool)) or not 2 <= v <= 1024:
            return c.fail(f"{path}.{k}", "a grid side has 2 to 1024 nodes")
        c.need(v <= cap, f"{path}.{k}", f"over the shipped-venue cap of {cap} nodes (venues.md §4.1)")
    for k in ("dx", "dy"):
        if not g[k] > 0:
            return c.fail(f"{path}.{k}", "spacing must be > 0")
        c.need(g[k] >= CAPS["min_spacing"], f"{path}.{k}", "spacing under 50 m (venues.md §4.1)")
    return True


def _values(c, arr, n, path, lo=-math.inf, hi=math.inf):
    if not isinstance(arr, list) or len(arr) != n:
        return c.fail(path, f"needs exactly {n} values")
    for i, v in enumerate(arr):
        if not _num(v):
            return c.fail(f"{path}[{i}]", "not a finite number")
        if not lo <= _f32(v) <= hi:
            return c.fail(f"{path}[{i}]", f"out of range [{lo}, {hi}]")
    return True


def _header(c, doc):
    c.need(doc.get("schema") == "windmark.venue/1", "$.schema", "must be windmark.venue/1")
    c.need(isinstance(doc.get("id"), str) and ID_RE.match(doc["id"] or ""), "$.id", "lowercase [a-z0-9_]")
    name = doc.get("name")
    c.need(isinstance(name, str) and name, "$.name", "required")
    if isinstance(name, str):
        c.need(EM_DASH not in name, "$.name", "player-facing: no em dashes")
    v = doc.get("version")
    c.need(isinstance(v, int) and not isinstance(v, bool) and v >= 1, "$.version", "integer >= 1")
    b = doc.get("bounds")
    if not (isinstance(b, list) and len(b) == 4 and all(_num(x) for x in b)):
        return c.fail("$.bounds", "four finite numbers")
    for i, x in enumerate(b):
        c.need(-8000 <= x <= 8000, f"$.bounds[{i}]", "within +-8000 m")
    c.need(b[0] < b[2] and b[1] < b[3], "$.bounds", "xmin < xmax and ymin < ymax")
    o = doc.get("origin")
    if o is not None:
        c.need(_num(o.get("lat")) and -90 <= o["lat"] <= 90, "$.origin.lat", "in [-90, 90]")
        c.need(_num(o.get("lon")) and -180 <= o["lon"] <= 180, "$.origin.lon", "in [-180, 180]")
    if "fetch" in doc:
        c.need(_num(doc["fetch"]) and doc["fetch"] > 0, "$.fetch", "> 0")
    if "exposure_default" in doc:
        c.need(_num(doc["exposure_default"]) and 0 <= doc["exposure_default"] <= 1, "$.exposure_default", "[0, 1]")
    if "source" in doc:
        c.need(isinstance(doc["source"], str), "$.source", "a string")
    return True


def _wind(c, w):
    if not _grid(c, w.get("grid"), "$.wind_field.grid", CAPS["wind_nodes"]):
        return
    g = w["grid"]
    n = g["nx"] * g["ny"]
    secs = w.get("sectors")
    if not (isinstance(secs, list) and len(secs) == 8):
        c.fail("$.wind_field.sectors", "exactly 8 sectors")
        return
    for k, s in enumerate(secs):
        p = f"$.wind_field.sectors[{k}]"
        if not (_values(c, s.get("f"), n, p + ".f", 0.0) and _values(c, s.get("d"), n, p + ".d", -math.pi, math.pi)):
            continue
        for r in range(n):
            i, j = r % g["nx"], r // g["nx"]
            if i in (0, g["nx"] - 1) or j in (0, g["ny"] - 1):
                if _f32(s["f"][r]) != 1.0:
                    c.fail(f"{p}.f[{r}]", "border nodes must be f = 1")
                    break
                if _f32(s["d"][r]) != 0.0:
                    c.fail(f"{p}.d[{r}]", "border nodes must be d = 0")
                    break


def _current(c, cf):
    if not _grid(c, cf.get("grid"), "$.current_field.grid", CAPS["field_nodes"]):
        return
    n = cf["grid"]["nx"] * cf["grid"]["ny"]
    _values(c, cf.get("vx"), n, "$.current_field.vx")
    _values(c, cf.get("vy"), n, "$.current_field.vy")
    if "ref_speed" in cf:
        c.need(_num(cf["ref_speed"]) and cf["ref_speed"] >= 0, "$.current_field.ref_speed", ">= 0")
    if "ref_to" in cf:
        c.need(_num(cf["ref_to"]) and 0 <= cf["ref_to"] < 2 * math.pi, "$.current_field.ref_to", "in [0, 2pi)")


def _exposure(c, e):
    if not _grid(c, e.get("grid"), "$.exposure.grid", CAPS["field_nodes"]):
        return
    n = e["grid"]["nx"] * e["grid"]["ny"]
    _values(c, e.get("e"), n, "$.exposure.e", 0.0, 1.0)


def _polygon(c, pts, path):
    if not (isinstance(pts, list) and len(pts) >= 3 and all(isinstance(q, list) and len(q) == 2 and
                                                             all(_num(v) for v in q) for q in pts)):
        return c.fail(path, "at least 3 points [x, y] of finite numbers"), None
    p = np.array(pts, np.float32).astype(np.float64)
    why = simple_problem(p)
    if why:
        return c.fail(path, why), None
    return True, p


def _land_obstacles(c, doc):
    land = doc.get("land", [])
    ids = set()
    total = 0
    for k, l in enumerate(land):
        path = f"$.land[{k}]"
        lid = l.get("id")
        c.need(isinstance(lid, str) and ID_RE.match(lid or "") and lid not in ids, path + ".id", "unique id")
        ids.add(lid)
        ok, p = _polygon(c, l.get("points"), path + ".points")
        if ok:
            c.need(signed_area(p) > 0, path + ".points", "land must be counter-clockwise")
            total += len(p)
            c.need(len(p) <= CAPS["land_vertices_polygon"], path + ".points",
                   f"over {CAPS['land_vertices_polygon']} vertices (venues.md §4.1)")
    c.need(total <= CAPS["land_vertices_total"], "$.land", f"over {CAPS['land_vertices_total']} vertices in total")
    obs = doc.get("obstacles", [])
    c.need(len(obs) <= CAPS["obstacles"], "$.obstacles", f"over {CAPS['obstacles']} obstacles")
    ids = set()
    for k, o in enumerate(obs):
        path = f"$.obstacles[{k}]"
        oid = o.get("id")
        c.need(isinstance(oid, str) and ID_RE.match(oid or "") and oid not in ids, path + ".id", "unique id")
        ids.add(oid)
        if ("polygon" in o) == ("circle" in o):
            c.fail(path, "exactly one of polygon and circle")
            continue
        if "circle" in o:
            ci = o["circle"]
            c.need(isinstance(ci.get("c"), list) and len(ci["c"]) == 2 and all(_num(v) for v in ci["c"]),
                   path + ".circle.c", "a point")
            c.need(_num(ci.get("r")) and ci["r"] > 0, path + ".circle.r", "r > 0")
            continue
        ok, p = _polygon(c, o["polygon"], path + ".polygon")
        if ok:
            n = len(p)
            for i in range(n):
                a, b, d = p[i], p[(i + 1) % n], p[(i + 2) % n]
                cr = (b[0] - a[0]) * (d[1] - b[1]) - (b[1] - a[1]) * (d[0] - b[0])
                if not cr > 0:
                    c.fail(f"{path}.polygon[{(i + 1) % n}]", "obstacle polygon not strictly convex and counter-clockwise")
                    break


def _range(c, v, path, lo, hi):
    return c.need(isinstance(v, list) and len(v) == 2 and all(_num(x) for x in v) and lo <= v[0] <= v[1] <= hi,
                  path, f"[min, max] with {lo} <= min <= max <= {hi}")


def check_conditions(c, cond, has_current_field):
    p = "$.conditions"
    if not isinstance(cond, dict):
        return c.fail(p, "an object")
    w = cond.get("wind", {})
    if "speed" in w:
        _range(c, w["speed"], p + ".wind.speed", SPEED_MIN, SPEED_MAX)
    if "from" in w:
        c.need(_num(w["from"]) and 0 <= w["from"] < 2 * math.pi, p + ".wind.from", "in [0, 2 pi)")
    if "from_spread" in w:
        c.need(_num(w["from_spread"]) and 0 <= w["from_spread"] <= 0.349, p + ".wind.from_spread", "in [0, 0.349]")
    s = cond.get("shift", {})
    if "preset" in s:
        c.need(s["preset"] in SHIFT_PRESETS, p + ".shift.preset", f"one of {SHIFT_PRESETS}")
    for k in ("amplitude", "hold_max", "hold_min", "trend_rate"):
        if k in s:
            c.need(_num(s[k]), f"{p}.shift.{k}", "a finite number")
    for k in ("amplitude", "hold_max", "hold_min"):
        if k in s and _num(s[k]):
            c.need(s[k] >= 0, f"{p}.shift.{k}", ">= 0")
    if _num(s.get("hold_min")) and _num(s.get("hold_max")):
        c.need(s["hold_min"] <= s["hold_max"], p + ".shift.hold_min", "hold_min <= hold_max")
    if "trend_max" in s:
        c.need(_num(s["trend_max"]) and 0 <= s["trend_max"] <= 0.35, p + ".shift.trend_max", "in [0, 0.35]")
    if "oscillation" in cond:
        o = cond["oscillation"]
        c.need(_num(o.get("amplitude")) and 0 <= o["amplitude"] <= 0.087, p + ".oscillation.amplitude",
               "in [0, 0.087]")
        c.need(_num(o.get("time_scale")) and o["time_scale"] > 0, p + ".oscillation.time_scale", "> 0")
    pf = cond.get("puffs", {})
    if "preset" in pf:
        c.need(pf["preset"] in PUFF_PRESETS, p + ".puffs.preset", f"one of {PUFF_PRESETS}")
    for k, v in pf.items():
        if k != "preset":
            c.need(_num(v) and v >= 0, f"{p}.puffs.{k}", "a finite number >= 0 (checked in full by wind.md §6)")
    cu = cond.get("current", {})
    if "speed" in cu:
        c.need(_num(cu["speed"]) and cu["speed"] >= 0, p + ".current.speed", ">= 0")
    if "to" in cu:
        c.need(_num(cu["to"]), p + ".current.to", "a finite number")
    if "tide" in cond:
        t = cond["tide"]
        c.need(has_current_field, p + ".tide", "requires a current_field")
        c.need(_num(t.get("scale")) and t["scale"] >= 0, p + ".tide.scale", ">= 0")
        per = t.get("period")
        c.need(isinstance(per, int) and not isinstance(per, bool) and per > 0, p + ".tide.period", "integer s > 0")
        extra = sorted(set(t) - {"scale", "period"})
        c.need(not extra, p + ".tide", f"unknown keys {extra} (each race draws the phase, race.md §2.1)")
    se = cond.get("sea", {})
    if "scale" in se:
        c.need(_num(se["scale"]) and se["scale"] >= 0, p + ".sea.scale", ">= 0")
    sw = se.get("swells", [])
    c.need(isinstance(sw, list) and len(sw) <= 4, p + ".sea.swells", "at most 4")
    for i, s_ in enumerate(sw if isinstance(sw, list) else []):
        q = f"{p}.sea.swells[{i}]"
        c.need(_num(s_.get("hs")) and s_["hs"] >= 0, q + ".hs", ">= 0")
        c.need(_num(s_.get("tp")) and (s_["tp"] > 0 or s_.get("hs") == 0), q + ".tp", "> 0 when hs > 0")
        c.need(_num(s_.get("from")), q + ".from", "a finite number")
    r = cond.get("random")
    if r is not None:
        if "speed" in r:
            _range(c, r["speed"], p + ".random.speed", SPEED_MIN, SPEED_MAX)
        if "from_spread" in r:
            c.need(_num(r["from_spread"]) and 0 <= r["from_spread"] <= 0.785, p + ".random.from_spread",
                   "in [0, 0.785]")
        for k, allowed in (("shift", SHIFT_PRESETS), ("puffs", PUFF_PRESETS)):
            if k in r:
                c.need(isinstance(r[k], list) and r[k] and all(x in allowed for x in r[k]), f"{p}.random.{k}",
                       f"a non-empty list of {allowed}")
        for k in ("tide_scale", "swell_scale"):
            if k in r:
                _range(c, r[k], f"{p}.random.{k}", 0.0, math.inf)
    return True


def check_briefing(c, b):
    p = "$.briefing"
    if not isinstance(b, dict):
        return c.fail(p, "an object")
    for k, n in (("tag", 24), ("tip", 80)):
        if k in b:
            c.need(isinstance(b[k], str) and len(b[k]) <= n, f"{p}.{k}", f"a string of at most {n} characters")
            c.need(EM_DASH not in str(b[k]), f"{p}.{k}", "player-facing: no em dashes")
    for lang, tr in (b.get("translations") or {}).items():
        for k, n in (("name", None), ("tag", 24), ("tip", 80)):
            if k in tr:
                v = tr[k]
                c.need(isinstance(v, str), f"{p}.translations.{lang}.{k}", "a string")
                if n:
                    c.need(len(v) <= int(n * 1.25), f"{p}.translations.{lang}.{k}", f"at most {int(n * 1.25)} characters")
                c.need(EM_DASH not in str(v), f"{p}.translations.{lang}.{k}", "player-facing: no em dashes")
    return True


def validate(doc, text=None):
    c = _Checker()
    _header(c, doc)
    if "wind_field" in doc:
        _wind(c, doc["wind_field"])
    if "current_field" in doc:
        _current(c, doc["current_field"])
    if "exposure" in doc:
        _exposure(c, doc["exposure"])
    _land_obstacles(c, doc)
    if "conditions" in doc:
        check_conditions(c, doc["conditions"], "current_field" in doc)
    if "briefing" in doc:
        check_briefing(c, doc["briefing"])
    if text is None:
        text = json.dumps(doc)
    c.need(len(text.encode()) <= CAPS["file_bytes"], "$", "file over 3 MB (venues.md §4.1)")
    return c.problems
