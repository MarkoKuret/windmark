class_name CoursePilot
extends RefCounted
## A crude helmsman for the sail test's race mode in tests and previews: holds 120 m behind the start line
## until 45 s before the gun, then beats up to start on starboard, then sails to the next step (close-hauled
## on the tack nearer the bearing, with 10 degrees of hysteresis, straight at it when off the wind). It sets the
## local helm command directly (set-and-hold) before each frame.

const HOLD_BACK := 120.0
const GO_AT := -45.0
const BEAT := deg_to_rad(44.0)

static var _tack := {}


static func steer(sc: Node) -> void:
	var cv: CourseView = sc.course_view
	if cv == null:
		return
	var sim: CoreSimSource = sc.sim
	var b: int = sc.runner.boat
	var s := sim.state(b)
	var c := Vector2(s.pos_x, s.pos_y)
	var tw := cv.twd()
	var up := Vector2(sin(tw), cos(tw))
	var rb: Dictionary = sim.core.race_boat(b)
	var want: float
	if not bool(rb.get("started", false)):
		var ends := cv.start_line()
		var mid := (ends[0] + ends[1]) * 0.5
		if cv.race_time() < GO_AT:
			var hold := mid - up * HOLD_BACK
			want = _toward(sc, c, hold, tw) if c.distance_to(hold) > 25.0 else Frames.wrap_2pi(tw + PI * 0.5)
		else:
			want = _toward(sc, c, mid + up * 50.0, tw)
	else:
		var k := cv.next_step()
		if k <= 0 or k >= cv.course["steps"].size():
			want = s.psi
		else:
			want = _toward(sc, c, cv.course["steps"][k]["ref"], tw)
	sc.controls.h_cmd = clampf(Frames.angle_diff(want, s.psi) * 2.5, -1.0, 1.0)


## Heading toward p, no closer than BEAT to the wind, keeping the tack unless the bearing leaves its cone.
static func _toward(sc: Node, c: Vector2, p: Vector2, tw: float) -> float:
	var brg := Frames.compass(p.x - c.x, p.y - c.y)
	var off := Frames.angle_diff(brg, tw)  # + = right of the wind (port tack side)
	if absf(off) >= BEAT:
		return brg
	var id := sc.get_instance_id()
	var tack: float = _tack.get(id, -1.0 if off < 0.0 else 1.0)
	if tack > 0.0 and off < -BEAT * 0.2:
		tack = -1.0
	elif tack < 0.0 and off > BEAT * 0.2:
		tack = 1.0
	_tack[id] = tack
	return Frames.wrap_2pi(tw + tack * BEAT)
