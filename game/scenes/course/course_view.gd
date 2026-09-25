class_name CourseView
extends Node3D
## The course of the race drawn from the core's resolved course and race state (courses.md, race.md, hud.md):
##   - every mark but `virtual` ones: buoys of their style that ride the sea (heave and tilt from the drawn sea
##     height), committee and mark boats on the 17-point outline of courses.md §2 at their resolved heading,
##     riding the sea with some inertia;
##   - the committee boat's flags from the race state (race.md §3.2, hud.md §9.1): orange (line end) always, the
##     class flag from the warning signal to the start, the prep flag from the preparatory signal to one
##     minute, X while shown; the finish mark boat flies blue from the start. Flags are hoisted and lowered on
##     their halyards over HOIST_TIME and stream downwind;
##   - water overlays through the Sea hooks (water_render.md §6): the start line (hud.md §9.3: white from the
##     warning signal, red while the viewed boat is over in the last minute, green after the gun until she has
##     started, then hidden), the gate line when the next step is a gate, the finish line on the last leg,
##     the laylines of hud.md §6 (red port tack, green starboard tack, refreshed at 2 Hz) and the zone circle of
##     hud.md §7 within 6 L of the next mark;
##   - hud.md §7 in 3-D: the rounding arrow on the next mark(s) and, beyond 500 m, a bouncing marker over it.
## Mark styles and labels come from the course file (the C API gives type, position, radius and heading).
##
##   view.bind(sim, boat, sea, course_path); per tick view.tick(); per frame view.frame(alpha, dt, cam_pos)

const HOIST_TIME := 1.5
const LAYLINE_REFRESH_TICKS := 10  # 2 Hz
const WIND_TAU := 10.0
const MARKER_DIST := 500.0
const COL_WHITE := Color(0.92, 0.92, 0.9)
const COL_RED := Color(0.95, 0.3, 0.25)
const COL_GREEN := Color(0.3, 0.85, 0.35)
const COL_YELLOW := Color(0.95, 0.8, 0.2)
const COL_BLUE := Color(0.35, 0.6, 1.0)

enum { MARK_BUOY, MARK_COMMITTEE, MARK_BOAT, MARK_VIRTUAL }
enum { STEP_START, STEP_MARK, STEP_GATE, STEP_FINISH }
enum { RACE_CREATED, RACE_FREE, RACE_SEQUENCE, RACE_RACING, RACE_CLOSING, RACE_CLOSED, RACE_ABANDONED }
enum { SEQ_5410, SEQ_3210, SEQ_MATCH }

var sim: CoreSimSource
var boat := 0
var sea: Sea
## the resolved course (CoreSim.course()) and the file's marks by id (style, labels)
var course := {}
var labels := {}
## assist: laylines and the zone circle (hud.md §14); arrows are always shown
var show_laylines := true
var show_zone := true
## per mark index: {node, type, pos: Vector2, radius, heading, length, beam, heave, pitch, roll}
var marks: Array = []
## overlays of the last frame (tests): the Sea's lines and circles
var lines: Array = []
var circles: Array = []
## the start line state of the last frame: "hidden", "white", "red", "green"
var start_line_state := "hidden"
## which flags are up on the committee boat (target of the halyards): Flag -> bool
var flags_up := {}
## laylines of the last refresh: [{a, b, tack (+1 starboard, -1 port), mark}]
var laylines: Array = []
## the leg type of the next step: "beat", "run", "reach", "" (none)
var leg := ""

var _race := {}
var _rb := {}
var _flags := {}  # Flag -> {node, level}
var _flag_boat := -1
var _blue_boat := -1
var _twd_vec := Vector2.ZERO  # smoothed clean wind direction as a unit vector (from)
var _tws := 0.0
var _vmg := {}
var _layline_age := 1 << 30
var _arrows: Array[MeshInstance3D] = []
var _marker: MeshInstance3D
var _marker_label: Label3D
var _t := 0.0
var _mat: StandardMaterial3D
var _guide_mat: StandardMaterial3D
var _flag_mat: StandardMaterial3D
var _loa := 7.2


func bind(source: CoreSimSource, boat_index: int, sea_node: Sea, course_path := "") -> void:
	sim = source
	boat = boat_index
	sea = sea_node
	course = sim.core.course()
	_loa = sim.class_info(boat).loa
	_read_file(course_path)
	_mat = ColorMesh.material(0.55)
	_flag_mat = ColorMesh.material(0.8, 0.0, true)
	_guide_mat = ColorMesh.material(1.0)
	_guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guide_mat.no_depth_test = false
	_build_marks()
	_build_guides()
	tick()


## The course file's mark styles and display labels (the core's resolved course has no styles).
func _read_file(course_path: String) -> void:
	var path := course_path
	if path != "" and not path.ends_with(".json"):
		path = BoatClassData.repo_path("game/data/courses/%s.course.json" % path)
	var d: Variant = BoatClassData._read_json(path) if path != "" else null
	var styles := {}
	if d is Dictionary:
		for m in d.get("marks", []):
			styles[m["id"]] = m.get("style", "inflatable")
		labels = d.get("display", {}).get("labels", {})
	for m in course.get("marks", []):
		m["style"] = styles.get(m["id"], "large" if float(m["radius"]) >= 1.5 else "inflatable")


func label(mark: int) -> String:
	var id: String = course["marks"][mark]["id"]
	return labels.get(id, id)


# ---- building -------------------------------------------------------------------------------------------------

func _build_marks() -> void:
	var start: Dictionary = course["steps"][0]
	var finish: Dictionary = course["steps"][-1]
	for i in course["marks"].size():
		var m: Dictionary = course["marks"][i]
		var rec := {"type": int(m["type"]), "pos": Vector2(m["x"], m["y"]), "radius": float(m["radius"]),
			"heading": float(m["heading"]), "length": float(m["length"]), "beam": float(m["beam"]),
			"heave": 0.0, "pitch": 0.0, "roll": 0.0, "node": null, "style": m["style"]}
		marks.append(rec)
		if rec["type"] == MARK_VIRTUAL:
			continue
		var n := Node3D.new()
		n.name = "mark_" + String(m["id"])
		add_child(n)
		rec["node"] = n
		var mi := MeshInstance3D.new()
		mi.name = "body"
		mi.material_override = _mat
		match rec["type"]:
			MARK_BUOY:
				match String(m["style"]):
					"tetra":
						mi.mesh = CourseProps.tetra(rec["radius"], CourseProps.ORANGE)
					"large":
						mi.mesh = CourseProps.buoy(rec["radius"], 2.3, CourseProps.ORANGE)
					_:
						mi.mesh = CourseProps.buoy(rec["radius"], 1.6, CourseProps.YELLOW)
			_:
				var small: bool = rec["type"] == MARK_BOAT
				mi.mesh = CourseProps.committee_boat(rec["length"], rec["beam"], small)
		n.add_child(mi)
		if rec["type"] == MARK_COMMITTEE and _flag_boat < 0:
			_flag_boat = i
			_build_flags(n, rec)
		elif rec["type"] == MARK_BOAT and i in [int(finish["marks"][0]), int(finish["marks"][1])] and _blue_boat < 0:
			_blue_boat = i
			_add_flag(n, CourseProps.Flag.BLUE, CourseProps.staff_top(rec["length"], true), 1.2, 0.0)
	_place_marks(0.0, true)
	if start.is_empty():
		push_warning("course without a start")


## Signal flags of the committee boat: class, prep (the race's), X on the yard; orange on the stern staff.
func _build_flags(n: Node3D, rec: Dictionary) -> void:
	var mast := CourseProps.signal_mast(rec["length"])
	var yard := mast + Vector3(0, 4.6, 0)
	var prep: int = [CourseProps.Flag.P, CourseProps.Flag.I, CourseProps.Flag.Z, CourseProps.Flag.U,
		CourseProps.Flag.BLACK][clampi(int(sim.core.race().get("prep_flag", 1)), 0, 4)]
	_add_flag(n, CourseProps.Flag.CLASS, yard + Vector3(-1.4, 0, 0), 3.6, 0.0)
	_add_flag(n, prep, yard + Vector3(1.4, 0, 0), 3.6, 0.0)
	_add_flag(n, CourseProps.Flag.X, yard + Vector3(0.7, 0, 0), 3.6, 0.0)
	_add_flag(n, CourseProps.Flag.ORANGE, CourseProps.staff_top(rec["length"], false), 1.0, 1.0)
	_flags[CourseProps.Flag.ORANGE]["prep"] = false
	_flags[prep]["prep"] = true


## A flag on a halyard from `top` down `drop` m; `level` 1 = fully hoisted.
func _add_flag(parent: Node3D, kind: int, top: Vector3, drop: float, level: float) -> void:
	var f := MeshInstance3D.new()
	f.name = "flag_%d" % kind
	f.mesh = CourseProps.flag(kind)
	f.material_override = _flag_mat
	parent.add_child(f)
	_flags[kind] = {"node": f, "level": level, "top": top, "drop": drop, "phase": randf() * TAU}


func _build_guides() -> void:
	for k in 2:
		var a := MeshInstance3D.new()
		a.name = "rounding_arrow_%d" % k
		a.mesh = CourseProps.rounding_arrow(1.0, COL_YELLOW)
		a.material_override = _guide_mat
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.visible = false
		add_child(a)
		_arrows.append(a)
	_marker = MeshInstance3D.new()
	_marker.name = "next_marker"
	_marker.mesh = CourseProps.marker(COL_YELLOW)
	_marker.material_override = _guide_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	_marker_label = Label3D.new()
	_marker_label.name = "next_label"
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_label.fixed_size = true
	_marker_label.pixel_size = 0.0012
	_marker_label.font_size = 28
	_marker_label.outline_size = 8
	_marker_label.modulate = COL_YELLOW
	_marker_label.no_depth_test = true
	_marker_label.visible = false
	add_child(_marker_label)


# ---- per tick -------------------------------------------------------------------------------------------------

## Once per simulation tick: race state, the smoothed wind for the laylines, the layline refresh at 2 Hz.
func tick() -> void:
	_race = sim.core.race()
	_rb = sim.core.race_boat(boat)
	var s := sim.state(boat)
	var w := sim.wind_clean(s.pos_x, s.pos_y)
	var u := Vector2(sin(w.y), cos(w.y))
	var k := Frames.smooth_k(SimSource.DT, WIND_TAU)
	if _twd_vec == Vector2.ZERO:
		_twd_vec = u
		_tws = s.tws
	else:
		_twd_vec += (u - _twd_vec) * k
		_tws += (s.tws - _tws) * k
	_layline_age += 1
	if _layline_age >= LAYLINE_REFRESH_TICKS:
		_layline_age = 0
		_refresh_laylines(s)


## The smoothed clean wind direction (from, compass) the laylines use.
func twd() -> float:
	return Frames.compass(_twd_vec.x, _twd_vec.y)


## The next step index of the viewed boat (0 before she has started) and its step record.
func next_step() -> int:
	return int(_rb.get("next", 0))


## The target points of a step: [buoy] for a mark, both buoys of a gate, both ends of a line.
func step_points(k: int) -> Array[Vector2]:
	var st: Dictionary = course["steps"][k]
	var out: Array[Vector2] = []
	var ms: PackedInt32Array = st["marks"]
	out.append(marks[ms[0]]["pos"])
	if int(st["kind"]) != STEP_MARK:
		out.append(marks[ms[1]]["pos"])
	return out


func _refresh_laylines(s: SimSource.BoatState) -> void:
	laylines.clear()
	leg = ""
	var k := next_step()
	if k <= 0 or k >= course["steps"].size() or bool(_rb.get("finished", false)):
		return
	var st: Dictionary = course["steps"][k]
	var c := Vector2(s.pos_x, s.pos_y)
	var pts := step_points(k)
	var r := pts[0]
	if int(st["kind"]) == STEP_GATE:
		r = pts[0] if c.distance_to(pts[0]) <= c.distance_to(pts[1]) else pts[1]
	elif int(st["kind"]) == STEP_FINISH:
		r = Geometry2D.get_closest_point_to_segment(c, pts[0], pts[1])
	_vmg = sim.core.polar_vmg(boat, _tws)
	if _vmg.is_empty():
		return
	var th_up: float = _vmg["up_twa"]
	var th_dn: float = _vmg["down_twa"]
	var tw := twd()
	var th_r := absf(Frames.wrap_pi(tw - Frames.compass(r.x - c.x, r.y - c.y)))
	var hyst := deg_to_rad(3.0)
	if th_r < th_up + hyst:
		leg = "beat"
	elif th_r > th_dn - hyst:
		leg = "run"
	else:
		leg = "reach"
		return
	var th := th_up if leg == "beat" else th_dn
	var v: float = _vmg["up_speed"] if leg == "beat" else _vmg["down_speed"]
	var length := 1.2 * maxf(c.distance_to(r), 500.0)
	var t_ms := sim.sea_time_ms(sim.tick())
	for p in pts:
		var cur := sim.current_at(p.x, p.y, t_ms)
		for tack in [1, -1]:
			# starboard tack (twa > 0): heading = TWD - theta; port: TWD + theta
			var psi := Frames.wrap_2pi(tw - tack * th)
			var g := v * Vector2(sin(psi), cos(psi)) + cur
			var cog := Frames.compass(g.x, g.y)
			laylines.append({"a": p, "b": p - length * Vector2(sin(cog), cos(cog)), "tack": tack, "mark": p})


# ---- per frame ------------------------------------------------------------------------------------------------

## Once per rendered frame: marks on the sea, flags, guides and the water overlays.
func frame(dt: float, cam_pos: Vector3, pose: SimSource.RenderPose) -> void:
	_t += dt
	_place_marks(dt, false)
	_update_flags(dt)
	_update_overlays(pose)
	_update_guides(pose, cam_pos)


func _sea_h(x: float, y: float) -> float:
	return sea.height_at(x, y) if sea else 0.0


func _place_marks(dt: float, snap: bool) -> void:
	for rec in marks:
		var n: Node3D = rec["node"]
		if n == null:
			continue
		var p: Vector2 = rec["pos"]
		var z: float
		var pitch: float
		var roll: float
		var psi: float = rec["heading"]
		var fwd := Vector2(sin(psi), cos(psi))
		var port := Vector2(-cos(psi), sin(psi))
		if rec["type"] == MARK_BUOY:
			var e := 0.6
			z = _sea_h(p.x, p.y)
			pitch = atan2(_sea_h(p.x + fwd.x * e, p.y + fwd.y * e) - _sea_h(p.x - fwd.x * e, p.y - fwd.y * e), 2.0 * e) * 0.7
			roll = atan2(_sea_h(p.x + port.x * e, p.y + port.y * e) - _sea_h(p.x - port.x * e, p.y - port.y * e), 2.0 * e) * 0.7
		else:
			var lx: float = 0.35 * rec["length"]
			var ly: float = 0.35 * rec["beam"]
			var hb := _sea_h(p.x + fwd.x * lx, p.y + fwd.y * lx)
			var hs := _sea_h(p.x - fwd.x * lx, p.y - fwd.y * lx)
			var hp := _sea_h(p.x + port.x * ly, p.y + port.y * ly)
			var hsb := _sea_h(p.x - port.x * ly, p.y - port.y * ly)
			z = 0.25 * (hb + hs + hp + hsb)
			pitch = atan2(hb - hs, 2.0 * lx) * 0.8
			roll = atan2(hp - hsb, 2.0 * ly) * 0.8
		var k := 1.0 if snap else Frames.smooth_k(dt, 0.15 if rec["type"] == MARK_BUOY else 0.6)
		rec["heave"] += (z - rec["heave"]) * k
		rec["pitch"] += (pitch - rec["pitch"]) * k
		rec["roll"] += (roll - rec["roll"]) * k
		# local frame: bow -Z, port -X; pitch bow-up about +X, roll port-up about -Z
		var b := Basis(Vector3.UP, -psi) * Basis(Vector3.RIGHT, rec["pitch"]) * Basis(Vector3.BACK, rec["roll"])
		n.transform = Transform3D(b, Frames.enu_to_scene(p.x, p.y, rec["heave"]))


## Race time (s, < 0 before the gun) and the warning time of the sequence.
func race_time() -> float:
	return float(_race.get("race_time", -INF))


func warning_time() -> float:
	return 180.0 if int(_race.get("sequence", SEQ_5410)) == SEQ_3210 else 300.0


func _update_flags(dt: float) -> void:
	var t := race_time()
	var tw := warning_time()
	var state := int(_race.get("state", RACE_CREATED))
	var seq := state == RACE_SEQUENCE
	flags_up.clear()
	for kind in _flags:
		var up := false
		match kind:
			CourseProps.Flag.ORANGE:
				up = true
			CourseProps.Flag.CLASS:
				up = seq and t >= -tw and t < 0.0
			CourseProps.Flag.X:
				up = bool(_race.get("x_flag", false))
			CourseProps.Flag.BLUE:
				up = state >= RACE_RACING and state < RACE_CLOSED
			_:
				up = seq and t >= -(tw - 60.0) and t < -60.0
		flags_up[kind] = up
		var f: Dictionary = _flags[kind]
		f["level"] = move_toward(f["level"], 1.0 if up else 0.0, dt / HOIST_TIME)
		var node: MeshInstance3D = f["node"]
		node.visible = f["level"] > 0.02
		# downwind: local +X to the compass direction the wind blows to, with a little flutter
		var to := twd() + PI
		var yaw := PI * 0.5 - to + 0.08 * sin(_t * 5.3 + f["phase"])
		var parent_yaw := -float(marks[_flag_boat if kind != CourseProps.Flag.BLUE else _blue_boat]["heading"])
		var pos: Vector3 = f["top"] - Vector3(0, f["drop"] * (1.0 - f["level"]) + CourseProps.FLAG_H, 0)
		node.transform = Transform3D(Basis(Vector3.UP, yaw - parent_yaw), pos)


## The start line A -> B oriented so the course side is on the left (race.md §3.3).
func start_line() -> Array[Vector2]:
	var ends := step_points(0)
	var a := ends[0]
	var b := ends[1]
	var ref: Vector2 = course["steps"][1]["ref"] if course["steps"].size() > 1 else a
	if (b - a).cross(ref - a) < 0.0:
		return [b, a]
	return [a, b]


## race.md §3.3 over the line under the active flag, from the hull ends and middle at the render pose.
func is_over(pose: SimSource.RenderPose) -> bool:
	var ab := start_line()
	var a := ab[0]
	var b := ab[1]
	var d := b - a
	var fwd := Vector2(sin(pose.psi), cos(pose.psi))
	var c := Vector2(pose.pos_x, pose.pos_y)
	var flag := int(_race.get("prep_flag", 1))
	var first: Vector2 = course["steps"][1]["ref"] if course["steps"].size() > 1 else a
	for q in [c + fwd * 0.5 * _loa, c, c - fwd * 0.5 * _loa]:
		var s := d.cross(q - a) / d.length()
		var u := d.dot(q - a) / d.length_squared()
		match flag:
			0:  # P: over in the line band
				if s > 0.0 and u >= 0.0 and u <= 1.0:
					return true
			1:  # I: on the course side incl. the extensions
				if s > 0.0:
					return true
			_:  # Z, U, black: inside the triangle
				if Geometry2D.point_is_inside_triangle(q, a, b, first):
					return true
	return false


func _update_overlays(pose: SimSource.RenderPose) -> void:
	lines = []
	circles = []
	var state := int(_race.get("state", RACE_CREATED))
	var t := race_time()
	var started := bool(_rb.get("started", false))
	var ends := start_line()
	start_line_state = "hidden"
	if state == RACE_SEQUENCE:
		start_line_state = "red" if t >= -60.0 and is_over(pose) else "white"
	elif state >= RACE_RACING and state < RACE_CLOSED and not started:
		start_line_state = "green"
	if start_line_state != "hidden":
		var col: Color = {"white": COL_WHITE, "red": COL_RED, "green": COL_GREEN}[start_line_state]
		lines.append({"a": ends[0], "b": ends[1], "color": col, "width": 0.35, "kind": "start"})
	var k := next_step()
	var n_steps: int = course["steps"].size()
	if started and k > 0 and k < n_steps and not bool(_rb.get("finished", false)):
		var st: Dictionary = course["steps"][k]
		var pts := step_points(k)
		match int(st["kind"]):
			STEP_GATE:
				lines.append({"a": pts[0], "b": pts[1], "color": COL_YELLOW, "width": 0.25, "kind": "gate"})
			STEP_FINISH:
				lines.append({"a": pts[0], "b": pts[1], "color": COL_BLUE, "width": 0.35, "kind": "finish"})
		if show_laylines:
			for l in laylines:
				lines.append({"a": l["a"], "b": l["b"], "color": COL_GREEN if l["tack"] > 0 else COL_RED,
					"width": 0.3, "kind": "layline"})
		if show_zone and int(st["kind"]) != STEP_FINISH:
			var c := Vector2(pose.pos_x, pose.pos_y)
			for i in pts.size():
				var mi: int = st["marks"][i]
				if c.distance_to(pts[i]) <= 6.0 * _loa:
					circles.append({"c": pts[i], "r": 3.0 * _loa, "color": COL_YELLOW, "width": 0.25, "mark": mi})
	if sea:
		sea.set_overlay_lines(lines)
		sea.set_overlay_circles(circles)


## Rounding arrows on the next step's buoys and the far marker (hud.md §7).
func _update_guides(pose: SimSource.RenderPose, cam_pos: Vector3) -> void:
	for a in _arrows:
		a.visible = false
	_marker.visible = false
	_marker_label.visible = false
	var k := next_step()
	var started := bool(_rb.get("started", false))
	if bool(_rb.get("finished", false)) or course.is_empty():
		return
	if not started:
		k = 1 if int(_race.get("state", 0)) >= RACE_SEQUENCE else -1  # show the first mark from the warning
	if k <= 0 or k >= course["steps"].size():
		return
	var st: Dictionary = course["steps"][k]
	var c := Vector2(pose.pos_x, pose.pos_y)
	var pts := step_points(k)
	var nearest := pts[0]
	if int(st["kind"]) != STEP_FINISH:
		for i in pts.size():
			var mi: int = st["marks"][i]
			var rec: Dictionary = marks[mi]
			var arrow := _arrows[i]
			var r: float = rec["radius"] + 3.0
			var toward := (c - pts[i]).normalized()
			var start_ang := Frames.compass(toward.x, toward.y)
			var port := int(st["sides"][i]) == 0
			# the mesh starts at north (-Z) and turns anticlockwise; rotate it to start on the boat's side
			var b := Basis(Vector3.UP, -start_ang) * Basis.from_scale(Vector3(r if port else -r, 1.0, r))
			arrow.transform = Transform3D(b, Frames.enu_to_scene(pts[i].x, pts[i].y, rec["heave"] + 2.6))
			arrow.visible = true
			if c.distance_to(pts[i]) < c.distance_to(nearest):
				nearest = pts[i]
	else:
		nearest = Geometry2D.get_closest_point_to_segment(c, pts[0], pts[1])
	var dist := c.distance_to(nearest)
	if dist > MARKER_DIST:
		var base := Frames.enu_to_scene(nearest.x, nearest.y, 0.0)
		var cam_d := maxf(cam_pos.distance_to(base), 1.0)
		var sc := cam_d * 0.018
		var bounce := (0.5 + 0.5 * sin(_t * TAU * 0.8)) * 0.6 * sc
		_marker.transform = Transform3D(Basis.from_scale(Vector3.ONE * sc), base + Vector3(0, 6.0 + sc * 0.4 + bounce, 0))
		_marker.visible = true
		var name_ := label(int(st["marks"][0])) if int(st["kind"]) == STEP_MARK else \
			("Finish" if int(st["kind"]) == STEP_FINISH else "Gate")
		_marker_label.text = "%s  %s" % [name_, HudFormat.distance(dist)]
		_marker_label.position = base + Vector3(0, 6.0 + sc * 1.6 + bounce, 0)
		_marker_label.visible = true


## The marks' scene nodes by course mark id (tests).
func mark_node(id: String) -> Node3D:
	for i in course["marks"].size():
		if course["marks"][i]["id"] == id:
			return marks[i]["node"]
	return null


## hud.md §7 distance to the next step from the bow: buoy centre minus radius (gate: the nearer buoy), the
## nearest point of a line. INF without a next step.
func distance_to_next(pose: SimSource.RenderPose) -> float:
	var k := next_step()
	if k <= 0 or k >= course["steps"].size():
		return INF
	var st: Dictionary = course["steps"][k]
	var bow := Vector2(pose.pos_x, pose.pos_y) + 0.5 * _loa * Vector2(sin(pose.psi), cos(pose.psi))
	var pts := step_points(k)
	if int(st["kind"]) == STEP_FINISH:
		return bow.distance_to(Geometry2D.get_closest_point_to_segment(bow, pts[0], pts[1]))
	var best := INF
	for i in pts.size():
		best = minf(best, bow.distance_to(pts[i]) - float(marks[int(st["marks"][i])]["radius"]))
	return maxf(best, 0.0)


## The next step's point in the scene for the aerial camera's boat-and-mark framing (cameras.md §4), null
## before the start and after the finish.
func next_mark_scene() -> Variant:
	var k := next_step()
	if k <= 0 or k >= course["steps"].size():
		return null
	var r: Vector2 = course["steps"][k]["ref"]
	return Frames.enu_to_scene(r.x, r.y, 0.0)
