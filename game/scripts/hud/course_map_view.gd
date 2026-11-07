class_name CourseMapView
extends HudCanvas
## hud.md §8.1 course map: a full-screen overlay over the running race, course up (the axis from the start line's
## middle to the first rounding step points up the screen, fixed for the race), the whole course fitted once into
## the frame inside the margins (every mark with 12 % of the larger span added on each side, at least 300 m across).
## Drawn bottom to top: the ink scrim, the course boundary, the course line through the steps (sailed legs faint,
## the current one in `mark`, the rest in `hair`), the start (dashed) and finish (checkered) lines, the next step's
## zone circle, the marks (rounding marks as round buoys with an ink rim, the next step's in `mark`), one rounding
## arrow and one name per rounding mark (one name per gate), every boat as the radar's icon in its radar colour
## (RadarView.contact_colour: pulses, ghosts, Minimal all white; boats with no relation at 70 %), the viewed boat
## larger in `mark` with an ink rim, name chips (viewed boat, selected boat, boats with a rules relation), the header (lap and
## leg, the next step), the wind arrow, the scale bar and the close hint. Boats outside the frame are small arrows on
## its edge. Positions are the render poses of the frame, as on the radar.

## the frame's padding, of the larger span on each side, and the smallest span (m)
const PAD := 0.12
const MIN_SPAN := 300.0
## design px: the header and footer rows, the icon length, the click radius
const HEADER := 72.0
const FOOTER := 48.0
const ICON := 14.0
const PICK := 24.0
const SCRIM := 0.82
## design px: the buoy radius, the name's gap from it; the viewed boat's size over the fleet's; the fleet's alpha
## with no rules relation
const BUOY := 5.0
const NAME_GAP := 14.0
const OWN_SCALE := 1.6
const QUIET := 0.7
## the scale bar's lengths (m): round in the §1 distance format (metres under 200 m, nautical miles from 0.2 nm)
const SCALES := [10.0, 20.0, 50.0, 100.0, 150.0, 0.2 * HudFormat.NM, 0.25 * HudFormat.NM, 0.5 * HudFormat.NM,
	1.0 * HudFormat.NM, 2.0 * HudFormat.NM, 5.0 * HudFormat.NM]

var values: RaceHudValues
var sim: SimSource
## the radar whose colours (and pulse clock) the icons share
var radar: RadarView
var alpha := 1.0
var twd := 0.0
var tws := 0.0
## the assist shows the zone circles (not with Minimal, hud.md §14)
var zone := true
## other boats' name chips (boat_names)
var names := true
## the selected boat (hud.md §16.4.1), -1 for none
var selected := -1
## px kept clear for the alert lane (hud.md §8.1): a band on top (portrait); in landscape the lane's drawn screen
## rect while it shows something (the frame moves right of it only when the course would run under it)
var lane_top := 0.0
var lane_rect := Rect2()

## drawn last (tests, picking): the frame (px), m per px, boat -> icon centre (px), boat -> colour, rounding mark
## index -> [side, colour], scale bar [metres, px, label], chips' boats
var frame := Rect2()
var m_per_px := 1.0
var icons := {}
var drawn := {}
var arrows := {}
var scale_bar := []
var chips: Array[int] = []
var path_px := PackedVector2Array()


func _init() -> void:
	super()


## The area (px) inside the screen's margins under the header and over the footer (under the portrait lane band).
func full_rect() -> Rect2:
	var m := HudStyle.margins(size)
	var top := m.y + HEADER * k + lane_top
	var bottom := size.y - HudStyle.bottom_margin(size) - FOOTER * k
	return Rect2(m.x, top, maxf(size.x - 2.0 * m.x, 1.0), maxf(bottom - top, 1.0))


## The frame (px) the course is fitted in: the full width, or right of the alert lane while the lane shows something
## and the course centred in the full width would run under it (hud.md §8.1).
func frame_rect() -> Rect2:
	var f := full_rect()
	if not lane_rect.has_area():
		return f
	var b := world_bounds()
	var s := minf(f.size.x / b.size.x, f.size.y / b.size.y)
	var r := Rect2(f.get_center() - b.size * s * 0.5, b.size * s)
	var gap := 24.0 * k
	if not r.grow(gap).intersects(lane_rect):
		return f
	var left := lane_rect.end.x + gap
	return Rect2(left, f.position.y, maxf(f.end.x - left, 1.0), f.size.y)


## hud.md §8.1: the compass bearing (rad) that points up the screen: from the start line's middle to the first
## rounding step's point; without them the race's mean wind
func up_bearing() -> float:
	if values == null:
		return 0.0
	var steps: Array = values.course().get("steps", [])
	if steps.size() >= 2 and int(steps[0]["kind"]) == RaceText.Step.START:
		var a := step_point(0)
		var b := step_point(1)
		if a.distance_to(b) > 1.0:
			return Frames.compass(b.x - a.x, b.y - a.y)
	return values.twd_mean if "twd_mean" in values else 0.0


## World (ENU) -> the map's frame (m): x right, y up the screen, the course axis along +y.
func to_map(p: Vector2) -> Vector2:
	var u := up_bearing()
	return Vector2(p.x * cos(u) - p.y * sin(u), p.x * sin(u) + p.y * cos(u))


## The world bounds the frame shows in the map's frame (m): every mark but virtual ones, padded, at least MIN_SPAN
## across.
func world_bounds() -> Rect2:
	var crs := values.course() if values != null else {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for m in crs.get("marks", []):
		if int(m["type"]) == 3:
			continue
		var p := to_map(Vector2(m["x"], m["y"]))
		lo = lo.min(p)
		hi = hi.max(p)
	if not lo.is_finite():
		return Rect2(-MIN_SPAN * 0.5, -MIN_SPAN * 0.5, MIN_SPAN, MIN_SPAN)
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0)
	var pad := Vector2.ONE * span * PAD
	var r := Rect2(lo, hi - lo).grow_individual(pad.x, pad.y, pad.x, pad.y)
	var mid := r.get_center()
	r.size = r.size.max(Vector2(MIN_SPAN, MIN_SPAN))
	r.position = mid - r.size * 0.5
	return r


## World (ENU m) -> px, course up, the bounds centred in the frame at one scale on both axes.
func to_px(p: Vector2) -> Vector2:
	var b := world_bounds()
	var f := frame_rect()
	var s := minf(f.size.x / b.size.x, f.size.y / b.size.y)
	var c := b.get_center()
	var q := to_map(p)
	return f.get_center() + Vector2(q.x - c.x, -(q.y - c.y)) * s


## The scale bar: the longest of SCALES not longer than a fifth of the frame's width (the shortest when none is).
static func scale_length(frame_w_px: float, m_px: float) -> float:
	var out: float = SCALES[0]
	for l in SCALES:
		if l / m_px <= frame_w_px * 0.2:
			out = l
	return out


## The point of each step the course line runs through (ENU m): line middles, marks, gate middles.
func step_point(st: int) -> Vector2:
	var pts := values.step_points(st)
	return pts[0] if pts.size() == 1 else (pts[0] + pts[1]) * 0.5


## A gate's name on the map: `Gate 4S / 4P` (a buoy label that already starts with "Gate" loses that word).
static func gate_label(a: String, b: String) -> String:
	return "Gate %s / %s" % [a.trim_prefix("Gate ").trim_prefix("gate "), b.trim_prefix("Gate ").trim_prefix("gate ")]


## The boat whose icon is within PICK design px of `pos` (the nearest), -1 for none.
func boat_at(pos: Vector2) -> int:
	var best := -1
	var bd := PICK * k
	for b in icons:
		if b == values.boat:
			continue
		var d: float = (icons[b] as Vector2).distance_to(pos)
		if d <= bd:
			bd = d
			best = b
	return best


func _build() -> void:
	icons.clear()
	drawn.clear()
	arrows.clear()
	chips.clear()
	scale_bar = []
	path_px = PackedVector2Array()
	_rect(Rect2(Vector2.ZERO, size), Color(HudStyle.INK, SCRIM))
	if values == null or not values.active:
		return
	var crs := values.course()
	var steps: Array = crs.get("steps", [])
	var marks: Array = crs.get("marks", [])
	if steps.is_empty() or marks.is_empty():
		return
	frame = frame_rect()
	var up := up_bearing()
	var wb := world_bounds()
	m_per_px = maxf(wb.size.x / frame.size.x, wb.size.y / frame.size.y)
	var hw := maxf(1.0, 1.5 * k)
	var faint := Color(HudStyle.HAIR, 0.45 * HudStyle.HAIR.a)
	# boundary
	var bnd: PackedVector2Array = crs.get("boundary", PackedVector2Array())
	for i in bnd.size():
		var seg := _clip(to_px(bnd[i]), to_px(bnd[(i + 1) % bnd.size()]))
		if not seg.is_empty():
			_l(seg[0], seg[1], Color(HudStyle.PORT, 0.5), hw)
	# course line: leg i runs from step i - 1 to step i
	var last := steps.size() - 1
	var cur := 1
	if values.finished:
		cur = last + 1
	elif values.next_step > 0:
		cur = values.next_step
	for st in steps.size():
		path_px.append(to_px(step_point(st)))
	for i in range(1, steps.size()):
		var col := faint if i < cur else (HudStyle.MARK if i == cur else HudStyle.HAIR)
		_l(path_px[i - 1], path_px[i], col, 2.0 * k if i == cur else hw)
	# start and finish lines
	var sp := values.step_points(0)
	_line(sp, false, 1.0 if not values.started else 0.45)
	if int(steps[last]["kind"]) == RaceText.Step.FINISH:
		_line(values.step_points(last), true, 1.0 if cur == last else 0.45)
	# rounding marks: the side of each (one per mark), the next step's in mark
	var next_marks := {}
	if values.next_step > 0 and values.next_step < steps.size():
		var nst: Dictionary = steps[values.next_step]
		if int(nst["kind"]) == RaceText.Step.MARK or int(nst["kind"]) == RaceText.Step.GATE:
			var ms: PackedInt32Array = nst["marks"]
			for i in (1 if int(nst["kind"]) == RaceText.Step.MARK else 2):
				next_marks[ms[i]] = true
	var rounding := {}
	var labels := []  # [mark index the name sits beside, text, the marks it names]
	var named := {}
	for st in steps:
		var kd := int(st["kind"])
		if kd != RaceText.Step.MARK and kd != RaceText.Step.GATE:
			continue
		var ms: PackedInt32Array = st["marks"]
		var sides: PackedInt32Array = st["sides"]
		for i in (1 if kd == RaceText.Step.MARK else 2):
			if not rounding.has(ms[i]):
				rounding[ms[i]] = sides[i]
		if kd == RaceText.Step.MARK:
			if not named.has(ms[0]):
				named[ms[0]] = true
				labels.append([ms[0], values.mark_label(ms[0]), [ms[0]]])
		elif not named.has(ms[0]) and not named.has(ms[1]):
			named[ms[0]] = true
			named[ms[1]] = true
			var right := ms[0] if to_map(Vector2(marks[ms[0]]["x"], marks[ms[0]]["y"])).x \
				>= to_map(Vector2(marks[ms[1]]["x"], marks[ms[1]]["y"])).x else ms[1]
			labels.append([right, gate_label(values.mark_label(ms[0]), values.mark_label(ms[1])), [ms[0], ms[1]]])
	# the zone circle: the next step's marks only
	if zone:
		var zl := float(crs.get("zone_lengths", 3.0))
		for mi in next_marks:
			var zr := (zl * values._loa + float(marks[mi].get("radius", 0.0))) / m_per_px
			if zr * 2.0 >= 4.0:
				var q := to_px(Vector2(marks[mi]["x"], marks[mi]["y"]))
				_a(q, zr, 0.0, TAU, 40, Color(HudStyle.MARK, 0.5), hw)
	# marks
	for i in marks.size():
		var md: Dictionary = marks[i]
		var q := to_px(Vector2(md["x"], md["y"]))
		match int(md["type"]):
			3:
				continue
			1, 2:
				_hull(q, (7.0 if int(md["type"]) == 1 else 5.0) * k)
			_:
				if rounding.has(i):
					var col := HudStyle.MARK if next_marks.has(i) else HudStyle.PAPER
					_c(q, (BUOY + 1.5) * k, HudStyle.INK)
					_c(q, BUOY * k, col)
				else:
					_c(q, 2.5 * k, Color(HudStyle.PAPER, 0.6))
	for mi in rounding:
		var col := HudStyle.MARK if next_marks.has(mi) else HudStyle.MIST
		HudPaint.rounding_arc(self, to_px(Vector2(marks[mi]["x"], marks[mi]["y"])), 10.0 * k,
			rounding[mi] == RaceText.Side.PORT, col, 2.0 * k)
		arrows[mi] = [rounding[mi], col]
	var lfs := int(roundf(HudPaint.LAB_S * k))
	for lb in labels:
		var nxt: bool = (lb[2] as Array).any(func(mi: int) -> bool: return next_marks.has(mi))
		var q := to_px(Vector2(marks[lb[0]]["x"], marks[lb[0]]["y"]))
		_s(q + Vector2(NAME_GAP * k, 0.36 * lfs), str(lb[1]), lfs, HudStyle.MARK if nxt else HudStyle.MIST, 600, 0.06)
	# boats
	if sim == null:
		return
	var tags := []
	for ct in values.contacts:
		var p := sim.render_pose(ct.boat, alpha)
		if p == null:
			continue
		var col: Color = radar.contact_colour(ct) if radar != null else HudStyle.TINTS[ct.tint]
		if not ct.ghost and (ct.tint == RaceHudValues.Tint.WHITE or (radar != null and not radar.colours)):
			col = Color(col, col.a * QUIET)
		drawn[ct.boat] = col
		var q := to_px(Vector2(p.pos_x, p.pos_y))
		var outline := (radar == null or radar.colours) and ct.pulse == RaceHudValues.Pulse.BREACH and not ct.ghost
		var len_px := maxf(sim.class_info(ct.boat).loa / m_per_px, ICON * k)
		if not frame.has_point(q):
			icons[ct.boat] = _edge_arrow(q, col)
			continue
		icons[ct.boat] = q
		HudPaint.boat_icon(self, q, p.psi - up, len_px, col, outline)
		if ct.boat == selected:
			var e := 9.0 * k
			HudPaint.bracket(self, Rect2(q - Vector2(e, e), Vector2(e, e) * 2.0), HudStyle.PAPER, 4.0)
		var related := not ct.ghost and (radar == null or radar.colours) and ct.tint != RaceHudValues.Tint.WHITE
		if names and (ct.boat == selected or related):
			tags.append([ct.boat, q, col, related, outline])
	var me := sim.render_pose(values.boat, alpha)
	if me != null:
		var q := to_px(Vector2(me.pos_x, me.pos_y))
		if frame.has_point(q):
			icons[values.boat] = q
			var ol := maxf(values._loa / m_per_px, ICON * k) * OWN_SCALE
			_own_icon(q, me.psi - up, ol)
		else:
			icons[values.boat] = _edge_arrow(q, HudStyle.MARK)
		tags.append([values.boat, icons[values.boat], HudStyle.MARK, true, false])
	for tg in tags:
		HudPaint.name_chip(self, tg[1] + Vector2(0, -14.0 * k), values.name_of(tg[0]).to_upper(), tg[2], tg[3], tg[4])
		chips.append(tg[0])
	_header()
	_wind()
	_footer()


## The viewed boat: the radar's triangle `l` px long in `mark` with a 2 px ink rim (hud.md §8.1).
func _own_icon(q: Vector2, psi: float, l: float) -> void:
	var f := Vector2(sin(psi), -cos(psi))
	var s := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([q + f * 0.5 * l, q - f * 0.5 * l + s * 0.22 * l, q - f * 0.5 * l - s * 0.22 * l])
	var rim := pts.duplicate()
	rim.append(pts[0])
	_pl(rim, HudStyle.INK, 4.0 * k)
	_p(pts, HudStyle.MARK)


## A dashed (start) or checkered (finish) line between two points, as the race card's map draws them.
func _line(ends: Array[Vector2], checkered: bool, strength: float) -> void:
	if ends.size() < 2:
		return
	var a := to_px(ends[0])
	var b := to_px(ends[1])
	var n := maxi(2, int(a.distance_to(b) / (6.0 * k)))
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		if checkered:
			_l(p0, p1, Color(HudStyle.PAPER, strength) if i % 2 == 0 else Color(HudStyle.INK.lightened(0.25), strength),
				4.0 * k)
		elif i % 2 == 0:
			_l(p0, p1, Color(HudStyle.PAPER, strength), 2.0 * k)


func _hull(p: Vector2, l: float) -> void:
	_p(PackedVector2Array([p + Vector2(0, -l), p + Vector2(l * 0.45, l * 0.3), p + Vector2(l * 0.3, l * 0.8),
		p + Vector2(-l * 0.3, l * 0.8), p + Vector2(-l * 0.45, l * 0.3)]), HudStyle.PAPER)


## A boat outside the frame: a small arrow on the frame's edge pointing towards her; returns where it was drawn.
func _edge_arrow(q: Vector2, col: Color) -> Vector2:
	var c := frame.get_center()
	var d := q - c
	var inner := frame.grow(-8.0 * k)
	var t := INF
	if absf(d.x) > 1e-6:
		t = minf(t, (inner.size.x * 0.5) / absf(d.x))
	if absf(d.y) > 1e-6:
		t = minf(t, (inner.size.y * 0.5) / absf(d.y))
	var at := c + d * minf(t, 1.0)
	var f := d.normalized()
	var s := Vector2(-f.y, f.x)
	var l := 8.0 * k
	_p(PackedVector2Array([at + f * l * 0.6, at - f * l * 0.4 + s * l * 0.4, at - f * l * 0.4 - s * l * 0.4]), col)
	return at


## Clips the segment a-b to the frame; [] when it is outside.
func _clip(a: Vector2, b: Vector2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for ax in 2:
		var lo := frame.position[ax]
		var hi := frame.end[ax]
		if absf(d[ax]) < 1e-9:
			if a[ax] < lo or a[ax] > hi:
				return []
			continue
		var u0 := (lo - a[ax]) / d[ax]
		var u1 := (hi - a[ax]) / d[ax]
		t0 = maxf(t0, minf(u0, u1))
		t1 = minf(t1, maxf(u0, u1))
	if t1 <= t0:
		return []
	return [a + d * t0, a + d * t1]


## Top left: COURSE MAP, then the lap and leg and the next step (hud.md §8.1).
func _header() -> void:
	var m := HudStyle.margins(size)
	var fs := int(roundf(HudPaint.LAB * k))
	_s(Vector2(m.x, m.y + 16.0 * k), "COURSE MAP", fs, HudStyle.MIST, 600, HudPaint.TRACK)
	var y := m.y + 46.0 * k
	var big := int(roundf(20.0 * k))
	var x := m.x
	var parts := header_parts()
	for i in parts.size():
		var col: Color = HudStyle.MARK if i == 2 and parts.size() == 4 else HudStyle.PAPER
		var txt: String = parts[i]
		_s(Vector2(x, y), txt, big, col)
		x += HudCanvas.text_width(txt, big) + (8.0 if i == 1 else 16.0) * k


## The header's second line in parts: ["Lap 1/2 · Leg 3/4", "Next", "Windward", "420 m"], ["Start", "85 m"] before
## the start, ["Finished"] after the finish.
func header_parts() -> Array[String]:
	if values.finished:
		return ["Finished"]
	if not values.started:
		return ["Start", HudFormat.distance(absf(values.line_dist))]
	if values.next_step > 0:
		return ["Lap %d/%d · Leg %d/%d" % [values.lap, values.laps, values.leg, values.legs], "Next", values.next_name,
			HudFormat.distance(values.next_dist)]
	return []


## Top right: the true wind as an arrow blowing the way it goes on the map, speed and direction under it; a small N
## with a tick pointing to north on the turned map.
func _wind() -> void:
	var m := HudStyle.margins(size)
	var fs := int(roundf(13.0 * k))
	var up := up_bearing()
	var nc := Vector2(size.x - m.x - 130.0 * k, m.y + 28.0 * k)
	var nd := Vector2(sin(-up), -cos(-up))  # north on the screen
	_l(nc - nd * 9.0 * k, nc + nd * 9.0 * k, HudStyle.MIST, maxf(1.0, 1.5 * k))
	_c(nc + nd * 9.0 * k, 2.0 * k, HudStyle.MIST)
	var nl := nc + nd * 20.0 * k
	_s(Vector2(nl.x, nl.y + 0.36 * fs), "N", fs, HudStyle.MIST, 600, 0.06, HORIZONTAL_ALIGNMENT_CENTER)
	var c := Vector2(size.x - m.x - 40.0 * k, m.y + 22.0 * k)
	var d := Vector2(sin(twd + PI - up), -cos(twd + PI - up))  # where it blows on the map
	var tail := c - d * 16.0 * k
	var tip := c + d * 16.0 * k
	_l(tail, tip - d * 6.0 * k, HudStyle.PAPER, 2.5 * k)
	var s := Vector2(-d.y, d.x)
	_p(PackedVector2Array([tip, tip - d * 9.0 * k + s * 5.5 * k, tip - d * 9.0 * k - s * 5.5 * k]), HudStyle.PAPER)
	_s(Vector2(size.x - m.x, m.y + 64.0 * k), "%s KN  %s" % [str(roundi(tws / HudFormat.KNOT)), HudFormat.compass_deg(twd)],
		fs, HudStyle.PAPER, 600, 0.06, HORIZONTAL_ALIGNMENT_RIGHT)


## Bottom: the scale bar left, the close hint right.
func _footer() -> void:
	var y := size.y - HudStyle.bottom_margin(size) - 14.0 * k
	var fs := int(roundf(13.0 * k))
	var l := scale_length(frame.size.x, m_per_px)
	var w := l / m_per_px
	var x := HudStyle.margins(size).x
	var hw := maxf(1.0, 1.5 * k)
	_l(Vector2(x, y), Vector2(x + w, y), HudStyle.PAPER, 2.0 * k)
	_l(Vector2(x, y - 6.0 * k), Vector2(x, y + 1.0 * k), HudStyle.PAPER, hw)
	_l(Vector2(x + w, y - 6.0 * k), Vector2(x + w, y + 1.0 * k), HudStyle.PAPER, hw)
	var label := HudFormat.distance(l)
	_s(Vector2(x + w + 10.0 * k, y + 4.0 * k), label, fs, HudStyle.PAPER, 600, 0.06)
	scale_bar = [l, w, label]
	_s(Vector2(frame.end.x, y + 4.0 * k), close_text(), fs, HudStyle.MIST, 600, HudPaint.TRACK, HORIZONTAL_ALIGNMENT_RIGHT)


## The close hint (hud.md §8.1): the `map` binding as the device used last names it, `M  CLOSE`, `D-PAD UP  CLOSE`.
static func close_text() -> String:
	return "%s  CLOSE" % Bindings.prompt(&"map", "M").to_upper()
