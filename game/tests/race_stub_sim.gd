class_name RaceStubSim
extends SimSource
## A scripted race behind the SimSource interface for the race HUD tests: every record the HUD reads is a field
## the test sets. The course is a two-lap windward-leeward on a north wind: start line A (pin) at (-100, 0) to B
## (committee boat) at (100, 0), windward mark W at (0, 1000) to port, gate L1 / L2 at (-20, 100) / (20, 100),
## the finish on the start line.

var infos: Array[ClassInfo] = []
var states: Array[BoatState] = []
var outs: Array[BoatOutputs] = []
var ctrls: Array[BoatControls] = []
var sv := SailsView.new()
var race_d := {}
var boats_d: Array[Dictionary] = []
var start_d: Array[Dictionary] = []
var rules_d: Array[Dictionary] = []
var pairs_a: Array = []
var race_ev: Array = []
var rules_ev: Array = []
var results_a: Array = []
var order := PackedInt32Array()
var course_d := {}
var labels := {"W": "Windward", "L1": "Gate left", "L2": "Gate right"}
var vmg := {"up_twa": deg_to_rad(42.0), "up_speed": 3.0, "down_twa": deg_to_rad(150.0), "down_speed": 3.5}
var polar_by_front := {-1: 2.8, 1: 3.0, 2: 3.4}
var splits := {}  # "boat:step" -> t
var hail := {}
## wind_shadow.md §5 the boats' environment (boat_env), {} = clear air
var env := {}
var wind := Vector2(5.0, 0.0)  # clean wind: speed, from
var current := Vector2.ZERO
var ticks := 0


func _init(n := 2) -> void:
	for i in n:
		var info := ClassInfo.new()
		info.id = "stub"
		info.loa = 7.0
		for nm in ["main", "jib", "code_zero"]:
			var si := SailInfo.new()
			si.name = nm
			si.type = "main" if nm == "main" else "jib"
			info.sails.append(si)
		info.main_sail = 0
		info.front_sails = PackedInt32Array([1, 2])
		infos.append(info)
		var s := BoatState.new()
		s.tws = 5.0
		states.append(s)
		outs.append(BoatOutputs.new())
		ctrls.append(BoatControls.new())
		boats_d.append({"started": false, "next": 0, "last_rounded": -1, "finished": false, "ghost": false, "D": 0.0,
			"rank": i + 1, "place": 0, "t_finish_us": 0, "code": 0})
		start_d.append({})
		rules_d.append({"pending": [], "turn_progress": 0.0, "turn_tacks": 0, "turn_gybes": 0, "deadline_s": -1.0,
			"received": 0, "served": 0, "turning_for_penalty": false, "turn_in_zone": false, "turn_reset": 0,
			"turn_reset_tick": 0})
		order.append(i)
	for nm in ["main", "jib", "code_zero"]:
		var st := SailState.new()
		st.phase = Phase.UP if nm != "code_zero" else Phase.DOWN
		sv.sails.append(st)
		sv.out.append(SailOutput.new())
	sv.front = 1
	race_d = {"state": 2, "sequence": 0, "prep_flag": 1, "race_time": -200.0, "x_flag": false,
		"general_recalls": 0, "twd_mean": 0.0}
	var marks := [
		{"id": "A", "type": 0, "x": -100.0, "y": 0.0, "radius": 0.5},
		{"id": "B", "type": 1, "x": 100.0, "y": 0.0, "radius": 0.0},
		{"id": "W", "type": 0, "x": 0.0, "y": 1000.0, "radius": 1.0},
		{"id": "L1", "type": 0, "x": -20.0, "y": 100.0, "radius": 1.0},
		{"id": "L2", "type": 0, "x": 20.0, "y": 100.0, "radius": 1.0},
	]
	var steps := [
		_step(0, [0, 1], [0, 0], 1, 0, Vector2(0, 0)),
		_step(1, [2, 2], [0, 0], 1, 1, Vector2(0, 1000)),
		_step(2, [3, 4], [1, 0], 1, 2, Vector2(0, 100)),
		_step(1, [2, 2], [0, 0], 2, 1, Vector2(0, 1000)),
		_step(3, [0, 1], [0, 0], 2, 2, Vector2(0, 0)),
	]
	course_d = {"id": "stub", "laps": 2, "marks": marks, "steps": steps, "boundary": PackedVector2Array()}


static func _step(kind: int, ms: Array, sides: Array, lap: int, leg: int, ref: Vector2) -> Dictionary:
	return {"kind": kind, "marks": PackedInt32Array(ms), "sides": PackedInt32Array(sides), "lap": lap,
		"leg_in_lap": leg, "ref": ref}


## places boat b at (x, y) on heading psi at speed v through the water and over the ground along the heading
func put(b: int, x: float, y: float, psi: float, v: float) -> void:
	var s := states[b]
	s.pos_x = x
	s.pos_y = y
	s.psi = psi
	s.v = v
	s.v_filt = v
	s.sog_filt_x = v * sin(psi)
	s.sog_filt_y = v * cos(psi)
	s.twd_from = wind.y
	s.twa = Frames.wrap_pi(wind.y - psi)
	s.tws = wind.x
	outs[b].vmg = v * cos(s.twa)
	outs[b].polar_speed = 3.0
	outs[b].cog = Frames.compass(s.sog_filt_x, s.sog_filt_y)


## the start status of the bow of boat b against the line A (-100, 0) to B (100, 0)
func line_status(b: int, over := false) -> void:
	var s := states[b]
	var bow := Vector2(s.pos_x, s.pos_y) + 3.5 * Vector2(sin(s.psi), cos(s.psi))
	start_d[b] = {"a": Vector2(-100, 0), "b": Vector2(100, 0), "s_bow": bow.y, "u_bow": (bow.x + 100.0) / 200.0,
		"in_band": over, "course_side": over, "in_triangle": over, "pre_start": not over, "over": over}


func pair(i: int, j: int, fields: Dictionary) -> Dictionary:
	var p := {"i": mini(i, j), "j": maxi(i, j), "relation": 0, "kc_giver": -1, "kc_holder": -1, "kc_rule": 0,
		"kc_state": 0, "room_entitled": -1, "room_giver": -1, "room_rule": 0, "room_mark": -1, "room_state": 0,
		"rule17_holder": -1, "incident": false, "gap": 10.0, "ttc": INF}
	p.merge(fields, true)
	return p


# ---- SimSource ----

func tick() -> int:
	return ticks


func boat_count() -> int:
	return states.size()


func class_info(b: int) -> ClassInfo:
	return infos[b]


func state(b: int) -> BoatState:
	return states[b]


func controls(b: int) -> BoatControls:
	return ctrls[b]


func outputs(b: int) -> BoatOutputs:
	return outs[b]


func sails(_b: int) -> SailsView:
	return sv


func render_pose(b: int, _alpha: float) -> RenderPose:
	var p := RenderPose.new()
	p.pos_x = states[b].pos_x
	p.pos_y = states[b].pos_y
	p.psi = states[b].psi
	p.z = states[b].z
	p.theta = states[b].theta
	p.phi = states[b].phi
	return p


func wind_clean(_x: float, _y: float) -> Vector2:
	return wind


func step() -> void:
	ticks += 1


func has_race() -> bool:
	return true


func race() -> Dictionary:
	return race_d


func race_boat(b: int) -> Dictionary:
	return boats_d[b] if b >= 0 and b < boats_d.size() else {}


func race_order() -> PackedInt32Array:
	return order


func course() -> Dictionary:
	return course_d


func course_labels() -> Dictionary:
	return labels


func results() -> Array:
	return results_a


func race_split(b: int, k: int) -> float:
	return splits.get("%d:%d" % [b, k], NAN)


func race_start_status(b: int) -> Dictionary:
	return start_d[b]


func boat_rules(b: int) -> Dictionary:
	return rules_d[b]


func pairs() -> Array:
	return pairs_a


func race_events() -> Array:
	return race_ev


func rules_events() -> Array:
	return rules_ev


func boat_env(_b: int) -> Dictionary:
	return env


func hail_state(_b: int) -> Dictionary:
	return hail


func polar_vmg(_b: int, _tws: float) -> Dictionary:
	return vmg


func polar(_b: int, _tws: float, _twa: float, front: int) -> float:
	return polar_by_front.get(front, NAN)


func current_at(_x: float, _y: float, _t: float) -> Vector2:
	return current
