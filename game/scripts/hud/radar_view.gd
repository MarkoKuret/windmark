class_name RadarView
extends HudCanvas
## hud.md §8 radar: centred on the viewed boat, heading-up (default) or north-up, range 100 m to 3 km in x1.5
## steps (remembered in user://hud.cfg). Boats as oriented icons of at least 8 px coloured by the pair records
## (RaceHudValues.contacts: red I keep clear, green she keeps clear, orange I owe room, cyan she owes me room,
## white none, grey translucent ghosts), pulsing at 2 Hz on Warning and 4 Hz with an outline on Breach. Marks:
## the next step in yellow with its rounding arrow and zone circle, the following step in white, the others as
## grey dots; the start line until the boat has started, the finish line on the last leg, the course boundary,
## the laylines (red port, green starboard) and the true wind arrow at the edge. Positions are the render poses
## of the frame. With `colours` off (Minimal assist) every racing boat is white; `laylines` off hides them.
## Look (hud.md §16.2): a soft ink disc with hairline rings, the own boat and the next mark in `mark`, the range and
## orientation under the disc (not with `compact`, the Glance density). The selected boat (hud.md §16.4.1) gets four
## hairline corners round her icon.

const RANGES := [100.0, 150.0, 225.0, 337.5, 506.25, 759.375, 1139.0625, 1708.59375, 2562.890625]
const CFG := "user://hud.cfg"

var range_index := 4
var north_up := false
var colours := true
var laylines := true
var values: RaceHudValues
var sim: SimSource
var alpha := 1.0
var twd := 0.0  # felt TWD (HudValues)
var tws := 0.0
## Glance: no range and orientation labels
var compact := false
## what was drawn last (tests): boat -> Color
var drawn := {}
## the selected boat (hud.md §16.4.1), -1 for none: her icon gets four hairline corners
var selected := -1
## where the selected boat's corners were drawn last (tests), Vector2.INF when not
var selected_at := Vector2.INF

var _t := 0.0
## the build's frame (_px): the viewed boat, the rotation, the disc centre and the px per metre
var _disc_o := Vector2.ZERO
var _disc_rot := 0.0
var _disc_c := Vector2.ZERO
var _disc_scale := 1.0


func _init() -> void:
	super()
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
	if not is_inside_tree() or get_parent() is not Hud:
		queue_redraw()  # on its own (tests, previews); in the HUD its redraw comes with the others (Hud._redraw)


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
		return HudStyle.TINTS[RaceHudValues.Tint.GREY]
	var col: Color = HudStyle.TINTS[ct.tint] if colours else HudStyle.TINTS[RaceHudValues.Tint.WHITE]
	if colours and ct.pulse != RaceHudValues.Pulse.NONE:
		var hz := 2.0 if ct.pulse == RaceHudValues.Pulse.WARNING else 4.0
		col.a *= 1.0 - 0.45 * (0.5 + 0.5 * sin(TAU * hz * _t))
	return col


## The radar as drawing primitives in its own coordinates (HudCanvas; offline previews read primitives()): the disc
## fills the width, the labels sit under it.
func _build() -> void:
	drawn.clear()
	selected_at = Vector2.INF
	var r := minf(size.x, size.y) * 0.5
	var c := Vector2(size.x * 0.5, r)
	var hw := maxf(1.0, 1.5 * k)
	_c(c, r, Color(HudStyle.INK, 0.38))
	_a(c, r, 0.0, TAU, 72, HudStyle.HAIR, hw)
	_a(c, r * 0.5, 0.0, TAU, 48, Color(HudStyle.HAIR, 0.45 * HudStyle.HAIR.a), hw)
	_l(c - Vector2(0, r), c + Vector2(0, r), Color(HudStyle.HAIR, 0.45 * HudStyle.HAIR.a), hw)
	if not compact:
		var fs := int(roundf(13.0 * k))
		if north_up:  # hud.md §8: heading-up is the default and needs no label
			_s(Vector2(0, 2.0 * r + 22.0 * k), "NORTH UP", fs, HudStyle.LABEL, 600, 0.14)
		_s(Vector2(size.x, 2.0 * r + 22.0 * k), HudFormat.distance(range_m()).to_upper(), fs, HudStyle.LABEL, 600, 0.14,
			HORIZONTAL_ALIGNMENT_RIGHT)
	if sim == null or values == null or not values.active:
		return
	var me := sim.render_pose(values.boat, alpha)
	if me == null:
		return
	var o := Vector2(me.pos_x, me.pos_y)
	var rot := 0.0 if north_up else me.psi
	var scale := r / range_m()
	# a point to the disc: ENU rotated so that the heading points up (_px); inside the disc when within r of c
	_disc_o = o
	_disc_rot = rot
	_disc_c = c
	_disc_scale = scale
	var crs := values.course()
	var steps: Array = crs.get("steps", [])
	var marks: Array = crs.get("marks", [])
	# boundary
	var bnd: PackedVector2Array = crs.get("boundary", PackedVector2Array())
	for i in bnd.size():
		_seg(_px(bnd[i]), _px(bnd[(i + 1) % bnd.size()]), c, r, Color(HudStyle.PORT, 0.5), hw)
	# lines
	if not values.started and steps.size() > 0:
		var p := values.step_points(0)
		_seg(_px(p[0]), _px(p[1]), c, r, HudStyle.PAPER, 2.0 * k)
	if values.next_step == steps.size() - 1 and values.next_step > 0:
		var p := values.step_points(values.next_step)
		_seg(_px(p[0]), _px(p[1]), c, r, HudStyle.PAPER, 2.0 * k)
	# laylines
	if laylines:
		for l in values.laylines:
			var col := HudStyle.STBD if int(l["tack"]) > 0 else HudStyle.PORT
			_seg(_px(l["a"]), _px(l["b"]), c, r, col, 1.5 * k)
	# marks
	var nk := values.next_step
	var following := nk + 1 if nk > 0 else -1
	var shown := {}
	for st in [nk, following]:
		if st <= 0 or st >= steps.size() or int(steps[st]["kind"]) == RaceText.Step.FINISH:
			continue
		var ms: PackedInt32Array = steps[st]["marks"]
		var sides: PackedInt32Array = steps[st]["sides"]
		var n := 1 if int(steps[st]["kind"]) == RaceText.Step.MARK else 2
		for i in n:
			if shown.has(ms[i]):
				continue
			shown[ms[i]] = true
			var mp := Vector2(marks[ms[i]]["x"], marks[ms[i]]["y"])
			var q: Vector2 = _px(mp)
			if q.distance_to(c) > r:
				q = c + (q - c).normalized() * (r - 4.0)
			var col := HudStyle.MARK if st == nk else HudStyle.PAPER
			var dm := 5.0 * self.k
			_p(PackedVector2Array([q + Vector2(0, -dm), q + Vector2(dm, 0), q + Vector2(0, dm), q + Vector2(-dm, 0)]), col)
			if st == nk:
				var zr := 3.0 * values._loa * scale
				if zr > 5.0:
					_a(q, zr, 0.0, TAU, 32, Color(HudStyle.MARK, 0.5), hw)
				# rounding arrow: an arc on the side the boat passes, with its head in the rounding direction
				HudPaint.rounding_arc(self, q, 10.0 * self.k, sides[i] == RaceText.Side.PORT, col, 2.0 * self.k)
	for i in marks.size():
		if shown.has(i) or int(marks[i]["type"]) == 3:
			continue
		var q: Vector2 = _px(Vector2(marks[i]["x"], marks[i]["y"]))
		if q.distance_to(c) <= r:
			_c(q, 2.5 * self.k, Color(HudStyle.PAPER, 0.6))
	# boats
	for ct in values.contacts:
		var p := sim.render_pose(ct.boat, alpha)
		if p == null:
			continue
		var q: Vector2 = _px(Vector2(p.pos_x, p.pos_y))
		if q.distance_to(c) > r:
			continue
		var col := contact_colour(ct)
		drawn[ct.boat] = col
		var outline := colours and ct.pulse == RaceHudValues.Pulse.BREACH and not ct.ghost
		_boat(q, p.psi - rot, sim.class_info(ct.boat).loa * scale, col, outline)
		if ct.boat == selected:
			var e := 9.0 * k
			HudPaint.bracket(self, Rect2(q - Vector2(e, e), Vector2(e, e) * 2.0), HudStyle.PAPER, 4.0)
			selected_at = q
	_boat(c, me.psi - rot, values._loa * scale, HudStyle.MARK, false)
	# message target pointer
	if values.message != null and values.message.other >= 0:
		var tp := sim.render_pose(values.message.other, alpha)
		if tp != null:
			var q: Vector2 = _px(Vector2(tp.pos_x, tp.pos_y))
			if q.distance_to(c) <= r:
				_a(q, 10.0 * self.k, 0.0, TAU, 20, HudStyle.PAPER, 1.5 * self.k)
	# true wind arrow at the edge, pointing where it blows
	var wa := twd - rot  # from
	var edge := c + r * Vector2(sin(wa), -cos(wa))
	var inward := (c - edge).normalized()
	var ln := 22.0 * k * clampf(0.6 + 0.9 * tws / (30.0 * HudFormat.KNOT), 0.6, 1.5)
	var tail := edge - inward * ln * 0.6
	var head := edge + inward * ln * 0.4
	_l(tail, head, HudStyle.PAPER, 2.0 * k)
	var side := Vector2(-inward.y, inward.x)
	_p(PackedVector2Array([head + inward * 7.0 * k, head + side * 6.0 * k, head - side * 6.0 * k]), HudStyle.PAPER)


func _px(p: Vector2) -> Vector2:
	var d := (p - _disc_o).rotated(_disc_rot)
	return _disc_c + Vector2(d.x, -d.y) * _disc_scale


func _boat(q: Vector2, psi_screen: float, len_px: float, col: Color, outline: bool) -> void:
	HudPaint.boat_icon(self, q, psi_screen, maxf(len_px, 13.0 * k), col, outline)


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
