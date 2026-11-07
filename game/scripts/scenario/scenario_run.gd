class_name ScenarioRun
extends RefCounted
## Starts a rules scenario (Scenario, data_format.md §9) on the core as race.md §14 says, and steers its `hold`
## boats: a world with the scenario's wind and seed, the race on its course, the boats held behind the start line
## to the gun, started by a move over the line, then put at their set-up poses. Clip time 0 is that set-up tick.
##
##   var run := ScenarioRun.new(Scenario.load_file("port_starboard"))
##   var cs := run.make_core()          # null on failure, run.error says why
##   ... cs.step() ...                  # the hold boats are steered before every step (CoreSimSource.before_step)
##   run.clip_time(cs), run.finished(cs)

## race.md §14 step 2 and 3: behind and over the start line (m), the speed over it (m/s)
const BEHIND := 25.0
const OVER := 5.0
const OVER_SPEED := 1.0
## race.md §14 step 5: the hold helm, gain per rad of heading error and its limit
const HOLD_GAIN := 2.5
const HOLD_LIMIT := 0.6
## the gun of a 3-2-1-0 sequence with no free sailing is 3600 ticks away: a bound on the wait
const MAX_WAIT_TICKS := 8000

var scenario: Scenario
var error := ""
## per boat: set-up heading (rad), speed (m/s), front sail index, position
var psi: PackedFloat32Array
## per boat: the headings of her `turns` (rad), in the file's order
var turn_psi: Array[PackedFloat32Array] = []
var speed: PackedFloat32Array
var front: PackedInt32Array
var setup_pos: PackedVector2Array
## the world tick of clip time 0
var tick0 := 0
## extra world settings merged over the scenario's (tests)
var core_settings := {}


func _init(s: Scenario) -> void:
	scenario = s


## The world settings of race.md §14 step 1.
func world_settings() -> Dictionary:
	var s := scenario
	var d := {
		"race_seed": s.seed, "wind_speed": s.wind_speed, "wind_from": s.wind_from, "shift_preset": s.shift_preset,
		"puffs": s.puffs, "oscillation": false, "free_sailing_s": 0.0, "sequence": 1, "prep_flag": 0,
		# the scripts were written on the full model (boat.md §2): the helm balance stays on whatever the player's setting
		"weather_helm": true,
	}
	d.merge(core_settings, true)
	return d


## A new core world running the scenario at clip time 0, its hold boats steered before every step. null on
## failure, with `error` set.
func make_core() -> CoreSimSource:
	var s := scenario
	var cs := CoreSimSource.new()
	cs.settings = world_settings()
	if not cs.create(s.venue):
		return _failed(cs.last_error())
	var n := s.boats.size()
	for i in n:
		var b := s.boats[i]
		if cs.add_entry(s.class_id, {"human": i == 0, "auto_trim": b.auto_trim}) != i:
			return _failed("add boat %d: %s" % [i, cs.last_error()])
	if not cs.create_race(s.course):
		return _failed("race on %s: %s" % [s.course, cs.last_error()])
	if not _resolve(cs):
		return null
	# step 2: held behind the line on their set-up headings until a race tick at or after the gun has seen them
	var line: Dictionary = cs.race_start_status(0)
	var a: Vector2 = line["a"]
	var ab: Vector2 = line["b"] - a
	var to_course := Vector2(-ab.y, ab.x).normalized()  # the course side is on the left of A -> B
	var waited := 0
	while true:
		var seen: bool = float(cs.race().get("race_time", -1.0)) >= 0.0
		for i in n:
			var p := a + ab * ((i + 0.5) / n) - to_course * BEHIND
			if not cs.scenario_place(i, p.x, p.y, psi[i], 0.0, front[i]):
				return _failed("hold boat %d: %s" % [i, cs.last_error()])
		cs.step()
		waited += 1
		if seen:
			break
		if waited > MAX_WAIT_TICKS:
			return _failed("no start signal after %d ticks" % waited)
	# step 3: over the line, one tick: every boat has started
	for i in n:
		var p := a + ab * ((i + 0.5) / n) + to_course * OVER
		cs.scenario_place(i, p.x, p.y, psi[i], OVER_SPEED, front[i])
	cs.step()
	for i in n:
		if not bool(cs.race_boat(i).get("started", false)):
			return _failed("boat %d did not start" % i)
	# step 4: the set-up poses; AI skippers from now on
	for i in n:
		var p := setup_pos[i]
		if not cs.scenario_place(i, p.x, p.y, psi[i], speed[i], front[i]):
			return _failed("set up boat %d: %s" % [i, cs.last_error()])
		var b := s.boats[i]
		if b.helm == "ai" and not cs.ai_add(i, b.ai_level):
			return _failed("AI for boat %d: %s" % [i, cs.last_error()])
	tick0 = cs.tick()
	cs.before_step = pilot.bind(weakref(cs))  # weak: the world holds the pilot, not the other way round
	return cs


## Headings, speeds, front sails and set-up positions (data_format.md §9.2) on the created race.
func _resolve(cs: CoreSimSource) -> bool:
	var s := scenario
	var n := s.boats.size()
	turn_psi.clear()
	psi.resize(n)
	speed.resize(n)
	front.resize(n)
	setup_pos.resize(n)
	var course: Dictionary = cs.course()
	var twd := float(course.get("twd_c", s.wind_from))
	var marks := {}
	for m in course.get("marks", []):
		marks[m["id"]] = Vector2(m["x"], m["y"])
	var line: Dictionary = cs.race_start_status(0)
	var mid: Vector2 = (line["a"] + line["b"]) * 0.5
	for i in n:
		var b := s.boats[i]
		var info := cs.class_info(i)
		var f := -2
		if b.front_sail == "none":
			f = -1
		elif b.front_sail != "":
			f = -3
			for k in info.sails.size():
				if info.sails[k].name == b.front_sail and k != info.main_sail:
					f = k
			if f == -3:
				error = "boat %d: class %s has no front sail %s" % [i, s.class_id, b.front_sail]
				return false
		front[i] = f
		psi[i] = Frames.wrap_2pi(twd - b.tack * b.twa)
		var tp := PackedFloat32Array()
		for tn in b.turns:
			tp.append(Frames.wrap_2pi(twd - float(tn["tack"]) * float(tn["twa"])))
		turn_psi.append(tp)
		var v := b.speed
		if v < 0.0:
			v = cs.polar(i, s.wind_speed, b.tack * b.twa, _front_index(cs, i, f))
		speed[i] = maxf(v, 0.0)
		var base := mid
		if b.from != "":
			if marks.has(b.from):
				base = marks[b.from]
			elif b.from.ends_with("_mid"):
				var two := _mid_pair(b.from.trim_suffix("_mid"), marks)
				if two.is_empty():
					error = "boat %d: at.from %s names no two marks of the course" % [i, b.from]
					return false
				base = (two[0] + two[1]) * 0.5
			else:
				error = "boat %d: at.from %s is not a mark of the course" % [i, b.from]
				return false
		var at := base + Frames.compass_vec(twd + b.bearing) * b.dist
		setup_pos[i] = at - Frames.compass_vec(psi[i]) * (speed[i] * s.lead)
	return true


## The front sail index the polar is read with: -2 (keep) is the class's start sail, which add_entry put up.
func _front_index(cs: CoreSimSource, b: int, f: int) -> int:
	if f != -2:
		return f
	return cs.sails(b).front


## "<a>_<b>" split into two mark positions (mark ids may hold underscores): [] when no split names two marks.
static func _mid_pair(ab: String, marks: Dictionary) -> Array:
	var parts := ab.split("_")
	for k in range(1, parts.size()):
		var a := "_".join(parts.slice(0, k))
		var b := "_".join(parts.slice(k))
		if marks.has(a) and marks.has(b):
			return [marks[a], marks[b]]
	return []


## race.md §14 step 5: the hold boats keep their set-up heading, or that of their last turn begun. Called before
## every step.
func pilot(world: WeakRef) -> void:
	var cs: CoreSimSource = world.get_ref()
	if cs == null:
		return
	var ct := clip_time(cs)
	for i in scenario.boats.size():
		var b := scenario.boats[i]
		if b.helm != "hold":
			continue
		var e := Frames.wrap_pi(held_psi(i, ct) - cs.state(i).psi)
		cs.core.set_helm(i, clampf(HOLD_GAIN * e, -HOLD_LIMIT, HOLD_LIMIT))
		cs.core.set_let_fly(i, false)
		cs.core.set_auto_trim(i, b.auto_trim)


## The heading boat `i` holds at clip time `ct`: her set-up heading, or that of the last of her turns begun.
func held_psi(i: int, ct: float) -> float:
	var h := psi[i]
	var tn := scenario.boats[i].turns
	for k in tn.size():
		if ct >= float(tn[k]["t"]) - 1e-6:
			h = turn_psi[i][k]
	return h


## Seconds since clip time 0.
func clip_time(sim: SimSource) -> float:
	return (sim.tick() - tick0) * SimSource.DT


## The clip has run `lead + after` seconds.
func finished(sim: SimSource) -> bool:
	return clip_time(sim) >= scenario.lead + scenario.after - 1e-6


func _failed(why: String) -> CoreSimSource:
	error = why
	push_warning("scenario %s: %s" % [scenario.id, why])
	return null
