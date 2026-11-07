class_name FreeCourse
extends RefCounted
## Free sail's progress round a laid course (courses.md §6.4) for one boat, the player's: the next step of the
## course in order, the start line first (step 0, a line to cross), then each mark and gate, then the finish line,
## and after the finish the start line again (step 1 when the finish line is the start line). A step is passed with
## the race's own tests on the boat's reference point once per tick (update): the start line crossed through its
## band from the pre-start side (race.md §4.1), a mark by the winding test (race.md §5.1), a gate by its crossing
## and the winding of either buoy (race.md §5.2), the finish line crossed through its band from the side of the
## step before it (race.md §6.1). No time, no distance limit, no penalties. The front end's, not the core's: the
## core lays the course (CoreSimSource.lay_course) and knows nothing of this.
##
##   var fc := FreeCourse.new(sim.course(), boat); fc.restart(pos); per tick fc.update(pos); fc.record()

const STEP_START := 0
const STEP_MARK := 1
const STEP_GATE := 2
const STEP_FINISH := 3
const SIDE_PORT := 0

## the resolved course (SimSource.course())
var course := {}
## the boat it follows
var boat := 0
## the next step index (0 the start line)
var next := 0
## steps passed since the last restart (tests, previews)
var passed := 0
## the step index passed last, -1 none since the restart
var last_passed := -1

var _prev := Vector2.INF
## per buoy of the next step: the winding angle so far and the angle that completes it
var _phi: Array[float] = [0.0, 0.0]
var _phi_done: Array[float] = [0.0, 0.0]
## gate crossings through the band from the entry side (race.md §5.2)
var _cross := 0


func _init(c: Dictionary, b := 0) -> void:
	course = c
	boat = b


func step_count() -> int:
	return course.get("steps", []).size()


## Back to the start line with the boat at `c` (a new world, the reset key).
func restart(c: Vector2) -> void:
	next = 0
	passed = 0
	last_passed = -1
	_prev = c
	_begin(c)


## The progress as the race's per-boat record names it (race_boat: next, started, finished), with `free` set.
func record() -> Dictionary:
	return {"next": next, "started": true, "finished": false, "free": true, "last_rounded": last_passed}


## Whether the finish line is the start line (its ends are the start's).
func finish_is_start() -> bool:
	var n := step_count()
	if n < 2:
		return false
	var a: PackedInt32Array = course["steps"][0]["marks"]
	var f: PackedInt32Array = course["steps"][n - 1]["marks"]
	return (a[0] == f[0] and a[1] == f[1]) or (a[0] == f[1] and a[1] == f[0])


## The step after `k`: in order, the start line after the finish (step 1 when the finish is the start line).
func after(k: int) -> int:
	var n := step_count()
	if k + 1 < n:
		return k + 1
	return 1 if finish_is_start() else 0


## Once per tick with the boat's reference point: passes the next step when its test says so. True on a pass.
func update(c: Vector2) -> bool:
	var n := step_count()
	if n < 2:
		return false
	if _prev == Vector2.INF:
		_prev = c
		_begin(c)
		return false
	var done := false
	var st: Dictionary = course["steps"][next]
	match int(st["kind"]):
		STEP_START:
			done = _crosses(_prev, c, 0, ref(1))
		STEP_FINISH:
			done = _crosses(_prev, c, next, ref(next - 1))
		STEP_MARK:
			_wind(0, _prev, c)
			done = _phi[0] >= _phi_done[0]
		STEP_GATE:
			_gate_cross(_prev, c)
			_wind(0, _prev, c)
			_wind(1, _prev, c)
			done = _cross >= 1 and (bool(st.get("gate_cross", false)) or _phi[0] >= _phi_done[0]
				or _phi[1] >= _phi_done[1])
	_prev = c
	if done:
		last_passed = next
		passed += 1
		next = after(next)
		_begin(c)
	return done


## The reference point of step `k` (wrapped round the course).
func ref(k: int) -> Vector2:
	var n := step_count()
	return course["steps"][posmod(k, n)]["ref"]


func _mark(i: int) -> Vector2:
	var m: Dictionary = course["marks"][i]
	return Vector2(float(m["x"]), float(m["y"]))


## The winding of the next step starts here (race.md §5.1: the angle already swept from the entry ray).
func _begin(c: Vector2) -> void:
	_cross = 0
	_phi = [0.0, 0.0]
	_phi_done = [0.0, 0.0]
	var st: Dictionary = course.get("steps", [{}])[next] if step_count() > 0 else {}
	var kind := int(st.get("kind", STEP_START))
	if kind != STEP_MARK and kind != STEP_GATE:
		return
	var p := ref(next - 1)
	var nx := ref(next + 1)
	if nx.distance_to(st["ref"]) < 1.0:
		nx = ref(next + 2)
	var ms: PackedInt32Array = st["marks"]
	var sides: PackedInt32Array = st["sides"]
	for i in (2 if kind == STEP_GATE else 1):
		var m := _mark(ms[i])
		var sigma := 1.0 if sides[i] == SIDE_PORT else -1.0
		var a_out := Frames.compass(nx.x - m.x, nx.y - m.y)
		var a_in := Frames.compass(p.x - m.x, p.y - m.y)
		if p.distance_to(m) < 1.0:
			a_in = a_out + sigma * PI
		var sweep := Frames.wrap_2pi(sigma * (a_in - a_out))
		if sweep < PI / 6.0:
			sweep += TAU
		_phi_done[i] = maxf(PI / 2.0, sweep - PI / 2.0)
		_phi[i] = sigma * Frames.wrap_pi(a_in - Frames.compass(c.x - m.x, c.y - m.y))


## race.md §5.1: the winding increment of buoy `i` from c0 to c1 (anticlockwise positive, port rounding positive).
func _wind(i: int, c0: Vector2, c1: Vector2) -> void:
	var st: Dictionary = course["steps"][next]
	var m := _mark((st["marks"] as PackedInt32Array)[i])
	var sigma := 1.0 if (st["sides"] as PackedInt32Array)[i] == SIDE_PORT else -1.0
	var u := c0 - m
	var v := c1 - m
	if u.length() < 1e-3 or v.length() < 1e-3:
		return
	_phi[i] += sigma * atan2(u.cross(v), u.dot(v))


## race.md §5.2: crossings of the gate line through its band, +1 from the entry side (the previous step's), -1 back.
func _gate_cross(c0: Vector2, c1: Vector2) -> void:
	var st: Dictionary = course["steps"][next]
	var ms: PackedInt32Array = st["marks"]
	var a := _mark(ms[0])
	var b := _mark(ms[1])
	var d := b - a
	var entry := signf(d.cross(ref(next - 1) - a))
	if entry == 0.0:
		return
	var s0 := entry * d.cross(c0 - a)
	var s1 := entry * d.cross(c1 - a)
	if s0 > 0.0 and s1 <= 0.0 and _in_band(a, d, c0, c1, s0, s1):
		_cross += 1
	elif s0 <= 0.0 and s1 > 0.0 and _in_band(a, d, c0, c1, s0, s1):
		_cross -= 1


## race.md §4.1 and §6.1: line step `k` crossed through its band from the side of `from_ref` to the other side.
func _crosses(c0: Vector2, c1: Vector2, k: int, from_ref: Vector2) -> bool:
	var st: Dictionary = course["steps"][k]
	var ms: PackedInt32Array = st["marks"]
	var a := _mark(ms[0])
	var b := _mark(ms[1])
	var d := b - a
	var side := signf(d.cross(from_ref - a))
	if side == 0.0:
		return false
	if k == 0:
		side = -side  # the start: from the pre-start side, the other side from step 1's reference point
	var s0 := side * d.cross(c0 - a)
	var s1 := side * d.cross(c1 - a)
	return s0 > 0.0 and s1 <= 0.0 and _in_band(a, d, c0, c1, s0, s1)


static func _in_band(a: Vector2, d: Vector2, c0: Vector2, c1: Vector2, s0: float, s1: float) -> bool:
	var f := s0 / (s0 - s1) if s0 != s1 else 0.0
	var q := c0 + f * (c1 - c0)
	var u := d.dot(q - a) / d.length_squared()
	return u >= 0.0 and u <= 1.0
