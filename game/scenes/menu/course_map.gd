class_name CourseMap
extends Control
## The race card's course map (menus.md §1.1): a course file drawn north up on a dark chart, its marks resolved as
## courses.md §3 resolves them with the course axis on the chosen wind (at the file's distances, without the
## scaling of courses.md §6.3), the start and finish lines, the course through the sequence, and the wind arrow.

const INK := Color("06121b")
const PAPER := Color("f5f8fa")
const MIST := Color(0.961, 0.973, 0.98, 0.66)
const HAIR := Color(0.961, 0.973, 0.98, 0.30)
const MARK := Color("ffd23f")

## the course file (courses.md), {} for none
var course := {}
## where the wind blows from, degrees (0 = north), and its speed, kn
var wind_from_deg := 0.0
var wind_kn := 12.0
## mark id -> Vector2 world ENU m (x east, y north), filled by show_course
var points := {}


func _init() -> void:
	custom_minimum_size = Vector2(300, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func show_course(c: Dictionary, from_deg: float, kn: float) -> void:
	course = c
	wind_from_deg = from_deg
	wind_kn = kn
	points = resolve(c, deg_to_rad(from_deg))
	queue_redraw()


static func _dir(psi: float) -> Vector2:
	return Vector2(sin(psi), cos(psi))


## courses.md §3: every mark's world position (ENU m) with the course axis `twd` (rad), unscaled. Wind frame:
## `p = base + dist · dir(twd + bearing)`, the base another mark, an `<a>_<b>_mid` point or the reference; world
## frame (or a world point in a wind-frame file): {x, y}.
static func resolve(c: Dictionary, twd: float) -> Dictionary:
	var out := {}
	var ref_d: Dictionary = c.get("reference", {})
	var ref := Vector2(float(ref_d.get("x", 0.0)), float(ref_d.get("y", 0.0)))
	for m in c.get("marks", []):
		if not (m is Dictionary) or not m.has("id"):
			continue
		var at: Dictionary = m.get("at", {})
		var p := ref
		if at.has("x") and at.has("y"):
			p = Vector2(float(at["x"]), float(at["y"]))
		elif at.has("dist"):
			var base := ref
			var from := str(at.get("from", ""))
			if from.ends_with("_mid"):
				# mark ids may hold underscores: try every split of the name into two known ids
				var ab := from.trim_suffix("_mid").split("_")
				for i in range(1, ab.size()):
					var a := "_".join(ab.slice(0, i))
					var b := "_".join(ab.slice(i))
					if out.has(a) and out.has(b):
						base = (out[a] + out[b]) * 0.5
						break
			elif from != "" and out.has(from):
				base = out[from]
			p = base + float(at["dist"]) * _dir(twd + float(at.get("bearing", 0.0)))
		out[str(m["id"])] = p
	return out


## The marks a boat rounds (the sequence's marks and gates), for the yellow diamonds.
static func rounding_ids(c: Dictionary) -> Array:
	var ids := []
	for e in c.get("sequence", []):
		if e is Dictionary:
			if e.has("mark"):
				ids.append(str(e["mark"]))
			for g in e.get("gate", []):
				ids.append(str(g))
	return ids


## Laps and legs of the sequence (menus.md §1.1): laps = "lap" entries + 1, legs = marks and gates + 1.
static func laps_legs(c: Dictionary) -> Vector2i:
	var laps := 1
	var legs := 1
	for e in c.get("sequence", []):
		if e is String and e == "lap":
			laps += 1
		elif e is Dictionary:
			legs += 1
	return Vector2i(laps, legs)


func _line_mid(key: String) -> Variant:
	var ends: Array = course.get(key, {}).get("ends", [])
	if ends.size() == 2 and points.has(str(ends[0])) and points.has(str(ends[1])):
		return (points[str(ends[0])] + points[str(ends[1])]) * 0.5
	return null


## The course path: start line middle, each mark or gate middle of the sequence, finish line middle (world m).
func path() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var s: Variant = _line_mid("start")
	if s != null:
		pts.append(s)
	for e in course.get("sequence", []):
		if e is Dictionary:
			if e.has("mark") and points.has(str(e["mark"])):
				pts.append(points[str(e["mark"])])
			elif e.has("gate"):
				var g: Array = e["gate"]
				if g.size() == 2 and points.has(str(g[0])) and points.has(str(g[1])):
					pts.append((points[str(g[0])] + points[str(g[1])]) * 0.5)
	var f: Variant = _line_mid("finish")
	if f != null:
		pts.append(f)
	return pts


## World m -> local px: the marks' bounds fitted into the control with a margin, north up.
func _fit() -> Callable:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points.values():
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := Vector2(28, 28)
	var room := (size - pad * 2.0).max(Vector2.ONE)
	var span := (hi - lo).max(Vector2(50, 50))
	var k := minf(room.x / span.x, room.y / span.y)
	var mid := (lo + hi) * 0.5
	var c := size * 0.5
	return func(p: Vector2) -> Vector2: return c + Vector2(p.x - mid.x, -(p.y - mid.y)) * k


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	# a faint chart grid
	var step := 40.0
	var x := fmod(size.x * 0.5, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(HAIR, 0.12), 1.0)
		x += step
	var y := fmod(size.y * 0.5, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(HAIR, 0.12), 1.0)
		y += step
	if points.is_empty():
		_text(Vector2(size.x * 0.5, size.y * 0.5), "No course", MIST, 16, HORIZONTAL_ALIGNMENT_CENTER)
		_wind()
		return
	var to_px := _fit()
	var pth := path()
	if pth.size() >= 2:
		var px := PackedVector2Array()
		for p in pth:
			px.append(to_px.call(p))
		draw_polyline(px, HAIR, 1.5, true)
	_line("start", to_px, false)
	_line("finish", to_px, true)
	var rounding := rounding_ids(course)
	for m in course.get("marks", []):
		var id := str(m.get("id", ""))
		if not points.has(id):
			continue
		var p: Vector2 = to_px.call(points[id])
		match str(m.get("type", "buoy")):
			"virtual":
				pass
			"committee_boat", "mark_boat":
				_hull(p, 7.0 if m.get("type") == "committee_boat" else 5.0)
			_:
				if id in rounding:
					var r := 6.0
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r),
						p + Vector2(-r, 0)]), MARK)
				else:
					draw_circle(p, 3.0, PAPER)
	_wind()


func _line(key: String, to_px: Callable, checkered: bool) -> void:
	var ends: Array = course.get(key, {}).get("ends", [])
	if ends.size() != 2 or not points.has(str(ends[0])) or not points.has(str(ends[1])):
		return
	var a: Vector2 = to_px.call(points[str(ends[0])])
	var b: Vector2 = to_px.call(points[str(ends[1])])
	var n := maxi(2, int(a.distance_to(b) / 6.0))
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		if checkered:
			draw_line(p0, p1, PAPER if i % 2 == 0 else Color(INK.lightened(0.25)), 4.0)
		elif i % 2 == 0:
			draw_line(p0, p1, PAPER, 2.0)


func _hull(p: Vector2, l: float) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -l), p + Vector2(l * 0.45, l * 0.3),
		p + Vector2(l * 0.3, l * 0.8), p + Vector2(-l * 0.3, l * 0.8), p + Vector2(-l * 0.45, l * 0.3)]), PAPER)


## The wind arrow in the top-right corner, blowing the way the wind goes, with speed and direction under it, and N.
func _wind() -> void:
	var c := Vector2(size.x - 34, 34)
	var to := deg_to_rad(wind_from_deg) + PI
	var d := Vector2(sin(to), -cos(to))  # screen: north up
	var tail := c - d * 16.0
	var tip := c + d * 16.0
	draw_line(tail, tip - d * 6.0, PAPER, 2.5, true)
	var s := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 9.0 + s * 5.5, tip - d * 9.0 - s * 5.5]), PAPER)
	_text(Vector2(c.x, c.y + 34), "%d KN  %03d°" % [roundi(wind_kn), posmod(roundi(wind_from_deg), 360)], PAPER, 13,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(18, 26), "N", MIST, 13, HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(Vector2(18, 30), Vector2(18, 44), MIST, 1.5)


func _text(at: Vector2, t: String, col: Color, sz: int, align: HorizontalAlignment) -> void:
	var f := MenuTheme.font(600, 0.06, sz)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := at.x - (w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0)
	draw_string(f, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
