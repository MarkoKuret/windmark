class_name ShotScript
extends RefCounted
## cameras.md §9.2 shot scripts: a `windmark.shot/1` file of cues keyed by shot time (the simulation's time from the
## session's zero: a scenario's clip time 0, a race's gun, free sailing's start) that run the capture actions, the
## HUD and world tags toggles, the camera choice and held boat actions, and end the run. This class reads the file
## and keeps the clock and the cue order; the sail scene applies the cues (sail_test.gd _shot_frame).
##
##   var why := []
##   var shot := ShotScript.load_file("rule10_penalty", why)   # null on failure, why[0] says why
##   for c in shot.due(now): ...                              # the cues up to `now`, once each, in order

const SCHEMA := "windmark.shot/1"
const DIR := "res://data/shots/"
## the camera names of a `camera` cue
const CAMERAS := {
	"chase": CameraRig.Mode.CHASE, "onboard": CameraRig.Mode.ONBOARD, "aerial": CameraRig.Mode.AERIAL,
	"free": CameraRig.Mode.FREE, "start_line": CameraRig.Mode.START_LINE, "mark": CameraRig.Mode.MARK,
	"long_lens": CameraRig.Mode.LONG_LENS, "helicopter": CameraRig.Mode.HELICOPTER,
}
## the cue actions; one per cue
const ACTIONS := ["camera", "slow", "pause", "resume", "hud", "tags", "view", "input", "end"]
## keys a cue may carry next to its action
const MODIFIERS := ["t", "preset", "params", "for", "note"]

var path := ""
var portrait := false
var hud := true
var world_tags := true
## the shot time of the first frame (the world is stepped there first); NAN: as the session starts
var start := NAN
## the cues by time (stable), each the file's dictionary with "t" a float and "action" its action's name
var cues: Array[Dictionary] = []
## the next cue to run
var next := 0
## held boat actions: action -> the shot time the hold ends
var holds := {}
## the actions the shot put into the last frame's input (taken out again when their hold ends)
var _held_last := {}


## A shot file by id (game/data/shots/<id>.shot.json) or path; null when it does not load, the reason in `why`.
static func load_file(id_or_path: String, why: Array = []) -> ShotScript:
	var p := id_or_path
	if not p.ends_with(".json"):
		p = DIR + p + ".shot.json"
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		why.append("cannot open %s" % p)
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		why.append("%s is not a JSON object" % p)
		return null
	var s := parse(d, why)
	if s != null:
		s.path = p
	return s


## A shot from its dictionary; null when it is not a valid `windmark.shot/1`, the reason in `why`.
static func parse(d: Dictionary, why: Array = []) -> ShotScript:
	if d.get("schema", "") != SCHEMA:
		why.append("schema is not %s" % SCHEMA)
		return null
	var s := ShotScript.new()
	s.portrait = bool(d.get("portrait", false))
	s.hud = bool(d.get("hud", true))
	s.world_tags = bool(d.get("world_tags", true))
	if d.has("start"):
		if not (d["start"] is float or d["start"] is int):
			why.append("start is not a number")
			return null
		s.start = float(d["start"])
	var list: Variant = d.get("cues", [])
	if not list is Array:
		why.append("cues is not a list")
		return null
	var order := []
	for i in list.size():
		var c: Variant = list[i]
		var bad := _check_cue(c)
		if bad != "":
			why.append("cue %d: %s" % [i, bad])
			return null
		var cue: Dictionary = (c as Dictionary).duplicate(true)
		cue["t"] = float(cue["t"])
		for k in cue:
			if k in ACTIONS:
				cue["action"] = k
		order.append([cue["t"], i, cue])
	order.sort()  # by time, then the file's order
	for o in order:
		s.cues.append(o[2])
	return s


## "" for a valid cue, else what is wrong with it.
static func _check_cue(c: Variant) -> String:
	if not c is Dictionary:
		return "not an object"
	if not (c.get("t") is float or c.get("t") is int):
		return "no time t"
	var acts := []
	for k in c:
		if k in ACTIONS:
			acts.append(k)
		elif not k in MODIFIERS:
			return "unknown key %s" % k
	if acts.size() != 1:
		return "%d actions (one per cue)" % acts.size()
	var v: Variant = c[acts[0]]
	match acts[0]:
		"camera":
			if not CAMERAS.has(v):
				return "unknown camera %s" % v
			if c.has("preset") and not (int(c["preset"]) >= 1 and int(c["preset"]) <= CameraRig.PRESET_COUNT):
				return "preset is not 1 to %d" % CameraRig.PRESET_COUNT
			if c.has("params") and not c["params"] is Dictionary:
				return "params is not an object"
		"slow":
			if not float(v) in CaptureMode.RATES:
				return "slow %s is not one of %s" % [v, CaptureMode.RATES]
		"view":
			if not (v is float or v is int or v == "leader"):
				return "view is not a boat or leader"
		"input":
			if not v is String or not InputMap.has_action(v):
				return "unknown action %s" % v
			if not (c.get("for") is float or c.get("for") is int):
				return "input without for"
		"hud", "tags", "pause", "resume", "end":
			if not v is bool:
				return "%s is not true or false" % acts[0]
	return ""


## The cues not run yet with t <= now, in order; each is returned once.
func due(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while next < cues.size() and float(cues[next]["t"]) <= now + 1e-6:
		out.append(cues[next])
		next += 1
	return out


## A cue's camera parameters: the file's, with the `_deg` keys in radians under their names without it.
static func camera_params(cue: Dictionary) -> Dictionary:
	var out := {}
	var p: Dictionary = cue.get("params", {})
	for k: String in p:
		if k.ends_with("_deg"):
			out[k.trim_suffix("_deg")] = deg_to_rad(float(p[k]))
		else:
			out[k] = p[k]
	return out


## An `input` cue at shot time `now`: its action held until now + for.
func hold(cue: Dictionary, now: float) -> void:
	holds[StringName(cue["input"])] = now + float(cue["for"])


## The held actions at shot time `now` into this frame's input: held while their time lasts (a press on the first
## frame); an ended hold is taken out of the input again and forgotten.
func apply_input(r: RawInput, now: float) -> void:
	for a: StringName in holds.keys():
		if now < holds[a] - 1e-6:
			r.held[a] = true
			if not _held_last.has(a):
				r.pressed.append(a)
			else:
				r.pressed.erase(a)
			_held_last[a] = true
		else:
			holds.erase(a)
			if _held_last.has(a):
				r.held.erase(a)
				r.pressed.erase(a)
				_held_last.erase(a)


## Every cue has run.
func done() -> bool:
	return next >= cues.size()
