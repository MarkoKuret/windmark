class_name RacePilot
extends RefCounted
## A small scripted skipper for every boat of a CoreSimSource race in tests (the C API example's skipper,
## core/examples/race_example.c): holds below the line, times the start, returns when over early, beats on the
## laylines, orbits marks on the rounding side, takes penalty turns, and sails through the finish. It sets the
## helm through CoreSim before each step. Not the computer skipper of ai.md.

const DEG := PI / 180.0

var sim: CoreSimSource
var _k: Array[Dictionary] = []


func _init(source: CoreSimSource) -> void:
	sim = source
	for i in sim.boat_count():
		_k.append({"tack": 1, "turning": false, "ret_stage": 0, "turn_dir": 1.0, "turn_started": 0.0,
			"slow_time": 0.0, "unstick_until": -INF})


## Once before each step.
func steer() -> void:
	var t := float(sim.race().get("race_time", 0.0))
	for i in sim.boat_count():
		_steer(i, t)


func _helm_to(i: int, s: SimSource.BoatState, want: float, limit: float) -> void:
	var e := Frames.wrap_pi(want - s.psi)
	var h := clampf(2.5 * e, -limit, limit)
	sim.core.set_helm(i, -h if s.v < 0.0 else h)


func _sail_to(i: int, s: SimSource.BoatState, tx: float, ty: float, twd: float, tws: float) -> void:
	var k := _k[i]
	var vm := sim.polar_vmg(i, tws if tws > 0.5 else 4.0)
	var th := float(vm.get("up_twa", 0.7)) + 3.0 * DEG
	var beta := Frames.compass(tx - s.pos_x, ty - s.pos_y)
	var twa_t := Frames.wrap_pi(twd - beta)
	var cur_twa := Frames.wrap_pi(twd - s.psi)
	if absf(twa_t) < th:
		if absf(cur_twa) < 0.5 * PI:
			k["tack"] = 1 if cur_twa >= 0.0 else -1
		if k["tack"] == 1 and twa_t <= -(th - 6.0 * DEG):
			k["tack"] = -1
		if k["tack"] == -1 and twa_t >= th - 6.0 * DEG:
			k["tack"] = 1
		_helm_to(i, s, Frames.wrap_2pi(twd - float(k["tack"]) * th), 0.7)
		return
	var want := beta
	if absf(twa_t) > 170.0 * DEG:
		want = Frames.wrap_2pi(twd - (1.0 if twa_t >= 0.0 else -1.0) * 170.0 * DEG)
	_helm_to(i, s, want, 0.6)


func _mark(m: int) -> Vector2:
	var md: Dictionary = sim.course()["marks"][m]
	return Vector2(md["x"], md["y"])


func _steer(i: int, t: float) -> void:
	var k := _k[i]
	var s := sim.state(i)
	var env := sim.boat_env(i)
	var rb := sim.race_boat(i)
	var br := sim.boat_rules(i)
	var twd: float = env["wind_from_clean"]
	var tws: float = env["wind_speed_clean"]
	var crs := sim.course()
	var start: Dictionary = crs["steps"][0]
	var a := _mark(start["marks"][0])
	var b := _mark(start["marks"][1])
	var mid := (a + b) * 0.5
	var u := (b - a).normalized()
	var up := Vector2(-u.y, u.x)  # towards the course side
	var c := Vector2(s.pos_x, s.pos_y)
	if bool(rb["ghost"]) or bool(rb["finished"]):
		_helm_to(i, s, Frames.compass(up.x, up.y), 0.6)
		return
	# in irons or pinned for 6 s: bear away onto a reach for 8 s
	k["slow_time"] = float(k["slow_time"]) + 0.05 if s.v < 0.4 else 0.0
	if float(k["slow_time"]) > 6.0 and not k["turning"]:
		k["unstick_until"] = t + 8.0
		k["slow_time"] = 0.0
	if t < float(k["unstick_until"]):
		var twa := Frames.wrap_pi(twd - s.psi)
		_helm_to(i, s, Frames.wrap_2pi(twd - (1.0 if twa >= 0.0 else -1.0) * 120.0 * DEG), 0.8)
		return
	# penalty turns, not while returning to start: a steady turn with way on, given up after 50 s
	var returning := t >= 0.0 and not bool(rb["started"]) and (bool(rb["ocs"]) or bool(rb["ocs_i"]) or bool(rb["returning"]))
	if br.get("pending", []).size() > 0 and not returning:
		if not k["turning"] and s.v > 1.2:
			var twa0 := Frames.wrap_pi(twd - s.psi)
			var toward := 1.0 if twa0 >= 0.0 else -1.0
			k["turning"] = true
			k["turn_started"] = t
			k["turn_dir"] = toward if absf(twa0) < 100.0 * DEG else -toward
		if k["turning"] and t - float(k["turn_started"]) < 50.0:
			sim.core.set_helm(i, 0.8 * float(k["turn_dir"]))
			return
	k["turning"] = false
	var slot := 18.0 * float(i % 5 - 2)
	var sp := mid + u * slot
	if not bool(rb["started"]) and not bool(rb["ocs_scored"]):
		if returning:
			if bool(rb["ocs_i"]):
				var a_near := c.distance_to(a) < c.distance_to(b)
				var out := -u if a_near else u
				var e := (a if a_near else b) + out * 25.0
				if k["ret_stage"] == 0 and c.distance_to(e + up * 10.0) < 12.0:
					k["ret_stage"] = 1
				var tgt := e + up * 10.0 if k["ret_stage"] == 0 else e - up * 20.0
				_sail_to(i, s, tgt.x, tgt.y, twd, tws)
			else:
				var tgt := c - up * 30.0
				_sail_to(i, s, tgt.x, tgt.y, twd, tws)
			return
		if t >= 0.0:
			var tgt := sp + up * 40.0
			_sail_to(i, s, tgt.x, tgt.y, twd, tws)
			return
		if t < -60.0:
			var hold := sp - up * 60.0
			if c.distance_to(hold) > 60.0:
				_sail_to(i, s, hold.x, hold.y, twd, tws)
			else:
				var west := int(floor((t + 10000.0) / 15.0)) % 2 == 0
				_helm_to(i, s, Frames.wrap_2pi(twd + (-90.0 if west else 90.0) * DEG), 0.6)
			return
		var d := (c - mid).dot(up)
		var v := maxf(s.v, 1.0)
		if -d / v >= -t - 1.0:
			var tgt := sp + up * 20.0
			_sail_to(i, s, tgt.x, tgt.y, twd, tws)
		elif d > -30.0:
			_helm_to(i, s, Frames.wrap_2pi(twd - 30.0 * DEG), 0.4)
		else:
			var tgt := sp - up * 25.0
			_sail_to(i, s, tgt.x, tgt.y, twd, tws)
		return
	var st: Dictionary = crs["steps"][int(rb["next"])]
	if int(st["kind"]) == RaceText.Step.FINISH:
		var fa := _mark(st["marks"][0])
		var fb := _mark(st["marks"][1])
		var fu := (fb - fa).normalized()
		var tgt := (fa + fb) * 0.5 + Vector2(fu.y, -fu.x) * 40.0
		_sail_to(i, s, tgt.x, tgt.y, twd, tws)
		return
	var sides: PackedInt32Array = st["sides"]
	var m := 1 if int(st["kind"]) == RaceText.Step.GATE and sides[1] == RaceText.Side.PORT else 0
	var mk := _mark(st["marks"][m])
	var sgn := 1.0 if sides[m] == RaceText.Side.PORT else -1.0
	var r := 14.0
	var dist := c.distance_to(mk)
	if dist < 45.0:
		var ang := atan2(c.y - mk.y, c.x - mk.x) + sgn * 50.0 * DEG
		_sail_to(i, s, mk.x + r * cos(ang), mk.y + r * sin(ang), twd, tws)
	else:
		var dd := (mk - c) / dist
		_sail_to(i, s, mk.x + dd.y * sgn * r, mk.y - dd.x * sgn * r, twd, tws)
