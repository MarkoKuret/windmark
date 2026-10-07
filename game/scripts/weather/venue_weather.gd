class_name VenueWeather
extends RefCounted
## A venue's weather on the menus' side: its conditions (data_format.md §6.7) read from the venue file, the weather
## modes it offers (race.md §2.1), the Custom rows' defaults, the pre-race briefing of menus.md §1.3 computed from
## the same numbers the race layer resolves, and the results screen's `Today:` line after a Random race (menus.md
## §5). Pure functions of the venue file, the mode, the Custom picks and the course; computed when a row changes,
## never in a race.

const KNOT := 0.514444
const G := 9.81
const MODES := ["local", "random", "custom"]
## shift presets of wind.md §1: amplitude (deg), hold max (s)
const SHIFTS := ["steady", "stable", "oscillating", "shifty", "unstable"]
const SHIFT_PRESETS := {"steady": [0.0, 0.0], "stable": [3.0, 120.0], "oscillating": [8.0, 90.0],
	"shifty": [15.0, 60.0], "unstable": [25.0, 45.0]}
## puff presets of wind.md §6.1 (menus.md §1: the Gusts row names them after the briefing's word)
const GUSTS := ["none", "light", "standard", "gusty"]
const GUST_NAMES := {"none": "weather.gusts.none", "light": "weather.gusts.light",
	"standard": "weather.gusts.moderate", "gusty": "weather.gusts.very_strong"}
const PUFF_DEFAULTS := {"puff_tile": 1000.0, "puff_count": 5, "lull_count": 5, "puff_diameter_min": 200.0,
	"puff_diameter_max": 300.0, "puff_strength_min": 0.3, "puff_strength_max": 0.5, "lull_strength_min": 0.5,
	"lull_strength_max": 0.7, "puff_life_min": 60.0, "puff_life_max": 120.0, "puff_cap_up": 0.25,
	"puff_cap_down": 0.4}
const PUFF_PRESETS := {
	"light": {"puff_strength_min": 0.10, "puff_strength_max": 0.20, "lull_strength_min": 0.15,
		"lull_strength_max": 0.30, "puff_cap_up": 0.15, "puff_cap_down": 0.25},
	"standard": {},
	"gusty": {"puff_strength_min": 0.40, "puff_strength_max": 0.70, "puff_diameter_min": 150.0,
		"puff_diameter_max": 300.0, "puff_life_min": 30.0, "puff_life_max": 90.0, "puff_count": 7,
		"puff_cap_up": 0.45, "puff_cap_down": 0.40},
}
## a venue without conditions (data_format.md §6.9): Custom only, at these
const NO_CONDITIONS_CUSTOM := {"kn": 12.0, "from_deg": 0.0, "shift": "shifty", "gusts": "standard"}


## What the menus need of a venue file (its parsed JSON): {id, name, tag, tip, has_conditions, conditions (with
## the defaults of data_format.md §6.7 filled), fetch, ref_speed, ref_to (-1 when the file has none),
## has_current_field}.
static func info(doc: Dictionary, lang := "") -> Dictionary:
	var b: Dictionary = doc.get("briefing", {}) if doc.get("briefing") is Dictionary else {}
	var tr: Dictionary = {}
	if lang != "" and b.get("translations") is Dictionary:
		tr = b["translations"].get(lang, {})
	var cf: Variant = doc.get("current_field")
	var out := {
		"id": str(doc.get("id", "")),
		"name": str(tr.get("name", doc.get("name", doc.get("id", "")))),
		"tag": str(tr.get("tag", b.get("tag", ""))),
		"tip": str(tr.get("tip", b.get("tip", ""))),
		"has_briefing": doc.has("briefing"),
		"has_conditions": doc.get("conditions") is Dictionary,
		"fetch": float(doc.get("fetch", 10000.0)),
		"has_current_field": cf is Dictionary,
		"ref_speed": float(cf.get("ref_speed", 0.0)) if cf is Dictionary else 0.0,
		"ref_to": float(cf.get("ref_to", -1.0)) if cf is Dictionary else -1.0,
	}
	out["conditions"] = conditions(doc.get("conditions", {}) if out["has_conditions"] else {})
	return out


## data_format.md §6.7 with its defaults: {speed: [s0, s1] m/s, from, from_spread, shift: {preset, amplitude
## (rad), hold_max (s)}, trend_rate, trend_max, oscillation, puffs (the preset with the overrides, plus `preset`
## and `enabled`), current: {speed, to}, tide ({} or {scale, period}), sea: {scale, swells}}.
static func conditions(c: Dictionary) -> Dictionary:
	var w: Dictionary = c.get("wind", {})
	var s: Dictionary = c.get("shift", {})
	var pf: Dictionary = c.get("puffs", {})
	var sp := str(s.get("preset", "shifty"))
	var amp := deg_to_rad(SHIFT_PRESETS.get(sp, SHIFT_PRESETS["shifty"])[0])
	var hold: float = SHIFT_PRESETS.get(sp, SHIFT_PRESETS["shifty"])[1]
	if s.has("amplitude"):
		amp = float(s["amplitude"])
	if s.has("hold_max"):
		hold = float(s["hold_max"])
	var pp := str(pf.get("preset", "standard"))
	var puffs := puff_preset(pp)
	for k in pf:
		if k != "preset" and puffs.has(k):
			puffs[k] = float(pf[k])
	var spd: Array = w.get("speed", [7.20, 7.20])
	var cu: Dictionary = c.get("current", {})
	var se: Dictionary = c.get("sea", {})
	return {
		"speed": [float(spd[0]), float(spd[1])],
		"from": float(w.get("from", 0.0)),
		"from_spread": float(w.get("from_spread", 0.0)),
		"shift": {"preset": sp, "amplitude": amp, "hold_max": hold, "explicit": s.has("amplitude")},
		"trend_rate": float(s.get("trend_rate", 0.0)),
		"trend_max": float(s.get("trend_max", 0.35)),
		"oscillation": c.has("oscillation"),
		"puffs": puffs,
		"current": {"speed": float(cu.get("speed", 0.0)), "to": float(cu.get("to", 0.0))},
		"tide": c.get("tide", {}) if c.get("tide") is Dictionary else {},
		"sea": {"scale": float(se.get("scale", 1.0)), "swells": se.get("swells", [])},
	}


## The §6.1 parameters of a puff preset (lifetimes in s), with `preset` and `enabled`.
static func puff_preset(p: String) -> Dictionary:
	var out := PUFF_DEFAULTS.duplicate()
	out.merge(PUFF_PRESETS.get(p, {}), true)
	out["preset"] = p
	out["enabled"] = p != "none"
	return out


## The weather modes a venue offers (menus.md §1): all three with conditions, Custom only without.
static func modes(vi: Dictionary) -> Array:
	return MODES.duplicate() if vi.get("has_conditions", false) else ["custom"]


## The Custom rows' defaults (menus.md §1): the middle of the venue's speed range rounded, its typical direction
## rounded to 5°, its shift preset (for an explicit amplitude, the preset whose band holds it) and puff preset.
static func custom_defaults(vi: Dictionary) -> Dictionary:
	if not vi.get("has_conditions", false):
		return NO_CONDITIONS_CUSTOM.duplicate()
	var c: Dictionary = vi["conditions"]
	var mid: float = 0.5 * (c["speed"][0] + c["speed"][1]) / KNOT
	var shift: String = c["shift"]["preset"]
	if c["shift"]["explicit"]:
		shift = shift_band(c["shift"]["amplitude"])
	return {"kn": clampf(roundf(mid), 4.0, 25.0), "from_deg": fposmod(roundf(rad_to_deg(c["from"]) / 5.0) * 5.0, 360.0),
		"shift": shift, "gusts": c["puffs"]["preset"]}


## The race's timing for the trend and the tide (race.md §2.1): t_gun (s after the boats appear) and T_race, from
## the course's sequence and target duration and the free sailing time; free sailing (no course) has no start.
## The caller adds `tide_factor` (tide_at_gun) for a tidal venue; without it the Current line names no state.
static func timing(course: Dictionary, free_sailing_s := 30.0) -> Dictionary:
	if course.is_empty():
		return {"t_gun": 0.0, "t_race": 900.0}
	var r: Dictionary = course.get("race", {}) if course.get("race") is Dictionary else {}
	var warn := 180.0 if str(r.get("sequence", "")) == "3-2-1-0" else 300.0
	var td := float(r.get("target_duration", 0.0))
	return {"t_gun": free_sailing_s + warn, "t_race": td if td > 0.0 else 900.0}


## wind.md §7 the tide factor at the start signal, from settings resolved for the race's seed (race.md §2.1,
## CoreSimSource.resolve_settings): tide_scale · cos(2π ((t_gun + tide_phase_ms) mod P) / P).
static func tide_at_gun(resolved: Dictionary, t_gun_s: float) -> float:
	var p := int(resolved.get("tide_period_ms", 0))
	if p <= 0:
		return 0.0
	var ph := (int(round(t_gun_s * 1000.0)) + int(resolved.get("tide_phase_ms", 0))) % p
	return float(resolved.get("tide_scale", 0.0)) * cos(TAU * float(ph) / float(p))


## What the race will get, as the briefing reads it (menus.md §1.3 "Inputs"): {lo, hi (m/s), from, amplitude,
## hold_max, trend (deg over the race, signed), puffs, current (m/s), uniform, uniform_to, tide, tide_factor (when
## known), tide_stream (m/s), ref_to, sea_scale, swells, fetch}.
## `custom`: {kn, from_deg, shift, gusts}.
static func inputs(vi: Dictionary, mode: String, custom: Dictionary, tm: Dictionary) -> Dictionary:
	var c: Dictionary = vi["conditions"]
	var out := {"fetch": vi.get("fetch", 10000.0), "sea_scale": c["sea"]["scale"], "swells": c["sea"]["swells"],
		"uniform": c["current"]["speed"], "uniform_to": c["current"]["to"], "tide": c["tide"]}
	if mode == "custom":
		var kn := float(custom.get("kn", 12.0))
		out["lo"] = kn * KNOT
		out["hi"] = kn * KNOT
		out["from"] = deg_to_rad(float(custom.get("from_deg", 0.0)))
		var sp: Array = SHIFT_PRESETS.get(str(custom.get("shift", "shifty")), SHIFT_PRESETS["shifty"])
		out["amplitude"] = deg_to_rad(sp[0])
		out["hold_max"] = sp[1]
		out["puffs"] = puff_preset(str(custom.get("gusts", "standard")))
	else:
		out["lo"] = c["speed"][0]
		out["hi"] = c["speed"][1]
		out["from"] = c["from"]
		out["amplitude"] = c["shift"]["amplitude"]
		out["hold_max"] = c["shift"]["hold_max"]
		out["puffs"] = c["puffs"]
	var rate: float = c["trend_rate"]
	var cap: float = c["trend_max"]
	var t0: float = tm["t_gun"]
	var t1: float = t0 + float(tm["t_race"])
	out["trend"] = rad_to_deg(clampf(rate * t1, -cap, cap) - clampf(rate * t0, -cap, cap))
	var tide_scale := float(c["tide"].get("scale", 0.0)) if not c["tide"].is_empty() else 0.0
	var tau := tide_scale
	if not c["tide"].is_empty() and tm.has("tide_factor"):
		tau = float(tm["tide_factor"])
		out["tide_factor"] = tau
	out["tide_stream"] = absf(tau) * float(vi.get("ref_speed", 0.0))
	out["ref_to"] = float(vi.get("ref_to", -1.0))
	out["current"] = absf(c["current"]["speed"]) + out["tide_stream"]
	return out


## The header line: `<NAME> · <tag>` (the name alone without a tag).
static func header(vi: Dictionary) -> String:
	var n := str(vi.get("name", "")).to_upper()
	var tag := str(vi.get("tag", ""))
	return Strings.t("briefing.header", {"name": n, "tag": tag}) if tag != "" else n


## The briefing's lines as [label, value] pairs (menus.md §1.3): Random has only the Weather line; Local ends with
## the Tip when the venue has one; Custom never shows it.
static func lines(vi: Dictionary, mode: String, custom: Dictionary, tm: Dictionary) -> Array:
	if mode == "random":
		return [[Strings.t("briefing.label.weather"), Strings.t("briefing.unknown")]]
	var x := inputs(vi, mode, custom, tm)
	var out := [
		[Strings.t("briefing.label.wind"), wind_text(x["lo"], x["hi"], x["from"])],
		[Strings.t("briefing.label.shifts"), shifts_text(x["amplitude"], x["hold_max"], x["trend"])],
		[Strings.t("briefing.label.gusts"), gusts_text(x["puffs"])],
		[Strings.t("briefing.label.current"), current_text(x)],
		[Strings.t("briefing.label.sea"), sea_text(x)],
	]
	if mode == "local" and str(vi.get("tip", "")) != "":
		out.append([Strings.t("briefing.label.tip"), str(vi["tip"])])
	return out


## The briefing as text, one line per entry, label and value separated by a tab (tests, stills).
static func text(vi: Dictionary, mode: String, custom: Dictionary, tm: Dictionary) -> String:
	var parts := PackedStringArray()
	if mode != "random":
		parts.append(header(vi))
	for l in lines(vi, mode, custom, tm):
		parts.append("%s\t%s" % [l[0], l[1]])
	return "\n".join(parts)


# ---- number formats and rating words (menus.md §1.3) ------------------------------------------------------------

static func round_half_even(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if absf(d - 0.5) < 1e-9:
		return int(f) if int(f) % 2 == 0 else int(f) + 1
	return int(roundf(x))


static func point(rad: float) -> String:
	const PTS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	return Strings.t("compass." + PTS[posmod(round_half_even(fposmod(rad_to_deg(rad), 360.0) / 45.0), 8)])


static func wind_text(lo: float, hi: float, from: float) -> String:
	var a := round_half_even(lo / KNOT)
	var b := round_half_even(hi / KNOT)
	if a == b:
		return Strings.t("briefing.line.wind_one", {"v": a, "point": point(from)})
	return Strings.t("briefing.line.wind", {"lo": a, "hi": b, "point": point(from)})


## menus.md §1.3 the shift word by amplitude (also the preset whose band holds an explicit amplitude).
static func shift_band(a: float) -> String:
	var d := rad_to_deg(a)
	if d < 1.5:
		return "steady"
	if d < 5.5:
		return "stable"
	if d < 11.5:
		return "oscillating"
	if d < 20.0:
		return "shifty"
	return "unstable"


static func shifts_text(a: float, hold_max: float, trend_deg: float) -> String:
	var word := shift_band(a)
	var line := Strings.t("briefing.word.shifts." + word)
	if word != "steady":
		var d := rad_to_deg(a)
		var size := "small" if d < 5.5 else ("medium" if d < 11.5 else ("large" if d < 20.0 else "very_large"))
		var pace := "slow" if hold_max >= 100.0 else ("regular" if hold_max >= 55.0 else "fast")
		line = Strings.t("briefing.line.shifts", {"word": line, "size": Strings.t("briefing.size." + size),
			"pace": Strings.t("briefing.pace." + pace), "a": round_half_even(d)})
	var n := round_half_even(absf(trend_deg))
	if n >= 3:
		line = Strings.t("briefing.line.trend", {"line": line, "n": n,
			"dir": Strings.t("briefing.trend.veers" if trend_deg > 0.0 else "briefing.trend.backs")})
	return line


## The gust word key by g = min(puff_cap_up, puff_strength_max); "none" when puffs are off.
static func gust_word(puffs: Dictionary) -> String:
	if not puffs.get("enabled", true):
		return "none"
	var g := minf(float(puffs["puff_cap_up"]), float(puffs["puff_strength_max"]))
	return "light" if g < 0.18 else ("moderate" if g < 0.28 else ("strong" if g < 0.40 else "very_strong"))


static func gusts_text(puffs: Dictionary) -> String:
	var word := gust_word(puffs)
	if word == "none":
		return Strings.t("briefing.word.gusts.none")
	var g := minf(float(puffs["puff_cap_up"]), float(puffs["puff_strength_max"]))
	var d := 0.25 * (float(puffs["puff_diameter_min"]) + float(puffs["puff_diameter_max"]))
	var k := float(puffs["puff_count"]) * PI * d * d / pow(float(puffs["puff_tile"]), 2.0)
	var spread := "scattered" if k < 0.15 else ("frequent" if k < 0.35 else "everywhere")
	return Strings.t("briefing.line.gusts", {"word": Strings.t("briefing.word.gusts." + word),
		"g": round_half_even(g * 100.0), "spread": Strings.t("briefing.spread." + spread)})


static func current_text(x: Dictionary) -> String:
	var kn: float = x["current"] / KNOT
	var tide: Dictionary = x["tide"]
	var known := not tide.is_empty() and x.has("tide_factor")
	var near_slack := known and float(x.get("tide_stream", 0.0)) / KNOT < 0.3
	if near_slack and absf(float(x["uniform"])) / KNOT < 0.2:
		return Strings.t("briefing.line.current_slack")
	if kn < 0.2:
		return Strings.t("briefing.word.current.none")
	var word := "light" if kn < 0.6 else ("moderate" if kn < 1.2 else ("strong" if kn < 2.0 else "very_strong"))
	var line := Strings.t("briefing.line.current", {"word": Strings.t("briefing.word.current." + word),
		"c": "%.1f" % (round_half_even(kn * 10.0) / 10.0)})
	if known and not near_slack:
		var tau := float(x["tide_factor"])
		var state := Strings.t("briefing.tide." + ("flooding" if tau > 0.0 else "ebbing"))
		var to := float(x.get("ref_to", -1.0))
		if to < 0.0:
			return Strings.t("briefing.line.current_tide_noset", {"line": line, "state": state})
		return Strings.t("briefing.line.current_tide", {"line": line, "state": state,
			"point": point(to if tau > 0.0 else to + PI)})
	if float(x["uniform"]) > 0.0:
		return Strings.t("briefing.line.current_sets", {"line": line, "point": point(x["uniform_to"])})
	return line


## sea.md §2 the wind-sea Hs for a wind U (m/s) and a fetch F (m).
static func wind_sea_hs(u: float, fetch: float) -> float:
	if u < 1.0:
		return 0.0
	var chi := minf(G * fetch / (u * u), 2.2e4)
	return 0.0016 * sqrt(chi) * u * u / G


static func _sea_word(hs: float) -> String:
	return "flat" if hs < 0.25 else ("chop" if hs < 0.5 else ("moderate" if hs < 1.0 else "rough"))


static func sea_text(x: Dictionary) -> String:
	var a := _sea_word(wind_sea_hs(x["lo"], x["fetch"]) * x["sea_scale"])
	var b := _sea_word(wind_sea_hs(x["hi"], x["fetch"]) * x["sea_scale"])
	var line := Strings.t("briefing.word.sea." + a)
	if a != b:
		line = Strings.t("briefing.line.sea_range", {"a": line, "b": Strings.t("briefing.word.sea." + b).to_lower()})
	for sw in x["swells"]:
		var hs := float(sw.get("hs", 0.0)) * float(x["sea_scale"])
		if hs >= 0.3:
			line = Strings.t("briefing.line.swell", {"line": line, "hs": "%.1f" % (round_half_even(hs * 10.0) / 10.0),
				"point": point(float(sw.get("from", 0.0)))})
	return line


## menus.md §5: the results screen's line after a Random race, from the race's resolved settings (CoreSim
## resolve_settings keys: wind_speed, wind_from, shift_amplitude, puffs, puff): `Today: 18 kn from the SW · Shifty
## · Very strong gusts`.
static func today(s: Dictionary) -> String:
	var speed := float(s.get("wind_speed", 0.0))
	var wind := wind_text(speed, speed, float(s.get("wind_from", 0.0)))
	var shifts := Strings.t("briefing.word.shifts." + shift_band(float(s.get("shift_amplitude", 0.0))))
	var p: Dictionary = s.get("puff", {})
	var puffs := {"enabled": bool(s.get("puffs", true)), "puff_cap_up": float(p.get("cap_up", 0.25)),
		"puff_strength_max": float(p.get("puff_strength_max", 0.5))}
	var gw := gust_word(puffs)
	var gusts := Strings.t("results.today.no_gusts") if gw == "none" else Strings.t("results.today.gusts",
		{"word": Strings.t("briefing.word.gusts." + gw)})
	return Strings.t("results.today", {"wind": wind, "shifts": shifts, "gusts": gusts})
