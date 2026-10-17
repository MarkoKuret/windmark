class_name Scenario
extends RefCounted
## A rules scenario file (docs/specs/data_format.md §9, `windmark.scenario/1`): a few boats placed on the first
## beat of an offline race, sailing into an incident `lead` seconds after the set-up. Loaded and validated here;
## ScenarioRun starts it on the core (race.md §14). Files: game/data/scenarios/<id>.scenario.json.

const SCHEMA := "windmark.scenario/1"
const SHIFTS := ["steady", "stable", "oscillating", "shifty", "unstable"]  # WM_SHIFT_* 0..4
const HELMS := ["hold", "ai", "player"]
const MIN_BOATS := 2
const MAX_BOATS := 8
## the hand-friendly units of §9 (the one exception to the SI rule): `*_deg` and `*_kn` keys
const DEG := PI / 180.0
const KN := 1852.0 / 3600.0


## One boat of the file (§9.2).
class Boat:
	## the incident position: a wind-frame offset, `from` "" = the middle of the start line
	var bearing := 0.0
	var dist := 0.0
	var from := ""
	## +1 starboard, -1 port
	var tack := 1
	## rad, 0 to π
	var twa := 0.0
	## m/s; < 0: the polar speed
	var speed := -1.0
	## a sail id, "none", or "": the class's start sail
	var front_sail := ""
	var auto_trim := true
	## hold, ai or player
	var helm := "hold"
	var ai_level := "intermediate"
	## a boat id of the class's livery file, "": the fleet rule
	var livery := ""
	## hold boats: course changes during the clip, {t (s of clip time), tack (+1/-1), twa (rad)} in order of t
	var turns: Array[Dictionary] = []


var id := ""
var name := ""
var note := ""
var class_id := ""
## "<venue>/<course id>"
var course := ""
var venue := ""
var seed := 1
## base wind: m/s, rad compass, the shift preset index (WM_SHIFT_*), puffs
var wind_speed := 0.0
var wind_from := 0.0
var shift_preset := 0
var puffs := false
## s from the set-up to the incident, and the clip's run past it
var lead := 20.0
var after := 5.0
var view := 0
var boats: Array[Boat] = []
## the file it came from
var path := ""


## The file of a scenario id (game/data/scenarios/<id>.scenario.json), or the path itself when it ends in .json.
static func file_of(id_or_path: String) -> String:
	if id_or_path.ends_with(".json"):
		return id_or_path
	return BoatClassData.repo_path("game/data/scenarios/%s.scenario.json" % id_or_path)


## Loads and validates a scenario by id or path. On failure returns null and puts the reason (file, JSON path,
## what is wrong) into `error[0]` when an array is given.
static func load_file(id_or_path: String, error: Array = []) -> Scenario:
	var p := file_of(id_or_path)
	if not FileAccess.file_exists(p):
		_fail(error, "%s: no such file" % p)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK:
		_fail(error, "%s: line %d: %s" % [p, json.get_error_line(), json.get_error_message()])
		return null
	var why := []
	var s := parse(json.data, why)
	if s == null:
		_fail(error, "%s: %s" % [p, why[0] if not why.is_empty() else "invalid"])
		return null
	s.path = p
	if s.id != p.get_file().trim_suffix(".scenario.json"):
		_fail(error, "%s: $.id: \"%s\" is not the file name" % [p, s.id])
		return null
	return s


## Validates the parsed JSON of a scenario file; null with the reason in `why[0]` when invalid.
static func parse(d: Variant, why: Array) -> Scenario:
	if not d is Dictionary:
		return _bad(why, "$", "not an object")
	if d.get("schema") != SCHEMA:
		return _bad(why, "$.schema", "expected \"%s\"" % SCHEMA)
	var s := Scenario.new()
	if not _is_id(d.get("id")):
		return _bad(why, "$.id", "an id of [a-z0-9_] is required")
	s.id = d["id"]
	if not d.get("name") is String or (d["name"] as String).length() < 1 or (d["name"] as String).length() > 60:
		return _bad(why, "$.name", "1 to 60 characters required")
	s.name = d["name"]
	s.note = str(d.get("note", ""))
	if not _is_id(d.get("class")):
		return _bad(why, "$.class", "a class id is required")
	s.class_id = d["class"]
	if not FileAccess.file_exists(BoatClassData.repo_path("data/perf/%s.perf.json" % s.class_id)):
		return _bad(why, "$.class", "no performance file for class %s" % s.class_id)
	var c: Variant = d.get("course")
	if not c is String or (c as String).split("/").size() != 2:
		return _bad(why, "$.course", "\"<venue>/<course id>\" required")
	s.course = c
	s.venue = s.course.split("/")[0]
	if not FileAccess.file_exists(BoatClassData.repo_path("game/data/courses/%s.course.json" % s.course)):
		return _bad(why, "$.course", "no course file %s" % s.course)
	if d.has("seed"):
		if not _is_num(d["seed"]) or float(d["seed"]) < 0.0 or float(d["seed"]) != floorf(float(d["seed"])):
			return _bad(why, "$.seed", "a whole number >= 0 required")
		s.seed = int(d["seed"])
	var w: Variant = d.get("wind")
	if not w is Dictionary:
		return _bad(why, "$.wind", "an object required")
	var ws := _unit(w, "speed", "_kn", KN, "$.wind", why)
	if ws.is_empty():
		return null
	if not ws["num"] or ws["v"] <= 0.0 or ws["v"] > 30.0:
		return _bad(why, ws["at"], "knots above 0 and up to 58 required" if ws["hand"] else "m/s above 0 and up to 30 required")
	s.wind_speed = ws["v"]
	var wf := _unit(w, "from", "_deg", DEG, "$.wind", why)
	if wf.is_empty():
		return null
	if not wf["num"] or wf["raw"] < 0.0 or wf["raw"] >= (360.0 if wf["hand"] else TAU):
		return _bad(why, wf["at"], "degrees in [0, 360) required" if wf["hand"] else "rad in [0, 2π) required")
	s.wind_from = wf["v"]
	var sh: Variant = w.get("shifts", "steady")
	if not sh is String or not SHIFTS.has(sh):
		return _bad(why, "$.wind.shifts", "one of %s" % ", ".join(SHIFTS))
	s.shift_preset = SHIFTS.find(sh)
	var pf: Variant = w.get("puffs", false)
	if not pf is bool:
		return _bad(why, "$.wind.puffs", "true or false")
	s.puffs = pf
	for k in ["lead", "after"]:
		if d.has(k):
			if not _is_num(d[k]) or float(d[k]) < 0.0 or float(d[k]) > 120.0:
				return _bad(why, "$." + k, "s in [0, 120] required")
			s.set(k, float(d[k]))
	var bl: Variant = d.get("boats")
	if not bl is Array or (bl as Array).size() < MIN_BOATS or (bl as Array).size() > MAX_BOATS:
		return _bad(why, "$.boats", "%d to %d boats required" % [MIN_BOATS, MAX_BOATS])
	for i in (bl as Array).size():
		var b := _parse_boat(bl[i], i, why)
		if b == null:
			return null
		s.boats.append(b)
	for i in s.boats.size():
		var tn := s.boats[i].turns
		if not tn.is_empty() and float(tn[-1]["t"]) > s.lead + s.after:
			return _bad(why, "$.boats[%d].turns[%d].t" % [i, tn.size() - 1], "s up to lead + after required")
	if d.has("view"):
		if not _is_num(d["view"]) or int(d["view"]) < 0 or int(d["view"]) >= s.boats.size():
			return _bad(why, "$.view", "a boat index required")
		s.view = int(d["view"])
	return s


static func _parse_boat(d: Variant, i: int, why: Array) -> Boat:
	var at := "$.boats[%d]" % i
	if not d is Dictionary:
		return _bad(why, at, "not an object")
	var b := Boat.new()
	var a: Variant = d.get("at")
	var need := "{\"bearing\": rad or \"bearing_deg\": degrees, \"dist\": m >= 0, \"from\": optional} required"
	if not a is Dictionary:
		return _bad(why, at + ".at", need)
	var br := _unit(a, "bearing", "_deg", DEG, at + ".at", why)
	if br.is_empty():
		return null
	if not br["num"] or not _is_num(a.get("dist")) or float(a["dist"]) < 0.0:
		return _bad(why, at + ".at", need)
	b.bearing = br["v"]
	b.dist = float(a["dist"])
	if a.has("from"):
		if not a["from"] is String or (a["from"] as String).is_empty():
			return _bad(why, at + ".at.from", "a mark id or \"<a>_<b>_mid\"")
		b.from = a["from"]
	var tk: Variant = d.get("tack")
	if tk != "starboard" and tk != "port":
		return _bad(why, at + ".tack", "\"starboard\" or \"port\" required")
	b.tack = 1 if tk == "starboard" else -1
	var tw := _unit(d, "twa", "_deg", DEG, at, why)
	if tw.is_empty():
		return null
	if not tw["num"] or tw["v"] < 0.0 or tw["v"] > PI + 1e-6:
		return _bad(why, tw["at"], "degrees in [0, 180] required" if tw["hand"] else "rad in [0, π] required")
	b.twa = minf(tw["v"], PI)
	var sp := _unit(d, "speed", "_kn", KN, at, why)
	if sp.is_empty():
		return null
	if sp["given"]:
		if not sp["num"] or sp["v"] < 0.0 or sp["v"] > 30.0:
			return _bad(why, sp["at"], "knots in [0, 58]" if sp["hand"] else "m/s in [0, 30]")
		b.speed = sp["v"]
	if d.has("front_sail"):
		if not d["front_sail"] is String or (d["front_sail"] != "none" and not _is_id(d["front_sail"])):
			return _bad(why, at + ".front_sail", "a sail id or \"none\"")
		b.front_sail = d["front_sail"]
	if d.has("auto_trim"):
		if not d["auto_trim"] is bool:
			return _bad(why, at + ".auto_trim", "true or false")
		b.auto_trim = d["auto_trim"]
	var hm: Variant = d.get("helm", "hold")
	if not hm is String or not HELMS.has(hm):
		return _bad(why, at + ".helm", "one of %s" % ", ".join(HELMS))
	if hm == "player" and i != 0:
		return _bad(why, at + ".helm", "only boat 0 can be the player's")
	b.helm = hm
	var lv: Variant = d.get("ai_level", "intermediate")
	if not lv is String or not CoreSimSource.AI_LEVELS.has(lv):
		return _bad(why, at + ".ai_level", "one of %s" % ", ".join(CoreSimSource.AI_LEVELS))
	b.ai_level = lv
	if d.has("livery"):
		if not _is_id(d["livery"]):
			return _bad(why, at + ".livery", "a boat id of the class's livery file")
		b.livery = d["livery"]
	if d.has("turns"):
		if b.helm != "hold":
			return _bad(why, at + ".turns", "only a hold boat turns")
		if not d["turns"] is Array:
			return _bad(why, at + ".turns", "a list of {\"t\", \"tack\", \"twa\"} required")
		var last := -1.0
		for k in (d["turns"] as Array).size():
			var tat := "%s.turns[%d]" % [at, k]
			var td: Variant = d["turns"][k]
			if not td is Dictionary:
				return _bad(why, tat, "not an object")
			if not _is_num(td.get("t")) or float(td["t"]) < 0.0 or float(td["t"]) <= last:
				return _bad(why, tat + ".t", "s >= 0, after the turn before, required")
			last = float(td["t"])
			var ttk: Variant = td.get("tack")
			if ttk != "starboard" and ttk != "port":
				return _bad(why, tat + ".tack", "\"starboard\" or \"port\" required")
			var ttw := _unit(td, "twa", "_deg", DEG, tat, why)
			if ttw.is_empty():
				return null
			if not ttw["num"] or ttw["v"] < 0.0 or ttw["v"] > PI + 1e-6:
				return _bad(why, ttw["at"], "degrees in [0, 180] required" if ttw["hand"] else "rad in [0, π] required")
			b.turns.append({"t": last, "tack": 1 if ttk == "starboard" else -1, "twa": minf(ttw["v"], PI)})
	return b


## The player sails boat 0 (helm player); otherwise the player watches.
func player_sails() -> bool:
	return boats[0].helm == "player"


## Reads one field of §9 that takes either its SI key or the hand key `<key><suffix>` (degrees, knots), scaled to
## SI by `scale`. Returns {given, num, v (SI), raw (as written), hand, at (the JSON path of the key used)}: `given`
## when either key is there, `num` when it also holds a finite number. Both keys present: {} with the reason in
## `why[0]`.
static func _unit(d: Dictionary, key: String, suffix: String, scale: float, at: String, why: Array) -> Dictionary:
	var hk := key + suffix
	if d.has(key) and d.has(hk):
		_bad(why, "%s.%s" % [at, hk], "give one of \"%s\" and \"%s\", not both" % [key, hk])
		return {}
	var hand := d.has(hk)
	var k := hk if hand else key
	var out := {"given": d.has(k), "num": false, "v": NAN, "raw": NAN, "hand": hand, "at": "%s.%s" % [at, k]}
	if d.has(k) and _is_num(d[k]):
		out["num"] = true
		out["raw"] = float(d[k])
		out["v"] = float(d[k]) * (scale if hand else 1.0)
	return out


static func _is_id(v: Variant) -> bool:
	if not v is String or (v as String).is_empty():
		return false
	for ch in (v as String):
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _bad(why: Array, at: String, what: String) -> Variant:
	why.clear()
	why.append("%s: %s" % [at, what])
	return null


static func _fail(error: Array, what: String) -> void:
	error.clear()
	error.append(what)
