class_name RadarView
extends Control
## hud.md §8 radar: centred on the viewed boat, heading-up (default) or north-up, range 100 m to 3 km in x1.5
## steps (remembered in user://hud.cfg). Boats as oriented icons of at least 8 px coloured by the pair records
## (RaceHudValues.contacts: red I keep clear, green she keeps clear, orange I owe room, cyan she owes me room,
## white none, grey translucent ghosts), pulsing at 2 Hz on Warning and 4 Hz with an outline on Breach. Marks:
## the next step in yellow with its rounding arrow and zone circle, the following step in white, the others as
## grey dots; the start line until the boat has started, the finish line on the last leg, the course boundary,
## the laylines (red port, green starboard) and the true wind arrow at the edge. Positions are the render poses
## of the frame. With `colours` off (Minimal assist) every racing boat is white; `laylines` off hides them.

const RANGES := [100.0, 150.0, 225.0, 337.5, 506.25, 759.375, 1139.0625, 1708.59375, 2562.890625]
const CFG := "user://hud.cfg"
const TINTS := {
	RaceHudValues.Tint.WHITE: Color(0.95, 0.95, 0.95),
	RaceHudValues.Tint.RED: Color(0.95, 0.25, 0.2),
	RaceHudValues.Tint.GREEN: Color(0.3, 0.9, 0.35),
	RaceHudValues.Tint.ORANGE: Color(1.0, 0.6, 0.15),
	RaceHudValues.Tint.CYAN: Color(0.25, 0.85, 0.95),
	RaceHudValues.Tint.YELLOW: Color(0.95, 0.8, 0.2),
	RaceHudValues.Tint.GREY: Color(0.7, 0.7, 0.7, 0.35),
}

var range_index := 4
var north_up := false
var colours := true
var laylines := true
var values: RaceHudValues
var sim: SimSource
var alpha := 1.0
var twd := 0.0  # felt TWD, tau 2 s (HudValues)
var tws := 0.0
## what was drawn last (tests): boat -> Color
var drawn := {}

var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(230, 230)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		range_index = clampi(int(cfg.get_value("radar", "range", range_index)), 0, RANGES.size() - 1)
		north_up = bool(cfg.get_value("radar", "north_up", north_up))


func range_m() -> float:
	return RANGES[range_index]


func zoom(steps: int) -> void:
	range_index = clampi(range_index + steps, 0, RANGES.size() - 1)
	_save()


func toggle_orientation() -> void:
	north_up = not north_up
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("radar", "range", range_index)
	cfg.set_value("radar", "north_up", north_up)
	cfg.save(CFG)


func advance(dt: float) -> void:
	_t += dt
	queue_redraw()


## boat -> the colour it is drawn in now, for the contacts inside the range
func contact_colours() -> Dictionary:
	var out := {}
	if sim == null or values == null or not values.active:
		return out
	var me := sim.render_pose(values.boat, alpha)
	if me == null:
		return out
	for ct in values.contacts:
		var p := sim.render_pose(ct.boat, alpha)
		if p != null and Vector2(p.pos_x - me.pos_x, p.pos_y - me.pos_y).length() <= range_m():
			out[ct.boat] = contact_colour(ct)
	return out


## the colour a contact is drawn in now (pulse included), for tests and the draw
func contact_colour(ct: RaceHudValues.Contact) -> Color:
	if ct.ghost:
		return TINTS[RaceHudValues.Tint.GREY]
	var col: Color = TINTS[ct.tint] if colours else TINTS[RaceHudValues.Tint.WHITE]
	if colours and ct.pulse != RaceHudValues.Pulse.NONE:
		var hz := 2.0 if ct.pulse == RaceHudValues.Pulse.WARNING else 4.0
		col = col.lerp(Color.WHITE, 0.45 * (0.5 + 0.5 * sin(TAU * hz * _t)))
	return col


## The radar as drawing primitives in its own coordinates (what _draw renders; offline previews read it):
## [{k: "circle"|"arc"|"line"|"poly"|"polyline"|"text", ...}]
func primitives() -> Array:
	var out := []
	_prims = out
	drawn.clear()
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	_c(c, r, Color(0.02, 0.08, 0.14, 0.72))
	_a(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 1.5)
	_a(c, r * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0)
	_s(Vector2(4, size.y - 4), HudFormat.distance(range_m()), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1, 1, 1, 0.7))
	_s(Vector2(size.x - 18, size.y - 4), "N" if north_up else "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(1, 1, 1, 0.7))
	if sim == null or values == null or not values.active:
		return out
	var me := sim.render_pose(values.boat, alpha)
	if me == null:
		return out
	var o := Vector2(me.pos_x, me.pos_y)
	var rot := 0.0 if north_up else me.psi
	var scale := r / range_m()
	var to_px := func(p: Vector2) -> Vector2:
		var d := (p - o).rotated(rot)  # ENU rotated so that the heading points up
		return c + Vector2(d.x, -d.y) * scale
	var clip := func(p: Vector2) -> bool: return p.distance_to(c) <= r
	var crs := values.course()
	var steps: Array = crs.get("steps", [])
	var marks: Array = crs.get("marks", [])
	# boundary
	var bnd: PackedVector2Array = crs.get("boundary", PackedVector2Array())
	for i in bnd.size():
		_seg(to_px.call(bnd[i]), to_px.call(bnd[(i + 1) % bnd.size()]), c, r, Color(1, 0.4, 0.4, 0.5), 1.0)
	# lines
	if not values.started and steps.size() > 0:
		var p := values.step_points(0)
		_seg(to_px.call(p[0]), to_px.call(p[1]), c, r, Color(1, 1, 1, 0.8), 2.0)
	if values.next_step == steps.size() - 1 and values.next_step > 0:
		var p := values.step_points(values.next_step)
		_seg(to_px.call(p[0]), to_px.call(p[1]), c, r, Color(0.4, 0.6, 1.0, 0.9), 2.0)
	# laylines
	if laylines:
		for l in values.laylines:
			var col := Color(0.3, 0.9, 0.35, 0.7) if int(l["tack"]) > 0 else Color(0.95, 0.25, 0.2, 0.7)
			_seg(to_px.call(l["a"]), to_px.call(l["b"]), c, r, col, 1.5)
	# marks
	var nk := values.next_step
	var following := nk + 1 if nk > 0 else -1
	var shown := {}
	for k in [nk, following]:
		if k <= 0 or k >= steps.size() or int(steps[k]["kind"]) == RaceText.Step.FINISH:
			continue
		var ms: PackedInt32Array = steps[k]["marks"]
		var sides: PackedInt32Array = steps[k]["sides"]
		var n := 1 if int(steps[k]["kind"]) == RaceText.Step.MARK else 2
		for i in n:
			if shown.has(ms[i]):
				continue
			shown[ms[i]] = true
			var mp := Vector2(marks[ms[i]]["x"], marks[ms[i]]["y"])
			var q: Vector2 = to_px.call(mp)
			if not clip.call(q):
				q = c + (q - c).normalized() * (r - 4.0)
			var col := Color(0.95, 0.8, 0.2) if k == nk else Color(0.95, 0.95, 0.95)
			_c(q, 4.0, col)
			if k == nk:
				var zr := 3.0 * values._loa * scale
				if zr > 5.0:
					_a(q, zr, 0.0, TAU, 32, Color(0.95, 0.8, 0.2, 0.5), 1.0)
				# rounding arrow: an arc on the side the boat passes, with its head in the rounding direction
				var port := sides[i] == RaceText.Side.PORT
				var a0 := -PI * 0.5
				var sweep := -PI * 0.6 if port else PI * 0.6  # port: anticlockwise on screen
				_a(q, 9.0, a0, a0 + sweep, 10, col, 2.0)
				var tip := q + 9.0 * Vector2(cos(a0 + sweep), sin(a0 + sweep))
				_c(tip, 2.5, col)
	for i in marks.size():
		if shown.has(i) or int(marks[i]["type"]) == 3:
			continue
		var q: Vector2 = to_px.call(Vector2(marks[i]["x"], marks[i]["y"]))
		if clip.call(q):
			_c(q, 2.0, Color(0.7, 0.7, 0.7, 0.8))
	# boats
	for ct in values.contacts:
		var p := sim.render_pose(ct.boat, alpha)
		if p == null:
			continue
		var q: Vector2 = to_px.call(Vector2(p.pos_x, p.pos_y))
		if not clip.call(q):
			continue
		var col := contact_colour(ct)
		drawn[ct.boat] = col
		var outline := colours and ct.pulse == RaceHudValues.Pulse.BREACH and not ct.ghost
		_boat(q, p.psi - rot, sim.class_info(ct.boat).loa * scale, col, outline)
	_boat(c, me.psi - rot, values._loa * scale, Color(1.0, 0.85, 0.3), false)
	# message target pointer
	if values.message != null and values.message.other >= 0:
		var tp := sim.render_pose(values.message.other, alpha)
		if tp != null:
			var q: Vector2 = to_px.call(Vector2(tp.pos_x, tp.pos_y))
			if clip.call(q):
				_a(q, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.5)
	# true wind arrow at the edge, pointing where it blows
	var wa := twd - rot  # from
	var edge := c + r * Vector2(sin(wa), -cos(wa))
	var inward := (c - edge).normalized()
	var ln := 22.0 * clampf(0.6 + 0.9 * tws / (30.0 * HudFormat.KNOT), 0.6, 1.5)
	var head := edge + inward * ln
	_l(edge, head, Color(0.6, 0.85, 1.0), 2.5)
	var side := Vector2(-inward.y, inward.x)
	_p(PackedVector2Array([head + inward * 6.0, head + side * 5.0, head - side * 5.0]),
		Color(0.6, 0.85, 1.0))
	return out


func _boat(q: Vector2, psi_screen: float, len_px: float, col: Color, outline: bool) -> void:
	var l := maxf(len_px, 8.0)
	var f := Vector2(sin(psi_screen), -cos(psi_screen))
	var s := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([q + f * 0.5 * l, q - f * 0.5 * l + s * 0.22 * l, q - f * 0.5 * l - s * 0.22 * l])
	_p(pts, col)
	if outline:
		pts.append(pts[0])
		_pl(pts, Color.WHITE, 1.5)


func _seg(a: Vector2, b: Vector2, c: Vector2, r: float, col: Color, w: float) -> void:
	# clip the segment to the radar disc
	var d := b - a
	var fa := a - c
	var qa := d.dot(d)
	if qa < 1e-6:
		return
	var qb := 2.0 * fa.dot(d)
	var qc := fa.dot(fa) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return
	var sq := sqrt(disc)
	var t0 := clampf((-qb - sq) / (2.0 * qa), 0.0, 1.0)
	var t1 := clampf((-qb + sq) / (2.0 * qa), 0.0, 1.0)
	if t1 <= t0:
		return
	_l(a + d * t0, a + d * t1, col, w)


# ---- primitive recording and drawing ----

var _prims: Array = []


func _c(p: Vector2, r: float, col: Color) -> void:
	_prims.append({"k": "circle", "p": p, "r": r, "col": col})


func _a(p: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
	_prims.append({"k": "arc", "p": p, "r": r, "a0": a0, "a1": a1, "n": n, "col": col, "w": w})


func _l(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_prims.append({"k": "line", "a": a, "b": b, "col": col, "w": w})


func _p(pts: PackedVector2Array, col: Color) -> void:
	_prims.append({"k": "poly", "pts": pts, "col": col})


func _pl(pts: PackedVector2Array, col: Color, w: float) -> void:
	_prims.append({"k": "polyline", "pts": pts, "col": col, "w": w})


func _s(p: Vector2, text: String, _align: int, _width: float, size_px: int, col: Color) -> void:
	_prims.append({"k": "text", "p": p, "text": text, "size": size_px, "col": col})


func _draw() -> void:
	var font := get_theme_default_font()
	for q in primitives():
		match q["k"]:
			"circle":
				draw_circle(q["p"], q["r"], q["col"])
			"arc":
				draw_arc(q["p"], q["r"], q["a0"], q["a1"], q["n"], q["col"], q["w"])
			"line":
				draw_line(q["a"], q["b"], q["col"], q["w"])
			"poly":
				draw_colored_polygon(q["pts"], q["col"])
			"polyline":
				draw_polyline(q["pts"], q["col"], q["w"])
			"text":
				draw_string(font, q["p"], q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, q["size"], q["col"])
