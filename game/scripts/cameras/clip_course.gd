class_name ClipCourse
extends RefCounted
## cameras.md §9 the course inputs of the clip cameras, in scene coordinates on the still water (y = 0): the
## start line ends, the viewed boat's next mark with the point she approaches it from and the side it is left
## to, the zone radius and the boats in race order. from_race() reads them from a CourseView and the core.

## the start line: `committee` the committee boat end (or the starboard end), `pin` the other one
var has_line := false
var committee := Vector3.ZERO
var pin := Vector3.ZERO
## the horizontal unit vector from the line to the pre-start side (the side the fleet starts from)
var pre_start := Vector3(0, 0, 1)
## the next mark `M`, the approach point `Q` and the side `s` (+1 left to port, -1 to starboard)
var has_mark := false
var mark := Vector3.ZERO
var approach := Vector3.ZERO
var side := 1
## 3 hull lengths of the viewed boat's class (rules.md §1)
var zone_r := 21.6
## every boat's reference point on the still water, leader first
var boats: Array[Vector3] = []


static func _scene(p: Vector2) -> Vector3:
	return Frames.enu_to_scene(p.x, p.y, 0.0)


## The inputs for viewed boat `viewed` from the course drawn by `cv` and the race on its core; null without a
## race. `loa` is the viewed boat's length overall.
static func from_race(cv: CourseView, viewed: int, loa: float) -> ClipCourse:
	if cv == null or cv.sim == null or cv.course.is_empty() or not cv.sim.core.has_race():
		return null
	var c := ClipCourse.new()
	c.zone_r = float(cv.course.get("zone_lengths", 3.0)) * loa  # rules.md §7.1 (2 L in a match race)
	var steps: Array = cv.course["steps"]
	if steps.size() > 0 and int(steps[0]["kind"]) == CourseView.STEP_START:
		var ab := cv.start_line()  # A -> B with the course on the left: B is the starboard end
		var ends: PackedInt32Array = steps[0]["marks"]
		var committee := ab[1]
		var other := ab[0]
		for i in 2:
			if int(cv.marks[ends[i]]["type"]) == CourseView.MARK_COMMITTEE:
				committee = cv.marks[ends[i]]["pos"]
				other = cv.marks[ends[1 - i]]["pos"]
				break
		c.has_line = true
		c.committee = _scene(committee)
		c.pin = _scene(other)
		var d: Vector2 = ab[1] - ab[0]
		if d.length() > 1e-6:
			c.pre_start = _scene(Vector2(d.y, -d.x)).normalized()  # the right of A -> B (race.md §3.3)
	var rb: Dictionary = cv.sim.core.race_boat(viewed)
	var s := cv.sim.state(viewed)
	var here := Vector2(s.pos_x, s.pos_y)
	var k := int(rb.get("next", 0))
	if not bool(rb.get("started", false)) or k <= 0:
		k = 1
	var done := bool(rb.get("finished", false)) or bool(rb.get("retired", false)) or int(rb.get("ghost", 0)) != 0
	if not done and k < steps.size():
		var pts := cv.step_points(k)
		var mi := 0
		if pts.size() > 1 and here.distance_to(pts[1]) < here.distance_to(pts[0]):
			mi = 1
		var m := pts[mi]
		var q := Vector2.ZERO
		if k - 1 <= 0:
			var line := cv.step_points(0)
			q = (line[0] + line[1]) * 0.5 if line.size() > 1 else line[0]
		else:
			var prev := cv.step_points(k - 1)
			q = prev[0]
			if prev.size() > 1 and m.distance_to(prev[1]) < m.distance_to(prev[0]):
				q = prev[1]
		var st: Dictionary = steps[k]
		if int(st["kind"]) == CourseView.STEP_FINISH and pts.size() > 1:
			# the camera outside the line: on the left of Q -> M when the other end is on the right
			var other_end := pts[1 - mi]
			c.side = 1 if (m - q).cross(other_end - m) < 0.0 else -1
		else:
			c.side = 1 if int(st["sides"][mi]) == 0 else -1
		c.has_mark = true
		c.mark = _scene(m)
		c.approach = _scene(q)
	for b in cv.sim.core.race_order():
		var bs := cv.sim.state(b)
		c.boats.append(_scene(Vector2(bs.pos_x, bs.pos_y)))
	return c
